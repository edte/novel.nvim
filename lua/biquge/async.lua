local Async = require("plenary.async")

Async.system = Async.wrap(vim.system, 3)

Async.input = Async.wrap(vim.schedule_wrap(vim.ui.input), 2)

Async.fn = setmetatable({}, {
  __index = function(_, k)
    return function(...)
      if vim.in_fast_event() then
        Async.util.scheduler()
      end

      return vim.fn[k](...)
    end
  end,
})

return Async
