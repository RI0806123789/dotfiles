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

# --- 円形ゲージ（下が欠けた270°リング＝かじられたバウムクーヘン）ダッシュボード -------
# 使い方 : Show-SysDash            （約2秒間隔で更新、Ctrl+C で終了）
#          Show-SysDash -IntervalSec 1
#          Show-SysDash -Once       （1回だけ描画。動作確認/スナップショット用）
# 仕組み : .NET System.Drawing で CPU/MEM/GPU/DISK/BAT の円弧ゲージPNGをメモリ上に生成し、
#          WezTerm のインライン画像プロトコル(iTerm2形式)で端末内へ埋め込み表示する。
#          CPU/GPUラベルの下にはハードウェアのモデル名、BATラベルの下には充電中なら
#          満充電までの時間、放電中なら残り駆動時間を1行追加で表示する。
# 前提   : 画像表示対応の端末（WezTerm 等）が必要。値の取得元はすべて CIM（ロケール非依存・高速）。
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
    # CIMのモデル名から (R)/(TM) 等の商標記号を除去して読みやすくする
    function _CleanModel($s) { ($s -replace '\(R\)', '' -replace '\(TM\)', '' -replace '\s{2,}', ' ').Trim() }

    # バッテリーの補足時間文字列を返す（放電中=残り駆動時間、充電中=満充電までの時間）
    # $b0 : Get-CimInstance Win32_Battery の1件分のインスタンス
    # 注意: Win32_Battery.BatteryStatus だけでは実機で状態を正しく判定できないことがある
    #       （AC接続中でも値が"2"のまま実際は放電している端末があるのを実機検証で確認済み）。
    #       そのため充電/放電の判定自体は root\WMI\BatteryStatus の Charging/Discharging
    #       ブール値を優先して使い、より確実な方を採用する。
    function _BatTimeText($b0) {
        try {
            $bs = Get-CimInstance -Namespace root\WMI -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        } catch {
            $bs = $null
        }

        if ($bs -and $bs.Charging) {
            # 充電中: (満充電容量 - 残容量) / 充電レート から満充電までの時間を算出
            try {
                $fc = Get-CimInstance -Namespace root\WMI -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1
                $rate = [double]$bs.ChargeRate
                if ($rate -gt 0) {
                    $min = ([double]$fc.FullChargedCapacity - [double]$bs.RemainingCapacity) / $rate * 60
                    if ($min -gt 0) {
                        $h = [int]($min / 60); $m = [int]($min % 60)
                        # "H:MM"表記だとMM:SS(分:秒)と誤読しやすいため、単位付きの"○h○m"表記にする
                        return ('{0}h{1:D2}m to full' -f $h, $m)
                    }
                }
            } catch {}
            return ''
        } elseif ($bs -and $bs.PowerOnline -and -not $bs.Charging) {
            # AC接続中だが充電はしていない状態（満充電付近での充電保護など）。
            # このときDischargingがTrueでもDischargeRateはごく僅かな微放電でしかなく、
            # そこから逆算した「残り時間」は実際に電源を抜いた場合の駆動時間として無意味
            # （実機で462mWのような極端に低いレートから「残り101時間」等の数字が出て誤解を招いた）。
            # そのため時間換算はせず、状態そのものを短く表示する。
            if ($b0.BatteryStatus -eq 3) { return 'Full' }
            return 'AC'
        } elseif ($bs -and $bs.Discharging) {
            # 放電中（AC非接続の純粋なバッテリー駆動）: まずEstimatedRunTime（分）を使う。
            # 71582788 は「不明」を示すセンチネル値。取れない場合は RemainingCapacity / DischargeRate から概算する。
            $runMin = $b0.EstimatedRunTime
            if ($runMin -and $runMin -gt 0 -and $runMin -lt 71582788) {
                $h = [int]($runMin / 60); $m = [int]($runMin % 60)
                # "H:MM"表記だとMM:SS(分:秒)と誤読しやすいため、単位付きの"○h○m"表記にする
                return ('{0}h{1:D2}m left' -f $h, $m)
            }
            $rate = [double]$bs.DischargeRate
            if ($rate -gt 0) {
                $min = [double]$bs.RemainingCapacity / $rate * 60
                $h = [int]($min / 60); $m = [int]($min % 60)
                return ('{0}h{1:D2}m left' -f $h, $m)
            }
            return ''
        } elseif ($b0.BatteryStatus -eq 3) {
            return 'Full'
        }
        return ''
    }

    # 値の配列（Label/Pct/Sub）から横並びゲージPNGを生成し byte[] を返す
    # Sub : ラベルの下にもう1行添える補足文字列（モデル名やバッテリー時間など。無ければ空文字）
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

            # ラベルのさらに下に補足情報（モデル名／バッテリー時間）を1行。
            # セル幅(gw)に収まらない場合はフォントを縮めて必ず1行に収める。
            $sub = [string]$items[$i].Sub
            if ($sub) {
                $maxW = $gw - 16
                $subSize = [single]($radius * 0.15)
                $fs = [System.Drawing.Font]::new('Segoe UI', $subSize, [System.Drawing.FontStyle]::Regular)
                $ss = $g.MeasureString($sub, $fs)
                while ($ss.Width -gt $maxW -and $subSize -gt 6) {
                    $fs.Dispose()
                    $subSize = [single]($subSize - 0.5)
                    $fs = [System.Drawing.Font]::new('Segoe UI', $subSize, [System.Drawing.FontStyle]::Regular)
                    $ss = $g.MeasureString($sub, $fs)
                }
                $bs2 = [System.Drawing.SolidBrush]::new((_Hex '#565f89'))
                $g.DrawString($sub, $fs, $bs2, [single]($cx - $ss.Width / 2), [single]($cy + $radius * 0.62 + $sl.Height + 2))
                $fs.Dispose(); $bs2.Dispose()
            }

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

        # 使用率系（高いほど危険で色付け）。CPU/GPUはSubにモデル名（起動時に1度だけ取得済み）を添える
        $list = @(
            [pscustomobject]@{ Label = 'CPU';  Pct = $cpu;  Accent = (_Accent $cpu);  Sub = $cpuModel },
            [pscustomobject]@{ Label = 'MEM';  Pct = $mem;  Accent = (_Accent $mem);  Sub = '' },
            [pscustomobject]@{ Label = 'GPU';  Pct = $gpu;  Accent = (_Accent $gpu);  Sub = $gpuModel },
            [pscustomobject]@{ Label = 'DISK'; Pct = $disk; Accent = (_Accent $disk); Sub = '' }
        )

        # バッテリー残量（ノートPC等でのみ存在。低いほど危険で色付け）。Subに充電/放電の時間を添える
        $b = Get-CimInstance Win32_Battery
        if ($b) {
            $b0 = @($b)[0]
            $batPct = [double]$b0.EstimatedChargeRemaining
            $list += [pscustomobject]@{ Label = 'BAT'; Pct = $batPct; Accent = (_AccentBat $batPct); Sub = (_BatTimeText $b0) }
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

    # CPU/GPUのモデル名は起動中に変わらないためループ開始前に1度だけ取得（_Collectから参照される）
    $cpuModel = _CleanModel (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
    $gpuModel = _CleanModel (Get-CimInstance Win32_VideoController | Select-Object -First 1 -ExpandProperty Name)

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

# --- PSReadLine: syntax highlighting（配色をTokyo Nightに合わせる）--------------------
# 注意: Windows PowerShell 5.1 同梱の PSReadLine は 2.0.0 と古く、
#       autosuggestion(PredictionSource / PredictionViewStyle)には非対応（PowerShell 7.1+が必須）。
#       ここでは配色カスタマイズのみ適用する。autosuggestionも使いたい場合は
#       PowerShell 7(pwsh)を使うこと（WezTermのランチャー Leader+M → "PowerShell 7"）。
Set-PSReadLineOption -Colors @{
    Command   = '#ae8b2d'  # コマンド名（金／タブのアクティブ色と統一）
    Parameter = '#7dcfff'  # パラメータ（シアン）
    Operator  = '#bb9af7'  # 演算子（紫）
    Variable  = '#ff9e64'  # 変数（オレンジ）
    String    = '#9ece6a'  # 文字列（緑）
    Number    = '#e0af68'  # 数値（黄）
    Type      = '#7dcfff'  # 型（シアン）
    Comment   = '#565f89'  # コメント（グレー）
    Keyword   = '#bb9af7'  # キーワード（紫）
    Member    = '#7dcfff'  # メンバー（シアン）
    Default   = '#c0caf5'  # 通常テキスト
}
