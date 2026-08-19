$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$LogPath = Join-Path $PSScriptRoot 'sync.log'

function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $LogPath -Value $line
}

$appdata = $env:APPDATA

# ディレクトリ(Junction)ペア
$JunctionPairs = @(
    @{ Live = "$HOME\.config\nvim";    Repo = "$RepoRoot\nvim" },
    @{ Live = "$HOME\.config\wezterm"; Repo = "$RepoRoot\wezterm" },
    @{ Live = "$HOME\.claude\skills";  Repo = "$RepoRoot\claude\skills" }
)

# ファイル(HardLink)ペア
$HardLinkPairs = @(
    @{ Live = "$HOME\.config\starship.toml"; Repo = "$RepoRoot\starship\starship.toml" },
    @{ Live = "$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Repo = "$RepoRoot\powershell\Microsoft.PowerShell_profile.ps1" },
    @{ Live = "$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"; Repo = "$RepoRoot\powershell7\Microsoft.PowerShell_profile.ps1" },
    @{ Live = "$HOME\.gitconfig"; Repo = "$RepoRoot\git\.gitconfig" },
    @{ Live = "$appdata\Code\User\settings.json"; Repo = "$RepoRoot\vscode\settings.json" },
    @{ Live = "$appdata\Code\User\keybindings.json"; Repo = "$RepoRoot\vscode\keybindings.json" },
    @{ Live = "$appdata\Code\User\chatLanguageModels.json"; Repo = "$RepoRoot\vscode\chatLanguageModels.json" },
    @{ Live = "$HOME\.claude\settings.json"; Repo = "$RepoRoot\claude\settings.json" },
    @{ Live = "$HOME\.claude\statusline-command.sh"; Repo = "$RepoRoot\claude\statusline-command.sh" },
    @{ Live = "$HOME\.claude\plugins\installed_plugins.json"; Repo = "$RepoRoot\claude\plugins\installed_plugins.json" }
)

$repaired = 0
$checked = 0

foreach ($p in $JunctionPairs) {
    $checked++
    if (-not (Test-Path $p.Repo)) {
        Write-Log "SKIP (repo側が存在しない): $($p.Repo)"
        continue
    }
    $needsRepair = $true
    if (Test-Path $p.Live) {
        $item = Get-Item $p.Live -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'Junction' -and $item.Target -eq $p.Repo) {
            $needsRepair = $false
        }
    }
    if ($needsRepair) {
        if (Test-Path $p.Live) {
            $backup = "$($p.Live).driftbak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
            # リンクが切れて実体ディレクトリに戻っていた場合、中身をrepoへ取り込んでから退避する
            robocopy $p.Live $p.Repo /E /XO /NFL /NDL /NJH /NJS | Out-Null
            Rename-Item -Path $p.Live -NewName (Split-Path $backup -Leaf)
            Write-Log "JUNCTION修復: $($p.Live) (旧実体を $backup へ退避し、差分をrepoへ取り込み済み)"
        } else {
            Write-Log "JUNCTION作成: $($p.Live)"
        }
        New-Item -ItemType Junction -Path $p.Live -Target $p.Repo | Out-Null
        $repaired++
    }
}

foreach ($p in $HardLinkPairs) {
    $checked++
    if (-not (Test-Path $p.Repo)) {
        Write-Log "SKIP (repo側が存在しない): $($p.Repo)"
        continue
    }
    $needsRepair = $true
    if (Test-Path $p.Live) {
        $item = Get-Item $p.Live -Force -ErrorAction SilentlyContinue
        if ($item -and $item.LinkType -eq 'HardLink') {
            $links = fsutil hardlink list $p.Live 2>$null
            $repoRel = $p.Repo.Substring(2)  # ドライブレター(例: "C:")を除いた \Users\... 形式に揃える
            if ($links -contains $repoRel) {
                $needsRepair = $false
            }
        }
    }
    if ($needsRepair) {
        if (Test-Path $p.Live) {
            # リンクが切れて独立ファイルに戻っていた場合、実配置側の最新内容をrepoへ取り込む
            $liveContent = Get-Content -Raw -LiteralPath $p.Live -ErrorAction SilentlyContinue
            $repoContent = Get-Content -Raw -LiteralPath $p.Repo -ErrorAction SilentlyContinue
            if ($liveContent -ne $repoContent) {
                Copy-Item -LiteralPath $p.Live -Destination $p.Repo -Force
                Write-Log "取り込み: $($p.Live) の内容差分をrepoへ反映"
            }
            $backup = "$($p.Live).driftbak_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
            Rename-Item -Path $p.Live -NewName (Split-Path $backup -Leaf)
            Write-Log "HARDLINK修復: $($p.Live) (旧実体を $backup へ退避)"
        } else {
            Write-Log "HARDLINK作成: $($p.Live)"
        }
        New-Item -ItemType HardLink -Path $p.Live -Value $p.Repo | Out-Null
        $repaired++
    }
}

Write-Log "チェック完了: $checked 件中 $repaired 件を修復"
