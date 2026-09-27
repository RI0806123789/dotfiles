---
name: daily-briefing
description: 今日のメール・カレンダー予定・試験情報・天気と服装・最近のAI/テクノロジーニュース・推しCheckを、実行時刻（朝/昼/夜）に応じた最適な粒度でまとめて報告する。「今日のメールと予定」「デイリーブリーフィング」「朝のまとめ」「今日のニュースとスケジュール」等、これらを横断的に確認したい依頼で使う。
model: haiku
effort: low
allowed-tools: [ToolSearch, Bash, PowerShell, mcp__claude_ai_Gmail__search_threads, mcp__claude_ai_Google_Calendar__list_events, mcp__claude_ai_Google_Calendar__list_calendars, WebSearch, WebFetch]
---

# デイリーブリーフィングスキル

「予定」「メール」「試験情報」「天気と服装」「AI/テクノロジーニュース」「推しCheck」を、実行時刻に応じた粒度でまとめて報告する。同じ内容を毎回フルで出すのではなく、朝は準備のためのフル情報、昼は移動中でもサッと読める簡易版、夜は翌日の準備に絞った内容に自動で切り替える。ただし試験情報と推しCheckはモードによらず常に出力する。

高速化のため、カレンダーAPI呼び出しの統合・位置情報のキャッシュ・天気APIの直接呼び出し・検索クエリの絞り込みを行っている（詳細は各手順を参照）。

## モード判定（最初に実行）

1. 現在時刻を取得する。`Bash` で `date +"%H:%M"`、または `PowerShell` で `Get-Date -Format "HH:mm"` を実行する（マシンのローカル時刻がAsia/Tokyo設定である前提）。明らかに異なるタイムゾーンだと分かった場合はその旨を一言断ってから進める。
2. 取得した時刻から以下の3モードのいずれかを選ぶ。
   - **朝モード**（5:00〜10:59）: フル版
   - **昼モード**（11:00〜16:59）: 簡易版
   - **夜モード**（17:00〜4:59）: 明日準備版
3. ユーザーが「朝の内容で」「明日の予定を教えて」のように明示的にモードや対象日を指定した場合は、時刻判定より優先する。
4. 選んだモードを出力の冒頭で一言明示する（例:「（昼モード・簡易版）」）。

## 共通手順

1. **ツールのロード**: Gmail/Calendar/WebSearch/WebFetchツールが未ロードなら `ToolSearch` で `select:mcp__claude_ai_Gmail__search_threads,mcp__claude_ai_Google_Calendar__list_events,mcp__claude_ai_Google_Calendar__list_calendars,WebSearch,WebFetch` を一括ロードする（個別に何度も呼ばない）。**既にロード済みならこのステップ自体を省略する。**
   - この手順は次の「現在地・天気の取得」（PowerShellのみで完結し、MCPツールに依存しない）と依存関係がないため、**同一メッセージ内で並列に実行する**（ToolSearchの完了を待ってからPowerShellを叩かない）。

