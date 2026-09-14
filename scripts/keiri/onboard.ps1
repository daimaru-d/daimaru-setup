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
#   irm | iex のときは exit せず return する（exit は貼り付けた PowerShell の窓ごと閉じ、
#   未完了の一覧が読めなくなる）。終了コードは $LASTEXITCODE に残る。
# 実行ログ: %USERPROFILE%\gscale-onboard.log
#
# PROJECT_SETUP_CMD の終了コード: 0=準備完了 / 2=準備はできたが人の対応待ち（未入力の設定など。
#   未完了にはしない）/ それ以外=失敗（未完了に数える）
# =============================================================================
param(
  [switch]$Check,
  [switch]$SkipVSCode,
  [switch]$SkipProject
)

$ErrorActionPreference = "Continue"
# 古い .NET 既定（TLS1.0）だと GitHub からの取得が理由不明で失敗するため
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# >>> PROFILE >>>
# ！このファイルは GScale-jp/fde-setup (@370ab14) から自動生成されています。
# ！ここを直接編集しないでください。編集は fde-setup 側 → vendor_onboard.sh で再生成。
# ！profile: daimaru-keiri
$PROFILE_ID = if ($env:PROFILE_ID) { $env:PROFILE_ID } else { "daimaru-keiri" }
$PROFILE_NAME = if ($env:PROFILE_NAME) { $env:PROFILE_NAME } else { "大丸開発グループ 総務経理 自動化" }
$PROJECT_REPO = if ($env:PROJECT_REPO) { $env:PROJECT_REPO } else { "https://github.com/daimaru-d/daimaru-keiri-automation.git" }
$PROJECT_DIR = if ($env:PROJECT_DIR) { $env:PROJECT_DIR } else { "$HOME/daimaru-keiri-automation" }
$PROJECT_SETUP_CMD = if ($env:PROJECT_SETUP_CMD) { $env:PROJECT_SETUP_CMD } else { "python scripts/keiri.py bootstrap" }
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
# irm | iex では $PSCommandPath が空になる（-File 実行では入る）
$script:ViaIex = [string]::IsNullOrEmpty($PSCommandPath)
# サービス/スケジューラ/CI などコンソール入力が無い環境では、Read-Host やブラウザログインで
# 永久に止まらないよう対話部分を飛ばす
$script:Interactive = [Environment]::UserInteractive -and -not ([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' })
$LogFile = Join-Path $env:USERPROFILE "gscale-onboard.log"
if (-not $Check) { "" | Out-File -FilePath $LogFile -Encoding utf8 }

function Log($m)  { Write-Host $m; if (-not $Check) { $m | Out-File -FilePath $LogFile -Append -Encoding utf8 } }
function Step($n,$t) { Log ""; Log ("[{0}/{1}] {2}" -f $n,$TOTAL,$t) }
function OK($m)   { Log ("  OK  " + $m) }
function NG($m)   { Log ("  --  " + $m) }
function Warn($m) { Log ("  !   " + $m) }
function Fail($k,$m) { $script:Failed += $k; NG $m }
function Have($c) { $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }
# 失敗したネイティブコマンドの出力（ErrorRecord 含む）を字下げしてログへ残す
function LogLines($lines) { foreach ($l in @($lines)) { $s = [string]$l; if ($s.Trim()) { Log ("    " + $s) } } }
function Refresh-Path {
  # install_all.ps1 の Refresh-Path と同じ既定の導入先も足す（ユーザー PATH に登録されない場所がある）
  $extra = @("$HOME\.local\bin", "$env:APPDATA\npm", "$env:LOCALAPPDATA\Programs\Python\Python312", "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts", "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin", "$env:ProgramFiles\Microsoft VS Code\bin", "$env:LOCALAPPDATA\Programs\gh\bin", "$env:ProgramFiles\GitHub CLI", "$env:LOCALAPPDATA\Programs\node", "$env:LOCALAPPDATA\Programs\PortableGit\cmd")
  $env:Path = (@([System.Environment]::GetEnvironmentVariable("Path","Machine"), [System.Environment]::GetEnvironmentVariable("Path","User")) + $extra) -join ";"
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
# install_all.ps1 は winget に依存しない（各ツールの公式インストーラで入れる）ため、無くても止めない
if (Have "winget") { OK "WinGet" } else { Warn "WinGet がありません（無くても続行できます）" }
try { Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 8 -UseBasicParsing | Out-Null; OK "インターネット接続" }
catch { Warn ("外部サイトへ接続できません。プロキシ/セキュリティソフトの可能性があります（続行します）: " + $_.Exception.Message) }

# =============================================================================
Step 2 "必要なソフトを入れています（ここが一番時間がかかります）"
# =============================================================================
# irm | iex では $PSScriptRoot が空。カレントフォルダは探さない（無関係・古い install_all.ps1 を実行しないため）
$installer = ""
if ($PSScriptRoot) {
  $localInstaller = Join-Path $PSScriptRoot "install_all.ps1"
  if (Test-Path $localInstaller) { $installer = $localInstaller }
}
if (-not $installer -and $ASSET_BASE_URL) {
  # 前回の取得物を使い回さないよう、毎回別名で取り直す
  $tmp = Join-Path $env:TEMP ("gscale-install_all-" + [guid]::NewGuid().ToString("N") + ".ps1")
  try {
    Invoke-WebRequest -Uri ($ASSET_BASE_URL + "/install_all.ps1") -OutFile $tmp -UseBasicParsing -ErrorAction Stop
    if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0) { $installer = $tmp; OK "インストーラを取得" }
  } catch { Warn ("インストーラの取得に失敗: " + $_.Exception.Message) }
}

if (-not $installer) {
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
  $instRc = $LASTEXITCODE
  # 合否は下のツール有無で判定する。終了コードは原因調査のために残す
  if ($instRc -ne 0) { Warn ("インストーラの終了コード: " + $instRc + "（下の確認で不足を判定します）") }
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
  elseif (-not $script:Interactive) { Fail "gh-auth" "GitHub 未ログイン（対話できない環境のためログインを飛ばしました）" }
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
  if ($LASTEXITCODE -eq 0) { OK "git が GitHub を使えるようになりました" }
  else { Warn "git と GitHub の連携設定に失敗しました（取り込みで失敗する場合はログを送ってください）" }

  # リポジトリ招待を自動で承諾（メールのボタンを押しに行く手間をなくす）。
  # 無関係な招待まで勝手に受けないよう、対象リポジトリと同じ持ち主（組織）の招待だけにする。
  $invOwner = if ($PROJECT_REPO -match 'github\.com[:/]+([^/]+)/') { $Matches[1] } else { "" }
  $invJson = (gh api user/repository_invitations 2>$null) -join "`n"
  $invites = @()
  if ($invJson) {
    # PS5.1 の ConvertFrom-Json は配列を1要素として返すため、ForEach-Object で展開する
    try { $invites = @($invJson | ConvertFrom-Json | ForEach-Object { $_ }) } catch { Warn ("招待一覧を読めませんでした: " + $_.Exception.Message) }
  }
  foreach ($inv in $invites) {
    if (-not $inv.id) { continue }
    if ($invOwner -and $inv.repository.owner.login -ne $invOwner) { continue }
    gh api --method PATCH ("user/repository_invitations/" + $inv.id) 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { OK ("リポジトリの招待を承諾しました（" + $inv.repository.full_name + "）") }
    else { Warn ("招待の承諾に失敗しました（" + $inv.repository.full_name + "）") }
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
  if ($canPush -eq "true") { OK "このリポジトリに書き込めます" }
  else {
    $needAccess = $true
    Warn "まだ書き込みの権限がありません（読むことはできます）"
    Warn ("GitHub ユーザー名「" + $myLogin + "」を担当者に伝えてください（権限をお付けします）")
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
  $projGit = Join-Path $PROJECT_DIR ".git"
  if (Test-Path $projGit) {
    Push-Location $PROJECT_DIR
    $pullOut = git pull --quiet --ff-only 2>&1
    $pullRc = $LASTEXITCODE
    Pop-Location
    if ($pullRc -eq 0) { OK "最新に更新しました" }
    else { Warn "最新への更新をスキップしました（手元の変更と重なる・接続できない等）"; LogLines $pullOut }
  } else {
    # 前回の取り込みが途中で止まった残骸があると clone が毎回失敗する。消さずに退避してから取り直す
    if ((Test-Path $PROJECT_DIR) -and (Get-ChildItem -Force -LiteralPath $PROJECT_DIR | Select-Object -First 1)) {
      $bak = $PROJECT_DIR + "-old-" + (Get-Date -Format "yyyyMMddHHmmss")
      try { Move-Item -LiteralPath $PROJECT_DIR -Destination $bak -ErrorAction Stop; Warn ("取り込み途中のフォルダを退避しました → " + $bak) }
      catch { Warn ("既存フォルダを退避できませんでした: " + $_.Exception.Message) }
    }
    $cloneOut = git clone --quiet $PROJECT_REPO $PROJECT_DIR 2>&1
    if (Test-Path $projGit) { OK ("取り込みました → " + $PROJECT_DIR) }
    else { Fail "project" ("取り込みに失敗しました（" + $PROJECT_REPO + "）"); LogLines $cloneOut }
  }

  # 認証情報ファイル（.env）のひな形。値は本人に入力してもらう。
  # ここでは絶対に Read-Host で受け取らない（このスクリプトは実行ログを残すため）。
  # PROJECT_SETUP_CMD の点検がひな形の有無を見られるよう、準備より先に作る。
  if ((Test-Path $projGit) -and $ENV_TEMPLATE) {
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

  if ((Test-Path $projGit) -and $PROJECT_SETUP_CMD) {
    Log "  + 依存パッケージを準備しています（数分かかります）..."
    Push-Location $PROJECT_DIR
    # 子プロセス（Python/Node）の出力は UTF-8。コンソール既定の文字コード（cp932 等）で読むと
    # 日本語が化けるため、この間だけ UTF-8 で受け取り、Python にも UTF-8 で出させる。
    $prevOutEnc = $null
    try { $prevOutEnc = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    $prevPyUtf8 = $env:PYTHONUTF8; $prevPyIoEnc = $env:PYTHONIOENCODING
    $env:PYTHONUTF8 = "1"; $env:PYTHONIOENCODING = "utf-8"
    # 出力は捨てない。ブラウザのダウンロード等はここで長く止まるため、
    # 「固まった」のか「進んでいる」のかが見えないと現場で不安になる。
    # 標準エラーは ErrorRecord で届くので、型名ではなく本文を表示する
    cmd /c $PROJECT_SETUP_CMD 2>&1 | ForEach-Object {
      $s = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
      if ($s -and $s.Trim()) { Log ("    " + $s) }
    }
    $setupRc = $LASTEXITCODE
    $env:PYTHONUTF8 = $prevPyUtf8; $env:PYTHONIOENCODING = $prevPyIoEnc
    if ($prevOutEnc) { try { [Console]::OutputEncoding = $prevOutEnc } catch { } }
    Pop-Location
    if ($setupRc -eq 0) { OK "準備完了" }
    elseif ($setupRc -eq 2) { Warn "準備はできました。上の点検で × の項目は、この後の案内に沿って対応してください" }
    else { Fail "project-setup" ("依存パッケージの準備が終わりませんでした（終了コード " + $setupRc + "）。上の表示を確認してください") }
  }
}

# =============================================================================
Step 6 "Claude にログインできているか確認します"
# =============================================================================
$claudeCred = Join-Path $env:USERPROFILE ".claude\.credentials.json"
$needClaudeLogin = $false
if (-not (Have "claude")) {
  Fail "claude" "claude が見つかりません"
} elseif (Test-Path $claudeCred) {
  OK "ログイン済み"
} elseif (-not $Check -and -not $script:Interactive) {
  # 対話できない環境ではこの後のログインを行わないため、集計（Step 7）より前に未完了として数える
  Fail "claude-login" "Claude 未ログイン（対話できない環境のためログインを飛ばしました）"
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
  $global:LASTEXITCODE = $rc
  if ($script:ViaIex) { return }
  exit $rc
}

Log ""
Log ("=" * 60)
if ($result -eq "PASS") { Log "  準備できました！" } else { Log "  あと少しです" }
Log ("=" * 60)

if ($script:Interactive -and -not $SkipVSCode -and (Have "code") -and $PROJECT_DIR -and (Test-Path $PROJECT_DIR)) {
  $welcome = if ($WELCOME_DOC) { Join-Path $PROJECT_DIR $WELCOME_DOC } else { "" }
  if ($welcome -and (Test-Path $welcome)) { code $PROJECT_DIR $welcome } else { code $PROJECT_DIR }
  Log "  VS Code を開きました。"
}

if ($script:NeedEnvFill) {
  Log ""
  Log "  【入力のお願い】"
  Log ("  " + $script:NeedEnvFill + " を開いて、ログイン情報を入力して保存してください。")
  Log "  このファイルは Git の管理対象外なので、外部に出ることはありません。"
  if ($script:Interactive) { if (Have "code") { code $script:NeedEnvFill } else { notepad $script:NeedEnvFill } }
}

if ($needAccess) {
  Log ""
  Log "  【ひとつだけお願いです】"
  Log ("  GitHub ユーザー名「" + $myLogin + "」を担当者に伝えてください。")
  Log "  これが無いと、作業内容を GitHub に保存（同期）するところまで進めません。"
}

Log ""
if ($needClaudeLogin -and $script:Interactive) {
  Log "  最後に1回だけ、Claude のログインをします。"
  Log "  ブラウザが開いたら、ご自身の Claude アカウントで許可してください。"
  Log "  （終わったら、そのまま Claude Code を使えます）"
  Log ""
  Read-Host "  Enter キーを押すと始まります" | Out-Null
  if ($PROJECT_DIR -and (Test-Path $PROJECT_DIR)) { Set-Location $PROJECT_DIR }
  claude
  # claude を閉じた後に、本当にログインできたかを確かめてから結果を出す
  if (Test-Path $claudeCred) { OK "Claude にログインできました" }
  else { Fail "claude-login" "Claude のログインが確認できませんでした（もう一度 claude を起動してログインしてください）"; $result = "PARTIAL"; $rc = 2 }
}

Log "  次にやること"
if ($NEXT_HINT) { Log $NEXT_HINT }
elseif ($PROJECT_DIR) { Log ("    cd " + $PROJECT_DIR + "; claude") }
Log ""
Log ("GSCALE_ONBOARD_RESULT: {0} profile={1} missing={2}" -f $result,$PROFILE_ID,(($script:Failed -join ",") -replace '^$','none'))
$global:LASTEXITCODE = $rc
if ($script:ViaIex) { return }
exit $rc
