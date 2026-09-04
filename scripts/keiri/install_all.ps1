# ！このファイルは GScale-jp/fde-setup (@b74f5a8) から自動生成されています。
# ！ここを直接編集しないでください。編集は fde-setup 側 → vendor_onboard.sh で再生成。
# ！profile: daimaru-keiri
#Requires -Version 5.1
<#
  install_all.ps1 — Windows 一括インストーラ（全部入り）

  まっさらな Windows に、FDE標準のツールチェーンを一括導入する:
    Node.js / @google/clasp / Python / gcloud SDK / uv(+workspace-mcp=gws) /
    Claude Code(CLI) / git(+Git Bash 同梱) / VS Code / GitHub CLI(gh)

  方針: winget に依存せず、各ツールの公式インストーラ/スクリプトで直接導入
        （Windows 10/11 デスクトップ と Windows Server の両方で同じ経路が動く）。
  冪等: 導入済みはスキップ。管理者でない場合は自動的にユーザー領域導入(-UserScope)へ
        切り替える（管理者権限なしでも全ツールが入る）。

  実行:
    powershell -ExecutionPolicy Bypass -File .\scripts\install_all.ps1
  オプション:
    -CheckOnly            何も変更せず現状診断だけ行う（サポートの切り分け用）
    -Minimal              コアのみ導入（node/git/gh/claude + Claude既定設定）
    -WithPython           -Minimal でも Python を入れる（積算Excel処理など）
    -WithPlaywright       Playwright と chromium を導入し、実際に起動して確認する
    -UserScope            管理者権限を使わず全てユーザー領域に導入（非管理者では自動ON）
    -SkipPython -SkipGit -SkipVSCode
    -RestoreCreds <zip>   backup_creds.ps1 / backup_creds.sh の出力から認証情報を復元
    -RestoreOnly          復元だけ実行（ツール導入はしない）
    -TrustDir <path>      Claude Code の信頼済みフォルダを事前登録（ベストエフォート）

  終了コード: 0=コア全て導入済(PASS) / 2=一部未導入(PARTIAL)
  実行ログ: %USERPROFILE%\fde-setup-install.log（つまずいたらこのファイルをサポートへ）
