-- Windows日本語対策
vim.scriptencoding = "utf-8"
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"

-- 外部通信文字コード固定
vim.opt.fileencodings = "utf-8,cp932"
if vim.fn.has("win32") == 1 then
  vim.g.stdin_encoding = "utf-8"
  vim.g.stdout_encoding = "utf-8"
  vim.g.stderr_encoding = "utf-8"
end

vim.opt.number = true        -- 左端に行番号を表示
vim.opt.cursorline = true    -- カーソルがある行の背景を少し明るくする（VSCode風）
vim.opt.autochdir = true

-- キーマップ（\ ＋ t でツリー開閉、\ ＋ w でサイズ変更モード）
vim.g.mapleader = "\\"
vim.keymap.set('n', '<leader>t', ':NvimTreeToggle<CR>', { silent = true })
vim.keymap.set('n', '<leader>w', ':WinResizerStartResize<CR>', { silent = true })
vim.keymap.set('n', '<leader>d', ':Dashboard<CR>', { silent = true })
vim.keymap.set('n', '<leader>f', ':Telescope find_files no_ignore=true hidden=true<CR>', { silent = true })

-- ターミナルを開いたとき、またはターミナルバッファに入ったときに自動で最下部にスクロールし、インサートモードにする
vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
  pattern = "term://*",
  callback = function()
    -- 念のため現在のバッファがターミナルかチェック
    if vim.bo.buftype == "terminal" then
      -- 最下行（最新のログ位置）にカーソルを移動
      local current_win = vim.api.nvim_get_current_win()
      local last_line = vim.api.nvim_buf_line_count(0)
      vim.api.nvim_win_set_cursor(current_win, { last_line, 0 })
      
      -- インサートモード（追従モード）を開始
      vim.cmd("startinsert")
    end
  end,
})

-- lazy.nvimの自動インストール
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- プラグインの設定
require("lazy").setup({
-- nvim-notify (透過背景時の警告回避)
  {
    "rcarriga/nvim-notify",
    config = function()
      require("notify").setup({
        background_colour = "#000000",
      })
    end
  },
-- 1. Telescopeの設定 (ファイル検索)
  {
    'nvim-telescope/telescope.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      require('telescope').setup({
        defaults = {
          -- ★追加: プレビュー画面でのTreesitter色付けを無効化し、クラッシュを完全に防ぐ
          preview = {
            treesitter = false,
          },
          -- 画像やバイナリファイル、MATLABの一時ファイルを除外
          -- file_ignore_patterns = {
          --   "%.png", "%.PNG", "%.jpg", "%.JPG", "%.jpeg", "%.JPEG",
          --   "%.gif", "%.GIF", "%.webp", "%.zip", "%.ZIP",
          --   "%.exe", "%.dll", "%.pdf", "%.PDF",
          --   "%.xlsx", "%.xls", "%.doc", "%.docx",
          --   "%.dat", "%.mat", "_temp_matlab", 
          --   "node_modules", "%.git"
          -- },
        }
      })
    end
  },

