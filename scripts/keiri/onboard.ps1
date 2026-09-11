# =============================================================================
# GScale Onboard — 「1コマンドで、AIと一緒に働けるPCにする」共通エンジン（Windows）
# =============================================================================
#
# install_all.ps1 が「ツールを入れる」までを担うのに対し、本スクリプトは
# 人がつまずく残り全部（GitHubログイン・招待承諾・Git設定・VS Code の日本語化と
# 拡張機能・プロジェクトの取り込み・Claudeログイン）まで面倒を見る。
#
# 実行:
#   irm <URL>/onboard.ps1 | iex
#   powershell -ExecutionPolicy Bypass -File onboard.ps1 -Check
#
# 終了コード: 0=完了(PASS) / 2=一部未完(PARTIAL)
# 実行ログ: %USERPROFILE%\gscale-onboard.log
# =============================================================================
param(
  [switch]$Check,
  [switch]$SkipVSCode,
  [switch]$SkipProject
)

$ErrorActionPreference = "Continue"

# >>> PROFILE >>>
# ！このファイルは GScale-jp/fde-setup (@a6917d8) から自動生成されています。
# ！ここを直接編集しないでください。編集は fde-setup 側 → vendor_onboard.sh で再生成。
# ！profile: daimaru-keiri
$PROFILE_ID = if ($env:PROFILE_ID) { $env:PROFILE_ID } else { "daimaru-keiri" }
$PROFILE_NAME = if ($env:PROFILE_NAME) { $env:PROFILE_NAME } else { "大丸開発グループ 総務経理 自動化" }
$PROJECT_REPO = if ($env:PROJECT_REPO) { $env:PROJECT_REPO } else { "https://github.com/daimaru-d/daimaru-keiri-automation.git" }
$PROJECT_DIR = if ($env:PROJECT_DIR) { $env:PROJECT_DIR } else { "$HOME/daimaru-keiri-automation" }
$PROJECT_SETUP_CMD = if ($env:PROJECT_SETUP_CMD) { $env:PROJECT_SETUP_CMD } else { "python scripts/keiri.py bootstrap || (npm install playwright && npx --yes playwright install chromium)" }
$TOOLSET = if ($env:TOOLSET) { $env:TOOLSET } else { "lite" }
$EXTRA_TOOLS = if ($env:EXTRA_TOOLS) { $env:EXTRA_TOOLS } else { "python playwright" }
$ENV_TEMPLATE = if ($env:ENV_TEMPLATE) { $env:ENV_TEMPLATE } else { ".env" }
$ENV_TEMPLATE_KEYS = if ($env:ENV_TEMPLATE_KEYS) { $env:ENV_TEMPLATE_KEYS } else { "NOFU_API_URL NOFU_API_TOKEN DRY_RUN=1 ETAX_USER_ID ETAX_PASSWORD ELTAX_USER_ID ELTAX_PASSWORD" }
$VSCODE_EXTENSIONS = if ($env:VSCODE_EXTENSIONS) { $env:VSCODE_EXTENSIONS } else { "anthropic.claude-code MS-CEINTL.vscode-language-pack-ja" }
$WELCOME_DOC = if ($env:WELCOME_DOC) { $env:WELCOME_DOC } else { "README.md" }
$ASSET_BASE_URL = if ($env:ASSET_BASE_URL) { $env:ASSET_BASE_URL } else { "https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main/scripts/keiri" }
$EXTRA_NPM_GLOBALS = if ($env:EXTRA_NPM_GLOBALS) { $env:EXTRA_NPM_GLOBALS } else { "" }
$NEXT_HINT = if ($env:NEXT_HINT) { $env:NEXT_HINT } else { "    VS Code で Claude Code を開き「/menu」と入力すると、できることの一覧が出ます（困ったら「点検して」）" }
# <<< PROFILE <<<

$TOTAL = 7
$script:Failed = @()
$script:NeedEnvFill = $null
$LogFile = Join-Path $env:USERPROFILE "gscale-onboard.log"
if (-not $Check) { "" | Out-File -FilePath $LogFile -Encoding utf8 }