#>
[CmdletBinding()]
param(
  [switch]$CheckOnly,
  [switch]$Minimal,
  [switch]$WithPython,
  [switch]$WithPlaywright,
  [switch]$UserScope,
  [switch]$SkipPython,
  [switch]$SkipGit,
  [switch]$SkipVSCode,
  [string]$RestoreCreds,
  [switch]$RestoreOnly,
  [string]$TrustDir
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # PS5.1: 進捗バーで大容量DLが激遅になるのを防ぐ
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$script:StartTime = Get-Date

# onboard.ps1 からは環境変数で渡ってくる（WITH_VSCODE と同じ経路）
if ($env:WITH_PYTHON     -eq '1') { $WithPython     = $true }
if ($env:WITH_PLAYWRIGHT -eq '1') { $WithPlaywright = $true }

function Has($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Log($m) { Write-Host $m }
function HasPython {
  # Microsoft Store の「python.exe スタブ」（実行するとストアが開くだけ）を導入済と誤検知しない
  $c = Get-Command python -ErrorAction SilentlyContinue
  if (-not $c) { return $false }
  if ($c.Source -like '*WindowsApps*') { return $false }
  return $true
}
function Refresh-Path {
  $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $u = [Environment]::GetEnvironmentVariable('Path', 'User')
  $extra = @("$HOME\.local\bin", "$env:APPDATA\npm", "$env:LOCALAPPDATA\Programs\Python\Python312", "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts", "$env:LOCALAPPDATA\Google\CloudSDK\google-cloud-sdk\bin", "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin", "$env:ProgramFiles\Microsoft VS Code\bin", "$env:LOCALAPPDATA\Programs\gh\bin", "$env:ProgramFiles\GitHub CLI", "$env:LOCALAPPDATA\Programs\node", "$env:LOCALAPPDATA\Programs\PortableGit\cmd")
  $env:Path = (@($m, $u) + $extra -join ';')
}
function Add-UserPath($dir) {
  if (-not $dir) { return }
  $up = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($up -notlike "*$dir*") { [Environment]::SetEnvironmentVariable('Path', "$up;$dir", 'User') }
  $env:Path = "$env:Path;$dir"
}
function Get-GitHubLatestTag($repo) {
  # API → 失敗時（レート制限等）は releases/latest のリダイレクトからタグを解決
  try { return (Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'gscale' }).tag_name } catch {}
  try {
    $req = [System.Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
    $req.AllowAutoRedirect = $false
    $req.UserAgent = 'gscale'
    $resp = $req.GetResponse()
    $loc = $resp.Headers['Location']
    $resp.Close()
    if ($loc) { return ($loc -split '/tag/')[-1] }
  } catch {}
  return $null
}
function Invoke-FdeDownload($url, $dst) { (New-Object System.Net.WebClient).DownloadFile($url, $dst) }

# ---- 認証情報の復元（backup_creds の ZIP・OS横断の統一レイアウト）----
function Restore-Creds($zipPath) {
  Log "`n[+] 認証情報の復元: $zipPath"
  if (-not (Test-Path $zipPath)) { Log "  X 指定の zip が見つかりません: $zipPath"; return $false }
  try {
    $stg = Join-Path $env:TEMP ("rcreds_" + [guid]::NewGuid().ToString('N'))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $stg)
    $map = @{
      '.clasprc.json'         = "$env:USERPROFILE\.clasprc.json"
      'gcloud'                = "$env:APPDATA\gcloud"
      'gh'                    = "$env:APPDATA\GitHub CLI"
      'GitHub CLI'            = "$env:APPDATA\GitHub CLI"
      '.claude.json'          = "$env:USERPROFILE\.claude.json"
      '.credentials.json'     = "$env:USERPROFILE\.claude\.credentials.json"
      '.google_workspace_mcp' = "$env:USERPROFILE\.google_workspace_mcp"
    }
    foreach ($k in $map.Keys) {
      $src = Join-Path $stg $k
      if (Test-Path $src) {
        $dst = $map[$k]; $par = Split-Path $dst -Parent
        # .claude.json はバックアップ内が最小化版のため、既存（MCP登録・信頼情報等を含む）を潰さない
        if ($k -eq '.claude.json' -and (Test-Path $dst)) { Log "  ~ .claude.json は既存を保持（上書きしない）"; continue }
        if ($par -and -not (Test-Path $par)) { New-Item -ItemType Directory -Force -Path $par | Out-Null }
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue }
        Copy-Item $src $dst -Recurse -Force -ErrorAction SilentlyContinue
        Log "  + 復元 $dst"
      }
    }
    Remove-Item $stg -Recurse -Force -ErrorAction SilentlyContinue
    Log "  → clasp / gcloud / gh / claude / gws が再ログイン無しで使えるはずです。"
    return $true
  } catch { Log ("  X 復元失敗: " + $_.Exception.Message); return $false }
}

# ---- サマリ（機械可読な FDE_RESULT 行で終わる）----
function Show-Summary {
  Refresh-Path
  Log "`n================================================"
  Log " 導入結果サマリ"
  Log "================================================"
  if ($Minimal) { $core = @('node', 'npm', 'git', 'gh', 'claude') }
  else { $core = @('node', 'npm', 'clasp', 'python', 'gcloud', 'uv', 'uvx', 'claude', 'git', 'gh') }
  # 明示指定した追加ツールも「入っていて当然」の扱いにする（PARTIAL で気づけるように）
  if ($WithPython -and $core -notcontains 'python') { $core += 'python' }
  if ($WithPlaywright) { $core += 'playwright' }
  $missing = @()
  foreach ($t in $core) {
    $present = if ($t -eq 'python') { HasPython } else { Has $t }
    if ($present) { Log "  OK  $t" } else { Log "  --  $t（未導入 / 新シェルで反映の場合あり）"; $missing += $t }
  }
  if (-not $Minimal) {
    if (Has code) { Log "  OK  code（任意）" } else { Log "  --  code（任意）" }
  }
  if ($WithPlaywright) {
    $pwDir = Join-Path $env:LOCALAPPDATA 'ms-playwright'
    if ((Test-Path $pwDir) -and (Get-ChildItem $pwDir -Directory -Filter 'chromium*' -ErrorAction SilentlyContinue)) { Log "  OK  chromium（ブラウザ本体）" }
    else { Log "  --  chromium（ブラウザ本体が未取得）" }
  }
  # Git Bash は Git for Windows / PortableGit に同梱
  $gitbash = @("$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\PortableGit\bin\bash.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($gitbash) { Log "  OK  git-bash（git に同梱）" } else { Log "  --  git-bash（git 導入後に同梱）" }
  $elapsed = [int]((Get-Date) - $script:StartTime).TotalSeconds
  Log ""
  if ($missing.Count -eq 0) {
    Log ("FDE_RESULT: PASS core=" + $core.Count + "/" + $core.Count + " elapsed=" + $elapsed + "s")
    return 0
  } else {
    Log ("FDE_RESULT: PARTIAL core=" + ($core.Count - $missing.Count) + "/" + $core.Count + " missing=" + ($missing -join ',') + " elapsed=" + $elapsed + "s")
    return 2
  }
}

# =============================================================
# メイン
# =============================================================
Log "================================================"
Log " Windows 一括インストーラ (install_all)"
try { Log ("  os=" + (Get-CimInstance Win32_OperatingSystem).Caption + " / PS=" + $PSVersionTable.PSVersion) } catch {}
$modeNote = @()
if ($CheckOnly) { $modeNote += '診断のみ' }
if ($Minimal) { $modeNote += 'MINIMAL' }
if ($UserScope) { $modeNote += 'UserScope' }
if ($modeNote.Count -gt 0) { Log ("  モード: " + ($modeNote -join ' / ')) }
Log "================================================"

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $UserScope) {
  $UserScope = $true
  Log "  ! 管理者で未実行 → ユーザー領域導入(-UserScope)に自動切替（管理者権限は使いません）。"
}

