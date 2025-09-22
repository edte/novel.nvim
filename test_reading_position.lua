-- 测试阅读位置记录和恢复功能
local biquge = require('biquge')

-- 设置测试配置
biquge.setup({
  width = 30,
  height = 5,
  hlgroup = 'Comment',
  bookshelf = '/tmp/test_bookshelf.json',
  last_reading = '/tmp/test_last_reading.json',
  picker = "builtin",
  local_dir = vim.fn.expand('~') .. '/Documents',
})

print("biquge.nvim 阅读位置功能测试")
print("================================")
print("可用的测试命令:")
print("1. :lua require('biquge').local_browse() -- 浏览本地文件")
print("2. :lua require('biquge').resume_last_reading() -- 恢复上次阅读")
print("3. :lua require('biquge').toggle() -- 显示/隐藏")
print("4. :lua require('biquge').scroll(1) -- 向下滚动")
print("5. :lua require('biquge').scroll(-1) -- 向上滚动")
print("")
print("功能说明:")
print("- 阅读时会自动保存当前位置（章节+行号）")
print("- 退出 Neovim 时自动保存最后阅读记录")
print("- 使用 resume_last_reading() 可恢复到上次阅读位置")
print("- 从书架打开书籍时会自动恢复到上次阅读位置")