function Log($m)  { Write-Host $m; if (-not $Check) { $m | Out-File -FilePath $LogFile -Append -Encoding utf8 } }
function Step($n,$t) { Log ""; Log ("[{0}/{1}] {2}" -f $n,$TOTAL,$t) }
function OK($m)   { Log ("  OK  " + $m) }
function NG($m)   { Log ("  --  " + $m) }
function Warn($m) { Log ("  !   " + $m) }
function Fail($k,$m) { $script:Failed += $k; NG $m }
function Have($c) { $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
}

if ($PROJECT_REPO -and -not $PROJECT_DIR) {
  $leaf = [System.IO.Path]::GetFileNameWithoutExtension($PROJECT_REPO)
  $PROJECT_DIR = Join-Path $env:USERPROFILE $leaf
}

Log ""
Log ("=" * 60)
Log ("  " + $PROFILE_NAME + " - かんたんセットアップ")
Log ("=" * 60)
Log "  途中でブラウザが2回開きます（GitHub と Claude のログイン）。"
Log "  合計10〜20分ほど。ほとんどは待ち時間です。"
if ($Check) { Log "  [診断モード] 何も変更しません" }

# =============================================================================
Step 1 "パソコンの状態を確認しています"
# =============================================================================
OK ("Windows " + [System.Environment]::OSVersion.Version)
if (-not (Have "winget")) {
  Fail "winget" "WinGet がありません"
  Log ""
  Log "  Microsoft Store から「アプリ インストーラー」を入れてから、もう一度実行してください。"
  Log "  https://apps.microsoft.com/detail/9NBLGGH4NNS1"
  Log ""
  Log ("GSCALE_ONBOARD_RESULT: PARTIAL profile={0} missing=winget" -f $PROFILE_ID)
  exit 2
}
OK "WinGet"
try { Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 8 -UseBasicParsing | Out-Null; OK "インターネット接続" }
catch { Warn "外部サイトへ接続できません。プロキシ/セキュリティソフトの可能性があります（続行します）" }

# =============================================================================
Step 2 "必要なソフトを入れています（ここが一番時間がかかります）"
# =============================================================================
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installer = Join-Path $scriptDir "install_all.ps1"
if (-not (Test-Path $installer) -and $ASSET_BASE_URL) {
  $tmp = Join-Path $env:TEMP "install_all.ps1"
  try {
    Invoke-WebRequest -Uri ($ASSET_BASE_URL + "/install_all.ps1") -OutFile $tmp -UseBasicParsing
    if ((Get-Item $tmp).Length -gt 0) { $installer = $tmp; OK "インストーラを取得" }
  } catch { }
}

if (-not (Test-Path $installer)) {
  Fail "installer" "インストーラ(install_all.ps1)が見つかりません"
} elseif ($Check) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -CheckOnly
} else {
  # $args は PowerShell の自動変数なので使わない（上書きすると splat が壊れる）
  $instArgs = @()
  if ($TOOLSET -eq "lite") { $instArgs += "-Minimal"; $env:WITH_VSCODE = "1" }
  # lite でも案件に要るものだけを足す（full にすると gcloud/clasp のDLで10分近く延びる）
  foreach ($t in ($EXTRA_TOOLS -split '\s+')) {
    switch ($t) {
      "python"     { $env:WITH_PYTHON     = "1" }
      "playwright" { $env:WITH_PLAYWRIGHT = "1" }
    }
  }
  if ($SkipVSCode)         { $instArgs += "-SkipVSCode"; $env:WITH_VSCODE = "0" }
  if ($PROJECT_DIR)        { $instArgs += @("-TrustDir", $PROJECT_DIR) }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $installer @instArgs
  Refresh-Path
}

$needTools = @("git","node","gh","claude")
foreach ($t in ($EXTRA_TOOLS -split '\s+')) {
  if ($t -eq "python")     { $needTools += "python" }
  if ($t -eq "playwright") { $needTools += "playwright" }
}
foreach ($t in $needTools) {
  if (Have $t) { OK $t } else { Fail $t ($t + " が見つかりません") }
}

