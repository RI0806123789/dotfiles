# Starship プロンプトを初期化する
Invoke-Expression (&starship init powershell)

# --- エラー時に wezterm のビジュアルベルを鳴らす -----------------------------------
# 仕組み: PowerShell は各コマンドの実行後に prompt 関数を呼ぶ。そのタイミングで
#         直前コマンドが失敗（$? が $false）なら BEL 文字(コード7)を出力し、
#         wezterm のビジュアルベル（背景フラッシュ）を発火させる。
# 注意 : Starship も $? で ❯ の色（成功=緑 / 失敗=赤）を判定している。そのため
#        BEL を出した後に $? と $LASTEXITCODE を元へ復元してから Starship 本来の
#        prompt を呼び、Starship の表示を壊さないようにしている。
# 削除 : このベル機能をやめたいときは、以下（この行から下）をまるごと消せばよい。

# Starship が定義した prompt を一度だけ退避する。
# （プロファイルを再読み込みしても二重ラップ＝無限ループにならないようガードする）
if (-not (Test-Path Function:__starshipPrompt)) {
    $function:__starshipPrompt = $function:prompt
}

function prompt {
    # ① 直前コマンドの成否と終了コードを「最優先」で退避する。
    #    以降のどんな処理でも $? は上書きされるため、必ず関数の先頭で取る。
    $lastOk   = $?
    $lastExit = $global:LASTEXITCODE

    # ② 失敗していたら BEL を出力 → ビジュアルベルがふわっと光る。
    if (-not $lastOk) { [Console]::Out.Write([char]7) }

    # ③ Starship の成功/失敗表示を壊さないよう、状態を復元してから呼ぶ。
    #    まず実際の終了コードを戻す（この後 $LASTEXITCODE を変える処理は無い）。
    $global:LASTEXITCODE = $lastExit
    if (-not $lastOk) {
        # $? を $false に戻す。-ErrorAction Ignore なら $Error を汚さずに
        # $? だけを $false にできる（実機で検証済み）。
        # これは Starship 呼び出し直前の「最後の文」であること（$? が確定するため）。
        Write-Error 'restore-dollar-question' -ErrorAction Ignore
    }
    __starshipPrompt
}

# --- wezterm の右ステータスバーへ任意の値を送る --------------------------------------
# 仕組み: OSC 1337 "SetUserVar" エスケープシーケンスで wezterm のユーザー変数へ値を送る。
#         wezterm.lua 側（update-right-status）が pane:get_user_vars().wz_status を読んで
#         左端に表示する。値を空文字にすると表示は消える。
# 使い方:
#   Set-WezVar "デプロイ完了"          # 既定の変数名 wz_status に送る（そのまま表示される）
#   Set-WezVar ""                      # 表示を消す
#   Set-WezVar "任意" -Name other      # 別名の変数へ送りたいとき
# 注意 : 値は Base64 エンコードが必須（wezterm 側の仕様）。ESC(27) と BEL(7) で囲む。
function Set-WezVar {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Value,
        [string]$Name = "wz_status"
    )

    # UTF-8 → Base64 に変換（日本語もそのまま送れる）
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))

    # ESC ] 1337 ; SetUserVar=NAME=BASE64 BEL の形で書き出す
    $esc = [char]27
    $bel = [char]7
    [Console]::Out.Write("$esc]1337;SetUserVar=$Name=$b64$bel")
}

