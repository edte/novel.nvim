local M = {}

local Async = require("biquge.async")

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

local DOMAIN = "http://www.xbiquzw.com"

local active = false

---@class BiqugeBook
---@field author string
---@field link string
---@field title string
local current_book = nil

---@class BiqugeChap
---@field link string
---@field title string

---@type BiqugeChap[]
local current_toc = nil

---@type BiqugeChap
local current_chap = nil

---@type string[]
local current_content = nil

local begin_index, end_index = -1, -1

---@class BiqugePosition
---@field bufnr integer
---@field row integer
local current_position = nil

local current_extmark_id = -1

---@class BiqugeBookRecord
---@field info BiqugeBook
---@field last_read integer
---
---@type BiqugeBookRecord[]
local bookshelf = nil

---@class BiqugeConfig
---@field width integer
---@field height integer
---@field hlgroup string
---@field bookshelf string
local config = {
  width = 30,
  height = 10,
  hlgroup = "Comment",
  bookshelf = vim.fs.joinpath(vim.fn.stdpath("data"), "biquge_bookshelf.json"),
}

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

---@param opts BiqugeConfig
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
---@return BiqugeChap[]
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

  ---@type BiqugeChap[]
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
---@return BiqugeBook[]
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

  ---@type BiqugeBook[]
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

  current_position = {
    bufnr = Async.api.nvim_get_current_buf(),
    row = Async.api.nvim_win_get_cursor(0)[1] - 1,
  }

  local virt_lines = {}
  for _, line in ipairs(vim.list_slice(current_content, begin_index, end_index)) do
    virt_lines[#virt_lines + 1] = { { line, config.hlgroup } }
  end

  current_extmark_id = Async.api.nvim_buf_set_extmark(current_position.bufnr, NS, current_position.row, 0, {
    id = (current_extmark_id ~= -1) and current_extmark_id or nil,
    virt_lines = virt_lines,
    virt_lines_above = false,
  })

  active = true
end

function M.hide()
  if not active then
    return
  end

  vim.api.nvim_buf_clear_namespace(current_position.bufnr, NS, 0, -1)
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
  if current_toc == nil then
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

    Async.util.scheduler()
    pickers
      .new({}, {
        prompt_title = current_book.title .. " - 目录",
        finder = finders.new_table({
          results = current_toc,
          entry_maker = function(entry)
            return {
              value = entry,
              display = entry.title,
              ordinal = entry.title,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            current_chap = action_state.get_selected_entry().value
            Async.run(cook_content)
          end)
          return true
        end,
      })
      :find()
  end)
end

local function reset()
  M.hide()
  save()

  current_book = nil
  current_toc = nil
  current_chap = nil
  current_content = nil
  begin_index, end_index = -1, -1
  current_position = nil
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

    Async.util.scheduler()
    pickers
      .new({}, {
        prompt_title = "搜索结果",
        finder = finders.new_table({
          results = results,
          entry_maker = function(entry)
            local display = entry.title .. " - " .. entry.author
            return {
              value = entry,
              display = display,
              ordinal = display,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            current_book = action_state.get_selected_entry().value
            M.toc()
          end)
          return true
        end,
      })
      :find()
  end)
end

---@param book BiqugeBook?
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

  local function new_finder()
    return finders.new_table({
      results = bookshelf,
      entry_maker = function(entry)
        local display = entry.info.title .. " - " .. entry.info.author
        return {
          value = entry,
          display = display,
          ordinal = display,
        }
      end,
    })
  end

  local function unstar(picker_bufnr)
    local selection = action_state.get_selected_entry().value
    local picker = action_state.get_current_picker(picker_bufnr)
    if selection then
      M.star(selection.info)
      picker:refresh(new_finder(), { reset_prompt = true })
    end
  end

  pickers
    .new({}, {
      prompt_title = "书架 | <CR> 打开 | <C-d> 取消收藏 (i) | dd 取消收藏 (n)",
      finder = new_finder(),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)

          local value = action_state.get_selected_entry().value
          current_book = value.info

          Async.run(function()
            if not fetch_toc() then
              return
            end

            current_chap = current_toc[value.last_read]
            cook_content()
          end)
        end)

        map({ "n" }, "dd", function()
          unstar(prompt_bufnr)
        end)
        map({ "i" }, "<C-d>", function()
          unstar(prompt_bufnr)
        end)

        return true
      end,
    })
    :find()
end

return M