-- 2. Dashboardの設定 (起動画面)
  {
    'nvimdev/dashboard-nvim',
    event = 'VimEnter',
    config = function()
      require('dashboard').setup({
        theme = 'hyper',
        config = {
          week_header = { enable = true },
          
          project = {
            enable = true,
            action = function(path)
              require("telescope.builtin").find_files({ cwd = path })
            end,
          },
          
          shortcut = {
            { desc = 'New File', group = 'DashboardShortCut', action = 'ene | startinsert', key = 'n' },
            { desc = 'Find File', group = 'DashboardShortCut', action = 'Telescope find_files', key = 'f' },
            { desc = 'Lazy', group = 'DashboardShortCut', action = 'Lazy', key = 'l' },
            { desc = 'Quit', group = 'DashboardShortCut', action = 'qa', key = 'q' },
          },
        },
      })
    end,
  },

  -- 3. nvim-tree.lua の設定 (ファイルツリー)
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    priority = 1000,
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        sort = { sorter = "case_sensitive" },
        view = { width = 30 },
        renderer = { group_empty = true },
        filters = { dotfiles = false },
      })
    end,
  },

  -- 4. winresizer の設定 (ウィンドウサイズ変更)
  {
    "simeji/winresizer",
    lazy = false,
  },

  -- 5. nvim-treesitter の設定 (VSCodeのような単語の色付け)
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function ()
      local ok, configs = pcall(require, "nvim-treesitter.configs")
      if not ok then return end
      
      configs.setup({
        ensure_installed = { "c", "cpp", "lua", "vim", "vimdoc", "javascript", "html", "css", "python" , "java" },
        sync_install = false,
        highlight = { enable = true },
        indent = { enable = true },
      })
    end
  },

  -- 6. vscode.nvim の設定 (全体のテーマをVSCode風にする)
  {
    "Mofiqul/vscode.nvim",
    priority = 1000,
    config = function()
      vim.cmd.colorscheme "vscode"
    end
  },

  -- 7. nvim-cmp の設定 (タブ補完機能)
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-buffer",       
      "hrsh7th/cmp-path",         
      "hrsh7th/cmp-nvim-lsp",     
      "L3MON4D3/LuaSnip",         
      "saadparwaiz1/cmp_luasnip", 
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      cmp.setup({
        snippet = {
          expand = function(args) luasnip.lsp_expand(args.body) end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { 'i', 's' }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'path' },
        })
      })
    end
  },

  -- 8. nvim-autopairs (カッコの自動入力)
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = true
  },

  -- 9. gitsigns.nvim (Gitの変更箇所表示)
  {
    "lewis6991/gitsigns.nvim",
    config = true
  },

  -- 10. Comment.nvim (簡単コメントアウト)
  {
    "numToStr/Comment.nvim",
    config = true
  },

-- 11. Mason & LSPConfig (エラー検知・定義ジャンプ・高精度補完)
  {
    "williamboman/mason.nvim",
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "neovim/nvim-lspconfig",
    },
    config = function()
      local ok_mason, mason = pcall(require, "mason")
      if not ok_mason then return end
      mason.setup()

      local ok_mason_lsp, mason_lsp = pcall(require, "mason-lspconfig")
      if not ok_mason_lsp then return end

      mason_lsp.setup({
        ensure_installed = { "pyright", "clangd", "ts_ls", "html", "cssls", "lua_ls" , "jdtls"}
      })
      
      local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
      local ok_cmp_lsp, cmp_lsp = pcall(require, 'cmp_nvim_lsp')
      if not (ok_lspconfig and ok_cmp_lsp) then return end

      local capabilities = cmp_lsp.default_capabilities()
      
      if type(mason_lsp.setup_handlers) == "function" then
        mason_lsp.setup_handlers({
          function(server_name)
            lspconfig[server_name].setup({
              capabilities = capabilities
            })
          end,
        })
      end
    end
  },
-- 12. lualine.nvim (ステータスラインの表示: 行・列番号、ファイル形式など)
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('lualine').setup({
        options = {
          theme = 'vscode', 
        },
        sections = {
          lualine_x = { 'encoding', 'fileformat', 'filetype' },
          lualine_y = { 
            'progress', 
            function()
              return vim.fn.wordcount().chars .. ' 文字'
            end
          },
          lualine_z = { 
            'location',
            function()
              return os.date('%H:%M:%S') -- 秒まで表示したい場合は '%H:%M:%S'
            end
          }
        }
      })
    end
  },-- 12. bufferline.nvim (上部のタブ表示)
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
      vim.opt.termguicolors = true
      require("bufferline").setup({
        options = {
          -- VSCodeに似たシンプルな見た目にする
          indicator = { style = 'none' },
          show_buffer_close_icons = true,
          show_close_icon = false,
        }
      })
      -- Shift + h / l でタブを左右に切り替えるショートカット
      vim.keymap.set('n', '<S-h>', '<Cmd>BufferLineCyclePrev<CR>', { silent = true })
      vim.keymap.set('n', '<S-l>', '<Cmd>BufferLineCycleNext<CR>', { silent = true })
    end
  },

  -- 13. indent-blankline.nvim (インデントの縦線表示)