# 復元だけ実行するモード
if ($RestoreOnly) {
  if (-not $RestoreCreds) { Log "  X -RestoreOnly には -RestoreCreds <zip> の指定が必要です"; exit 1 }
  if (Restore-Creds $RestoreCreds) { exit 0 } else { exit 1 }
}

# 実行ログ（診断モード以外は自動でファイルにも残す）
$logPath = Join-Path $env:USERPROFILE 'fde-setup-install.log'
$transcriptOn = $false
if (-not $CheckOnly -and $env:FDE_NO_LOG -ne '1') {
  try { Start-Transcript -Path $logPath -Append | Out-Null; $transcriptOn = $true } catch {}
}

# ネットワーク事前診断（プロキシ/セキュリティソフトの切り分け・警告のみで続行）
$netOk = $false
foreach ($u in @('https://www.google.com', 'https://claude.ai')) {
  try { Invoke-WebRequest -Uri $u -Method Head -TimeoutSec 8 -UseBasicParsing | Out-Null; $netOk = $true; break } catch {}
}
if (-not $netOk) { Log "  ! 外部サイトへ接続できません。プロキシ/セキュリティソフト/ネット接続を確認してください（続行はします）。" }

# 診断のみモード: 何も変更せず現状を報告して終了
if ($CheckOnly) {
  $rc = Show-Summary
  exit $rc
}

# ---- 1. Node.js（管理者=公式MSI / UserScope=公式ZIP）------------
Log "`n[1/10] Node.js (LTS)"
if (Has node) { Log ("  OK node " + (node --version)) }
else {
  try {
    $idx = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    $lts = ($idx | Where-Object { $_.lts } | Select-Object -First 1).version
    if ($UserScope) {
      $zurl = "https://nodejs.org/dist/$lts/node-$lts-win-x64.zip"
      $nzip = "$env:TEMP\node-lts.zip"
      Log "  DL $zurl（ユーザー領域導入）"
      Invoke-FdeDownload $zurl $nzip
      $ntmp = Join-Path $env:TEMP ("nodezip_" + [guid]::NewGuid().ToString('N'))
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      [System.IO.Compression.ZipFile]::ExtractToDirectory($nzip, $ntmp)
      $inner = Get-ChildItem -Path $ntmp -Directory | Select-Object -First 1
      $ndst = "$env:LOCALAPPDATA\Programs\node"
      if (Test-Path $ndst) { Remove-Item $ndst -Recurse -Force -ErrorAction SilentlyContinue }
      New-Item -ItemType Directory -Force -Path (Split-Path $ndst -Parent) | Out-Null
      Move-Item $inner.FullName $ndst -Force
      Add-UserPath $ndst
      Remove-Item $ntmp -Recurse -Force -ErrorAction SilentlyContinue
    } else {
      $url = "https://nodejs.org/dist/$lts/node-$lts-x64.msi"
      $msi = "$env:TEMP\node-lts.msi"
      Log "  DL $url"
      Invoke-FdeDownload $url $msi
      Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
    }
  } catch { Log ("  X Node 失敗: " + $_.Exception.Message) }
  Refresh-Path
  if (Has node) { Log ("  OK node " + (node --version)) } else { Log "  X node 未導入" }
}