2. **現在地・天気の取得（キャッシュ＋API直叩き版。モードによらず1回だけ実行し、結果を朝/昼/夜モードの天気ステップで使い回す）**:

   位置情報は数時間単位ではほぼ変わらないためキャッシュし、天気は毎回変わるためOpen-Meteo APIから直接JSONを取得する（WebSearchでの検索・要約やWebFetchでのスクレイピングは行わない。曖昧な要約による手戻りを避け、かつ高速）。

   ```powershell
   $cacheDir = "$env:LOCALAPPDATA\ClaudeDailyBriefing"
   $cachePath = Join-Path $cacheDir "location_cache.json"
   $place = $null; $lat = $null; $lon = $null

   if (Test-Path $cachePath) {
       try {
           $cache = Get-Content $cachePath -Raw | ConvertFrom-Json
           if (((Get-Date) - [datetime]$cache.timestamp).TotalHours -lt 6) {
               $place = $cache.place; $lat = $cache.lat; $lon = $cache.lon
           }
       } catch {}
   }

   if (-not $lat) {
       Add-Type -AssemblyName System.Device
       $watcher = New-Object System.Device.Location.GeoCoordinateWatcher
       $watcher.Start()
       $t = 0
       while ($watcher.Status -ne 'Ready' -and $watcher.Status -ne 'Error' -and $t -lt 80) {
           Start-Sleep -Milliseconds 100; $t++
       }
       if ($watcher.Status -eq 'Ready') {
           $pos = $watcher.Position.Location
           $lat = $pos.Latitude; $lon = $pos.Longitude
           try {
               $res = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&accept-language=ja&zoom=12" `
                   -Headers @{ "User-Agent" = "daily-briefing-skill" } -TimeoutSec 5
               $a = $res.address
               $p = if ($a.city) { $a.city } elseif ($a.town) { $a.town } elseif ($a.county) { $a.county } else { $null }
               if ($p) { $place = "$($a.province)$p" }
           } catch {}
       }
       $watcher.Stop(); $watcher.Dispose()

       if ($lat -and $place) {
           if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
           @{ place = $place; lat = $lat; lon = $lon; timestamp = (Get-Date).ToString("o") } | ConvertTo-Json | Set-Content $cachePath
       }
   }

   if (-not $lat -or -not $place) {
       "LOCATION_FAILED"
   } else {
       try {
           $uri = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weathercode&hourly=temperature_2m,precipitation_probability,weathercode&timezone=Asia%2FTokyo&forecast_days=2"
           $weather = Invoke-RestMethod -Uri $uri -TimeoutSec 8
           @{ place = $place; weather = $weather } | ConvertTo-Json -Depth 6 -Compress
       } catch {
           "WEATHER_FETCH_FAILED:$place"
       }
   }
   ```

   - キャッシュ（`location_cache.json`）が6時間以内なら位置情報取得（GeoCoordinateWatcher・Nominatim）を丸ごとスキップする。天気自体は毎回このAPIで最新値を取得するため、キャッシュしているのは「地点（緯度経度・地名）」のみで「天気」はキャッシュしない。
   - GeoCoordinateWatcherの待機タイムアウトは検証の結果8秒（80回×100ms）のまま維持している。5秒に短縮すると環境によって`NoData`のまま失敗するケースが実際に確認されたため、速度より信頼性を優先した。高速化の主眼はこのキャッシュによる「6時間以内は丸ごとスキップ」の方にある。
   - 出力JSONの`weather.daily`配列は`[0]`が今日、`[1]`が明日（`timezone=Asia/Tokyo`指定のため）。`weather.hourly`は48時間分（`time`配列のインデックスと対応）。
   - `daily.weathercode`／`hourly.weathercode`はWMO weathercodeで、以下の対応表で日本語表現に変換する。
     - `0`: 快晴 / `1〜3`: 晴れ〜曇り / `45,48`: 霧 / `51,53,55`: 霧雨 / `56,57`: 着氷性霧雨 / `61,63,65`: 雨（弱い/並/強い） / `66,67`: 着氷性の雨 / `71,73,75`: 雪 / `77`: 霧雪 / `80,81,82`: にわか雨 / `85,86`: にわか雪 / `95`: 雷雨 / `96,99`: 雷雨（雹あり）
   - **時間帯別の推移**: 対象日（今日=`hourly`の先頭24件、明日=次の24件）の`precipitation_probability`を見て、50%を跨ぐタイミングを1文で要約する（例:「15時ごろから降水確率が上がる見込み」）。目立った変化がなければ「一日を通して大きな変化はありません」。
   - `LOCATION_FAILED`または`WEATHER_FETCH_FAILED`が返った場合、この手順自体が実行できない環境（WSL/Bash専用環境など）の場合は`<在住市区町村>`（本人の環境に合わせて読み替える）にフォールバックし、可能なら旧来のWebSearchベースの天気検索（`"<地名> 天気 今日/明日 <日付>"`）に切り替える。出力冒頭で「（現在地取得または天気APIに失敗したため、〇〇ベースで表示しています）」と一言添える。
   - KIT（<UNIVERSITY>）もこの近辺のため、カレンダーのタイムゾーンは常に `Asia/Tokyo` を使う。

3. メールの検索結果数（`resultCountEstimate`）が表示件数より多い場合、全件を確認したわけではない旨を一言添える。
4. 機微・プライベートな内容（アダルト系サービス通知等）は要約に留め、詳細な文面を出力に含めない。性的・アダルト系コンテンツ配信サービス（Fantia等）からの通知は「〇〇から新着通知が複数件」のように概要のみに留める。

5. **カレンダー統合取得（当日/翌日の予定＋試験情報を1回のAPI呼び出しで取得）**: `mcp__claude_ai_Google_Calendar__list_events`で`startTime`=当日00:00、`endTime`=当日から14日後の23:59（`timeZone: "Asia/Tokyo"`、`orderBy: "startTime"`）を**1回だけ**取得する。
   - この1回の結果から、モードごとに以下をローカルで振り分ける。
     - **表示用の予定**: 朝/昼モードは当日分（開始日=当日）、夜モードは翌日分（開始日=翌日）を抽出。終日イベントも含める。
     - **試験情報**: 全結果のうち、予定名が「教科名（期末試験／中間試験／小テスト／再試験／追試／テスト／試験）」のように丸括弧で試験関連キーワードが付いているものだけを抽出し、日付・科目名（種別）・場所を日付順に整理する。該当がなければ「直近の試験予定はありません」と明記する。
   - 試験情報の走査範囲は「当日〜14日後」に固定する（旧仕様の「当月末まで」より速度優先で短縮しているため、月末が2週間より先にある場合はその時点の試験を拾えない。許容されたトレードオフ）。

6. **推しCheckの取得（モードによらず常に実行、検索1クエリに統合）**: `WebSearch`で1クエリ（例:「<FAVORITE_VTUBER> 配信 最新情報」）のみ実行し、直近の配信予定・新着動画・話題になっているトピックを2〜4行程度で簡潔にまとめる。日付が分かるものは明記する。該当情報が見つからなければ「新着情報は見つかりませんでした」と明記する。参照したURLは`Sources:`に記載する。

## 朝モード（5:00〜10:59・フル版）

1. **カレンダー**: 共通手順5で取得済みの「当日分」データをそのまま使う（追加のAPI呼び出しは不要）。
2. **メール**: `query: "newer_than:1d in:inbox"`、`pageSize: 20`程度で取得。
   - `IMPORTANT`ラベル、または送信元が公共機関・大学・金融/インフラ系のものは「要確認」として個別見出しで記載。
   - それ以外は送信元/カテゴリ単位でまとめて一覧化（1件ずつ本文引用しない）。
   - 返信・対応が必要そうなメールは明示的に指摘する。
3. **天気**: 共通手順2で取得済みの`weather.daily[0]`（今日）と対象時間帯の`weather.hourly`データを使う。追加のWebSearchは行わない。
   - 目安: 最高気温30℃以上は半袖+通気性重視、25〜29℃は半袖、20〜24℃は長袖1枚、15〜19℃は長袖+薄手の羽織り、14℃以下は上着必須。
   - 降水確率50%以上または雨系weathercodeなら傘を明記。最高最低差10℃以上なら羽織りものを勧める。
   - 時間帯別の推移は共通手順2の算出結果をそのまま1文で使う。
4. **AI/テクノロジーニュース**: `WebSearch`を**1クエリのみ**実行する（日本語「生成AI ニュース <year>年<month>月」・英語「AI technology news <month year>」のうち、その時点でより新しい情報が見込める方を選ぶ）。モデルリリース・企業/資金動向・インフラ/地政学・技術トレンド等カテゴリ別に整理。`Sources:`セクション必須。
   - 旧仕様（英語＋日本語の2クエリ）より速いが、選ばなかった言語圏のニュースは拾えない点はトレードオフとして許容する。
5. **GIZMODO最新記事**: `WebFetch`で`https://www.gizmodo.jp/`（GIZMODO Japanトップページ）を取得し、掲載されている直近10件の記事タイトルとリンクをそのまま抽出する（AI/テック関連に絞らず、サイト全体の新着でよい）。各記事について、記事の内容が一目でわかる一言要約（一文）も添える。ページ上の見出し・リード文から分かる範囲で簡潔にまとめ、憶測で内容を補わない。10件に満たない場合は取得できた件数のみ記載し、その旨を一言添える。
6. **出力**（6セクション）:
   - `# 今日の予定`: 時間・内容・場所を表形式で。
   - `# 試験情報`: 当日〜14日後の試験関連予定を日付順の表または箇条書きで。該当なしなら「直近の試験予定はありません」の一言。
   - `# 今日のメール概要`: 「要確認」と「参考程度（カテゴリまとめ）」に分けて記載。
   - `# 今日の天気と服装`: 気温・降水確率・天候の要約1〜2行＋時間帯別の推移（傘を持つタイミングの目安）1行＋服装/持ち物を箇条書きで。
   - `# 最近のAI・テクノロジーニュース`: カテゴリ見出しごとに要点を箇条書き、末尾にSourcesリンク。続けて`## GIZMODO最新記事`小見出しでGIZMODO Japanの直近10件を列挙する。各記事は「タイトル＋リンク」の行の次の行に一言要約を添える形式（1件につき2行）で記載する。
   - `# 推しCheck`: <FAVORITE_VTUBER>の配信予定・新着動画等を箇条書きで。末尾にSourcesリンク。

