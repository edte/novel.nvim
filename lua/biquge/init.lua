local M = {}

local Async = require("biquge.async")
local Local = require("biquge.local")

local DOMAIN = "http://www.xbiquzw.com"
local NS_ID = vim.api.nvim_create_namespace("biquge_virtual_text")

local current_book = nil ---@type biquge.Book?
local current_toc = {} ---@type biquge.Chapter[]
local current_chap = nil ---@type biquge.Chapter?
local current_content = {} ---@type string[]
local current_location = nil ---@type biquge.Location?
local active = false
local begin_index, end_index = -1, -1
local bookshelf = nil ---@type biquge.Record[]
local reading_history = nil ---@type table<string, biquge.ReadingRecord> -- 所有书籍的阅读记录
local is_local_file = false -- 标识当前是否为本地文件
local last_book = nil ---@type biquge.Record? -- 最后阅读的书籍

local config = { ---@type biquge.Config
  width = 30,
  height = 10,
  hlgroup = "Comment",
  bookshelf = vim.fs.joinpath(vim.fn.stdpath("data"), "biquge_bookshelf.json"),
  reading_history = vim.fs.joinpath(vim.fn.stdpath("data"), "biquge_reading_history.json"), -- 所有书籍阅读历史
  last_reading = vim.fs.joinpath(vim.fn.stdpath("data"), "biquge_last_reading.json"), -- 最后阅读记录
  picker = "builtin",
  local_dir = vim.fs.joinpath(vim.fn.expand("~"), "Documents"), -- 默认本地文件目录
}

local Picker = setmetatable({}, {
  __index = function(_, k)
    return require("biquge.picker." .. config.picker)[k]
  end,
})

---@param msg string
---@param level integer
local function notify(msg, level)
  vim.notify(msg, level, { title = "biquge.nvim" })
end

---生成书籍的唯一标识
---@param book biquge.Book
---@return string
local function get_book_id(book)
  -- 使用标题+作者+链接生成唯一ID，避免重复
  local id_string = book.title .. "|" .. book.author .. "|" .. book.link
  return vim.fn.sha256(id_string)
end

---@return integer
local function current_chap_index()
  for i, item in ipairs(current_toc) do
    if vim.deep_equal(item, current_chap) then
      return i
    end
  end
  return -1
end

local function save()
  if current_book ~= nil then
    local book_id = get_book_id(current_book)
    local reading_record = {
      info = current_book,
      last_read = current_chap_index(),
      is_local = is_local_file,
      chapters = is_local_file and current_toc or nil,
      reading_position = {
        chapter_index = current_chap_index(),
        line_index = begin_index,
        timestamp = os.time()
      }
    }
    
    -- 保存到阅读历史（所有书籍）
    reading_history[book_id] = reading_record
    
    -- 保存到书架（仅收藏的书籍）
    for _, r in ipairs(bookshelf) do
      if vim.deep_equal(current_book, r.info) then
        r.last_read = current_chap_index()
        r.reading_position = reading_record.reading_position
        break
      end
    end
    
    -- 保存最后阅读的书籍
    last_book = reading_record
  end
end

---@param opts biquge.Config
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts)

  -- 加载书架
  if vim.fn.filereadable(config.bookshelf) == 1 then
    local text = vim.fn.readfile(config.bookshelf)
    bookshelf = vim.json.decode(table.concat(text))
  else
    bookshelf = {}
  end
  
  -- 加载阅读历史记录
  if vim.fn.filereadable(config.reading_history) == 1 then
    local text = vim.fn.readfile(config.reading_history)
    reading_history = vim.json.decode(table.concat(text))
  else
    reading_history = {}
  end
  
  -- 加载最后阅读记录
  if vim.fn.filereadable(config.last_reading) == 1 then
    local text = vim.fn.readfile(config.last_reading)
    last_book = vim.json.decode(table.concat(text))
  else
    last_book = nil
  end

  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      save()
      vim.fn.writefile({ vim.json.encode(bookshelf) }, config.bookshelf)
      vim.fn.writefile({ vim.json.encode(reading_history) }, config.reading_history)
      -- 保存最后阅读记录
      if last_book then
        vim.fn.writefile({ vim.json.encode(last_book) }, config.last_reading)
      end
    end,
    group = vim.api.nvim_create_augroup("biquge_bookshelf", {}),
  })
