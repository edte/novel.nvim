-- 测试所有书籍阅读位置记录功能
local biquge = require('biquge')

-- 设置测试配置
biquge.setup({
  width = 30,
  height = 5,
  hlgroup = 'Comment',
  bookshelf = '/tmp/test_bookshelf.json',
  reading_history = '/tmp/test_reading_history.json',
  last_reading = '/tmp/test_last_reading.json',
  picker = "builtin",
  local_dir = vim.fn.expand('~') .. '/Documents',
})

print("biquge.nvim 所有书籍阅读位置记录测试")
print("=====================================")
print("新功能说明:")
print("✅ 所有书籍（包括未收藏的）都会自动记录阅读位置")
print("✅ 每本书都有独立的阅读历史记录")
print("✅ 支持查看完整的阅读历史")
print("")
print("测试步骤:")
print("1. 打开多本不同的书籍阅读")
print("2. 在每本书中滚动到不同位置")
print("3. 使用 reading_history() 查看所有阅读记录")
print("4. 从历史记录中选择任意书籍，会自动恢复到上次位置")
print("")
print("可用命令:")
print(":lua require('biquge').local_browse() -- 打开本地文件")
print(":lua require('biquge').search() -- 搜索在线小说")
print(":lua require('biquge').reading_history() -- 查看阅读历史")
print(":lua require('biquge').resume_last_reading() -- 恢复最后阅读")
print("")
print("数据文件位置:")
print("- 阅读历史: /tmp/test_reading_history.json")
print("- 书架: /tmp/test_bookshelf.json")
print("- 最后阅读: /tmp/test_last_reading.json")