# プロファイル指定の追加CLI（例: Gemini CLI / Codex CLI）
if ($EXTRA_NPM_GLOBALS -and -not $Check -and (Have "npm")) {
  foreach ($pkg in ($EXTRA_NPM_GLOBALS -split '\s+')) {
    if (-not $pkg) { continue }
    cmd /c "npm install -g $pkg" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { OK $pkg } else { Warn ($pkg + " の導入に失敗（必須ではありません）") }
  }
}

# =============================================================================
Step 3 "GitHub にログインします"
# =============================================================================
$ghAuthed = $false
if (-not (Have "gh")) {
  Fail "gh-auth" "gh が無いためログインできません"
} else {
  gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { $ghAuthed = $true; OK ("ログイン済み（" + (gh api user --jq .login 2>$null) + "）") }
  elseif ($Check) { NG "未ログイン" }
  else {
    # アカウントの有無をここで確認する（無い人を「作成」まで連れて行く）
    Log "  GitHub のアカウントはお持ちですか？"
    $hasGh = Read-Host "  お持ちなら y、これから作るなら n を入れて Enter [y/n]"
    if ($hasGh -match '^(n|no)$') {
      Log ""
      Log "  作成ページをブラウザで開きます。"
      Log "  招待メール（GitHub からの Invitation）が届いている方は、"
      Log "  そのメールのリンクから作成してください。参加の手続きが自動で終わります。"
      Log ""
      Log "  入力するのは メールアドレス／パスワード／ユーザー名 の3つだけです。"
      Log "  ユーザー名は半角英数字で、他の人と同じものは使えません（例: uema-shoko）。"
      Start-Process "https://github.com/signup"
      Log ""
      Read-Host "  作成が終わったら Enter を押してください" | Out-Null
    }
    Log ""
    Log "  続けて、このパソコンと GitHub をつなぎます。"
    Log "  ブラウザが開いたら、画面に出る8文字のコードを貼り付けてください。"
    gh auth login --hostname github.com --git-protocol https --web
    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ghAuthed = $true; OK "ログインできました" }
    else { Fail "gh-auth" "GitHub ログイン未完了" }
  }
}

if ($ghAuthed -and -not $Check) {
  gh auth setup-git 2>$null | Out-Null
  OK "git が GitHub を使えるようになりました"

  # リポジトリ招待を自動で承諾（メールのボタンを押しに行く手間をなくす）
  $invites = gh api user/repository_invitations --jq '.[].id' 2>$null
  if ($invites) {
    foreach ($id in $invites) {
      if ($id) { gh api --method PATCH ("user/repository_invitations/" + $id) 2>$null | Out-Null; OK "リポジトリの招待を承諾しました" }
    }
  }

  # Git の名前・メールは GitHub から取得（入力させない＝つまずきを1つ消す）
  $gname = git config --global user.name  2>$null
  $gmail = git config --global user.email 2>$null
  if (-not $gname -or -not $gmail) {
    $login = gh api user --jq .login 2>$null
    $name  = gh api user --jq '.name // .login' 2>$null
    $uid   = gh api user --jq .id 2>$null
    $mail  = gh api user --jq '.email // empty' 2>$null
    if (-not $mail -and $uid) { $mail = "$uid+$login@users.noreply.github.com" }
    if ($name -and $mail) {
      git config --global user.name  $name
      git config --global user.email $mail
      OK ("Git の名前を設定: " + $name + " <" + $mail + ">")
    }
  } else { OK ("Git の名前は設定済み（" + $gname + "）") }
}

