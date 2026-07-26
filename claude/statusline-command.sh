#!/bin/bash
# Claude Code ステータスライン用スクリプト
# 標準入力からセッション情報のJSONを受け取り、以下の5項目を1行で表示する
#   1. モデル名と推論レベル              例: Sonnet 5 [high]
#   2. リポジトリ名と Git ブランチ        例: my-project ⎇ main
#   3. コンテキスト使用量（ゲージ+割合）  例: ●●●●○○○○○○ 40%
#   4. レートリミット消費（5h/7dウィンドウ）例: 5h: 26% ↺17:00 7d: 12%
#   5. 稼働時間（累計コストは非表示。理由は下記コメント参照）
# jq は未インストールのため、PATH 上の node で JSON をパースしている

node -e '
const fs = require("fs");
const { execSync } = require("child_process");

// 標準入力のJSONを同期的に読み込む（0 = stdin）
const raw = fs.readFileSync(0, "utf8");

let d;
try {
  d = JSON.parse(raw);
} catch {
  process.exit(0); // パース失敗時は何も表示しない
}

// このステータスラインは端末側で dim 表示される前提なので、
// あえて強調したい箇所（モデル名）だけ bold、区切り記号は dim にする
const dim = (s) => `\x1b[2m${s}\x1b[0m`;
const bold = (s) => `\x1b[1m${s}\x1b[0m`;

const parts = [];

// ---------------------------------------------------------------
// 1. モデル名と推論レベル
// ---------------------------------------------------------------
const modelName = d.model?.display_name ?? "unknown";
// effort は推論レベルに対応したモデルの場合のみ存在するフィールド
const effortLevel = d.effort?.level;
parts.push(effortLevel ? `${bold(modelName)} [${effortLevel}]` : bold(modelName));

// ---------------------------------------------------------------
// 2. リポジトリ名と Git ブランチ
// ---------------------------------------------------------------
// リポジトリ名: workspace.repo（originリモートから解決される任意フィールド）を優先し、
// 無ければ project_dir のディレクトリ名で代用する
const repoInfo = d.workspace?.repo;
const fallbackDir = d.workspace?.project_dir ?? d.workspace?.current_dir ?? d.cwd ?? "";
const repoName = repoInfo?.name ?? fallbackDir.split(/[\\/]/).filter(Boolean).pop() ?? "";

// ブランチ名: stdin の JSON には一般的な「現在の git ブランチ名」フィールドが存在しないため、
// --worktree セッションの worktree.branch を優先しつつ、無ければ git コマンドで直接取得する。
// git 呼び出しは他プロセスとのロック競合を避けるため --no-optional-locks を付与する。
let branch = d.worktree?.branch ?? "";
const gitCwd = d.workspace?.current_dir ?? d.cwd;
if (!branch && gitCwd) {
  try {
    branch = execSync(
      `git --no-optional-locks -C "${gitCwd}" branch --show-current`,
      { stdio: ["ignore", "pipe", "ignore"] }
    ).toString().trim();
  } catch {
    branch = ""; // gitリポジトリでない場合などは無視する
  }
}
if (repoName) {
  parts.push(branch ? `${repoName} ⎇ ${branch}` : repoName);
}

// ---------------------------------------------------------------
// 3. コンテキスト使用量（ゲージ + パーセンテージ）
// ---------------------------------------------------------------
const cw = d.context_window ?? {};
if (typeof cw.used_percentage === "number") {
  const used = Math.round(cw.used_percentage);
  const filled = Math.max(0, Math.min(10, Math.round(used / 10)));
  const gauge = "●".repeat(filled) + "○".repeat(10 - filled);
  parts.push(`${gauge} ${used}%`);
} else {
  // 会話開始前などで used_percentage がまだ計算されていない場合
  parts.push(dim("context: -"));
}

// ---------------------------------------------------------------
// 4. レートリミット消費（5時間 / 7日ウィンドウ）
// ---------------------------------------------------------------
// rate_limits は Claude.ai サブスクリプションかつ最初のAPI応答後にのみ含まれる任意フィールド
const rl = d.rate_limits;
if (rl) {
  const bits = [];
  if (rl.five_hour && typeof rl.five_hour.used_percentage === "number") {
    const pct = Math.round(rl.five_hour.used_percentage);
    let resetStr = "";
    if (typeof rl.five_hour.resets_at === "number") {
      // resets_at は UNIX epoch秒。ローカル時刻の HH:MM に変換する
      const t = new Date(rl.five_hour.resets_at * 1000);
      const hh = String(t.getHours()).padStart(2, "0");
      const mm = String(t.getMinutes()).padStart(2, "0");
      resetStr = ` ↺${hh}:${mm}`;
    }
    bits.push(`5h: ${pct}%${resetStr}`);
  }
  if (rl.seven_day && typeof rl.seven_day.used_percentage === "number") {
    bits.push(`7d: ${Math.round(rl.seven_day.used_percentage)}%`);
  }
  if (bits.length) parts.push(bits.join(" "));
}

// ---------------------------------------------------------------
// 5. 累計コストと稼働時間
// ---------------------------------------------------------------
// USD→JPY の換算レート。為替は変動するためスクリプト内の固定値であり、
// 実勢レートとはズレる。必要に応じてこの値を手動で更新すること。
const USD_TO_JPY = 155;

const cost = d.cost ?? {};
const costBits = [];

// total_cost_usd はクライアント側で推定されるセッション累計コスト（実際の請求額とは異なる）
if (typeof cost.total_cost_usd === "number") {
  const jpy = Math.round(cost.total_cost_usd * USD_TO_JPY);
  // 3桁区切りのカンマを入れて ¥1,227 形式にする
  costBits.push(`¥${jpy.toLocaleString("en-US")}`);
}

// total_duration_ms はセッション開始からの実経過時間（ミリ秒）
if (typeof cost.total_duration_ms === "number") {
  const totalMin = Math.floor(cost.total_duration_ms / 60000);
  const h = Math.floor(totalMin / 60);
  const m = totalMin % 60;
  costBits.push(h > 0 ? `${h}h${m}m` : `${m}m`);
}

if (costBits.length) parts.push(dim(costBits.join(" / ")));

process.stdout.write(parts.join(dim(" | ")));
'
