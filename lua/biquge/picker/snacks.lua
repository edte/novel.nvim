---@param opts biquge.picker.Opts
local function transform_items(opts)
  return vim
    .iter(opts.items)
    :map(function(item)
      return { value = item, text = opts.display(item) }
    end)
    :totable()
end

return {
  ---@param opts biquge.picker.Opts
  pick = vim.schedule_wrap(function(opts)
    local actions = vim.deepcopy(opts.actions)
    for k, action in pairs(actions or {}) do
      actions[k] = function(picker, item)
        action(picker, item.value)
      end
    end

    Snacks.picker.pick({
      items = transform_items(opts),
      format = function(item)
        return { { item.text, "SnacksPickerLabel" } }
      end,
      confirm = function(picker, item)
        picker:close()
        opts.confirm(picker, item.value)
      end,
      layout = { preview = false, layout = { title = opts.prompt } },
      win = { input = { keys = opts.keys } },
      actions = actions,
    })
  end),
  ---@param picker snacks.Picker
  ---@param opts biquge.picker.Opts
  refresh = function(picker, opts)
    picker.finder.items = transform_items(opts)
    picker:find()
  end,
}
