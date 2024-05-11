local M = {}

local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values
local action_state = require('telescope.actions.state')
local actions = require('telescope.actions')

local DOMAIN = 'http://www.xbiquzw.com'

local active = false

---@type BookItem
local current_book = nil

---@type ChapItem[]
local current_toc = nil

---@type ChapItem
local current_chap = nil

---@type string[]
local current_content = nil

local begin_index, end_index = -1, -1

---@class Position
---@field bufnr integer
---@field row integer
---
---@type Position
local current_position = nil

local current_extmark_id = -1

---@class Config
---@field width integer
---@field height integer
---@field hlgroup string
---
---@type Config
local config = {
  width = 30,
  height = 10,
  hlgroup = 'Comment',
}

M.setup = function(opts)
  config = vim.tbl_extend('force', config, opts)
end

local function notify(msg, level)
  vim.notify(msg, level, { title = 'biquge.nvim' })
end

local function info(msg)
  notify(msg, vim.log.levels.INFO)
end

local function warn(msg)
  notify(msg, vim.log.levels.WARN)
end

local function error(msg)
  notify(msg, vim.log.levels.ERROR)
end

---@param text string
local function normalize(text)
  return text:gsub('&nbsp;', ' '):gsub('<br%s*/>', '\n'):gsub('\r\n', '\n')
end

---@param text string
---@return string[]
local function get_content(text)
  local normalized = normalize(text)
  local parser = vim.treesitter.get_string_parser(normalized, 'html')
  local root = parser:parse()[1]:root()
  local q = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag
    (tag_name) @tag_name
    (attribute
      (attribute_name) @attr_name
      (quoted_attribute_value
        (attribute_value) @attr_value))) @start_tag
  (#eq? @tag_name "div")
  (#eq? @attr_name "id")
  (#eq? @attr_value "content"))
  ]]
  )
  for id, node in q:iter_captures(root, normalized) do
    local capture = q.captures[id]
    if capture == 'start_tag' then
      local sibling = node
      repeat
        sibling = sibling:next_sibling()
      until sibling == nil or sibling:type() == 'text'
      if sibling then
        return vim.split(vim.treesitter.get_node_text(sibling, normalized), '\n')
      end
    end
  end
  return {}
end

