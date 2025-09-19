<h1 align="center">biquge.nvim</h1>

在Neovim里看小说！

![](https://github.com/v1nh1shungry/biquge.nvim/assets/98312435/158a13b5-2af2-4e16-9caf-0c6d8e858829)

本项目启发自[z-reader](https://github.com/aooiuu/z-reader)。但我时常觉得直接在 vscode 里打开一个窗口看小说实在是太过
明目张胆，在工位上瑟瑟发抖~

本插件在光标所在位置以virtual text 的形式插入小说内容，将高亮设置为注释后，就可以完美cosplay 注释了:) virtual text 也不
会污染buffer 的内容。

## 目录

<!-- markdown-toc -->
* [功能](#功能)
* [依赖](#依赖)
* [安装](#安装)
* [配置](#配置)
* [使用](#使用)
  * [书架 Telescope 热键](#书架-Telescope-热键)
* [宇宙安全声明](#宇宙安全声明)
<!-- markdown-toc -->

## 功能

* 支持在线小说搜索
* 支持本地 TXT 文件阅读
* virtual text 显示小说内容，放心摸鱼
* 支持收藏小说，收藏的小说将记录阅读进度（精度仅限章节）
* 智能章节识别（支持多种标题格式）

## 依赖

* Neovim >= 0.10.0
* curl

## 安装

💤 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'v1nh1shungry/biquge.nvim',
    dependencies = {
        'nvim-telescope/telescope.nvim', -- optional for telescope picker
        "folke/snacks.nvim", -- optional for snacks picker
    },
    keys = {
        { '<Leader>b/', function() require('biquge').search() end, desc = 'Search online' },
        { '<Leader>bf', function() require('biquge').local_search() end, desc = 'Open local file' },
        { '<Leader>bd', function() require('biquge').local_browse() end, desc = 'Browse local directory' },
        { '<Leader>bb', function() require('biquge').toggle() end, desc = 'Toggle' },
        { '<Leader>bt', function() require('biquge').toc() end, desc = 'Toc' },
        { '<Leader>bn', function() require('biquge').next_chap() end, desc = 'Next chapter' },
        { '<Leader>bp', function() require('biquge').prev_chap() end, desc = 'Previous chapter' },
        { '<Leader>bs', function() require('biquge').star() end, desc = 'Star current book' },
        { '<Leader>bl', function() require('biquge').bookshelf() end, desc = 'Bookshelf' },
        { '<M-d>', function() require('biquge').scroll(1) end, desc = 'Scroll down' },
        { '<M-u>', function() require('biquge').scroll(-1) end, desc = 'Scroll up' },
    },
    opts = {},
}
```

## 配置

**使用插件前必须调用`require('biquge').setup`!**

```lua
-- 默认配置
{
    width = 30, -- 显示文本的宽度（字数）
    height = 10, -- 显示文本的行数
    hlgroup = 'Comment', -- 高亮组
    bookshelf = vim.fs.joinpath(vim.fn.stdpath('data'), 'biquge_bookshelf.json'), -- 书架存储路径
    local_dir = vim.fs.joinpath(vim.fn.expand('~'), 'Documents'), -- 本地文件默认目录
    -- * builtin: vim.ui.select
    -- * telescope
    -- * snacks
    picker = "builtin",
}
```

## 使用

|       API        |                描述                |
|:----------------:|:----------------------------------:|
|     search()     |          根据书名搜索小说          |
|  local_search()  |          打开本地 TXT 文件         |
|  local_browse()  |        浏览本地文件目录           |
|       toc()      |              打开目录              |
|      show()      |       在当前光标所在位置显示       |
|      hide()      |                隐藏                |
|     toggle()     |              显示/隐藏             |
|  scroll(offset)  | 向下滚动offset行（负数时向上滚动） |
|      star()      |                收藏                |
|    next_chap()   |              下一章节              |
|    prev_chap()   |              上一章节              |
|    bookshelf()   |              查看书架              |

### 本地文件支持

插件现在支持阅读本地 TXT 文件！功能特点：

* **智能章节识别**：自动识别多种章节标题格式
  - `第X章 标题` (支持中文数字和阿拉伯数字)
  - `Chapter X 标题`
  - `1. 标题` 或 `一、标题`
* **完整功能支持**：本地文件享有与在线小说相同的功能
  - 章节导航、书签、进度保存
  - Virtual text 显示
  - 书架管理（标识为 `[本地]`）

**使用方法**：

**方法一：浏览目录（推荐）**
1. 调用 `require('biquge').local_browse()`
2. 从默认目录中选择 TXT 文件
3. 自动加载并显示章节目录

**方法二：手动输入路径**
1. 调用 `require('biquge').local_search()`
2. 输入文件路径：
   - 绝对路径：`/path/to/novel.txt`
   - 相对路径：`novel.txt`（优先在默认目录中查找）
   - 家目录：`~/Documents/novel.txt`
3. 插件自动解析章节并显示目录

**默认目录**：`~/Documents`（可在配置中修改 `local_dir`）

### 书架热键

**NOTE: builtin picker does not support any following keymaps.**

|   热键   | 模式 |        描述        |
|:--------:|:----:|:------------------:|
|  &lt;CR> | i, n | 在上次阅读章节打开 |
| &lt;C-d> |   i  |      取消收藏      |
|    dd    |   n  |      取消收藏      |

## 宇宙安全声明

* 该软件仅供学习交流使用, 禁止个人用于非法商业用途, 请于安装后 24 小时内删除
* 所有资源来自网上, 该软件不参与任何制作, 上传, 储存等内容, 禁止传播违法资源
* 请支持正版，我起点已经lv.7了