## 昼モード（11:00〜16:59・簡易版）

1. **カレンダー**: 共通手順5で取得済みの「当日分」データのうち、現在時刻より前に終了したイベントを除外し「残りの予定」として提示する。
2. **メール**: `query: "newer_than:1d in:inbox is:important"`で「要確認」候補のみに絞って取得する（朝モードの全件取得より速いが、`IMPORTANT`ラベルが付かない要確認メール——例えば個別の大学ドメイン等——は拾えない可能性があるトレードオフを許容する）。参考程度のメールは個別列挙せず「その他〇件（プロモーション等）」のように件数だけ触れる（正確な件数が必要な場合のみ、朝モード相当の全件クエリで補う）。
3. **天気**: 共通手順2で取得済みの`weather.daily[0]`（今日）データを使い、気温・降水確率・傘要否を1〜2行の一言サマリに圧縮する（詳細な服装箇条書きは省略してよい）。現在時刻以降で天候が変わるタイミングがあれば、傘のタイミング判断材料として一言含める。目立った変化がなければ触れなくてよい。
4. **ニュース**: `WebSearch`は1クエリ（日本語 or 英語どちらか主要な方）に絞り、直近で一番大きいトピックを1〜2行で紹介する程度に留める。提示した情報の分だけSourcesを記載。
5. **出力**（5セクション）:
   - `# 残りの今日の予定`: 表形式。
   - `# 試験情報`: 当日〜14日後の試験関連予定を日付順の箇条書きで。該当なしなら「直近の試験予定はありません」の一言。
   - `# 要確認メール`: 箇条書き。なければ「要確認メールはありません」。
   - `# 天気・ニュースひとことメモ`: 天気1行（変化のタイミングがあれば含める）＋ニュース1〜2行。
   - `# 推しCheck`: <FAVORITE_VTUBER>の新着情報を1〜2行程度で簡潔に。

