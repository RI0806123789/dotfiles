local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.font = wezterm.font("JetBrainsMono Nerd Font Mono")
config.font_size = 9.5
config.use_ime = true

config.unix_domains = {
  { name = "mux" },
}

-- 透過・ぼかし
-- config.win32_system_backdrop = "Acrylic"
config.window_background_opacity = 0.9

-- レンダラー・パフォーマンス
config.front_end = "OpenGL"
config.max_fps = 60
config.animation_fps = 60

-- カーソル
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500
-- 点滅の出入りを滑らかなイージングにする（ぬるっとしたフェード）
config.cursor_blink_ease_in = "EaseIn"
config.cursor_blink_ease_out = "EaseOut"

-- ANSIエスケープ(\e[5m等)による点滅テキストも、カーソルと同じくイージングで滑らかにする
config.text_blink_rate = 500
config.text_blink_ease_in = "EaseIn"
config.text_blink_ease_out = "EaseOut"

-- カラースキーム
config.color_scheme = "Tokyo Night"

----------------------------------------------------
-- ハイパーリンク（クリックでURL/ファイルパスを開けるようにする）
----------------------------------------------------
-- 標準ルール（http/https, mailto等）をベースに、Windowsの絶対パスを開けるルールを追加する
config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, {
  regex = [[[A-Za-z]:\\(?:[^\s\\<>:"|?*]+\\)*[^\s\\<>:"|?*]+]],
  format = "file:///$0",
})

-- 余白
config.window_padding = {
  left = 10, right = 10,
  top = 5,   bottom = 5,
}

-- スクロールバー非表示
config.enable_scroll_bar = false

-- マウスバインディング（キーボード駆動が基本だが、右クリック貼り付けだけは残しておく）
config.mouse_bindings = {
  -- 右クリックでクリップボードの内容を貼り付け（テキスト選択中は選択範囲のコピー扱いになる）
  { event = { Down = { streak = 1, button = "Right" } }, mods = "NONE", action = wezterm.action.PasteFrom("Clipboard") },
}

-- ベル無効（音は鳴らさない）
config.audible_bell = "Disabled"

-- ビジュアルベル：ベル受信時に画面をふわっと点滅させて知らせる。
config.visual_bell = {
  fade_in_function     = "EaseIn",
  fade_in_duration_ms  = 100,
  fade_out_function    = "EaseOut",
  fade_out_duration_ms = 200,
  -- BackgroundColor: 背景色をフラッシュさせる。CursorColor にするとカーソルだけ点滅
  target = "BackgroundColor",
}

-- ⑥ 非アクティブペインを暗くする
config.inactive_pane_hsb = {
  saturation = 0.7,
  brightness  = 0.6,
}

-- スクロールバック行数
config.scrollback_lines = 10000

----------------------------------------------------
-- 起動時のウィンドウサイズ（画面に対する比率で決定）
----------------------------------------------------
-- 画面サイズに対する割合。大きくしたい/小さくしたい場合はここだけ触る
local WIDTH_RATIO  = 0.90
local HEIGHT_RATIO = 0.85

-- 画面の比率からサイズを決めて中央に配置する
local function apply_default_size(gui)
  -- アクティブなスクリーン（マルチモニタなら現在の作業画面）の情報を取得
  local screen = wezterm.gui.screens().active
  if not screen then
    return
  end

  local width  = math.floor(screen.width  * WIDTH_RATIO)
  local height = math.floor(screen.height * HEIGHT_RATIO)

  -- 内側（文字が描画される領域）のサイズを指定
  gui:set_inner_size(width, height)

  -- 画面中央に配置。screen.x/y はマルチモニタでの原点オフセット
  gui:set_position(
    screen.x + math.floor((screen.width  - width)  / 2),
    screen.y + math.floor((screen.height - height) / 2)
  )
end

wezterm.on("gui-startup", function(cmd)
  -- `wezterm start -- <prog>` の引数を引き継ぐ（無ければ default_prog が使われる）
  local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
  apply_default_size(window:gui_window())
end)

local maximized = {}

wezterm.on("toggle-maximize", function(window, pane)
  local id = tostring(window:window_id())
  if maximized[id] then
    -- 最大化前（＝起動時の比率サイズ）に戻す
    window:restore()
    maximized[id] = nil
  else
    window:maximize()
    maximized[id] = true
  end
end)

----------------------------------------------------
-- コーディング用レイアウトを新規タブで開く（左: Neovim / 右: Claude Code）
-- キーは keybinds.lua の Leader → N
----------------------------------------------------
wezterm.on("spawn-coding-tab", function(window, pane)
  local mux_window = window:mux_window()

  -- カレントディレクトリを引き継ぐ（取得できない場合はnilのままデフォルトに任せる）
  local cwd_uri = pane:get_current_working_dir()
  local cwd = cwd_uri and cwd_uri.file_path or nil

  -- 左ペイン: Neovim（現在のペインと同じドメインに新規タブを作成。
  -- 以前は domain = "mux" を指定していたが、別のmux接続を新規に張るため非同期になり、
  -- タブ生成直後のsend_textがシェル起動前に送られて失われる不具合があった。2026-07-23修正）
  local tab = mux_window:spawn_tab({ cwd = cwd, domain = "CurrentPaneDomain" })
  local left_pane = tab:active_pane()
  -- PowerShell(ConPTY)は\nだけではEnter確定と認識しないため\rを使う
  left_pane:send_text("nvim\r")

  -- 右ペイン: Claude Code（右側に幅35%で分割）
  local right_pane = left_pane:split({ direction = "Right", size = 0.35, cwd = cwd })
  right_pane:send_text("claude\r")

  left_pane:activate()
end)

----------------------------------------------------
-- KITプロキシ経由のコーディング用レイアウトを新規タブで開く
-- （左: Neovim / 右: kit_proxy設定済みのClaude Code）
-- キーは keybinds.lua の Leader → C
----------------------------------------------------
wezterm.on("spawn-kit-proxy-claude", function(window, pane)
  local mux_window = window:mux_window()

  local cwd_uri = pane:get_current_working_dir()
  local cwd = cwd_uri and cwd_uri.file_path or nil

  -- 左ペイン: Neovim（spawn-coding-tabと同様、CurrentPaneDomainで作成）
  local tab = mux_window:spawn_tab({ cwd = cwd, domain = "CurrentPaneDomain" })
  local left_pane = tab:active_pane()
  left_pane:send_text("nvim\r")

  -- 右ペイン: kit_proxy実行後にClaude Code（右側に幅35%で分割）
  local right_pane = left_pane:split({ direction = "Right", size = 0.35, cwd = cwd })

  -- kit_proxy.bat（C:\tools\kit_proxy.bat）はプロキシ環境変数を設定した後、
  -- `cmd /k` で新しいcmdシェルに常駐する設計。そのcmdシェルへの切り替えが
  -- 完了する前にclaudeを送るとPowerShell側に取りこぼされる。固定sleep(800ms)
  -- では新規タブのシェル起動時間のばらつきで間に合わないことが実測で確認できた
  -- （2026-07-23）ため、フォアグラウンドプロセスがcmd.exeになるまでポーリングで
  -- 待ってから送る（最大5秒、取得APIが使えない環境向けに2秒のフォールバックも兼ねる）。
  right_pane:send_text("kit_proxy\r")
  local switched = false
  for _ = 1, 50 do
    wezterm.sleep_ms(100)
    local ok, proc = pcall(function()
      return right_pane:get_foreground_process_name()
    end)
    if ok and proc and proc:lower():find("cmd.exe", 1, true) then
      switched = true
      break
    end
  end
  if not switched then
    wezterm.sleep_ms(2000)
  end
  right_pane:send_text("claude\r")

  left_pane:activate()
end)

----------------------------------------------------
-- バッテリー残量（wezterm.battery_info() の組み込みAPIを使用）
----------------------------------------------------
local function battery_color(ratio)
  if ratio <= 0.10 then
    return "#f7768e"  -- 赤：要充電
  elseif ratio <= 0.20 then
    return "#e0af68"  -- 黄：そろそろ充電
  end
  return "#9ece6a"    -- 緑：十分
end

-- Nerd Font のアイコン名を安全に引く（名前が無いバージョンでも落とさない）
local function nf(name, fallback)
  return wezterm.nerdfonts[name] or fallback
end

-- 残量と充電状態から表示するアイコンを決める
local function battery_icon(ratio, state)
  -- 10刻みに丸める（md_battery_10 〜 md_battery_90 が10刻みで存在するため）
  local step = math.floor(ratio * 10 + 0.5) * 10

  if state == "Charging" then
    if step >= 100 then
      return nf("md_battery_charging_100", "")
    end
    -- 0% は md_battery_charging_10 で代用（charging_0 は存在しない）
    return nf("md_battery_charging_" .. math.max(step, 10), "")
  end

  if step >= 100 then
    return nf("md_battery", "")
  elseif step <= 0 then
    return nf("md_battery_outline", "")
  end
  return nf("md_battery_" .. step, "")
end

-- バッテリーが無い環境（デスクトップ等）では nil を返して非表示にする
local function battery_text()
  local batteries = wezterm.battery_info()
  if #batteries == 0 then
    return nil
  end

  local b = batteries[1]
  local ratio = b.state_of_charge  -- 0.0 〜 1.0
  local percent = math.floor(ratio * 100 + 0.5)

  return battery_icon(ratio, b.state) .. " " .. percent .. "%", battery_color(ratio)
end

----------------------------------------------------
-- 今日の日付（年月日＋曜日）
----------------------------------------------------
-- strftime の %a は英語（Thu 等）になるため、曜日番号 %w から日本語へ変換する
local WEEKDAYS_JP = { "日", "月", "火", "水", "木", "金", "土" }

local function date_text()
  -- %w は 0=日曜 〜 6=土曜。Lua の配列は 1 始まりなので +1 する
  local wday = tonumber(wezterm.strftime("%w")) + 1
  return wezterm.strftime("%Y年%m月%d日") .. "（" .. WEEKDAYS_JP[wday] .. "）"
end

----------------------------------------------------
-- ⑨ 右ステータスバー（キーテーブル名 + バッテリー + 日付 + 時計）
--    ※keybinds.lua の update-right-status は削除済み
--    表示順は左から：TABLE → バッテリー → 日付 → 時計
----------------------------------------------------
wezterm.on("update-right-status", function(window, pane)
  -- 中身を丸ごとpcallで囲む。API名の打ち間違い等で例外が起きた場合、
  -- ここで止めないと以降のTABLE/バッテリー/日付/時計が軒並み描画されず右上が全消えする
  -- （2026-07-23、window:is_leader_active() の綴り間違いで実際に発生した）。
  -- 保険としてエラー時は赤字で内容を出す。
  local ok, err = pcall(function()
    local name = window:active_key_table()
    local time = wezterm.strftime("%H:%M")

    -- wezterm.format に渡す要素を左から順に積んでいく
    local cells = {}

    -- LEADER(Ctrl+Q)押下直後〜タイムアウトまでの間、視覚的にわかるようにする。
    -- これが無いとLEADERが効いているか操作者側から判別できず、押し方のミスに気づけない。
    if window:leader_is_active() then
      table.insert(cells, { Foreground = { Color = "#f7768e" } })  -- Tokyo Night 赤系
      table.insert(cells, { Text = "  LEADER   " })
    end

    -- シェルから OSC 1337 SetUserVar で送られたユーザー変数 "wz_status" を表示する。
    -- PowerShell 側の Set-WezVar 関数（$PROFILE に定義）で送信する想定。
    -- 値が空／未設定のときは何も出さない（＝送った時だけ左端に出る）。
    local user_status = pane:get_user_vars().wz_status
    if user_status and user_status ~= "" then
      table.insert(cells, { Foreground = { Color = "#bb9af7" } })  -- Tokyo Night 紫系
      table.insert(cells, { Text = "  " .. user_status .. "   " })
    end

    if name then
      table.insert(cells, { Foreground = { Color = "#888888" } })
      table.insert(cells, { Text = "  TABLE: " .. name .. "   " })
    end

    local batt, batt_color = battery_text()
    if batt then
      table.insert(cells, { Foreground = { Color = batt_color } })
      table.insert(cells, { Text = "  " .. batt .. "   " })
    end

    -- 日付（時計の左）。時計と区別しやすいよう Tokyo Night の青系で表示
    table.insert(cells, { Foreground = { Color = "#7aa2f7" } })
    table.insert(cells, { Text = date_text() .. "   " })

    -- 時計（一番右）。既存の見た目を維持するため灰色 + 末尾の余白
    table.insert(cells, { Foreground = { Color = "#888888" } })
    table.insert(cells, { Text = time .. "  " })

    window:set_right_status(wezterm.format(cells))
  end)

  if not ok then
    window:set_right_status(wezterm.format({
      { Foreground = { Color = "#f7768e" } },
      { Text = "  status error: " .. tostring(err) .. "  " },
    }))
  end
end)

config.status_update_interval = 1000

----------------------------------------------------
-- Tab
----------------------------------------------------
config.window_decorations = "RESIZE"
config.show_tabs_in_tab_bar = true
-- タブバー自体は常に表示する（false = 常時表示）。
-- hide_tab_bar_if_only_one_tab は右上のステータス（時計等）ごとバー全体を消してしまうため使わない。
-- タブが1つのときの見た目の非表示化は format-tab-title 側で行う
config.hide_tab_bar_if_only_one_tab = false

config.window_frame = {
  -- fancy tab bar（デフォルト有効）ではタブバーの背景はここで決まる。
  -- Tokyo Night のターミナル背景色(#1a1b26)に合わせて食い違いを解消する
  inactive_titlebar_bg = "#1a1b26",
  active_titlebar_bg = "#1a1b26",
  -- タブバーのフォントを本体と統一（バッテリー等のNerd Fontグリフも本体と同じ見た目になる）
  font = wezterm.font("JetBrainsMono Nerd Font Mono"),
}

config.show_new_tab_button_in_tab_bar = false
config.show_close_tab_button_in_tabs = false

-- ⑩ タブ境界線 + ペイン区切り線の色
config.colors = {
  -- カーソル色をステータスバーの青系(#7aa2f7)に統一。cursor_fgは背景色にして
  -- カーソルが重なった位置の文字が読めるようにする
  cursor_bg = "#7aa2f7",
  cursor_fg = "#1a1b26",
  cursor_border = "#7aa2f7",
  tab_bar = {
    -- タブが無い余白部分の背景色。Tokyo Night のターミナル背景色(#1a1b26)と揃えて
    -- タブバーとターミナル本体の色が食い違って見える問題を解消する
    background = "#1a1b26",
    inactive_tab_edge = "none",
  },
  split = "#444444",
  -- ビジュアルベルのフラッシュ色。背景(#1a1b26)より少し明るい青系にして、
  -- 派手すぎず気づける程度に。強めにしたいなら #7aa2f7(青) や #f7768e(赤) へ
  visual_bell = "#414868",
}

-- タブの形をカスタマイズ（半円グリフで両端を丸め、楕円＝ピル型にする）
local ROUND_LEFT_EDGE  = wezterm.nerdfonts.ple_left_half_circle_thick
local ROUND_RIGHT_EDGE = wezterm.nerdfonts.ple_right_half_circle_thick

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  -- タブが1つだけのときはタブの見た目（文字・ピル型背景）を消す。
  -- バー自体は消さないので、右上のステータス（時計・日付・バッテリー）は表示され続ける
  if #tabs <= 1 then
    return {
      { Background = { Color = "#1a1b26" } },
      { Text = "" },
    }
  end

  local background      = "#5c6d74"
  local foreground      = "#FFFFFF"
  local edge_background = "none"
  if tab.is_active then
    background = "#ae8b2d"
    foreground = "#FFFFFF"
  end
  local edge_foreground = background
  local title = "   " .. wezterm.truncate_right(tab.active_pane.title, max_width - 1) .. "   "
  return {
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = ROUND_LEFT_EDGE },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = ROUND_RIGHT_EDGE },
  }
end)

----------------------------------------------------
-- ランチャーメニュー（Leader → M で開く。config.launch_menuの一覧から選んで新規タブで起動）
----------------------------------------------------
config.launch_menu = {
  { label = "PowerShell",     args = { "powershell.exe", "-NoLogo" } },
  { label = "WSL",            args = { "wsl.exe" } },
  { label = "Neovim",         args = { "nvim" } },
  { label = "Claude Code",    args = { "claude" } },
  -- kit_proxy.bat（プロキシ環境変数を設定後、cmd /k で常駐するスクリプト）を
  -- 単体で起動したい時用。左Neovim・右Claude Codeのレイアウトごと開きたい場合は
  -- 従来通り Leader+c（spawn-kit-proxy-claude）を使う
  { label = "KIT Proxy起動", args = { "cmd.exe", "/k", "C:\\tools\\kit_proxy.bat" } },
}

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

-- pwsh.exe → powershell.exe に変更
config.default_prog = { "powershell.exe", "-NoLogo" }

return config
