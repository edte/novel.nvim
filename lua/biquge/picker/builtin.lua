return {
  ---@param opts biquge.picker.Opts
  pick = vim.schedule_wrap(function(opts)
    vim.ui.select(opts.items, {
      prompt = opts.prompt,
      format_item = opts.display,
    }, function(item)
      if not item then
        return
      end

      opts.confirm(nil, item)
    end)
  end),
}