## 夜モード（17:00〜4:59・明日準備版）

1. **メール（見落としチェック）**: `query: "newer_than:1d in:inbox is:important"`で当日分の要確認候補を取得し、対応・返信した形跡がなさそうなものを列挙する。なければ「見落としている要確認メールは特にありません」と明記する。参考程度メールは扱わない。
2. **カレンダー**: 共通手順5で取得済みの「翌日分」データをそのまま使う（追加のAPI呼び出しは不要）。
3. **天気**: 共通手順2で取得済みの`weather.daily[1]`（明日）データと対応する`weather.hourly`（25〜48件目）を使い、朝モードと同じ基準（時間帯別の推移も含む）でフルの服装提案を行う。
4. **ニュース**: このモードではセクション自体を省略する（翌朝以降にフル版で確認する想定）。
5. **出力**（5セクション）:
   - `# 今日の見落としチェック`: 未対応と思われる要確認メールを箇条書き。
   - `# 試験情報`: 当日〜14日後の試験関連予定を日付順の箇条書きで。該当なしなら「直近の試験予定はありません」の一言。
   - `# 明日の予定`: 時間・内容・場所を表形式で。
   - `# 明日の天気と服装`: 気温・降水確率・天候の要約1〜2行＋時間帯別の推移（傘を持つタイミングの目安）1行＋服装/持ち物を箇条書きで。
   - `# 推しCheck`: <FAVORITE_VTUBER>の新着情報を箇条書きで。
