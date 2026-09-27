# Starship プロンプトを初期化する（Windows PowerShell側のprofileと統一感を保つため）
Invoke-Expression (&starship init powershell)

# --- PSReadLine: autosuggestion + syntax highlighting -----------------------------
# PredictionSource History       : 履歴からゴースト文字(inline suggestion)を出す。
#                                   zsh-autosuggestions と同じ「履歴ベースの候補」方式。
# PredictionViewStyle InlineView : 候補を1行のゴースト文字として表示（→ or End で確定）。
#                                   PredictionSource/InlineViewは PowerShell 7.1+ が必須で、
#                                   Windows PowerShell 5.1 側では使えない（そちらは配色のみ）。
# try/catch : `pwsh -Command "..."` 等の非対話・出力リダイレクト時はVT非対応で例外になるため、
#             スクリプト経由の呼び出し（自動化等）でエラーを出さないようにガードする。
try {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle InlineView
} catch {}

# トークン別の配色（wezterm.lua / SysDash と同じ Tokyo Night パレットに合わせる）
Set-PSReadLineOption -Colors @{
    Command          = '#ae8b2d'  # コマンド名（金／タブのアクティブ色と統一）
    Parameter        = '#7dcfff'  # パラメータ（シアン）
    Operator         = '#bb9af7'  # 演算子（紫）
    Variable         = '#ff9e64'  # 変数（オレンジ）
    String           = '#9ece6a'  # 文字列（緑）
    Number           = '#e0af68'  # 数値（黄）
    Type             = '#7dcfff'  # 型（シアン）
    Comment          = '#565f89'  # コメント（グレー）
    Keyword          = '#bb9af7'  # キーワード（紫）
    Member           = '#7dcfff'  # メンバー（シアン）
    Default          = '#c0caf5'  # 通常テキスト
    InlinePrediction = '#565f89'  # autosuggestionのゴースト文字（グレー）
}

# --- PDFをSumatraPDFで開く -----------------------------------------------------
# 導入: winget install SumatraPDF.SumatraPDF
# 注意: SumatraPDFのインストーラはPATHにもApp Pathsにも登録しない。そのため
#       `Start-Process SumatraPDF` は名前解決できずエラーになる。ここでは実体のexeを
#       既知の候補パスから自前で探し、初回だけ探索して $global:SumatraPdfExe にキャッシュする。
# 使い方: pdf report.pdf           … 相対パスでもOK（カレントディレクトリ基準で解決）
#         pdf report.pdf -Page 12  … 12ページ目を開く
#         pdf *.pdf                … ワイルドカード可（ヒットした分だけ開く）
#         ls *.pdf | pdf           … パイプ入力も可
function Resolve-SumatraPdfExe {
    # キャッシュが生きていればそれを返す（毎回ディスクを探しに行かない）
    if ($global:SumatraPdfExe -and (Test-Path -LiteralPath $global:SumatraPdfExe)) {
        return $global:SumatraPdfExe
    }
    $candidates = @(
        "$env:LOCALAPPDATA\SumatraPDF\SumatraPDF.exe"         # wingetの既定（ユーザー単位インストール）
        "$env:ProgramFiles\SumatraPDF\SumatraPDF.exe"         # 管理者インストール(64bit)
        "${env:ProgramFiles(x86)}\SumatraPDF\SumatraPDF.exe"  # 32bit版
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $global:SumatraPdfExe = $c; return $c }
    }
    # 将来PATHに入った場合の保険
    $cmd = Get-Command SumatraPDF.exe -ErrorAction SilentlyContinue
    if ($cmd) { $global:SumatraPdfExe = $cmd.Source; return $cmd.Source }
    return $null
}

function pdf {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('FullName')]
        [string[]]$Path,

        [int]$Page
    )
    begin {
        $exe = Resolve-SumatraPdfExe
        if (-not $exe) {
            Write-Host "SumatraPDFが見つかりません。winget install SumatraPDF.SumatraPDF で導入してください。" -ForegroundColor Yellow
        }
    }
    process {
        if (-not $exe) { return }
        if (-not $Path) {
            Write-Host "使い方: pdf <ファイル> [-Page <番号>]" -ForegroundColor DarkGray
            return
        }
        foreach ($p in $Path) {
            # ワイルドカード展開と絶対パス化を同時に行う（1件も無ければ $null が返る）
            $resolved = Resolve-Path -Path $p -ErrorAction SilentlyContinue
            if (-not $resolved) {
                Write-Host "ファイルが見つかりません: $p" -ForegroundColor Yellow
                continue
            }
            foreach ($item in $resolved) {
                # Start-Process は配列引数を空白で連結するだけで、空白入りパスを
                # 引用符で囲ってはくれない。そのため自前で " " を付けてから渡す。
                $sumatraArgs = @('-reuse-instance')  # 既存ウィンドウをタブとして再利用する
                if ($Page -gt 0) { $sumatraArgs += @('-page', "$Page") }
                $sumatraArgs += '"{0}"' -f $item.Path
                Start-Process -FilePath $exe -ArgumentList $sumatraArgs
            }
        }
    }
}