---@class ChapItem
---@field link string
---@field title string
---
---@param text string
---@return ChapItem[]
local function get_toc(text)
  local normalized = normalize(text)
  local parser = vim.treesitter.get_string_parser(normalized, 'html')
  local root = parser:parse()[1]:root()

  local start_query = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag (tag_name) @tag_name) @start_tag
  (#eq? @tag_name "dl"))
  ]]
  )

  ---@type TSNode
  local dl_tag
  for id, node in start_query:iter_captures(root, normalized) do
    local capture = start_query.captures[id]
    if capture == 'start_tag' then
      dl_tag = node
      break
    end
  end

  if dl_tag == nil then
    return {}
  end

  local item_query = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag
    (tag_name) @tag_name
    (attribute
      (attribute_name) @href_name
      (quoted_attribute_value
        (attribute_value) @href_value))
    (attribute
      (attribute_name) @title_name
      (quoted_attribute_value
        (attribute_value) @title_value)))
  (#eq? @tag_name "a")
  (#eq? @href_name "href")
  (#eq? @title_name "title"))
  ]]
  )

  ---@type ChapItem[]
  local res = {}
  local parent = dl_tag:parent()
  for _, match in item_query:iter_matches(parent, normalized, parent:start(), parent:end_(), { all = true }) do
    local record = {}
    for id, nodes in pairs(match) do
      local name = item_query.captures[id]
      for _, node in ipairs(nodes) do
        if name == 'href_value' then
          record.link = vim.treesitter.get_node_text(node, normalized)
        elseif name == 'title_value' then
          record.title = vim.treesitter.get_node_text(node, normalized)
        end
      end
    end
    res[#res + 1] = record
  end

  return res
end

---@class BookItem
---@field author string
---@field link string
---@field title string
---
---@param text string
---@return BookItem[]
local function get_books(text)
  local normalized = normalize(text)
  local parser = vim.treesitter.get_string_parser(normalized, 'html')
  local root = parser:parse()[1]:root()

  local grid_query = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag
    (tag_name) @tag_name
    (attribute
      (attribute_name) @attr_name
      (quoted_attribute_value) @attr_value)) @start_tag
  (#eq? @tag_name "table")
  (#eq? @attr_name "class")
  (#eq? @attr_value "\"grid\""))
  ]]
  )

  ---@type TSNode
  local grid_tag
  for id, node in grid_query:iter_captures(root, normalized) do
    local capture = grid_query.captures[id]
    if capture == 'start_tag' then
      grid_tag = node
      break
    end
  end

  if grid_tag == nil then
    return {}
  end

  local tr_query = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag
    (tag_name) @tag_name) @start_tag
  (#eq? @tag_name "tr"))
  ]]
  )

  local td_query = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag
    (tag_name) @tag_name
    (attribute
      (attribute_name) @attr_name
      (quoted_attribute_value) @attr_value)) @start_tag
  (#eq? @tag_name "td")
  (#eq? @attr_name "class")
  (#eq? @attr_value "\"odd\""))
  ]]
  )

  local elem_query = vim.treesitter.query.parse(
    'html',
    [[
(
  (start_tag
    (tag_name) @tag_name
    (attribute
      (attribute_name) @attr_name
      (quoted_attribute_value
        (attribute_value) @attr_value)))
  (#eq? @tag_name "a")
  (#eq? @attr_name "href"))

(text) @text
  ]]
  )

  ---@type BookItem[]
  local res = {}
  for i, ni in tr_query:iter_captures(grid_tag:parent(), normalized) do
    if tr_query.captures[i] == 'start_tag' and ni:named_child_count() == 1 then
      local item = {}
      for j, nj in td_query:iter_captures(ni:parent(), normalized) do
        if td_query.captures[j] == 'start_tag' and nj:named_child_count() == 2 then
          local sibling = nj:next_sibling()
          if sibling:type() == 'text' then
            item.author = vim.treesitter.get_node_text(sibling, normalized)
          elseif sibling:type() == 'element' then
            for k, nk in elem_query:iter_captures(sibling, normalized) do
              local name = elem_query.captures[k]
              if name == 'text' then
                item.title = vim.treesitter.get_node_text(nk, normalized)
              elseif name == 'attr_value' then
                item.link = vim.treesitter.get_node_text(nk, normalized)
              end
            end
          end
        end
      end
      res[#res + 1] = item
    end
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

local function cook_content()
  vim.system(
    {
      'curl',
      '--compressed',
      DOMAIN .. current_book.link .. current_chap.link,
    },
    { text = true },
    vim.schedule_wrap(function(obj)
      local content = get_content(obj.stdout)
      current_content = { '-- ' .. current_chap.title .. ' --' }
      for _, line in ipairs(content) do
        vim.list_extend(current_content, pieces(line))
      end
      current_content[#current_content + 1] = '-- 本章完 --'
      begin_index, end_index = 1, 1 + config.height
      M.show()
    end)
  )
end

local vt_ns = vim.api.nvim_create_namespace('biquge_virtual_text')

function M.show()
  if begin_index == -1 or end_index == -1 then
    warn('没有正在阅读的章节，请先搜索想要阅读的章节')
    return
  end
  current_position = {
    bufnr = vim.api.nvim_get_current_buf(),
    row = vim.api.nvim_win_get_cursor(0)[1] - 1,
  }
  local virt_lines = {}
  for _, line in ipairs(vim.list_slice(current_content, begin_index, end_index)) do
    virt_lines[#virt_lines + 1] = { { line, config.hlgroup } }
  end
  current_extmark_id = vim.api.nvim_buf_set_extmark(current_position.bufnr, vt_ns, current_position.row, 0, {
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
  vim.api.nvim_buf_clear_namespace(current_position.bufnr, vt_ns, 0, -1)
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
  local index = -1
  for i, item in ipairs(current_toc) do
    if item.title == current_chap.title and item.link == current_chap.link then
      index = i
    end
  end
  local target = index + offset
  if target < 1 or target > #current_toc then
    return
  end
  current_chap = current_toc[target]
  cook_content()
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

function M.toc()
  if current_book == nil then
    warn('没有正在阅读的小说，请先搜索想要阅读的小说')
    return
  end
  vim.system(
    {
      'curl',
      '--compressed',
      DOMAIN .. current_book.link,
    },
    { text = true },
    vim.schedule_wrap(function(obj)
      current_toc = get_toc(obj.stdout)
      pickers
        .new({}, {
          prompt_title = current_book.title .. ' - 目录',
          finder = finders.new_table {
            results = current_toc,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.title,
                ordinal = entry.title,
              }
            end,
          },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              current_chap = action_state.get_selected_entry().value
              cook_content()
            end)
            return true
          end,
        })
        :find()
    end)
  )
end

local function reset()
  M.hide()
  current_book = nil
  current_toc = {}
  current_chap = nil
  current_content = {}
  begin_index, end_index = -1, -1
  current_position = nil
  current_extmark_id = -1
end

M.search = function()
  reset()
  vim.ui.input({ prompt = '书名' }, function(input)
    if input == nil then
      return
    end
    vim.system(
      {
        'curl',
        '--compressed',
        DOMAIN .. '/modules/article/search.php?searchkey=' .. input:gsub(' ', '+'),
      },
      { text = true },
      vim.schedule_wrap(function(obj)
        local results = get_books(obj.stdout)
        pickers
          .new({}, {
            prompt_title = '搜索结果',
            finder = finders.new_table {
              results = results,
              entry_maker = function(entry)
                local display = entry.title .. ' - ' .. entry.author
                return {
                  value = entry,
                  display = display,
                  ordinal = display,
                }
              end,
            },
            sorter = conf.generic_sorter {},
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
    )
  end)
end

return M