end

---@param text string
local function normalize(text)
  return text:gsub("&nbsp;", " "):gsub("<br%s*/>", "\n"):gsub("\r\n", "\n")
end

---@param text string
---@return string[]
local function get_content(text)
  local normalized = normalize(text)
  local parser = vim.treesitter.get_string_parser(normalized, "html")
  local root = parser:parse()[1]:root()

  local query = vim.treesitter.query.parse(
    "html",
    [[
(
 (element
   (start_tag
     (tag_name) @tag_name
     (attribute
       (attribute_name) @attr_name
       (quoted_attribute_value) @attr_value))
   (text) @text)
 (#eq? @tag_name "div")
 (#eq? @attr_name "id")
 (#eq? @attr_value "\"content\""))
  ]]
  )

  for id, node in query:iter_captures(root, normalized) do
    local capture = query.captures[id]
    if capture == "text" then
      return vim.split(vim.treesitter.get_node_text(node, normalized), "\n")
    end
  end

  return {}
end

---@param text string
---@return biquge.Chapter[]
local function get_toc(text)
  local normalized = normalize(text)
  local parser = vim.treesitter.get_string_parser(normalized, "html")
  local root = parser:parse()[1]:root()

  local query = vim.treesitter.query.parse(
    "html",
    [[
(
 (element
   (start_tag
     (tag_name) @div_tag_name
     (attribute
       (attribute_name) @id_attr_name
       (quoted_attribute_value) @id_attr_value))
   (element
     (element
       (element
         (start_tag
           (tag_name) @a_tag_name
           (attribute
             (attribute_name) @href_attr_name
             (quoted_attribute_value
               (attribute_value) @link))
           (attribute
             (attribute_name) @title_attr_name
             (quoted_attribute_value
               (attribute_value) @title)))))))
 (#eq? @div_tag_name "div")
 (#eq? @id_attr_name "id")
 (#eq? @id_attr_value "\"list\"")
 (#eq? @a_tag_name "a")
 (#eq? @href_attr_name "href")
 (#eq? @title_attr_name "title"))
  ]]
  )

  ---@type biquge.Chapter[]
  local res = {}
  for _, match in query:iter_matches(root, normalized, 0, -1, { all = true }) do
    local item = {}

    for id, nodes in pairs(match) do
      local name = query.captures[id]
      if vim.list_contains({ "link", "title" }, name) then
        for _, node in ipairs(nodes) do
          item[name] = vim.treesitter.get_node_text(node, normalized)
        end
      end
    end

    res[#res + 1] = item
  end

  return res
end

---@param text string
---@return biquge.Book[]
local function get_books(text)
  local normalized = normalize(text)
  local parser = vim.treesitter.get_string_parser(normalized, "html")
  local root = parser:parse()[1]:root()

  local query = vim.treesitter.query.parse(
    "html",
    [[
(
 (element
   (start_tag
     (tag_name) @table_tag_name
     (attribute
       (attribute_name) @grid_attr_name
       (quoted_attribute_value) @grid_attr_value))
   (element
     (element
       (start_tag
         (tag_name) @a_td_tag_name
         (attribute
           (attribute_name) @a_odd_attr_name
           (quoted_attribute_value) @a_odd_attr_value))
       (element
         (start_tag
           (tag_name) @a_tag_name
           (attribute
             (attribute_name) @href_attr_name
             (quoted_attribute_value
               (attribute_value) @link)) .)
         (text) @title))
     (element
       (start_tag
         (tag_name) @text_td_tag_name
         (attribute
           (attribute_name) @text_odd_attr_name
           (quoted_attribute_value) @text_odd_attr_value) .)
       (text) @author)))
 (#eq? @table_tag_name "table")
 (#eq? @grid_attr_name "class")
 (#eq? @grid_attr_value "\"grid\"")
 (#eq? @a_td_tag_name "td")
 (#eq? @a_odd_attr_name "class")
 (#eq? @a_odd_attr_value "\"odd\"")
 (#eq? @a_tag_name "a")
 (#eq? @text_td_tag_name "td")
 (#eq? @text_odd_attr_name "class")
 (#eq? @text_odd_attr_value "\"odd\""))
  ]]
  )

  ---@type biquge.Book[]
  local res = {}
  for _, match in query:iter_matches(root, normalized, 0, -1, { all = true }) do
    local item = {}

    for id, nodes in pairs(match) do
      local name = query.captures[id]
      if vim.list_contains({ "link", "title", "author" }, name) then
        for _, node in ipairs(nodes) do
          item[name] = vim.treesitter.get_node_text(node, normalized)
        end
      end
    end

    res[#res + 1] = item
  end

  return res
end

---@param line string
---@return string[]
local function pieces(line)
  local res = {}
  local pos = vim.str_utf_pos(line)

  if #pos == 0 then
    return {}
  end

  local i, j = 1, 1 + config.width
  repeat
    res[#res + 1] = string.sub(line, pos[i], (pos[j] or 0) - 1)
    i = i + config.width
    j = j + config.width
  until i > #pos

  return res
end

---@async
---@param uri string
local function request(uri)
  return Async.system({
    "curl",
    "-fsSL",
    "--compressed",
    DOMAIN .. uri,
  })
end

---@async
---@param restore_position? boolean 是否恢复到上次阅读位置
local function cook_content(restore_position)
  if not current_book or not current_chap then
    return
  end

  local content = {}
  
  if is_local_file then
    -- 本地文件直接从章节中获取内容
    content = Local.get_chapter_content(current_chap)
  else
    -- 在线文件通过网络请求获取
    local res = request(current_book.link .. current_chap.link)
    if res.code ~= 0 then
      notify("Failed to fetch chapter content: " .. res.stderr, vim.log.levels.ERROR)
      return
    end
    content = get_content(res.stdout)
  end

  current_content = { "# " .. current_chap.title }

  for _, line in ipairs(content) do
    vim.list_extend(current_content, pieces(line))
  end

  -- 恢复阅读位置或从头开始
  if restore_position and current_book then
    local book_id = get_book_id(current_book)
    local reading_record = reading_history[book_id]
    
    if reading_record and reading_record.reading_position then
      local pos = reading_record.reading_position
      if pos.chapter_index == current_chap_index() and pos.line_index > 0 then
        begin_index = math.min(pos.line_index, #current_content - config.height + 1)
        begin_index = math.max(1, begin_index)
        end_index = begin_index + config.height - 1
        -- 已恢复到上次阅读位置
      else
        begin_index, end_index = 1, config.height
      end
    else
      begin_index, end_index = 1, config.height
    end
  else
    begin_index, end_index = 1, config.height
  end

  M.show()
end

function M.show()
  if begin_index == -1 or end_index == -1 then
    notify("没有正在阅读的章节，请先搜索想要阅读的章节", vim.log.levels.WARN)
    return
  end

  current_location = {
    bufnr = Async.api.nvim_get_current_buf(),
    row = Async.api.nvim_win_get_cursor(0)[1] - 1,
  }

  local virt_lines = {}
  for _, line in ipairs(vim.list_slice(current_content, begin_index, end_index)) do
    virt_lines[#virt_lines + 1] = { { line, config.hlgroup } }
  end

  Async.api.nvim_buf_clear_namespace(current_location.bufnr, NS_ID, 0, -1)
  Async.api.nvim_buf_set_extmark(current_location.bufnr, NS_ID, current_location.row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
  })

  active = true
  
  -- 实时保存阅读位置
  save()
end

function M.hide()
  if not active or not current_location then
    return
  end

  vim.api.nvim_buf_clear_namespace(current_location.bufnr, NS_ID, 0, -1)
  active = false
end

function M.toggle()
  if active then
    M.hide()
  else
    -- 如果没有当前书籍，尝试恢复上次阅读的书籍
    if not current_book and last_book then
      M.resume_last_reading()
      return
    end
    M.show()
  end
end

local function jump_chap(offset)
  if #current_toc == 0 then
    notify("没有正在阅读的小说，请先搜索想要阅读的小说", vim.log.levels.WARN)
    return
  end

  local index = current_chap_index()
  local target = index + offset
  if target < 1 or target > #current_toc then
    return
  end

  current_chap = current_toc[target]
  Async.run(function() cook_content(false) end)
end

function M.next_chap()
  jump_chap(1)
end

function M.prev_chap()
  jump_chap(-1)
end

---@param offset integer
function M.scroll(offset)
  if not active then
    return
  end

  local step = offset < 0 and math.max(1 - begin_index, offset) or math.min(#current_content - end_index, offset)
  if step == 0 then
    return
  end

  begin_index = begin_index + step
  end_index = end_index + step

  M.show()
  -- 滚动时也保存位置
  save()
end

---@async
---@return boolean
local function fetch_toc()
  if not current_book then
    return false
  end

  if is_local_file then
    -- 本地文件的目录已经在解析时生成，直接返回
    return #current_toc > 0
  else
    -- 在线文件通过网络请求获取目录
    local res = request(current_book.link)
    if res.code ~= 0 then
      notify("Failed to fetch table of contents: " .. res.stderr, vim.log.levels.ERROR)
      return false
    end

    current_toc = get_toc(res.stdout)
    return true
  end
end

function M.toc()
  if current_book == nil then
    notify("没有正在阅读的小说，请先搜索想要阅读的小说", vim.log.levels.WARN)
    return
  end

  Async.run(function()
    if not fetch_toc() then
      return
    end

    Picker.pick({
      prompt = current_book.title .. " - 目录",
      items = current_toc,
      ---@param item biquge.Chapter
      display = function(item)
        return item.title
      end,
      ---@param chap biquge.Chapter
      confirm = function(_, chap)
        current_chap = chap
        Async.run(function() cook_content(false) end)
      end,
    })
  end)
end

local function reset()
  M.hide()
  save()

  current_book = nil
  current_toc = {}
  current_chap = nil
  current_content = {}
  begin_index, end_index = -1, -1
  current_location = nil
  is_local_file = false
end

M.search = function()
  reset()

  Async.run(function()
    local input = Async.input({ prompt = "书名" })
    if input == nil then
      return
    end

    local res = request("/modules/article/search.php?searchkey=" .. vim.uri_encode(input))
    if res.code ~= 0 then
      notify("Failed to search: " .. res.stderr, vim.log.levels.ERROR)
      return
    end

    local results = get_books(res.stdout)

    Picker.pick({
      prompt = "搜索结果",
      items = results,
      ---@param item biquge.Book
      display = function(item)
        return item.title .. " - " .. item.author
      end,
      ---@param item biquge.Book
      confirm = function(_, item)
        current_book = item
        M.toc()
      end,
    })
  end)
end

---@param book biquge.Book?
function M.star(book)
  book = book or current_book
  if book == nil then
    notify("没有正在阅读的小说，无法收藏", vim.log.levels.WARN)
    return
  end

  for i, r in ipairs(bookshelf) do
    if vim.deep_equal(book, r.info) then
      -- 取消收藏
      table.remove(bookshelf, i)
      return
    end
  end

  -- 收藏成功
  local record = {
    info = book,
    last_read = current_chap_index(),
    is_local = is_local_file,
  }
  
  -- 如果是本地文件，保存章节信息
  if is_local_file then
    record.chapters = current_toc
  end
  
  bookshelf[#bookshelf + 1] = record
end

function M.bookshelf()
  reset()

  ---@param item biquge.Record
  local function display(item)
    local prefix = item.is_local and "[本地] " or "[在线] "
    return prefix .. item.info.title .. " - " .. item.info.author
  end

  local function unstar(picker, item)
    M.star(item.info)
    Picker.refresh(picker, {
      items = bookshelf,
      display = display,
    })
  end

  Picker.pick({
    prompt = "书架",
    items = bookshelf,
    display = display,
    ---@param item biquge.Record
    confirm = function(_, item)
      current_book = item.info
      is_local_file = item.is_local or false
      
      -- 优先从阅读历史中获取最新的阅读记录
      local book_id = get_book_id(current_book)
      local history_record = reading_history[book_id]
      local target_chapter_index = history_record and history_record.last_read or item.last_read

      if is_local_file then
        -- 本地文件直接使用保存的章节信息
        current_toc = (history_record and history_record.chapters) or item.chapters or {}
        if #current_toc > 0 and target_chapter_index > 0 and target_chapter_index <= #current_toc then
          current_chap = current_toc[target_chapter_index]
          Async.run(function() cook_content(true) end)
        else
          notify("本地文件章节信息丢失，请重新加载", vim.log.levels.WARN)
        end
      else
        -- 在线文件
        Async.run(function()
          if not fetch_toc() then
            return
          end

          if target_chapter_index > 0 and target_chapter_index <= #current_toc then
            current_chap = current_toc[target_chapter_index]
          else
            current_chap = current_toc[1] -- 默认第一章
          end
          cook_content(true)
        end)
      end
    end,
    actions = { unstar = unstar },
    keys = {
      ["<C-x>"] = { "unstar", mode = "i" },
      ["dd"] = "unstar",
    },
  })
end

-- 浏览本地文件目录
M.local_browse = function()
  reset()
  
  -- 获取默认目录下的所有 TXT 文件
  local txt_files = vim.fn.glob(vim.fs.joinpath(config.local_dir, "*.txt"), false, true)
  
  if #txt_files == 0 then
    notify("在目录 " .. config.local_dir .. " 中没有找到 TXT 文件", vim.log.levels.WARN)
    return
  end
  
  -- 转换为文件名显示
  local items = {}
  for _, filepath in ipairs(txt_files) do
    local filename = vim.fn.fnamemodify(filepath, ":t")
    table.insert(items, {
      display = filename,
      path = filepath
    })
  end
  
  Picker.pick({
    prompt = "选择本地文件 (" .. config.local_dir .. ")",
    items = items,
    display = function(item)
      return item.display
    end,
    confirm = function(_, item)
      -- 直接加载选中的文件
      local book, chapters = Local.parse_txt_file(item.path)
      if not book then
        notify("解析文件失败", vim.log.levels.ERROR)
        return
      end

      current_book = book
      current_toc = chapters
      is_local_file = true

      -- 成功加载文件
      M.toc()
    end,
  })
end

-- 本地文件搜索功能
M.local_search = function()
  reset()

  Async.run(function()
    -- 使用文件选择器选择TXT文件
    local input = Async.input({ 
      prompt = "请输入TXT文件路径 (默认目录: " .. config.local_dir .. "): ",
      completion = "file"
    })
    
    if not input or input == "" then
      return
    end

    -- 智能路径处理
    local filepath
    if vim.startswith(input, "/") or vim.startswith(input, "~") then
      -- 绝对路径或家目录路径
      filepath = vim.fn.expand(input)
    else
      -- 相对路径，先尝试相对于默认目录
      local default_path = vim.fs.joinpath(config.local_dir, input)
      if vim.fn.filereadable(default_path) == 1 then
        filepath = default_path
      else
        -- 尝试模糊匹配（在默认目录中查找包含输入文本的文件）
        local pattern = vim.fs.joinpath(config.local_dir, "*" .. input .. "*.txt")
        local matches = vim.fn.glob(pattern, false, true)
        if #matches > 0 then
          if #matches == 1 then
            filepath = matches[1]
            -- 找到匹配文件
          else
            -- 多个匹配，让用户选择
            local items = {}
            for _, match in ipairs(matches) do
              local filename = vim.fn.fnamemodify(match, ":t")
              table.insert(items, {
                display = filename,
                path = match
              })
            end
            
            Picker.pick({
              prompt = "找到多个匹配文件，请选择:",
              items = items,
              display = function(item) return item.display end,
              confirm = function(_, item)
                -- 递归调用，使用选中的文件路径
                local book, chapters = Local.parse_txt_file(item.path)
                if not book then
                  notify("解析文件失败", vim.log.levels.ERROR)
                  return
                end

                current_book = book
                current_toc = chapters
                is_local_file = true

                -- 成功加载文件
                M.toc()
              end,
            })
            return
          end
        else
          -- 尝试相对于当前工作目录
          filepath = vim.fn.expand(input)
        end
      end
    end
    
    -- 检查文件是否存在
    if vim.fn.filereadable(filepath) ~= 1 then
      notify("文件不存在或无法读取: " .. filepath, vim.log.levels.ERROR)
      return
    end

    -- 检查是否为TXT文件
    local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
    if ext ~= "txt" then
      notify("目前只支持 .txt 文件", vim.log.levels.WARN)
      return
    end

    -- 解析本地文件
    local book, chapters = Local.parse_txt_file(filepath)
    if not book then
      notify("解析文件失败", vim.log.levels.ERROR)
      return
    end

    -- 设置当前状态
    current_book = book
    current_toc = chapters
    is_local_file = true

    -- 成功加载本地文件

    -- 显示章节选择器
    M.toc()
  end)
end

-- 恢复上次阅读的书籍和位置
M.resume_last_reading = function()
  if not last_book then
    notify("没有上次阅读记录", vim.log.levels.WARN)
    return
  end
  
  reset()
  
  current_book = last_book.info
  is_local_file = last_book.is_local or false
  
  if is_local_file then
    -- 本地文件
    current_toc = last_book.chapters or {}
    if #current_toc > 0 and last_book.last_read > 0 and last_book.last_read <= #current_toc then
      current_chap = current_toc[last_book.last_read]
      Async.run(function() cook_content(true) end)
      -- 已恢复阅读
    else
      notify("本地文件章节信息丢失", vim.log.levels.WARN)
    end
  else
    -- 在线文件
    Async.run(function()
      if not fetch_toc() then
        return
      end
      
      if last_book.last_read > 0 and last_book.last_read <= #current_toc then
        current_chap = current_toc[last_book.last_read]
        cook_content(true)
        -- 已恢复阅读
      else
        notify("章节信息已过期，请重新选择章节", vim.log.levels.WARN)
        M.toc()
      end
    end)
  end
end

-- 查看所有书籍的阅读历史
M.reading_history = function()
  reset()
  
  if not reading_history or vim.tbl_isempty(reading_history) then
    notify("没有阅读历史记录", vim.log.levels.WARN)
    return
  end
  
  -- 转换为数组并按时间排序
  local history_items = {}
  for _, record in pairs(reading_history) do
    if record.reading_position and record.reading_position.timestamp then
      table.insert(history_items, record)
    end
  end
  
  -- 按最后阅读时间倒序排列
  table.sort(history_items, function(a, b)
    return a.reading_position.timestamp > b.reading_position.timestamp
  end)
  
  ---@param item biquge.ReadingRecord
  local function display(item)
    local prefix = item.is_local and "[本地] " or "[在线] "
    local time_str = os.date("%m-%d %H:%M", item.reading_position.timestamp)
    return prefix .. item.info.title .. " - " .. item.info.author .. " (" .. time_str .. ")"
  end
  
  Picker.pick({
    prompt = "阅读历史 (共 " .. #history_items .. " 本书)",
    items = history_items,
    display = display,
    ---@param item biquge.ReadingRecord
    confirm = function(_, item)
      current_book = item.info
      is_local_file = item.is_local or false
      
      if is_local_file then
        -- 本地文件
        current_toc = item.chapters or {}
        if #current_toc > 0 and item.last_read > 0 and item.last_read <= #current_toc then
          current_chap = current_toc[item.last_read]
          Async.run(function() cook_content(true) end)
        else
          notify("本地文件章节信息丢失", vim.log.levels.WARN)
        end
      else
        -- 在线文件
        Async.run(function()
          if not fetch_toc() then
            return
          end
          
          if item.last_read > 0 and item.last_read <= #current_toc then
            current_chap = current_toc[item.last_read]
          else
            current_chap = current_toc[1]
          end
          cook_content(true)
        end)
      end
    end,
  })
end

return M
