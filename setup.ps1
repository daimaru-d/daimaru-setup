# Windows PowerShell 5.1 / irm .../setup.ps1 | iex
$ErrorActionPreference = 'Continue'
$script:KBase = if ($env:DAIMARU_SETUP_BASE) { $env:DAIMARU_SETUP_BASE.TrimEnd('/') } else { 'https://raw.githubusercontent.com/daimaru-d/daimaru-setup/main' }
if ($script:KBase -notmatch '^https://' -and -not ($env:DAIMARU_SETUP_ALLOW_FILE -eq '1' -and $script:KBase -match '^file://')) { Write-Host 'DAIMARU_SETUP_BASE は https:// のみ指定できます'; return }
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
if ($env:OS -eq 'Windows_NT') { try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch { Write-Host '実行ポリシーは組織設定に従います。続行します' } }
$script:KRoot = $null
$script:KTemp = $null
$localRoot = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'profiles'))) { $localRoot=$PSScriptRoot }
if ($localRoot) { $script:KRoot=$localRoot }
elseif ($env:DAIMARU_DRY_RUN -eq '1') {
  $role=if ($env:DAIMARU_ROLE) { $env:DAIMARU_ROLE } else { try { (Get-Content (Join-Path $env:APPDATA 'daimaru-setup\state.json') -Raw | ConvertFrom-Json).role } catch { 'base' } }
  if (@('base','sekkei','togo','yochi','somu-keiri') -notcontains $role) { Write-Host '役割名が正しくありません'; return }
  Write-Host "予定: $role の準備（オンラインのプロファイル取得を省略）"
  Write-Host '予定: Claude Code / Git / Node.js / GitHub CLI / daimaru-skills / doctor'
  switch ($role) {
    'sekkei' { Write-Host '予定: VS Code / gws / Chrome / 1Password / Chrome 拡張の案内' }
    'togo' { Write-Host '予定: gws / clasp / gcloud / ADC / 1Password' }
    'yochi' { Write-Host '予定: gws / 1Password' }
    'somu-keiri' { Write-Host '予定: gws / 1Password / 経理の追加手順' }
  }
  return
} else {
  $script:KTemp=Join-Path ([IO.Path]::GetTempPath()) ('daimaru-setup-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $script:KTemp 'lib'),(Join-Path $script:KTemp 'profiles'),(Join-Path $script:KTemp 'doctor') | Out-Null
  try { Invoke-WebRequest "$script:KBase/lib/common.ps1" -OutFile (Join-Path $script:KTemp 'lib\common.ps1') -UseBasicParsing -ErrorAction Stop } catch { Write-Host '共通部品を取得できません'; return }
  $script:KRoot=$script:KTemp
}
try { . (Join-Path $script:KRoot 'lib\common.ps1') } catch { Write-Host '共通部品を読み込めません。セットアップを中止します'; return }
if (-not (Get-Command Select-Role -ErrorAction SilentlyContinue)) { Write-Host '共通部品を読み込めません。セットアップを中止します'; return }
if (-not (Select-Role)) { return }
$profileFile=Join-Path $script:KRoot "profiles\$script:KRole.env"
if (-not (Test-Path $profileFile)) {
  try { Invoke-WebRequest "$script:KBase/profiles/$script:KRole.env" -OutFile $profileFile -UseBasicParsing -ErrorAction Stop } catch { Err 'プロファイルを取得できません'; return }
}
if (-not (Load-Profile $profileFile)) { Err 'プロファイルを読めません'; return }
$env:DAIMARU_ROLE=$script:KRole
Say "==> $($script:KProfile.ROLE_LABEL) の準備"
if ($script:KProfile.NOTE) { Hint $script:KProfile.NOTE }
$script:KHub=Join-Path $HOME 'daimaru-skills'
if (-not (Is-DryRun)) { Clear-GwsTemps }
if (-not (Is-DryRun) -and -not (Is-Update)) {
  try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop } catch { Warn '実行ポリシーは組織設定に従います。.cmd 経由で続行します' }
}
Run-Step 'git' { Have git } { winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path; Have git }
Run-Step 'node' { Have node } { winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path; Have node }
Run-Step 'gh' { Have gh } { winget install --id GitHub.cli -e --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path; Have gh }
Run-Step 'claude' { Have claude.cmd } { Invoke-Cli npm @('install','-g','@anthropic-ai/claude-code') | Out-Null; Refresh-Path; Have claude.cmd }
Run-Step 'gh-access' { if (-not (Have gh)) { return $false }; gh auth status 2>$null | Out-Null;   if ($LASTEXITCODE -ne 0) { return $false }; gh api repos/daimaru-d/daimaru-skills 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) } {
  if (-not (Have gh)) { return $false }
  gh auth status 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { gh auth login --hostname github.com --git-protocol https --web }
  gh api repos/daimaru-d/daimaru-skills 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { Hint '管理者に daimaru-d の read 権限を依頼してください'; return $false }
  return $true
}
if (-not (Is-DryRun) -and (Have gh)) { gh auth setup-git 2>$null | Out-Null }
Run-Step 'hub' {
  if (-not (Test-Path (Join-Path $script:KHub '.git'))) { return $false }
  if (Test-Path (Join-Path $script:KHub '.gitmodules')) { Push-Location $script:KHub; try { git submodule update --init --recursive | Out-Null; return ($LASTEXITCODE -eq 0) } finally { Pop-Location } }
  return $true
} {
  git clone --recurse-submodules https://github.com/daimaru-d/daimaru-skills.git $script:KHub | Out-Null
  return (Test-Path (Join-Path $script:KHub '.git'))
}
if (Is-Update) {
  Run-Step 'hub-update' { return $false } {
    if (-not (Test-Path (Join-Path $script:KHub '.git'))) { git clone --recurse-submodules https://github.com/daimaru-d/daimaru-skills.git $script:KHub }
    else { Push-Location $script:KHub; git pull --recurse-submodules | Out-Null; $rc=$LASTEXITCODE; Pop-Location; if ($rc -ne 0) { return $false } }
    return (Test-Path (Join-Path $script:KHub '.git'))
  }
}
Run-Step 'npm-ci' { -not (Test-Path (Join-Path $script:KHub 'repos\eigyo-talk-analyzer')) -or (Test-Path (Join-Path $script:KHub 'repos\eigyo-talk-analyzer\node_modules\pg')) } {
  Push-Location (Join-Path $script:KHub 'repos\eigyo-talk-analyzer'); Invoke-Cli npm @('ci') | Out-Null; $rc=$LASTEXITCODE; Pop-Location; return ($rc -eq 0)
}
if (Needs 'op') {
  Run-Step 'op' { (Have op) -and (Test-Path (Join-Path $HOME '.claude\skills\op-secrets\scripts\op-doctor.sh')) } {
    $opFile=Join-Path $script:KRoot 'scripts\op\setup.ps1'
    try {
      if (Test-Path $opFile) { . $opFile } else { Invoke-Expression (Get-RemoteScript "$script:KBase/scripts/op/setup.ps1") }
      return (Test-Path (Join-Path $HOME '.claude\skills\op-secrets\scripts\op-doctor.sh'))
    } catch { return $false }
  }
}
if (Needs 'gws') {
  Run-Step 'gws' { Have gws.cmd } { Invoke-Cli npm @('i','-g','@googleworkspace/cli') | Out-Null; Refresh-Path; return (Have gws.cmd) }
  if (-not $env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR -and -not (Is-DryRun)) {
    $env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR=Join-Path $HOME '.config\gws'
    [Environment]::SetEnvironmentVariable('GOOGLE_WORKSPACE_CLI_CONFIG_DIR',$env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR,'User')
  }
  $gwsDir=if ($env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR) { $env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR } else { Join-Path $HOME '.config\gws' }
  $secretFile=Join-Path $gwsDir 'client_secret.json'
  $validSecret={
    if (-not (Test-Path $secretFile)) { return $false }
    try {
      if (-not (Set-PrivateAcl $secretFile $false)) { return $false }
      $j=Get-Content $secretFile -Raw | ConvertFrom-Json
      return [bool]($j.installed.client_id -and $j.installed.client_secret)
    } catch { return $false }
  }
  if (Is-Update) { & $validSecret | Out-Null }
  Run-Step 'gws-secret' $validSecret {
    if (-not (Have op)) { Hint '管理者に 1Password の招待を頼んでください'; return $false }
    $opRef=Get-OpRef
    $dir=Split-Path $secretFile -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Get-ChildItem $dir -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.client_secret-*' -or $_.Name -eq '.op-error.tmp' } | Remove-Item -Force -ErrorAction SilentlyContinue
    if (-not (Set-PrivateAcl $dir $true)) { return $false }
    $tmp=Join-Path $dir ('.client_secret-' + [guid]::NewGuid().ToString('N'))
    $opCmd=(Get-Command op.exe,op -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $opCmd) { return $false }
    try {
      $p=Start-Process -FilePath $opCmd.Source -ArgumentList @('read',$opRef) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp -RedirectStandardError (Join-Path $dir '.op-error.tmp')
      if ($p.ExitCode -ne 0) { Hint '管理者に 1Password の招待を頼んでください'; return $false }
      $j=Get-Content $tmp -Raw | ConvertFrom-Json
      if (-not ($j.installed.client_id -and $j.installed.client_secret)) { return $false }
      if (-not (Set-PrivateAcl $tmp $false)) { return $false }
      Move-Item -Force $tmp $secretFile
      return $true
    } catch { return $false }
    finally { Remove-Item $tmp,(Join-Path $dir '.op-error.tmp') -Force -ErrorAction SilentlyContinue }
  }
  Run-Step 'gws-auth' { if (-not (Have gws.cmd)) { return $false }; Invoke-Gws @('drive','files','list') 2>$null | Out-Null; return ($LASTEXITCODE -eq 0 -and (Test-Scopes (Get-StateScopes) $script:KProfile.GWS_SCOPES)) } {
    if (-not (& $validSecret)) { Hint '管理者に 1Password の招待を頼んでください'; return $false }
    Invoke-Cli gws @('auth','login','-s',$script:KProfile.GWS_SCOPES)
    if ($LASTEXITCODE -ne 0) { return $false }
    Invoke-Gws @('drive','files','list') 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    Set-StateScopes $script:KProfile.GWS_SCOPES
    return $true
  }
}
if (Needs 'vscode') {
  Run-Step 'vscode' { Have code.cmd } { winget install --id Microsoft.VisualStudioCode -e --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path; return (Have code.cmd) }
  Run-Step 'vscode-extensions' {
    if (-not (Have code.cmd)) { return $false }
    $installed=@(Invoke-Cli code @('--list-extensions'))
    foreach ($ext in @('ms-ceintl.vscode-language-pack-ja','anthropic.claude-code') + @($script:KProfile.VSCODE_EXTENSIONS -split ' ' | Where-Object { $_ })) { if ($installed -notcontains $ext) { return $false } }
    return $true
  } {
    if (-not (Have code.cmd)) { return $false }
    foreach ($ext in @('ms-ceintl.vscode-language-pack-ja','anthropic.claude-code') + @($script:KProfile.VSCODE_EXTENSIONS -split ' ' | Where-Object { $_ })) { Invoke-Cli code @('--install-extension',$ext) | Out-Null; if ($LASTEXITCODE -ne 0) { return $false } }
    return $true
  }
}
if (Needs 'chrome') {
  Run-Step 'chrome' { Chrome-Installed } { winget install --id Google.Chrome -e --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path; return (Chrome-Installed) }
  if ($script:KProfile.NEEDS_CLAUDE_CHROME -eq '1') {
    Run-Step 'chrome-extension' { Find-ClaudeChrome } {
      Hint 'Chrome ストアで Claude を検索し、追加ボタンを押してください（未確認）'
      if ((Get-StateStep 'chrome-extension-open') -ne 'ok') { Start-Process 'https://chromewebstore.google.com/search/Claude'; Set-StateStep 'chrome-extension-open' 'ok' }
      return $false
    }
  }
}
if (Needs 'clasp') {
  Run-Step 'clasp' { Have clasp.cmd } { Invoke-Cli npm @('install','-g','@google/clasp') | Out-Null; return ($LASTEXITCODE -eq 0) }
  Run-Step 'clasp-auth' { Test-Path (Join-Path $HOME '.clasprc.json') } { Invoke-Cli clasp @('login') | Out-Null; return ($LASTEXITCODE -eq 0) }
}
if (Needs 'gcloud') {
  Run-Step 'gcloud' { Have gcloud.cmd } { winget install --id Google.CloudSDK -e --accept-package-agreements --accept-source-agreements | Out-Null; Refresh-Path; return (Have gcloud.cmd) }
  Run-Step 'gcloud-auth' { if (-not (Have gcloud.cmd)) { return $false }; $a=Invoke-Cli gcloud @('auth','list','--filter=status:ACTIVE','--format=value(account)'); return [bool]$a } { Invoke-Cli gcloud @('auth','login') | Out-Null; return ($LASTEXITCODE -eq 0) }
  Run-Step 'adc' { if (-not (Have gcloud.cmd)) { return $false }; Invoke-Cli gcloud @('auth','application-default','print-access-token') 2>$null | Out-Null; return ($LASTEXITCODE -eq 0) } { Invoke-Cli gcloud @('auth','application-default','login') | Out-Null; return ($LASTEXITCODE -eq 0) }
  Run-Step 'cloud-sql-proxy' { Have cloud-sql-proxy.exe } { Invoke-Cli gcloud @('components','install','cloud-sql-proxy','--quiet') | Out-Null; return ($LASTEXITCODE -eq 0) }
}
Run-Step 'skills' { return (-not (Test-Path (Join-Path $script:KHub "profiles\$script:KRole.json"))) } {
  return (Copy-RoleSkills $script:KHub $script:KRole)
}
if ($script:KRole -eq 'somu-keiri') { Hint '総務経理の追加手順: scripts/keiri/onboard.ps1 を参照してください' }
if (Is-DryRun) { Say '予定の表示を完了しました'; return }
if (Is-Update) { Say '更新を完了しました'; return }
$doctorFile=Join-Path $script:KRoot 'doctor\doctor.ps1'
if (-not (Test-Path $doctorFile)) { try { Invoke-WebRequest "$script:KBase/doctor/doctor.ps1" -OutFile $doctorFile -UseBasicParsing -ErrorAction Stop } catch { Warn 'doctor を取得できませんでした' } }
if (Test-Path $doctorFile) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $doctorFile }
if (Test-Path (Join-Path $script:KHub '.git')) {
  Clear-GwsTemps
  Set-Location (Get-RoleWorkspace $script:KHub $script:KRole)
  if (Have claude.cmd) { Invoke-Cli claude @('--permission-mode','acceptEdits') }
}
if ($script:KTemp) { Remove-Item -Recurse -Force $script:KTemp -ErrorAction SilentlyContinue }
