local wezterm = require("wezterm")
local act = wezterm.action

-- ※ update-right-status は wezterm.lua 側に統合済み

return {
  keys = {
    -- ワークスペース切り替え
    { key = "w", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }) },
    -- ワークスペース名変更
    {
      key = "$", mods = "LEADER",
      action = act.PromptInputLine({
        description = "(wezterm) Set workspace title:",
        action = wezterm.action_callback(function(win, pane, line)
          if line then wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line) end
        end),
      }),
    },
    -- 新規ワークスペース作成
    {
      key = "W", mods = "LEADER|SHIFT",
      action = act.PromptInputLine({
        description = "(wezterm) Create new workspace:",
        action = wezterm.action_callback(function(window, pane, line)
          if line then
            window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
          end
        end),
      }),
    },

    -- コマンドパレット
    { key = "p", mods = "ALT",        action = act.ActivateCommandPalette },
    { key = "p", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },

    -- ランチャーメニュー（config.launch_menuの一覧から選んで新規タブで開く）
    { key = "m", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS" }) },

    -- Muxドメイン"mux"へ明示的にアタッチ（閉じる前のタブが残っていれば復元される）
    -- ※ act.AttachDomain は文字列引数（ドメイン名）を取る。テーブルを渡すとLuaエラーになり
    --   設定ファイル全体の読み込みに失敗するので注意（2026-07-22に実際に踏んだ）。
    { key = "M", mods = "LEADER|SHIFT", action = act.AttachDomain("mux") },

    -- タブ移動
    { key = "Tab", mods = "CTRL",       action = act.ActivateTabRelative(1) },
    { key = "Tab", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },

    -- タブ入れ替え
    { key = "{", mods = "LEADER", action = act({ MoveTabRelative = -1 }) },
    { key = "}", mods = "LEADER", action = act({ MoveTabRelative =  1 }) },

    -- タブ新規作成・閉じる
    { key = "t", mods = "ALT", action = act({ SpawnTab = "CurrentPaneDomain" }) },
    { key = "w", mods = "ALT", action = act({ CloseCurrentTab = { confirm = true } }) },

    -- 最大化 / 元のサイズ をトグル（実処理は wezterm.lua の toggle-maximize）
    { key = "f", mods = "ALT", action = act.EmitEvent("toggle-maximize") },

    -- コピーモード
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },

    -- コピー・貼り付け
    { key = "c", mods = "ALT", action = act.CopyTo("Clipboard") },
    { key = "v", mods = "ALT", action = act.PasteFrom("Clipboard") },

    -- ペイン作成
    { key = "d", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "r", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },

    -- コーディング用レイアウトを新規タブで開く（左Neovim・右Claude Code）
    { key = "n", mods = "LEADER", action = act.EmitEvent("spawn-coding-tab") },

    -- KITプロキシ(kit_proxy)を設定した上でClaude Codeを新規タブで起動
    { key = "c", mods = "LEADER", action = act.EmitEvent("spawn-kit-proxy-claude") },

    -- ペインを閉じる
    { key = "x", mods = "LEADER", action = act({ CloseCurrentPane = { confirm = true } }) },

    -- ペイン移動
    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },

    -- ペイン選択・ズーム
    { key = "[", mods = "CTRL|SHIFT", action = act.PaneSelect },
    { key = "z", mods = "LEADER",     action = act.TogglePaneZoomState },

    -- フォントサイズ
    { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
    { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
    { key = "0", mods = "CTRL", action = act.ResetFontSize },

    -- タブ番号で切替
    { key = "1", mods = "ALT", action = act.ActivateTab(0) },
    { key = "2", mods = "ALT", action = act.ActivateTab(1) },
    { key = "3", mods = "ALT", action = act.ActivateTab(2) },
    { key = "4", mods = "ALT", action = act.ActivateTab(3) },
    { key = "5", mods = "ALT", action = act.ActivateTab(4) },
    { key = "6", mods = "ALT", action = act.ActivateTab(5) },
    { key = "7", mods = "ALT", action = act.ActivateTab(6) },
    { key = "8", mods = "ALT", action = act.ActivateTab(7) },
    { key = "9", mods = "ALT", action = act.ActivateTab(-1) },

    -- 設定再読み込み
    { key = "r", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },

    -- キーテーブル起動
    { key = "s", mods = "LEADER", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
    { key = "a", mods = "LEADER", action = act.ActivateKeyTable({ name = "activate_pane", timeout_milliseconds = 1000 }) },
  },

  key_tables = {
    resize_pane = {
      { key = "h",     action = act.AdjustPaneSize({ "Left",  5 }) },
      { key = "l",     action = act.AdjustPaneSize({ "Right", 5 }) },
      { key = "k",     action = act.AdjustPaneSize({ "Up",    5 }) },
      { key = "j",     action = act.AdjustPaneSize({ "Down",  5 }) },
      { key = "Enter", action = "PopKeyTable" },
    },
    activate_pane = {
      { key = "h", action = act.ActivatePaneDirection("Left") },
      { key = "l", action = act.ActivatePaneDirection("Right") },
      { key = "k", action = act.ActivatePaneDirection("Up") },
      { key = "j", action = act.ActivatePaneDirection("Down") },
    },
    copy_mode = {
      { key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
      { key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
      { key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
      { key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
      { key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
      { key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
      { key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
      { key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
      { key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
      { key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
      { key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
      { key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
      { key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
      { key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
      { key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
      { key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
      { key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
      { key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage =  0.5 }) },
      { key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
      { key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
      { key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
      { key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
      { key = "y", mods = "NONE", action = act.CopyTo("Clipboard") },
      {
        key = "Enter", mods = "NONE",
        action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
      },
      { key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
      { key = "c",      mods = "CTRL", action = act.CopyMode("Close") },
      { key = "q",      mods = "NONE", action = act.CopyMode("Close") },
    },
  },
}
