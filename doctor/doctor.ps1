# PowerShell 5.1 doctor。setup.ps1 からも単独でも実行できる。
$script:DoctorTemp=$null
try {
$script:DoctorBase = if ($env:DAIMARU_SETUP_BASE) { $env:DAIMARU_SETUP_BASE.TrimEnd('/') } else { 'https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main' }
if ($script:DoctorBase -notmatch '^https://' -and -not ($env:DAIMARU_SETUP_ALLOW_FILE -eq '1' -and $script:DoctorBase -match '^file://')) { Write-Host 'DAIMARU_DOCTOR: FAIL missing=base'; if ($PSCommandPath) { exit 2 } else { return } }
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if ($env:OS -eq 'Windows_NT') { try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { Write-Host '実行ポリシーは組織設定に従います。診断を続行します' } }
$script:DoctorRoot = if ($env:DAIMARU_SETUP_ROOT) { $env:DAIMARU_SETUP_ROOT } elseif ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { $null }
if (-not $script:DoctorRoot -or -not (Test-Path (Join-Path $script:DoctorRoot 'lib\common.ps1'))) {
  $script:DoctorRoot=Join-Path ([IO.Path]::GetTempPath()) ('daimaru-doctor-' + [guid]::NewGuid().ToString('N'))
  $script:DoctorTemp=$script:DoctorRoot
  New-Item -ItemType Directory -Force -Path (Join-Path $script:DoctorRoot 'lib'),(Join-Path $script:DoctorRoot 'profiles') | Out-Null
  try { Invoke-WebRequest "$script:DoctorBase/lib/common.ps1" -OutFile (Join-Path $script:DoctorRoot 'lib\common.ps1') -UseBasicParsing -ErrorAction Stop } catch { Write-Host 'DAIMARU_DOCTOR: FAIL missing=common'; if ($PSCommandPath) { exit 2 } else { return } }
}
try { . (Join-Path $script:DoctorRoot 'lib\common.ps1') } catch { Write-Host 'DAIMARU_DOCTOR: FAIL missing=common'; if ($PSCommandPath) { exit 2 } else { return } }
$script:DoctorRole = $env:DAIMARU_ROLE
if (-not $script:DoctorRole) { $script:DoctorRole=Get-StateRole }
if (-not $script:DoctorRole) { $script:DoctorRole='base' }
if (-not (Valid-Role $script:DoctorRole)) { Write-Host 'DAIMARU_DOCTOR: FAIL missing=role'; if ($PSCommandPath) { exit 2 } else { return } }
$script:KRole=$script:DoctorRole
$profilePath=Join-Path $script:DoctorRoot "profiles\$script:DoctorRole.env"
if (-not (Test-Path $profilePath)) { try { Invoke-WebRequest "$script:DoctorBase/profiles/$script:DoctorRole.env" -OutFile $profilePath -UseBasicParsing -ErrorAction Stop } catch { Write-Host 'DAIMARU_DOCTOR: FAIL missing=profile'; if ($PSCommandPath) { exit 2 } else { return } } }
if (-not (Load-Profile $profilePath)) { Write-Host 'DAIMARU_DOCTOR: FAIL missing=profile'; if ($PSCommandPath) { exit 2 } else { return } }
$script:Missing=New-Object 'System.Collections.Generic.List[string]'
function Doctor-Fail([string]$Slug,[string]$Message,[string]$Fix) { Err $Message; $script:Missing.Add($Slug); Hint $Fix }
function Doctor-Skip([string]$Message) { Warn "$Message`: 省略" }
Refresh-Path
Say "==> daimaru-setup 診断 ($($script:KProfile.ROLE_LABEL) / Windows)"
Ok 'OS: Windows'
try { $mem=(Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory; if ($mem -lt 8GB) { Warn 'メモリ: 8GB 未満'; Hint '使わないアプリを閉じてください' } else { Ok 'メモリ: 8GB 以上' } } catch { Warn 'メモリ: 判定できません' }
try { $battery=Get-CimInstance Win32_Battery -ErrorAction Stop; if ($battery -and $battery.BatteryStatus -eq 1) { Warn '電源: バッテリー使用中'; Hint '電源アダプターを接続してください' } } catch { }
$policy=Get-ExecutionPolicy
if ($policy -eq 'Restricted') { Warn '実行ポリシー: Restricted'; Hint '管理者に実行ポリシーを相談するか .cmd を使ってください' } else { Ok "実行ポリシー: $policy" }
foreach ($tool in @('claude','node','git','gh','gws','code','op')) {
  $needed=($tool -in @('claude','node','git','gh')) -or (Needs $(if ($tool -eq 'code') { 'vscode' } else { $tool }))
  if (-not $needed) { continue }
  if ($(if ($tool -eq 'claude') { Have claude.cmd } else { Have $tool })) { Ok "PATH: $tool" }
  else { Doctor-Fail $(if ($tool -eq 'code') { 'vscode' } else { $tool }) "$tool が見つかりません" "winget / npm で $tool を導入してください" }
}
if (Have claude.cmd) { Invoke-Cli claude @('auth','status') 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { Ok 'Claude: ログイン済み' } else { Warn 'Claude: ログイン状態を確認できません'; Hint 'claude.cmd を起動してログインしてください' } }
$hub=Join-Path $HOME 'daimaru-skills'
if (-not (Test-Path (Join-Path $hub '.git'))) { Doctor-Fail 'hub' 'daimaru-skills が見つかりません' 'セットアップをもう一度実行してください' }
if ($env:DAIMARU_DOCTOR_SKIP_NETWORK -eq '1') { Doctor-Skip 'GitHub 権限'; Doctor-Skip 'daimaru-skills 更新' }
else {
  if (Have gh) { gh auth status 2>$null | Out-Null; $auth=($LASTEXITCODE -eq 0); if ($auth) { gh api repos/daimaru-d/daimaru-skills 2>$null | Out-Null; $auth=($LASTEXITCODE -eq 0) } } else { $auth=$false }
  if ($auth) { Ok 'GitHub: daimaru-d read' } else { Doctor-Fail 'gh-access' 'GitHub の read 権限を確認できません' 'gh auth login または管理者に daimaru-d read 権限を依頼してください' }
  if ((Test-Path (Join-Path $hub '.git')) -and (Have git)) {
    Push-Location $hub
    git fetch -q origin 2>$null
    $fetchOk=($LASTEXITCODE -eq 0)
    if ($fetchOk) { $behind=git rev-list --count 'HEAD..@{u}' 2>$null; $fetchOk=($LASTEXITCODE -eq 0 -and $behind -eq '0') }
    Pop-Location
    if ($fetchOk) { Ok 'daimaru-skills: 最新' } else { Warn 'daimaru-skills は更新が必要か確認できません'; Hint 'セットアップをもう一度実行してください' }
  }
}
if (Needs 'gws') {
  if (-not (Test-Scopes (Get-StateScopes) $script:KProfile.GWS_SCOPES)) { Doctor-Fail 'gws-scopes' 'gws: この役割の認可スコープが記録されていません' "DAIMARU_ROLE=$script:DoctorRole を指定して setup.ps1 を再実行してください" }
  if ($env:DAIMARU_DOCTOR_SKIP_NETWORK -eq '1') { Doctor-Skip 'gws 実 API' }
  elseif (Have gws.cmd) {
    $errFile=Join-Path ([IO.Path]::GetTempPath()) ('gws-doctor-' + [guid]::NewGuid().ToString('N'))
    Invoke-Gws @('drive','files','list') 2>$errFile | Out-Null
    $rc=$LASTEXITCODE
    if ($rc -eq 0) { Ok 'gws: Drive 実 API 成功' }
    else { Doctor-Fail 'gws-api' 'gws: Drive 実 API に失敗' 'gws auth login -s drive,sheets,gmail を実行'; if ((Get-Content $errFile -Raw -ErrorAction SilentlyContinue) -match '401') { Hint '401: ~/.config/gws/token_cache.json を退避して再ログインしてください' } }
    Remove-Item $errFile -ErrorAction SilentlyContinue
  } else { Doctor-Fail 'gws-api' 'gws: 実 API を確認できません' 'npm.cmd i -g @googleworkspace/cli' }
}
if (Needs 'op') {
  $opDoctor=Join-Path $HOME '.claude\skills\op-secrets\scripts\op-doctor.sh'
  if ($env:DAIMARU_DOCTOR_SKIP_NETWORK -eq '1') { Doctor-Skip '1Password 診断' }
  elseif (Test-Path $opDoctor) {
    $gitBash=Get-GitBash
    $out=if ($gitBash) { @(& $gitBash ($opDoctor -replace '\\','/') 2>&1) } else { @() }
    if ($out.Count -gt 0 -and $out[-1] -eq 'OP_DOCTOR: PASS') { Ok '1Password: OP_DOCTOR PASS' }
    else { Doctor-Fail 'op-doctor' '1Password: OP_DOCTOR が PASS ではありません' 'bash ~/.claude/skills/op-secrets/scripts/op-doctor.sh' }
  } else { Doctor-Fail 'op-doctor' '1Password の診断スクリプトがありません' 'scripts/op/setup.ps1 を実行してください' }
}
if (Needs 'vscode') { if (Have code.cmd) { Ok 'VS Code: 利用可能' } }
if (Needs 'chrome') {
  if (Chrome-Installed) { Ok 'Chrome: 導入済み' } else { Doctor-Fail 'chrome' 'Chrome が見つかりません' 'winget install Google.Chrome' }
  if ($script:KProfile.NEEDS_CLAUDE_CHROME -eq '1') {
    if (Find-ClaudeChrome) { Ok 'Claude in Chrome: 検出' } else { Warn 'Claude in Chrome: 未確認'; Hint 'Chrome ストアで Claude を検索してください' }
  }
}
foreach ($tool in @('clasp','gcloud')) { if (Needs $tool) { if (Have $tool) { Ok "$tool`: 利用可能" } else { Doctor-Fail $tool "$tool がありません" "winget / npm で $tool を導入してください" } } }
if (Needs 'clasp') {
  if (Test-Path (Join-Path $HOME '.clasprc.json')) { Ok 'clasp: ログイン済み' }
  else { Doctor-Fail 'clasp-login' 'clasp にログインしていません' 'clasp login を実行してください' }
}
if (Needs 'gcloud') {
  if ($env:DAIMARU_DOCTOR_SKIP_NETWORK -eq '1') { Doctor-Skip 'ADC' }
  elseif (Have gcloud.cmd) { Invoke-Cli gcloud @('auth','application-default','print-access-token') 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { Ok 'ADC: 利用可能' } else { Doctor-Fail 'adc' 'ADC を確認できません' 'gcloud auth application-default login を実行してください' } }
  else { Doctor-Fail 'adc' 'ADC を確認できません' 'gcloud auth application-default login を実行してください' }
  if (Have cloud-sql-proxy.exe) { Ok 'cloud-sql-proxy: 利用可能' }
  else { Doctor-Fail 'cloud-sql-proxy' 'cloud-sql-proxy がありません' 'cloud-sql-proxy を導入してください' }
}
foreach ($dir in @((Join-Path $HOME 'Downloads'),(Join-Path $HOME 'Desktop'))) {
  if (-not (Test-Path $dir)) { continue }
  Get-ChildItem $dir -Recurse -Depth 1 -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'client_secret*.json' -or $_.Name -eq '.env' } | ForEach-Object { Warn "機密ファイル候補: $($_.FullName)"; Hint '不要なら安全な場所へ移し、元のファイルを削除してください' }
}
if ($script:Missing.Count -eq 0) { Write-Host 'DAIMARU_DOCTOR: PASS'; if ($PSCommandPath) { exit 0 } else { return } }
Write-Host ('DAIMARU_DOCTOR: FAIL missing=' + ($script:Missing -join ','))
if ($PSCommandPath) { exit 2 } else { return }
} finally { if ($script:DoctorTemp) { Remove-Item $script:DoctorTemp -Recurse -Force -ErrorAction SilentlyContinue } }