-- 13. indent-blankline.nvim (インデントの縦線表示)
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    config = function()
      require("ibl").setup({
        exclude = {
          -- ダッシュボードや設定画面などでは縦線を無効化する
          filetypes = { "dashboard", "NvimTree", "lazy", "mason", "toggleterm" },
        }
      })
    end
  },

  -- 14. neoscroll.nvim (滑らかなスクロールアニメーション)
  {
    "karb94/neoscroll.nvim",
    config = function()
      require('neoscroll').setup({
        -- アニメーションの速度調整（ミリ秒）
        hide_cursor = true,          
        stop_eof = true,             
        respect_scrolloff = false,   
        cursor_scrolls_alone = true, 
      })
    end
  },

  -- 15. toggleterm.nvim (フローティングターミナル)
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      require("toggleterm").setup({
        -- Ctrl + \ でターミナルを開閉する
        open_mapping = [[<C-\>]],
        direction = 'float', -- 画面中央に浮かせる設定
        float_opts = {
          border = 'curved',
        },
      })
    end
  },
-- 16. auto-save.nvim (オートセーブ)
  {
    "okuuva/auto-save.nvim",
    cmd = "ASToggle", 
    event = { "InsertLeave", "TextChanged" }, 
    config = function()
      -- 廃止された execution_message のブロックを削除し、デフォルト設定のみにします
      require("auto-save").setup({})
    end,
  },

  -- 17. nvim-ts-autotag (HTML/XMLタグの自動補完)
  {
    "windwp/nvim-ts-autotag",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("nvim-ts-autotag").setup()
    end,
  },

  -- 18. nvim-colorizer.lua (カラーコードの色付け)
  {
    "NvChad/nvim-colorizer.lua",
    event = "BufReadPre",
    config = function()
      require("colorizer").setup({
        filetypes = { "*", "!dashboard", "!lazy" }, -- ダッシュボードや設定画面では無効化
        user_default_options = {
          RGB = true,
          RRGGBB = true,
          names = false,
          RRGGBBAA = true,
          css = true,
          css_fn = true,
          mode = "background", -- 背景色として実際の色を表示
        },
      })
    end,
  },
-- 19. lspkind.nvim (補完メニューのアイコン表示)
  {
    "onsails/lspkind.nvim",
    config = function()
      local cmp = require("cmp")
      local lspkind = require("lspkind")
      
      -- 既存のcmpの設定にformattingを上書き/追加する形になります
      cmp.setup({
        formatting = {
          format = lspkind.cmp_format({
            mode = 'symbol_text', -- アイコンとテキストの両方を表示
            maxwidth = 50,
          })
        }
      })
    end
  },

  -- 20. todo-comments.nvim (TODOなどの強調)
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("todo-comments").setup()
    end
  },

  -- 21. noice.nvim (滑らかなポップアップUIとアニメーション)
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    config = function()
      require("noice").setup({
        lsp = {
          override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
            ["cmp.entry.get_documentation"] = true,
          },
        },
        presets = {
          bottom_search = true,
          command_palette = true, -- 中央に浮かび上がるコマンドパレット
          long_message_to_split = true,
          inc_rename = false,
          lsp_doc_border = false,
        },
      })
    end
  },
-- 22. Catppuccin (カラースキーム) と背景透過設定
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        -- ★ ここで背景透過を有効化します
        transparent_background = true,
        
        -- 必要に応じて、特定のプラグインUIも透過させる設定
        integrations = {
          cmp = true,
          gitsigns = true,
          nvimtree = true,
          telescope = true,
          notify = false,
          mini = true,
        },
      })
      
      -- フレーバーは latte, frappe, macchiato, mocha から選べます（デフォルトは一番暗い mocha）
      vim.cmd.colorscheme "catppuccin"
    end
  },
