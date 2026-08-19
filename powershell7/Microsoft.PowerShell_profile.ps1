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
