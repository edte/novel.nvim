local M = {}

---@param fn function
---@return function
function M.wrap(fn)
  return function(...)
    local this = assert(coroutine.running(), "Must called within a coroutine.")
    local ret = nil
    local args = { ... }
    table.insert(args, function(r)
      ret = r
      if coroutine.status(this) == "suspended" then
        coroutine.resume(this)
      end
    end)
    fn(unpack(args))
    coroutine.yield()
    return ret
  end
end

---@param fn function
function M.run(fn, ...)
  assert(coroutine.resume(coroutine.create(fn), ...))
end

---@param fn function
---@return function
function M.void(fn, ...)
  local args = vim.F.pack_len(...)
  return function()
    M.run(fn, vim.F.unpack_len(args))
  end
end

M.system = M.wrap(vim.system) ---@type async fun(cmd: string[], opts?: vim.SystemOpts): vim.SystemCompleted

M.input = M.wrap(vim.schedule_wrap(vim.ui.input)) ---@type async fun(opts?: table)

M.schedule = M.wrap(vim.schedule) ---@type async fun()

---@param t table
local function schedule_wrapper(t)
  return setmetatable({}, {
    __index = function(_, k)
      return function(...)
        if vim.in_fast_event() then
          M.schedule()
        end
        return t[k](...)
      end
    end,
  })
end

M.api = schedule_wrapper(vim.api)

M.fn = schedule_wrapper(vim.fn)

return M