# ---- 2. @google/clasp（npm）-------------------------------------
if (-not $Minimal) {
  Log "`n[2/10] @google/clasp"
  if (Has clasp) { Log ("  OK clasp " + (clasp --version 2>$null)) }
  elseif (Has npm) {
    cmd /c "npm install -g @google/clasp" 2>$null | Out-Null
    Refresh-Path
    if (Has clasp) { Log "  OK clasp 導入" } else { Log "  X clasp 失敗" }
  }
  else { Log "  X npm 無し（Node 導入後に再実行）" }
}

# ---- 3. Python（公式インストーラ・/quiet。UserScope=ユーザー導入）----
if (((-not $Minimal) -or $WithPython) -and (-not $SkipPython)) {
  Log "`n[3/10] Python 3"
  if (HasPython) { Log ("  OK " + (python --version 2>&1)) }
  else {
    try {
      $pver = '3.12.7'
      $purl = "https://www.python.org/ftp/python/$pver/python-$pver-amd64.exe"
      $pexe = "$env:TEMP\python-setup.exe"
      Log "  DL $purl"
      Invoke-FdeDownload $purl $pexe
      if ($UserScope) {
        Start-Process $pexe -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_test=0" -Wait
      } else {
        Start-Process $pexe -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
      }
    } catch { Log ("  X Python 失敗: " + $_.Exception.Message) }
    Refresh-Path
    if (HasPython) { Log ("  OK " + (python --version 2>&1)) } else { Log "  X python 未導入" }
  }
}

# ---- 4. gcloud SDK（bundled zip + install.bat --quiet）----------
if (-not $Minimal) {
  Log "`n[4/10] gcloud SDK"
  if (Has gcloud) { Log ("  OK " + ((gcloud --version 2>$null) | Select-Object -First 1)) }
  else {
    try {
      if (HasPython) {
        $zurl = 'https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-windows-x86_64.zip'                 # 軽量(約80MB)・導入済Pythonを利用
        $py = (Get-Command python).Source
      } else {
        $zurl = 'https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-windows-x86_64-bundled-python.zip' # 自己完結(約104MB)
        $py = $null
      }
      $zip = "$env:TEMP\gcloud.zip"
      $dst = "$env:LOCALAPPDATA\Google\CloudSDK"   # スペース無しパス（install.bat/PATH の事故防止）
      Log "  ※ gcloud は容量が大きく、DL+展開で数分かかります（進捗は出ません。そのままお待ちください）..."
      Invoke-FdeDownload $zurl $zip
      if (Test-Path $dst) { Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue }
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dst)
      if ($py) { $env:CLOUDSDK_PYTHON = $py }   # 非bundled は外部Python を使う
      & "$dst\google-cloud-sdk\install.bat" --quiet --path-update true --usage-reporting false 2>$null | Out-Null
      # install.bat の PATH 反映が効かない環境向けに、bin を明示的に PATH へ追加
      Add-UserPath "$dst\google-cloud-sdk\bin"
    } catch { Log ("  X gcloud 失敗: " + $_.Exception.Message) }
    Refresh-Path
    if (Has gcloud) { Log "  OK gcloud 導入" } else { Log "  X gcloud 未導入（新シェルで反映の場合あり）" }
  }
}

