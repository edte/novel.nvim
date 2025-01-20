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

* 支持小说搜索
* virtual text 显示小说内容，放心摸鱼
* 支持收藏小说，收藏的小说将记录阅读进度（精度仅限章节）

## 依赖

* Neovim >= 0.10.0
* curl

## 安装

💤 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'v1nh1shungry/biquge.nvim',
    dependencies = {
        'nvim-lua/plenary.nvim',
        'nvim-telescope/telescope.nvim', -- optional for telescope picker
        "folke/snacks.nvim", -- optional for snacks picker
    },
    keys = {
        { '<Leader>b/', function() require('biquge').search() end, desc = 'Search' },
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
    -- * builtin: vim.ui.select
    -- * telescope
    -- * snacks
    picker = "builtin",
}
```

## 使用

|       API      |                描述                |
|:--------------:|:----------------------------------:|
|    search()    |          根据书名搜索小说          |
|      toc()     |              打开目录              |
|     show()     |       在当前光标所在位置显示       |
|     hide()     |                隐藏                |
|    toggle()    |              显示/隐藏             |
| scroll(offset) | 向下滚动offset行（负数时向上滚动） |
|     star()     |                收藏                |
|   next_chap()  |              下一章节              |
|   prev_chap()  |              上一章节              |
|   bookshelf()  |              查看书架              |

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
