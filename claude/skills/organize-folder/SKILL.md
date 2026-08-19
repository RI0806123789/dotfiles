---
name: organize-folder
description: PC内のディレクトリを横断調査し、不要ファイル・キャッシュ・重複・残骸の削除候補を「理由」と「危険度」付きでリストアップする。削除は一切行わない読み取り専用の棚卸し。サブエージェントで領域を分担し、最後に使用内訳の円グラフを出力する。「ディレクトリを整理したい」「不要なファイルを洗い出して」「ディスクの空きを増やしたい」「容量食ってるもの調べて」「棚卸しして」等の依頼で使う。
---

# ディレクトリ棚卸しスキル

PC内のディレクトリを調査し、**削除候補を根拠付きでリストアップする**。実際の削除は行わない。

`organize-downloads` との違い: あちらは Downloads の中身を KIT 体系へ**移動**する。こちらは**何も動かさず**、全ドライブ規模で候補と根拠を出す。

## 絶対ルール（自分にもサブエージェントにも課す）

- **削除・移動・リネームは一切行わない。** `rm` / `del` / `Remove-Item` / `rmdir` / `rd` / `Clear-RecycleBin` / `cleanmgr` / `Dism ... /StartComponentCleanup` / `vssadmin delete` を実行しない。
- **git操作を一切行わない。** `git status` も `git gc` も `git clean` も禁止。`.git` のサイズ計測は可。
- 実行してよいのは **列挙・サイズ計測・内容確認・ハッシュ比較** のみ。
- サブエージェントはこのルールを継承しない。**各プロンプトに毎回明記する。**
- 計測できなかったものは「計測不能」と正直に書く。**推測値で埋めない。**

## 手順

### 0. 前提の裏取り（省略禁止）

`df` や `Get-PSDrive` の出力を鵜呑みにしない。ここを飛ばすと内訳が二重計上になる。

```powershell
Get-Disk | Format-Table Number, FriendlyName, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, PartitionStyle
Get-Volume | Where-Object DriveLetter | Format-Table DriveLetter, FileSystemLabel, FileSystem, DriveType,
  @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}}
Get-PSDrive -PSProvider FileSystem; net use; subst
```