# 対象リポジトリへ「書き込める」か（当日いちばん多い失敗を前日に検知する）
$needAccess = $false
$myLogin = ""
if ($PROJECT_REPO -and (Have "gh") -and $ghAuthed) {
  $slug = ($PROJECT_REPO -replace '^https?://[^/]+/','') -replace '\.git$',''
  $myLogin = gh api user --jq .login 2>$null
  $canPush = gh api ("repos/" + $slug) --jq '.permissions.push' 2>$null
  if ($canPush -eq "true") { OK "このリポジトリに公開できます" }
  else {
    $needAccess = $true
    Warn "まだ公開の権限がありません（読むことはできます）"
    Warn ("GitHub ユーザー名「" + $myLogin + "」をグループに投稿してください（権限をお付けします）")
  }
}

# =============================================================================
Step 4 "VS Code を使えるようにしています"
# =============================================================================
if ($SkipVSCode) {
  NG "スキップ指定"
} else {
  if (-not (Have "code")) {
    # winget 導入直後は PATH 未反映のことがある → 既定の場所を直接探す
    foreach ($p in @(
      (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin"),
      "C:\Program Files\Microsoft VS Code\bin"
    )) {
      if (Test-Path (Join-Path $p "code.cmd")) { $env:Path = "$p;$env:Path"; break }
    }
  }
  if (Have "code") {
    OK ("VS Code (" + ((code --version 2>$null) | Select-Object -First 1) + ")")
    if (-not $Check) {
      $installed = (code --list-extensions 2>$null)
      foreach ($ext in ($VSCODE_EXTENSIONS -split '\s+')) {
        if (-not $ext) { continue }
        if ($installed -contains $ext) { OK ("拡張機能 " + $ext + "（導入済）") }
        else {
          code --install-extension $ext --force 2>$null | Out-Null
          if ($LASTEXITCODE -eq 0) { OK ("拡張機能 " + $ext + " を追加") }
          else { Warn ("拡張機能 " + $ext + " の追加に失敗（後で入れられます）") }
        }
      }
    }
  } else { Fail "vscode" "VS Code が見つかりません" }
}

# =============================================================================
Step 5 "プロジェクトを取り込んでいます"
# =============================================================================
if (-not $PROJECT_REPO -or $SkipProject) {
  NG "対象なし（スキップ）"
} elseif ($Check) {
  if (Test-Path (Join-Path $PROJECT_DIR ".git")) { OK $PROJECT_DIR } else { NG ($PROJECT_DIR + " が未取得") }
} elseif (-not (Have "git")) {
  Fail "project" "git が無いため取り込めません"
} else {
  if (Test-Path (Join-Path $PROJECT_DIR ".git")) {
    Push-Location $PROJECT_DIR; git pull --quiet --ff-only 2>$null; Pop-Location
    if ($LASTEXITCODE -eq 0) { OK "最新に更新しました" } else { Warn "更新をスキップ（ローカルに変更あり）" }
  } else {
    git clone --quiet $PROJECT_REPO $PROJECT_DIR 2>$null
    if (Test-Path (Join-Path $PROJECT_DIR ".git")) { OK ("取り込みました → " + $PROJECT_DIR) }
    else { Fail "project" ("取り込みに失敗しました（" + $PROJECT_REPO + "）") }
  }
  if ((Test-Path $PROJECT_DIR) -and $PROJECT_SETUP_CMD) {
    Log "  + 依存パッケージを準備しています（数分かかります）..."
    Push-Location $PROJECT_DIR
    # 出力は捨てない。ブラウザのダウンロード等はここで長く止まるため、
    # 「固まった」のか「進んでいる」のかが見えないと現場で不安になる。
    cmd /c $PROJECT_SETUP_CMD 2>&1 | ForEach-Object { if ($_) { Log ("    " + $_) } }
    if ($LASTEXITCODE -eq 0) { OK "準備完了" } else { Warn "依存パッケージの準備に失敗（後で再実行できます）" }
    Pop-Location
  }

  # 認証情報ファイル（.env）のひな形。値は本人に入力してもらう。
  # ここでは絶対に Read-Host で受け取らない（このスクリプトは実行ログを残すため）。
  if ((Test-Path $PROJECT_DIR) -and $ENV_TEMPLATE) {
    $envPath = Join-Path $PROJECT_DIR $ENV_TEMPLATE
    if (Test-Path $envPath) {
      OK ("設定ファイルは作成済み: " + $ENV_TEMPLATE)
    } else {
      $par = Split-Path $envPath -Parent
      if ($par -and -not (Test-Path $par)) { New-Item -ItemType Directory -Force -Path $par | Out-Null }
      $lines = @()
      foreach ($k in ($ENV_TEMPLATE_KEYS -split '\s+')) {
        if (-not $k) { continue }
        if ($k -like "*=*") { $lines += $k } else { $lines += ($k + "=") }
      }
      [System.IO.File]::WriteAllText($envPath, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
      OK ("設定ファイルのひな形を作成: " + $envPath)
      $script:NeedEnvFill = $envPath
    }
  }
}

# =============================================================================
Step 6 "Claude にログインできているか確認します"
# =============================================================================
$needClaudeLogin = $false
if (-not (Have "claude")) {
  Fail "claude" "claude が見つかりません"
} elseif (Test-Path (Join-Path $env:USERPROFILE ".claude\.credentials.json")) {
  OK "ログイン済み"
} else {
  NG "未ログイン（この後の案内でログインします）"
  $needClaudeLogin = $true
}

# =============================================================================
Step 7 "確認"
# =============================================================================
if ($script:Failed.Count -gt 0) {
  Log ""
  Log "== 未完了があります =="
  foreach ($f in $script:Failed) { Log ("  ・" + $f) }
  Log ""
  Log "  この画面をそのままスクリーンショットして送ってください。"
  Log ("  ログ: " + $LogFile)
  $result = "PARTIAL"; $rc = 2
} else { $result = "PASS"; $rc = 0 }

if ($Check) {
  Log ""
  Log ("GSCALE_ONBOARD_RESULT: {0} profile={1} missing={2}" -f $result,$PROFILE_ID,(($script:Failed -join ",") -replace '^$','none'))
  exit $rc
}

Log ""
Log ("=" * 60)
if ($result -eq "PASS") { Log "  準備できました！" } else { Log "  あと少しです" }
Log ("=" * 60)

if (-not $SkipVSCode -and (Have "code") -and $PROJECT_DIR -and (Test-Path $PROJECT_DIR)) {
  $welcome = if ($WELCOME_DOC) { Join-Path $PROJECT_DIR $WELCOME_DOC } else { "" }
  if ($welcome -and (Test-Path $welcome)) { code $PROJECT_DIR $welcome } else { code $PROJECT_DIR }
  Log "  VS Code を開きました。"
}

if ($script:NeedEnvFill) {
  Log ""
  Log "  【入力のお願い】"
  Log ("  " + $script:NeedEnvFill + " を開いて、ログイン情報を入力して保存してください。")
  Log "  このファイルは Git の管理対象外なので、外部に出ることはありません。"
  if (Have "code") { code $script:NeedEnvFill } else { notepad $script:NeedEnvFill }
}

if ($needAccess) {
  Log ""
  Log "  【ひとつだけお願いです】"
  Log ("  GitHub ユーザー名「" + $myLogin + "」をグループに投稿してください。")
  Log "  これが無いと、当日ホームページを公開するところまで進めません。"
}

Log ""
if ($needClaudeLogin) {
  Log "  最後に1回だけ、Claude のログインをします。"
  Log "  ブラウザが開いたら、ご自身の Claude アカウントで許可してください。"
  Log "  （終わったら、そのまま Claude Code を使えます）"
  Log ""
  Read-Host "  Enter キーを押すと始まります" | Out-Null
  if ($PROJECT_DIR -and (Test-Path $PROJECT_DIR)) { Set-Location $PROJECT_DIR }
  claude
  exit $rc
}

Log "  次にやること"
if ($NEXT_HINT) { Log $NEXT_HINT }
elseif ($PROJECT_DIR) { Log ("    cd " + $PROJECT_DIR + "; claude") }
Log ""
Log ("GSCALE_ONBOARD_RESULT: {0} profile={1} missing={2}" -f $result,$PROFILE_ID,(($script:Failed -join ",") -replace '^$','none'))
exit $rc