# ---- 5. uv / uvx（astral.sh 公式・ユーザー領域）-----------------
if (-not $Minimal) {
  Log "`n[5/10] uv / uvx"
  if ((Has uvx) -or (Has uv)) { Log "  OK uv/uvx" }
  else {
    # 子プロセスで実行: ベンダーの install.ps1 を iex で現在スコープに流し込むと、
    # 先方が定義する関数（例: uv の `Download`）が本スクリプトの関数を上書きしてしまう
    try { & powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex" *> $null } catch { Log ("  X uv 失敗: " + $_.Exception.Message) }
    Refresh-Path
    if (Has uvx) { Log "  OK uv 導入" } else { Log "  X uv 未導入（新シェルで反映の場合あり）" }
  }
}

# ---- 6. workspace-mcp (gws) 動作確認 ----------------------------
if (-not $Minimal) {
  Log "`n[6/10] workspace-mcp (gws)"
  if (Has uvx) {
    try { uvx workspace-mcp --help *> $null; Log "  OK workspace-mcp 実行可" }
    catch { Log "  ! workspace-mcp 取得失敗（ネット/Python 要確認）" }
  }
  else { Log "  ~ uvx 無しでスキップ" }
}

# ---- 7. Claude CLI（claude.ai 公式・ユーザー領域）---------------
Log "`n[7/10] Claude CLI"
if (Has claude) { Log "  OK claude" }
else {
  # 子プロセスで実行（スコープ汚染防止・uv と同じ理由）
  try { & powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex" *> $null } catch { Log ("  X claude 失敗: " + $_.Exception.Message) }
  Refresh-Path
  if (Has claude) { Log "  OK claude 導入" } else { Log "  X claude 未導入（新シェルで反映の場合あり）" }
}

# ---- 8. git（管理者=Git for Windows / UserScope=PortableGit）----
if (-not $SkipGit) {
  Log "`n[8/10] git"
  if (Has git) { Log ("  OK " + (git --version)) }
  else {
    try {
      $gtag = Get-GitHubLatestTag 'git-for-windows/git'   # 例: v2.50.1.windows.1
      $gname = $null
      if ($gtag -match '^v(\d+\.\d+\.\d+)\.windows\.(\d+)$') {
        $gname = $Matches[1]
        if ([int]$Matches[2] -gt 1) { $gname = $Matches[1] + '.' + $Matches[2] }
      }
      if (-not $gname) { throw "git バージョン解決に失敗 (tag=$gtag)" }
      if ($UserScope) {
        # PortableGit（自己展開7z・管理者不要・bash 同梱）
        $gasset = "PortableGit-$gname-64-bit.7z.exe"
        $gexe = "$env:TEMP\$gasset"
        $gdst = "$env:LOCALAPPDATA\Programs\PortableGit"
        Log "  DL $gasset（ユーザー領域導入）"
        Invoke-FdeDownload "https://github.com/git-for-windows/git/releases/download/$gtag/$gasset" $gexe
        if (Test-Path $gdst) { Remove-Item $gdst -Recurse -Force -ErrorAction SilentlyContinue }
        Start-Process $gexe -ArgumentList "-o`"$gdst`" -y" -Wait
        Add-UserPath "$gdst\cmd"
        Refresh-Path
        if (-not (Has git)) {
          # SFX が動かない環境向けフォールバック: MinGit ZIP（純ZIP展開・bash 無しの最小構成）
          $masset = "MinGit-$gname-64-bit.zip"
          $mzip = "$env:TEMP\mingit.zip"
          Log "  DL $masset（フォールバック）"
          Invoke-FdeDownload "https://github.com/git-for-windows/git/releases/download/$gtag/$masset" $mzip
          if (Test-Path $gdst) { Remove-Item $gdst -Recurse -Force -ErrorAction SilentlyContinue }
          New-Item -ItemType Directory -Force -Path $gdst | Out-Null
          Add-Type -AssemblyName System.IO.Compression.FileSystem
          [System.IO.Compression.ZipFile]::ExtractToDirectory($mzip, $gdst)
          Add-UserPath "$gdst\cmd"
        }
      } else {
        $gasset = "Git-$gname-64-bit.exe"
        $gexe = "$env:TEMP\git-setup.exe"
        Log "  DL $gasset"
        Invoke-FdeDownload "https://github.com/git-for-windows/git/releases/download/$gtag/$gasset" $gexe
        Start-Process $gexe -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP-" -Wait
      }
    } catch { Log ("  X git 失敗: " + $_.Exception.Message) }
    Refresh-Path
    if (Has git) { Log ("  OK " + (git --version)) } else { Log "  X git 未導入" }
  }
}

# ---- 9. Visual Studio Code（公式 user installer・管理者不要=UACなし）---
# WITH_VSCODE=1 は「コアのみ + VS Code」（onboard.ps1 の lite プロファイル）用。
if (((-not $Minimal) -or ($env:WITH_VSCODE -eq "1")) -and (-not $SkipVSCode)) {
  Log "`n[9/10] Visual Studio Code"
  if (Has code) { Log "  OK code 導入済" }
  else {
    try {
      $vexe = "$env:TEMP\vscode-setup.exe"
      Log "  DL VS Code (user installer・管理者不要)..."
      Invoke-FdeDownload 'https://update.code.visualstudio.com/latest/win32-x64-user/stable' $vexe
      Start-Process $vexe -ArgumentList '/VERYSILENT /NORESTART /MERGETASKS="!runcode,addtopath"' -Wait
    } catch { Log ("  X VSCode 失敗: " + $_.Exception.Message) }
    Refresh-Path
    if (Has code) { Log "  OK VSCode 導入" } else { Log "  X VSCode 未導入（新シェルで反映の場合あり）" }
  }
}

# ---- 10. GitHub CLI（gh / 公式 ZIP・管理者不要）-----------------
Log "`n[10/10] GitHub CLI (gh)"
if (Has gh) { Log ("  OK " + ((gh --version 2>$null) | Select-Object -First 1)) }
else {
  try {
    $tag = Get-GitHubLatestTag 'cli/cli'
    if (-not $tag) { throw 'gh バージョン解決に失敗' }
    $ver = $tag.TrimStart('v')
    $gzip = "$env:TEMP\gh.zip"
    $gdst = "$env:LOCALAPPDATA\Programs\gh"
    Log "  DL gh_${ver}_windows_amd64.zip"
    Invoke-FdeDownload "https://github.com/cli/cli/releases/download/$tag/gh_${ver}_windows_amd64.zip" $gzip
    if (Test-Path $gdst) { Remove-Item $gdst -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $gdst | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($gzip, $gdst)
    $ghbin = (Get-ChildItem -Path $gdst -Recurse -Filter gh.exe | Select-Object -First 1).DirectoryName
    if ($ghbin) { Add-UserPath $ghbin }
  } catch { Log ("  X gh 失敗: " + $_.Exception.Message) }
  Refresh-Path
  if (Has gh) { Log ("  OK " + ((gh --version 2>$null) | Select-Object -First 1)) } else { Log "  X gh 未導入（新シェルで反映の場合あり）" }
}

# ---- Playwright（ブラウザ操作の自動化・-WithPlaywright / WITH_PLAYWRIGHT=1）----
# AndPad のようにAPIが使えない業務システムを Claude Code から操作するための土台。
# ブラウザ本体は %LOCALAPPDATA%\ms-playwright に入るため管理者権限は不要。
# ここで先に取得しておくと、各プロジェクト側の npm install は同じキャッシュを共有するので
# 現場での待ち時間が数分短くなる。
if ($WithPlaywright) {
  Log "`n[+] Playwright（ブラウザ操作）"
  if (-not (Has npm)) {
    Log "  X npm 無し（Node 導入後に再実行してください）"
  } else {
    if (-not (Has playwright)) {
      Log "  npm install -g playwright ..."
      cmd /c "npm install -g playwright" 2>&1 | Out-Null
      Refresh-Path
    }
    if (Has playwright) { Log ("  OK playwright " + ((playwright --version 2>$null) | Select-Object -First 1)) }
    else { Log "  X playwright CLI 未導入" }

    # ブラウザ本体。約150MB・回線により数分かかる。取得済みなら即座に終わる。
    Log "  ブラウザ(chromium)を取得しています。数分かかります..."
    cmd /c "npx --yes playwright install chromium" 2>&1 | ForEach-Object { if ($_) { Log ("    " + $_) } }

    # 「ダウンロードは成功したが起動できない」をここで検出する。
    # プロキシ/セキュリティソフト配下では実際に起こるため、当日ではなく今つぶす。
    $gRoot = $null
    try { $gRoot = (cmd /c "npm root -g" 2>$null | Where-Object { $_ } | Select-Object -Last 1).Trim() } catch {}
    if ($gRoot -and (Test-Path $gRoot)) {
      # グローバル node_modules の「親」に置くと ESM の解決が playwright を見つけられる
      $probe = Join-Path (Split-Path $gRoot -Parent) 'fde_pw_probe.mjs'
      $code = @'
import { chromium } from "playwright";
const b = await chromium.launch({ headless: true });
console.log("PW_PROBE_OK " + b.version());
await b.close();
'@
      $wrote = $false
      try { [System.IO.File]::WriteAllText($probe, $code, (New-Object System.Text.UTF8Encoding($false))); $wrote = $true } catch {}
      if (-not $wrote) {
        Log "  ! 確認用ファイルを書き込めず、起動確認をスキップしました"
        $out = @()
      } else {
        $out = & node $probe 2>&1
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
      }
      if ($out -match 'PW_PROBE_OK') { Log ("  OK ブラウザ起動を確認: " + (($out | Select-String 'PW_PROBE_OK') -replace 'PW_PROBE_OK ', 'chromium ')) }
      elseif ($wrote) {
        Log "  X ブラウザを起動できませんでした（ダウンロードは終わっている可能性があります）"
        Log ("    " + ($out -join ' / '))
      }
    } else {
      Log "  ! npm root -g を解決できず、起動確認をスキップしました"
    }
  }
}

# ---- Claude Code 既定設定（auto モード・摩擦ゼロ化）-------------
# 許可プロンプトを激減させる auto モードを既定化（安全チェックは維持）。
# auto は ~/.claude/settings.json（ユーザー設定）に置く必要がある（プロジェクト設定では無効化される）。
# FDE_CLAUDE_BLOCK_BEGIN
Log "`n[+] Claude Code 既定設定（auto モード）"
try {
  $cdir = "$env:USERPROFILE\.claude"
  if (-not (Test-Path $cdir)) { New-Item -ItemType Directory -Force -Path $cdir | Out-Null }
  $cset = Join-Path $cdir 'settings.json'
  $defaultAllow = @(
    'Read', 'Write', 'Edit',
    'Bash(git:*)', 'Bash(gh:*)',
    'Bash(python:*)', 'Bash(python3:*)', 'Bash(pip:*)', 'Bash(pip3:*)',
    'Bash(node:*)', 'Bash(npm:*)', 'Bash(npx:*)', 'Bash(clasp:*)',
    'Bash(uv:*)', 'Bash(uvx:*)', 'Bash(gcloud:*)',
    'Bash(rg:*)', 'Bash(grep:*)', 'Bash(sed:*)', 'Bash(awk:*)',
    'Bash(ls:*)', 'Bash(cat:*)', 'Bash(find:*)', 'Bash(mkdir:*)',
    'Bash(mv:*)', 'Bash(cp:*)', 'Bash(chmod:*)', 'Bash(which:*)', 'Bash(where:*)',
    'Bash(echo:*)', 'Bash(head:*)', 'Bash(tail:*)',
    'Bash(open:*)', 'Bash(start:*)', 'Bash(explorer:*)', 'Bash(code:*)',
    'Bash(powershell:*)', 'Bash(pwsh:*)', 'Bash(bash:*)'
  )
  $defaultDeny = @('Bash(rm -rf:*)', 'Bash(sudo rm:*)', 'Bash(del /s:*)', 'Bash(rmdir /s:*)')
  # 既存ファイルは読めれば尊重・壊さない。無効JSON/コメントなら「上書きせずスキップ」（破壊回避）。
  $o = $null
  $skip = $false
  if (Test-Path $cset) {
    $content = Get-Content $cset -Raw
    if (-not [string]::IsNullOrWhiteSpace($content)) {
      try { $o = $content | ConvertFrom-Json }
      catch { $skip = $true }
    }
  }
  if ($skip) {
    Log "  ! 既存 settings.json の解析に失敗（無効JSON/コメント）。破壊回避のため変更をスキップしました。"
  } else {
    if ($null -eq $o -or $o -isnot [System.Management.Automation.PSCustomObject]) { $o = [pscustomobject]@{} }
    # env（型が壊れていれば作り直し）
    if ($null -eq $o.env -or $o.env -isnot [System.Management.Automation.PSCustomObject]) {
      $o | Add-Member -NotePropertyName 'env' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $o.env | Add-Member -NotePropertyName 'CLAUDE_CODE_ENABLE_AUTO_MODE' -NotePropertyValue '1' -Force
    # permissions（同上）
    if ($null -eq $o.permissions -or $o.permissions -isnot [System.Management.Automation.PSCustomObject]) {
      $o | Add-Member -NotePropertyName 'permissions' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    # 既存 defaultMode は尊重（破壊しない）。無いときだけ auto。
    $dmExisting = $null
    if ($o.permissions.PSObject.Properties.Name -contains 'defaultMode') { $dmExisting = $o.permissions.defaultMode }
    if (-not $dmExisting) { $o.permissions | Add-Member -NotePropertyName 'defaultMode' -NotePropertyValue 'auto' -Force }
    # allow/deny は「無い or 配列でない(null/文字列等)」とき既定リストを補完（Node版 !Array.isArray() と等価・死にコード解消）
    if (-not ($o.permissions.PSObject.Properties.Name -contains 'allow') -or $o.permissions.allow -isnot [System.Array]) { $o.permissions | Add-Member -NotePropertyName 'allow' -NotePropertyValue $defaultAllow -Force }
    if (-not ($o.permissions.PSObject.Properties.Name -contains 'deny')  -or $o.permissions.deny  -isnot [System.Array]) { $o.permissions | Add-Member -NotePropertyName 'deny'  -NotePropertyValue $defaultDeny  -Force }
    $json = $o | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($cset, $json, (New-Object System.Text.UTF8Encoding($false)))
    if ($dmExisting -and $dmExisting -ne 'auto') {
      Log ("  + settings.json を更新（auto有効化＋安全リスト補完）。既存 defaultMode='" + $dmExisting + "' を尊重（auto未適用）。")
    } else {
      Log "  + settings.json に auto モード＋安全な許可/拒否リストを反映（既存値は保持）"
    }
  }
  Log "  * auto モードは Opus 4.7/4.8 で有効（許可待ちを激減・危険操作は自動ブロック）。"
} catch { Log ("  X Claude 既定設定 失敗: " + $_.Exception.Message) }
# FDE_CLAUDE_BLOCK_END

# ---- Claude Code 信頼済みフォルダの事前登録（任意・-TrustDir）---
# 新PCの非対話運用で「workspace has not been trusted」により権限設定が無効化されるのを防ぐ。
# 内部仕様（~/.claude.json の projects.*.hasTrustDialogAccepted）依存のベストエフォート。
if ($TrustDir) {
  Log "`n[+] Claude Code 信頼済みフォルダの事前登録: $TrustDir"
  try {
    if (Test-Path $TrustDir -PathType Container) {
      $abs = (Resolve-Path $TrustDir).Path
      $cj = "$env:USERPROFILE\.claude.json"
      $obj = $null; $bad = $false
      if (Test-Path $cj) {
        $raw = Get-Content $cj -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) { try { $obj = $raw | ConvertFrom-Json } catch { $bad = $true } }
      }
      if ($bad) {
        Log "  ! 既存 .claude.json の解析に失敗 → 破壊回避でスキップ（初回に対話で claude を起動して承諾してください）"
      } else {
        if ($null -eq $obj -or $obj -isnot [System.Management.Automation.PSCustomObject]) { $obj = [pscustomobject]@{} }
        if ($null -eq $obj.projects -or $obj.projects -isnot [System.Management.Automation.PSCustomObject]) {
          $obj | Add-Member -NotePropertyName 'projects' -NotePropertyValue ([pscustomobject]@{}) -Force
        }
        $pr = $null
        if ($obj.projects.PSObject.Properties.Name -contains $abs) { $pr = $obj.projects.$abs }
        if ($null -eq $pr -or $pr -isnot [System.Management.Automation.PSCustomObject]) { $pr = [pscustomobject]@{} }
        $pr | Add-Member -NotePropertyName 'hasTrustDialogAccepted' -NotePropertyValue $true -Force
        $obj.projects | Add-Member -NotePropertyName $abs -NotePropertyValue $pr -Force
        $json = $obj | ConvertTo-Json -Depth 30
        [System.IO.File]::WriteAllText($cj, $json, (New-Object System.Text.UTF8Encoding($false)))
        Log "  + 登録済（初回の信頼ダイアログを省略できる場合あり・仕様変更時は無害に失敗）"
      }
    } else { Log "  ! ディレクトリが存在しません → スキップ" }
  } catch { Log ("  X 登録失敗: " + $_.Exception.Message) }
}

# ---- 認証情報の復元（任意・-RestoreCreds <zip>）----------------
if ($RestoreCreds) { Restore-Creds $RestoreCreds | Out-Null }

# ---- サマリ -----------------------------------------------------
$rc = Show-Summary
Log "`n※ 反映を確実にするには PowerShell を開き直してください。"
Log "※ Claude Code は auto モード既定（許可待ち最小化／Opus 4.7+）。変更は %USERPROFILE%\.claude\settings.json。"
Log "※ 次のログイン/登録は別途(対話): claude（初回起動＋フォルダ信頼）/ clasp login / gcloud auth login / gws(MCP)登録。"
Log "※ 実行ログ: $logPath（つまずいたらこのファイルをサポートへ送ってください）"
if ($transcriptOn) { try { Stop-Transcript | Out-Null } catch {} }
exit $rc