`Get-Volume` に出ないドライブレターは実ボリュームではない。このPCでは **G: は Googleドライブの仮想ドライブ**（メモリ `gdrive-virtual-drive-g` 参照）。**`G:\` を再帰スキャンしない** — クラウド上のファイルを実ダウンロード（ハイドレート）させる。

### 1. トップレベルの実測

`du` は Windows では遅い。**robocopy のドライラン**を使う（実コピーは発生しない）。

```powershell
robocopy "<対象>" NULL /L /S /NJH /BYTES /FP /NC /NDL /NP /XJ | Select-String 'Bytes :'
```

`/XJ` でジャンクションを除外（二重計上防止）。robocopy はアクセス拒否時に終了コード16を返し、PowerShell 経由だと呼び出し全体が失敗扱いになる。**出力にデータが出ていれば成功しているので、終了コードだけで捨てない。**

C:\ 直下（`Get-ChildItem C:\ -Force`）で `hiberfil.sys` / `pagefile.sys` / `swapfile.sys` / `Windows.old` / `$WinREAgent` / `$Recycle.Bin` の有無とサイズも押さえる。

### 2. サブエージェントを並列展開

領域ごとに1体。各プロンプトに「絶対ルール」「報告フォーマット」「robocopyの計測方法」を必ず含める。

| 担当 | 範囲 |
|---|---|
| AppData\Local | Temp / ブラウザキャッシュ / Packages / CrashDumps / パッケージマネージャキャッシュ |
| Roaming・ドット | AppData\Roaming / ホーム直下の `.xxx` / ホーム直下のゴミファイル |
| ユーザーデータ | Desktop / Documents / Downloads / Pictures / Videos / Music / OneDrive |
| 開発環境 | node_modules / `__pycache__` / venv / build / VM / WSL / Docker / ランタイム重複 |
| システム領域 | C:\Windows / ProgramData / Program Files / ごみ箱 / ダンプ・ログ / C:\直下の残骸 |
| クラウド同期 | DriveFS・OneDrive の**ローカルキャッシュのみ**（クラウド実体は触らない） |

報告フォーマットは統一する:

```
| パス | サイズ(MB) | 分類 | 削除候補とした理由 | リスク |
```

加えて **第1階層のサイズ一覧（円グラフ用）** と **領域合計・候補合計** を必ず出させる。

### 3. 統合と重複排除

複数のエージェントが同じ対象を報告する（pipキャッシュ、huggingface、DriveFS、Arduinoなど）。**集計スクリプトを書いて重複を排除する。** 手計算しない。

Python で集計する場合、Windowsパスは **raw文字列 `r"..."`** で書く（`\U` `\x` 等がエスケープと衝突する）。

### 4. 重複フォルダは2段階で検証

サイズ合計の一致だけでは「完全重複」と言い切れない。

1. **相対パス＋サイズの全件突合** — `Compare-Object` で差分ゼロを確認
2. **最大ファイル数件の SHA256 突合** — `Get-FileHash` で内容一致を確認

両方通って初めて「削除してよい重複」と報告する。

### 5. 危険度3段階に分類

| 段階 | 意味 |
|---|---|
| 🟢 安全 | 自動再生成される／ハッシュ一致の重複。手動削除しても実害なし |
| 🟡 要確認 | 使用状況の判断が要る、または**公式手順**を使うべきもの（アンインストーラ / ディスククリーンアップ / `powercfg /h off` / アプリ内のキャッシュクリア） |
| 🔴 危険 | 削除するとシステム・環境が壊れる。**サイズが大きく候補に見えるものほど明記する** |

要確認・危険には「手動削除ではなく何を使うべきか」を必ず併記する。

### 6. 報告と円グラフ

`dataviz` スキルを読んでから作図する。円グラフの要点:

- **セグメントは5つまで。** 単色相の序数ランプを使う（大→小で light→dark）。カテゴリカル配色は全ペア比較で3スロットが上限のため、6分割以上では成立しない。
- `validate_palette.js` で **ライト・ダーク両モードを検証**してから使う。目視で決めない。
- 各スライスに%を直接ラベル、凡例と表も併置する。
- SVGのラベル色は**必ずCSS変数**にする。リテラルで書くと片方のテーマで読めなくなる。

`artifact-design` を読んでから Artifact として公開する。

## 既知の罠

- **PowerShell 5.1 の文字化け**: 日本語コメント入りUTF-8スクリプトを `powershell -File` で実行すると Shift-JIS と誤認して壊れ、**意図しないパスを走査する**事故が起きる。計測スクリプトは**英語のみ**で書く。
- **シンボリックリンクの二重計上**: robocopy がリンク先を辿って加算する。`/XJ` を付け、`WinGet\Links` のような場所は実体か確認する。
- **非管理者権限で計測不能な領域**: `C:\Windows\Temp` / `Prefetch` / `LiveKernelReports` / `PerfLogs` / `ProgramData\Packages` / `Program Files\WindowsApps` / `System Volume Information`。実使用量との差はここに出る。
- **NTFSの最終アクセス日時は既定で無効**: 「最後に使ったのはいつか」は機械的に判定できない。アプリの使用状況は**本人に聞く**。

## 保護対象（候補にしない）

- `~/.claude/projects/**/memory/` と `CLAUDE.md` — 永続メモリ
- `.local/bin/claude.exe` と `versions/<現行版>` — 実行中のClaude Code本体（旧世代のみ候補）
- `Documents\KIT\` の学業コンテンツ — 資料・レポート・録画・録音。**ただしインストーラ実行ファイルは候補に含めてよい**（この線引きは報告時に明示して確認を取る）
- 稼働中の仮想マシンイメージ、メインのPython/Node環境、`.vscode\extensions`
- `C:\Windows\WinSxS` / `C:\Windows\Installer` / `pagefile.sys` — 手動削除厳禁
- クラウド同期のメタデータDB（DriveFSの `metadata_sqlite_db` 等）— 消すとフル再同期

## 報告に必ず含めるもの

- 危険度別の候補リスト（パス・サイズ・**理由**・リスク・正しい削除手段）
- 使用内訳の円グラフ
- 計測できなかった領域の明示
- **判断が要る問い**（本人にしか決められないもの）を最後にまとめる

## 参照

- メモリ `gdrive-virtual-drive-g` — G:の正体と再帰スキャン禁止
- メモリ `kit_directory_structure` — KIT配下の構成
- スキル `dataviz` / `artifact-design` — 作図と公開
- スキル `organize-downloads` — Downloads を実際に移動する方（別物）