-- 23. transparent.nvim (すべての背景色を強制クリアして透過させる)
  {
    "xiyaowong/transparent.nvim",
    config = function()
      require("transparent").setup({
        -- 標準機能に加えて、ダッシュボードやツリー画面の背景も透過対象に指定
        extra_groups = {
          "NormalFloat",
          "NvimTreeNormal",
          "NvimTreeNormalNC",
          "DashboardNormal",
          "TelescopeNormal",
          "TelescopeBorder",
        },
      })
      -- 起動時に自動で透過を有効化
      vim.cmd("TransparentEnable")
    end
  },
-- 24. mini.animate (究極の滑らかアニメーション)
-- 既存の mini.animate の設定を以下のように変更
  {
  "echasnovski/mini.animate",
  version = "*",
  config = function()
    require("mini.animate").setup({
      cursor = { enable = false }, -- smear-cursorと競合するためオフにする
    })
  end
  },
-- 新しくこれを追加
  {
  "sphamba/smear-cursor.nvim",
  event = "VeryLazy",
  opts = {
    -- 好みに応じて色などを変更可能（デフォルトでも十分綺麗です）
    cursor_color = "none", -- カラースキームの色に自動で合わせる
  },
  },
  -- 24. twilight.nvim (集中力を高めるコードの暗転)
  {
    "folke/twilight.nvim",
    config = function()
      require("twilight").setup({
        dimming = {
          alpha = 0.25, -- 暗くする度合い（0.0 〜 1.0）
        }
      })
    end
  },
-- 25. vim-illuminate (カーソル下の単語をハイライト)
  {
    "RRethy/vim-illuminate",
    config = function()
      require('illuminate').configure({
        providers = { 'lsp', 'treesitter', 'regex' },
      })
    end
  },

  -- 26. nvim-scrollbar (エラーや変更がわかるスクロールバー)
  {
    "petertriho/nvim-scrollbar",
    config = function()
      require("scrollbar").setup()
    end
  },

  -- 27. mini.indentscope (アニメーションするインデントガイド)
  {
    "echasnovski/mini.indentscope",
    version = "*",
    config = function()
      require("mini.indentscope").setup({
        symbol = "│",
        options = { try_as_border = true },
      })
    end
  },
-- 27. mini.indentscope (アニメーションするインデントガイド)
  {
    "echasnovski/mini.indentscope",
    version = "*",
    config = function()
      require("mini.indentscope").setup({
        symbol = "│",
        options = { try_as_border = true },
      })
    end
  }, -- ←★ここにカンマ(,)を追記します

-- 28. vim-quickrun (プログラムの即時実行)
  {
    "thinca/vim-quickrun",
    config = function()
      vim.g.quickrun_config = {
        ["_"] = {
          outputter = "buffer",
          ["outputter/buffer/split"] = ":botright 8sp", 
          ["outputter/buffer/close_on_empty"] = 1,
        },
        -- ★ここを修正: 配列形式に戻し、Java側から強制的にUTF-8を出力させる
        ["java"] = {
          exec = {
            "javac -encoding UTF-8 %s",
            "java -Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 -cp \"%s:p:h\" %s:t:r"
          }
        }
      }
      -- \ ＋ r でQuickRunを実行するショートカット
      vim.keymap.set('n', '<leader>r', ':QuickRun<CR>', { silent = true })
    end
  },
-- 29. barbecue.nvim (ステータスラインにファイルパスを表示) 
  {
  "utilyre/barbecue.nvim",
  name = "barbecue",
  version = "*",
  dependencies = {
    "SmiteshP/nvim-navic",
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("barbecue").setup({
      theme = "catppuccin", -- すでに導入済みのcatppuccinテーマと同期
    })
  end,
  },
-- 30. render-markdown.nvim (Markdownのプレビュー)
  {
  "MeanderingProgrammer/render-markdown.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" }, -- あなたの環境なら依存関係はバッチリです
  ft = { "markdown" }, -- Markdownファイルを開いたときだけ動く（軽量）
  opts = {},
  },
-- 31. colorful-winsep.nvim (ウィンドウの境界線をカラフルにする)
  {
  "nvim-zh/colorful-winsep.nvim",
  config = function()
    require("colorful-winsep").setup()
  end,
  event = { "WinNew" },
  },
})