# --- ターミナル内 CPU/メモリ/GPU/DISK/NET バー版ダッシュボード（旧Show-SysDash）------
# 使い方 : Show-SysBar             （既定 約1秒間隔で更新、Ctrl+C で終了）
#          Show-SysBar -IntervalSec 2
# 取得元 : すべて CIM（ロケール非依存・高速）。
#          CPU = Win32_PerfFormattedData_PerfOS_Processor(_Total)
#          MEM = Win32_OperatingSystem（Total/Free）
#          GPU = Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
#                → エンジン種別ごとに使用率を合計し、その最大値をタスクマネージャ風の
#                  「GPU使用率」として表示する（Intel Arc 対応）。
# 注意   : GPUはエンジン種別（3d / videodecode 等）ごとの内訳も下段に表示する。
function Show-SysBar {
    param([double]$IntervalSec = 1)

    $ESC   = [char]27
    $full  = [char]0x2588   # █ バーの塗り
    $light = [char]0x2591   # ░ バーの余白

    # 割合(0-100)を幅widthのバー文字列にする
    function _Bar([double]$pct, [int]$width = 28) {
        if ($pct -lt 0) { $pct = 0 } elseif ($pct -gt 100) { $pct = 100 }
        $fill = [int][math]::Round($pct / 100 * $width)
        return ($full.ToString() * $fill) + ($light.ToString() * ($width - $fill))
    }
    # 割合に応じた色（緑→黄→赤）
    function _Col([double]$pct) {
        if ($pct -ge 85) { 'Red' } elseif ($pct -ge 60) { 'Yellow' } else { 'Green' }
    }
    # bytes/秒 を読みやすい単位（B/s・KB/s・MB/s）へ変換する
    function _Rate([double]$bps) {
        if     ($bps -ge 1MB) { '{0,6:N1} MB/s' -f ($bps / 1MB) }
        elseif ($bps -ge 1KB) { '{0,6:N1} KB/s' -f ($bps / 1KB) }
        else                  { '{0,6:N0} B/s ' -f  $bps }
    }

    # WMIプロバイダの初回初期化コストを先に払っておく（1周目のカクつき防止）
    $null = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor
    $null = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
    $null = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk
    $null = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface

    [Console]::CursorVisible = $false
    Clear-Host
    try {
        while ($true) {
            # --- CPU ---
            $cpu = [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime

            # --- メモリ（KB→MB）---
            $os = Get-CimInstance Win32_OperatingSystem
            $memTotalMB = [math]::Round($os.TotalVisibleMemorySize / 1KB)
            $memUsedMB  = $memTotalMB - [math]::Round($os.FreePhysicalMemory / 1KB)
            $memPct = if ($memTotalMB -gt 0) { $memUsedMB / $memTotalMB * 100 } else { 0 }

            # --- GPU（エンジン種別ごとに合計→最大値を全体使用率とする）---
            $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
            $byType = $eng | Group-Object { ($_.Name -split 'engtype_')[-1] } | ForEach-Object {
                [pscustomobject]@{ Type = $_.Name; Val = ($_.Group | Measure-Object UtilizationPercentage -Sum).Sum }
            }
            $gpu = [double](($byType | Measure-Object Val -Maximum).Maximum)
            if ($gpu -gt 100) { $gpu = 100 }
            $topEng = (($byType | Where-Object { $_.Val -gt 0 } | Sort-Object Val -Descending |
                Select-Object -First 3 | ForEach-Object { '{0} {1:N0}%' -f $_.Type, $_.Val }) -join '   ')

            # --- ディスク I/O（物理ディスク _Total: ビジー率＋読み書き速度）---
            $pd = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
            $diskAct = 100 - [double]$pd.PercentIdleTime          # アイドル率の裏＝ビジー率
            if ($diskAct -lt 0) { $diskAct = 0 } elseif ($diskAct -gt 100) { $diskAct = 100 }
            $diskR = [double]$pd.DiskReadBytesPersec
            $diskW = [double]$pd.DiskWriteBytesPersec

            # --- ディスク容量（固定ドライブ DriveType=3 の使用率）---
            $volLine = ((Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3") | ForEach-Object {
                '{0} {1:N0}% ({2:N0}/{3:N0}GB)' -f $_.DeviceID, (($_.Size - $_.FreeSpace) / $_.Size * 100), (($_.Size - $_.FreeSpace) / 1GB), ($_.Size / 1GB)
            }) -join '   '

            # --- ネットワーク速度（全IF合計の受信/送信バイト/秒）---
            $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface
            $netRx = [double](($net | Measure-Object BytesReceivedPersec -Sum).Sum)
            $netTx = [double](($net | Measure-Object BytesSentPersec -Sum).Sum)

            # --- 描画（左上へ戻し、カーソル以降を消去して上書き＝ちらつき防止）---
            [Console]::SetCursorPosition(0, 0)
            [Console]::Write("$ESC[0J")

            Write-Host ('  System Dashboard      ' + (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
            Write-Host ''
            Write-Host '   CPU  ' -NoNewline
            Write-Host ('{0}  {1,5:N1} %' -f (_Bar $cpu), $cpu) -ForegroundColor (_Col $cpu)
            Write-Host '   MEM  ' -NoNewline
            Write-Host ('{0}  {1,5:N1} %   {2:N0} / {3:N0} MB' -f (_Bar $memPct), $memPct, $memUsedMB, $memTotalMB) -ForegroundColor (_Col $memPct)
            Write-Host '   GPU  ' -NoNewline
            Write-Host ('{0}  {1,5:N1} %   Intel Arc' -f (_Bar $gpu), $gpu) -ForegroundColor (_Col $gpu)
            if ($topEng) { Write-Host ('        ' + $topEng) -ForegroundColor DarkGray }
            Write-Host '   DISK ' -NoNewline
            Write-Host ('{0}  {1,5:N1} %   R {2}  W {3}' -f (_Bar $diskAct), $diskAct, (_Rate $diskR), (_Rate $diskW)) -ForegroundColor (_Col $diskAct)
            Write-Host ('        cap: ' + $volLine) -ForegroundColor DarkGray
            Write-Host '   NET  ' -NoNewline
            Write-Host ('down {0}    up {1}' -f (_Rate $netRx), (_Rate $netTx)) -ForegroundColor Green
            Write-Host ''
            Write-Host '  Ctrl+C : quit' -ForegroundColor DarkGray

            Start-Sleep -Seconds $IntervalSec
        }
    }
    finally {
        # 後片付け：カーソルを戻し、画面を消してからプロンプトへ返す
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, 0)
        [Console]::Write("$ESC[0J")
    }
}

# --- 円形ゲージ（下が欠けた270°リング＝かじられたバウムクーヘン）ダッシュボード -------
# 使い方 : Show-SysDash            （約2秒間隔で更新、Ctrl+C で終了）
#          Show-SysDash -IntervalSec 1
#          Show-SysDash -Once       （1回だけ描画。動作確認/スナップショット用）
# 仕組み : .NET System.Drawing で CPU/MEM/GPU/DISK/BAT の円弧ゲージPNGをメモリ上に生成し、
#          WezTerm のインライン画像プロトコル(iTerm2形式)で端末内へ埋め込み表示する。
# 前提   : 画像表示対応の端末（WezTerm 等）が必要。値の取得元は Show-SysBar と同じCIM。
# 色     : 負荷で緑(#9ece6a)→黄(#e0af68)→赤(#f7768e)。配色は Tokyo Night。
function Show-SysDash {
    param([double]$IntervalSec = 2, [switch]$Once)

    Add-Type -AssemblyName System.Drawing   # 二重呼び出しでも無害

    $ESC = [char]27
    $BEL = [char]7
    $Round = [System.Drawing.Drawing2D.LineCap]::Round
    function _Hex($h) { [System.Drawing.ColorTranslator]::FromHtml($h) }
    # 使用率系：高いほど危険（緑→黄→赤）
    function _Accent($p) { if ($p -ge 85) { '#f7768e' } elseif ($p -ge 60) { '#e0af68' } else { '#9ece6a' } }
    # バッテリー：低いほど危険（＝逆。少ないと赤）
    function _AccentBat($p) { if ($p -le 15) { '#f7768e' } elseif ($p -le 30) { '#e0af68' } else { '#9ece6a' } }

    # 値の配列（Label/Pct）から横並びゲージPNGを生成し byte[] を返す
    function _RenderPng($items) {
        $gw = 220; $n = $items.Count; $W = $gw * $n; $H = 250; $radius = 78
        $bmp = [System.Drawing.Bitmap]::new($W, $H)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear((_Hex '#1a1b26'))
        for ($i = 0; $i -lt $n; $i++) {
            $cx = $gw * $i + $gw / 2; $cy = 105
            $pct = [double]$items[$i].Pct; $label = $items[$i].Label
            $x = [single]($cx - $radius); $y = [single]($cy - $radius); $d = [single]($radius * 2)
            $penW = [single]($radius * 0.26)

            # トラック（270°の背景リング）: 135°開始・時計回り270° → 下側45〜135°が「かじられた」隙間
            $track = [System.Drawing.Pen]::new((_Hex '#3b4261'), $penW)
            $track.StartCap = $Round; $track.EndCap = $Round
            $g.DrawArc($track, $x, $y, $d, $d, [single]135, [single]270)

            # 値リング
            $sweep = [single](270 * ([math]::Max(0, [math]::Min(100, $pct)) / 100))
            if ($sweep -gt 0) {
                $acc = [System.Drawing.Pen]::new((_Hex $items[$i].Accent), $penW)
                $acc.StartCap = $Round; $acc.EndCap = $Round
                $g.DrawArc($acc, $x, $y, $d, $d, [single]135, $sweep)
                $acc.Dispose()
            }

            # 中央の％
            $fp = [System.Drawing.Font]::new('Segoe UI', [single]($radius * 0.38), [System.Drawing.FontStyle]::Bold)
            $t = '{0:N0}%' -f $pct; $s = $g.MeasureString($t, $fp)
            $bt = [System.Drawing.SolidBrush]::new((_Hex '#c0caf5'))
            $g.DrawString($t, $fp, $bt, [single]($cx - $s.Width / 2), [single]($cy - $s.Height / 2))

            # 欠けた下部にラベル
            $fl = [System.Drawing.Font]::new('Segoe UI', [single]($radius * 0.22), [System.Drawing.FontStyle]::Regular)
            $sl = $g.MeasureString($label, $fl)
            $bl = [System.Drawing.SolidBrush]::new((_Hex '#7aa2f7'))
            $g.DrawString($label, $fl, $bl, [single]($cx - $sl.Width / 2), [single]($cy + $radius * 0.62))

            $track.Dispose(); $fp.Dispose(); $fl.Dispose(); $bt.Dispose(); $bl.Dispose()
        }
        $ms = [System.IO.MemoryStream]::new()
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        $bytes = $ms.ToArray(); $ms.Dispose()
        return , $bytes    # byte[] をそのまま返す（カンマで配列展開を防ぐ）
    }

    # 現在値を集めて4項目（CPU/MEM/GPU/DISK）の配列にする
    function _Collect {
        $cpu = [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        $os = Get-CimInstance Win32_OperatingSystem
        $mem = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100
        $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
        $gpu = [double]((($eng | Group-Object { ($_.Name -split 'engtype_')[-1] } | ForEach-Object { ($_.Group | Measure-Object UtilizationPercentage -Sum).Sum }) | Measure-Object -Maximum).Maximum)
        $pd = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
        $disk = 100 - [double]$pd.PercentIdleTime
        if ($disk -lt 0) { $disk = 0 } elseif ($disk -gt 100) { $disk = 100 }

        # 使用率系（高いほど危険で色付け）
        $list = @(
            [pscustomobject]@{ Label = 'CPU';  Pct = $cpu;  Accent = (_Accent $cpu) },
            [pscustomobject]@{ Label = 'MEM';  Pct = $mem;  Accent = (_Accent $mem) },
            [pscustomobject]@{ Label = 'GPU';  Pct = $gpu;  Accent = (_Accent $gpu) },
            [pscustomobject]@{ Label = 'DISK'; Pct = $disk; Accent = (_Accent $disk) }
        )

        # バッテリー残量（ノートPC等でのみ存在。低いほど危険で色付け）
        $b = Get-CimInstance Win32_Battery
        if ($b) {
            $batPct = [double](@($b)[0].EstimatedChargeRemaining)
            $list += [pscustomobject]@{ Label = 'BAT'; Pct = $batPct; Accent = (_AccentBat $batPct) }
        }
        return , $list
    }

    # 1フレーム分の画像をインライン画像シーケンスで端末へ出力する
    function _EmitFrame {
        $png = _RenderPng (_Collect)
        $b64 = [Convert]::ToBase64String($png)
        [Console]::Out.Write("$ESC]1337;File=inline=1;size=$($png.Length);preserveAspectRatio=1:$b64$BEL")
    }

    # WMIプロバイダの初回初期化コストを先に払っておく
    $null = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor
    $null = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
    $null = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk

    if ($Once) {
        _EmitFrame
        [Console]::Out.Write("`r`n")
        return
    }

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            [Console]::Out.Write("$ESC[H")                       # 左上へ戻す
            _EmitFrame
            # 画像の下に時刻と操作ヒント、以降を消去して残像を防ぐ
            [Console]::Out.Write("`r`n  " + (Get-Date -Format 'HH:mm:ss') + "   Ctrl+C : quit$ESC[0J`r`n")
            Start-Sleep -Seconds $IntervalSec
        }
    }
    finally {
        [Console]::CursorVisible = $true
        [Console]::Out.Write("$ESC[2J$ESC[H")   # 画面をクリアしてプロンプトへ
    }
}
