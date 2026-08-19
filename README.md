# dotfiles

開発環境設定ファイル管理用リポジトリ。

## 構成

| フォルダ | 内容 | 元の配置場所 |
|---|---|---|
| `nvim/` | Neovim設定 | `~/.config/nvim/` |
| `wezterm/` | WezTerm設定・キーバインド | `~/.config/wezterm/` |
| `starship/` | プロンプト設定 | `~/.config/starship.toml` |
| `powershell/` | PowerShellプロファイル (Windows PowerShell 5.1) | `$PROFILE` (`Documents\WindowsPowerShell\`) |
| `powershell7/` | PowerShellプロファイル (PowerShell 7 / pwsh) | `$PROFILE` (`Documents\PowerShell\`) |
| `git/` | Git設定 | `~/.gitconfig` |
| `vscode/` | VSCodeユーザー設定(settings/keybindings) | `%APPDATA%\Code\User\` |
| `claude/` | Claude Code設定(一部のみ) | `~/.claude/` |

## セットアップ(別PCで使う場合)

1. リポジトリをクローンする

   ```powershell
   git clone https://github.com/RI0806123789/dotfiles.git Documents\GitHub\dotfiles
   ```

2. 元の配置場所にあるファイルを退避し、代わりにシンボリックリンクを張る

   ```powershell
   # 例: Neovim設定
   Remove-Item -Recurse ~\.config\nvim
   New-Item -ItemType SymbolicLink -Path ~\.config\nvim -Target Documents\GitHub\dotfiles\nvim

   # 例: WezTerm設定
   Remove-Item -Recurse ~\.config\wezterm
   New-Item -ItemType SymbolicLink -Path ~\.config\wezterm -Target Documents\GitHub\dotfiles\wezterm

   # 例: starship
   Remove-Item ~\.config\starship.toml
   New-Item -ItemType SymbolicLink -Path ~\.config\starship.toml -Target Documents\GitHub\dotfiles\starship\starship.toml

   # 例: PowerShellプロファイル (Windows PowerShell 5.1)
   Remove-Item $PROFILE
   New-Item -ItemType SymbolicLink -Path $PROFILE -Target Documents\GitHub\dotfiles\powershell\Microsoft.PowerShell_profile.ps1

   # 例: PowerShellプロファイル (PowerShell 7 / pwsh。pwsh上で実行すること)
   Remove-Item $PROFILE
   New-Item -ItemType SymbolicLink -Path $PROFILE -Target Documents\GitHub\dotfiles\powershell7\Microsoft.PowerShell_profile.ps1

   # 例: Git設定
   Remove-Item ~\.gitconfig
   New-Item -ItemType SymbolicLink -Path ~\.gitconfig -Target Documents\GitHub\dotfiles\git\.gitconfig
   ```

