local M = {}
local Async = require("biquge.async")

---@param msg string
---@param level integer
local function notify(msg, level)
  vim.notify(msg, level, { title = "biquge.nvim" })
end

---读取本地文件内容并处理换行符
---@param filepath string
---@return string[]|nil
local function read_file(filepath)
  local file = io.open(filepath, "rb") -- 使用二进制模式读取
  if not file then
    notify("无法打开文件: " .. filepath, vim.log.levels.ERROR)
    return nil
  end
  
  local content = file:read("*all")
  file:close()
  
  if not content then
    notify("读取文件内容失败: " .. filepath, vim.log.levels.ERROR)
    return nil
  end
  
  -- 统一处理各种换行符
  -- 先将 \r\n 替换为 \n，再将单独的 \r 替换为 \n
  content = content:gsub("\r\n", "\n"):gsub("\r", "\n")
  
  -- 分割成行
  local lines = {}
  for line in content:gmatch("([^\n]*)\n?") do
    -- 移除行末的空白字符
    line = line:gsub("%s+$", "")
    table.insert(lines, line)
  end
  
  -- 移除最后的空行（如果有的话）
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
  
  return lines
end

---智能分割章节
---@param lines string[]
---@return biquge.Chapter[]
local function split_chapters(lines)
  local chapters = {}
  local current_chapter = nil
  local current_content = {}
  
  -- 章节标题的匹配模式 (更严格的匹配)
  local patterns = {
    "^第[一二三四五六七八九十百千万零0-9]+章",  -- 第X章
    "^Chapter[%s]+[0-9]+"                      -- Chapter X
  }
  
  for i, line in ipairs(lines) do
    local is_chapter_title = false
    local chapter_title = nil
    
    -- 检查是否匹配章节标题模式
    for _, pattern in ipairs(patterns) do
      if line:match(pattern) then
        is_chapter_title = true
        chapter_title = line
        break
      end
    end
    
    -- 如果是章节标题
    if is_chapter_title then
      -- 保存上一章节
      if current_chapter then
        current_chapter.content = current_content
        table.insert(chapters, current_chapter)
      end
      
      -- 开始新章节
      current_chapter = {
        title = chapter_title,
        link = tostring(#chapters + 1), -- 使用章节序号作为链接
        start_line = i,
        content = {}
      }
      current_content = {}
    else
      -- 添加到当前章节内容
      if current_chapter then
        table.insert(current_content, line)
      else
        -- 如果还没有章节，创建一个默认章节
        if #chapters == 0 then
          current_chapter = {
            title = "开始",
            link = "1",
            start_line = 1,
            content = {}
          }
          current_content = {}
        end
        table.insert(current_content, line)
      end
    end
  end
  
  -- 保存最后一章
  if current_chapter then
    current_chapter.content = current_content
    table.insert(chapters, current_chapter)
  end
  
  -- 如果没有找到章节，把整个文件作为一章
  if #chapters == 0 then
    table.insert(chapters, {
      title = "全文",
      link = "1",
      start_line = 1,
      content = lines
    })
  end
  
  return chapters
end

---解析本地TXT文件
---@param filepath string
---@return biquge.Book|nil, biquge.Chapter[]
function M.parse_txt_file(filepath)
  local lines = read_file(filepath)
  if not lines then
    return nil, {}
  end
  
  local filename = vim.fn.fnamemodify(filepath, ":t:r") -- 获取不带扩展名的文件名
  
  -- 创建书籍信息
  local book = {
    title = filename,
    author = "本地文件",
    link = filepath -- 使用文件路径作为链接
  }
  
  -- 分割章节
  local chapters = split_chapters(lines)
  
  return book, chapters
end

---获取章节内容（已经在解析时处理好了）
---@param chapter biquge.Chapter
---@return string[]
function M.get_chapter_content(chapter)
  return chapter.content or {}
end

return M