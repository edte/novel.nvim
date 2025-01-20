local M = {}

local Async = require("biquge.async")

local DOMAIN = "http://www.xbiquzw.com"

local active = false

---@type biquge.Book?
local current_book = nil

---@type biquge.Chapter[]
local current_toc = {}

---@type biquge.Chapter?
local current_chap = nil

---@type string[]
local current_content = {}

local begin_index, end_index = -1, -1

---@type biquge.Location?
local current_location = nil

local current_extmark_id = -1

---@type biquge.Record[]
local bookshelf = nil

---@type biquge.Config
local config = {
  width = 30,
  height = 10,
  hlgroup = "Comment",
  bookshelf = vim.fs.joinpath(vim.fn.stdpath("data"), "biquge_bookshelf.json"),
  picker = "builtin",
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
    for _, r in ipairs(bookshelf) do
      if vim.deep_equal(current_book, r.info) then
        r.last_read = current_chap_index()
        return
      end
    end
  end
end

---@param opts biquge.Config
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts)

  if vim.fn.filereadable(config.bookshelf) == 1 then
    local text = vim.fn.readfile(config.bookshelf)
    bookshelf = vim.json.decode(table.concat(text))
  else
    bookshelf = {}
  end

  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
      save()
      vim.fn.writefile({ vim.json.encode(bookshelf) }, config.bookshelf)
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
local function cook_content()
  if not current_book or not current_chap then
    return
  end

  local res = Async.system({
    "curl",
    "--compressed",
    DOMAIN .. current_book.link .. current_chap.link,
  })

  if res.code ~= 0 then
    notify("Failed to fetch chapter content: " .. res.stderr, vim.log.levels.ERROR)
    return
  end

  local content = get_content(res.stdout)
  current_content = { "-- " .. current_chap.title .. " --" }

  for _, line in ipairs(content) do
    vim.list_extend(current_content, pieces(line))
  end

  current_content[#current_content + 1] = "-- 本章完 --"
  begin_index, end_index = 1, 1 + config.height

  M.show()
end

local NS = vim.api.nvim_create_namespace("biquge_virtual_text")

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

  current_extmark_id = Async.api.nvim_buf_set_extmark(current_location.bufnr, NS, current_location.row, 0, {
    id = (current_extmark_id ~= -1) and current_extmark_id or nil,
    virt_lines = virt_lines,
    virt_lines_above = false,
  })

  active = true
end

function M.hide()
  if not active or not current_location then
    return
  end

  vim.api.nvim_buf_clear_namespace(current_location.bufnr, NS, 0, -1)
  current_extmark_id = -1
  active = false
end

function M.toggle()
  if active then
    M.hide()
  else
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
  Async.run(cook_content)
end

function M.next_chap()
  jump_chap(1)
end

function M.prev_chap()
  jump_chap(-1)
end

function M.scroll(offset)
  if not active then
    return
  end

  if begin_index + offset < 1 then
    return
  end

  if end_index + offset > #current_content then
    return
  end

  begin_index = begin_index + offset
  end_index = end_index + offset
  M.show()
end

---@async
---@return boolean
local function fetch_toc()
  if not current_book then
    return false
  end

  local res = Async.system({
    "curl",
    "--compressed",
    DOMAIN .. current_book.link,
  })

  if res.code ~= 0 then
    notify("Failed to fetch table of contents: " .. res.stderr, vim.log.levels.ERROR)
    return false
  end

  current_toc = get_toc(res.stdout)

  return true
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
        Async.run(cook_content)
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
  current_extmark_id = -1
end

M.search = function()
  reset()

  Async.run(function()
    local input = Async.input({ prompt = "书名" })
    if input == nil then
      return
    end

    local res = Async.system({
      "curl",
      "--compressed",
      DOMAIN .. "/modules/article/search.php?searchkey=" .. input:gsub(" ", "+"),
    })

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
      notify("取消收藏 " .. book.title .. " - " .. book.author, vim.log.levels.INFO)
      table.remove(bookshelf, i)
      return
    end
  end

  notify("收藏 " .. book.title .. " - " .. book.author, vim.log.levels.INFO)
  bookshelf[#bookshelf + 1] = {
    info = book,
    last_read = current_chap_index(),
  }
end

function M.bookshelf()
  reset()

  ---@param item biquge.Record
  local function display(item)
    return item.info.title .. " - " .. item.info.author
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

      Async.run(function()
        if not fetch_toc() then
          return
        end

        current_chap = current_toc[item.last_read]
        cook_content()
      end)
    end,
    actions = { unstar = unstar },
    keys = {
      ["<C-x>"] = { "unstar", mode = "i" },
      ["dd"] = "unstar",
    },
  })
end

return M
