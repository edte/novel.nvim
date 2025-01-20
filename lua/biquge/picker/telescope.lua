local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

---@param opts BiqugePickerOpts
local function new_finder(opts)
  return finders.new_table({
    results = opts.items,
    entry_maker = function(item)
      local text = opts.display(item)
      return {
        value = item,
        display = text,
        ordinal = text,
      }
    end,
  })
end

return {
  ---@param opts BiqugePickerPickOpts
  pick = vim.schedule_wrap(function(opts)
    pickers
      .new({}, {
        prompt_title = opts.prompt,
        finder = new_finder(opts),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            opts.confirm(action_state.get_current_picker(prompt_bufnr), action_state.get_selected_entry().value)
          end)

          for key, mapping in pairs(opts.keys or {}) do
            map(type(mapping) == "string" and "n" or mapping.mode, key, function()
              opts.actions[type(mapping) == "string" and mapping or mapping[1]](
                action_state.get_current_picker(prompt_bufnr),
                action_state.get_selected_entry().value
              )
            end)
          end

          return true
        end,
      })
      :find()
  end),
  ---@param picker Picker
  ---@param opts BiqugePickerRefreshOpts
  refresh = vim.schedule_wrap(function(picker, opts)
    picker:refresh(new_finder(opts), { reset_prompt = true })
  end),
}
