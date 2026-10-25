# PowerShell 5.1 共通部品
$script:KOpVaultDefault = 'Claude-Automation'
$script:KOpItem = 'gws-oauth-client'
$script:KOpField = 'client_secret.json'
$script:KState = Join-Path (Join-Path $env:APPDATA 'daimaru-setup') 'state.json'
function Test-SetupBase([string]$Base) {
  return ($Base -match '^https://' -or ($env:DAIMARU_SETUP_ALLOW_FILE -eq '1' -and $Base -match '^file://'))
}
function Move-LegacyState {
  if ($env:DAIMARU_DRY_RUN -eq '1') { return }
  $oldDir=Join-Path $HOME '.daimaru-setup'
  $old=Join-Path $oldDir 'state.json'
  if (-not (Test-Path $old) -or (Test-Path $script:KState) -or (Test-Path (Join-Path $oldDir '.git'))) { return }
  if (@(Get-ChildItem -Force $oldDir).Count -ne 1) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $script:KState -Parent) | Out-Null
  Move-Item $old $script:KState
  Remove-Item $oldDir -ErrorAction SilentlyContinue
}
Move-LegacyState
function Say([string]$Message) { Write-Host $Message -ForegroundColor Cyan }
function Ok([string]$Message) { Write-Host "  ✓ $Message" -ForegroundColor Green }
function Warn([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }
function Err([string]$Message) { Write-Host "  ✗ $Message" -ForegroundColor Red }
function Hint([string]$Message) { Write-Host "      $Message" }
function Have([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Is-DryRun { return ($env:DAIMARU_DRY_RUN -eq '1') }
function Is-Update { return ($env:DAIMARU_UPDATE -eq '1') }
function Valid-Role([string]$Role) { return @('base','sekkei','togo','yochi','somu-keiri').Contains($Role) }
function Get-StateRole {
  try { if (-not (Test-Path $script:KState)) { return $null }; return (Get-Content $script:KState -Raw -Encoding UTF8 | ConvertFrom-Json).role } catch { return $null }
}
function Get-StateScopes {
  try { if (-not (Test-Path $script:KState)) { return $null }; return (Get-Content $script:KState -Raw -Encoding UTF8 | ConvertFrom-Json).gwsScopes } catch { return $null }
}
function Test-Scopes([string]$Granted,[string]$Required) {
  foreach ($scope in ($Required -split ',')) { if ($scope -and @($Granted -split ',') -notcontains $scope) { return $false } }
  return $true
}
function Set-StateScopes([string]$Scopes) {
  if (Is-DryRun) { return }
  $dir=Split-Path $script:KState -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  try { if (Test-Path $script:KState) { $s=Get-Content $script:KState -Raw -Encoding UTF8 | ConvertFrom-Json } else { $s=$null } } catch { $s=$null }
  if (-not $s) { $s=[pscustomobject]@{role=$script:KRole;steps=[pscustomobject]@{};lastRun=''} }
  if ($s.role -ne $script:KRole) { $s.role=$script:KRole; $s.steps=[pscustomobject]@{} }
  $s | Add-Member -NotePropertyName gwsScopes -NotePropertyValue $Scopes -Force
  [IO.File]::WriteAllText($script:KState,($s | ConvertTo-Json -Depth 8) + "`n",(New-Object Text.UTF8Encoding($false)))
}
function Select-Role {
  $script:KRole = $env:DAIMARU_ROLE
  if (-not $script:KRole) { $script:KRole = Get-StateRole; if (-not (Valid-Role $script:KRole)) { $script:KRole=$null } }
  if (-not $script:KRole) {
    $script:KRole = 'base'
    if (-not (Is-DryRun) -and [Environment]::UserInteractive -and $Host.Name -eq 'ConsoleHost') {
      $answer = Read-Host '役割 (base/sekkei/togo/yochi/somu-keiri、Enter=base)'
      if ($answer) { $script:KRole = $answer }
    } elseif (-not (Is-DryRun)) {
      Hint '対話端末がないため、役割は base で進めます（DAIMARU_ROLE で指定できます）'
    }
  }
  if (-not (Valid-Role $script:KRole)) { Err '役割名が正しくありません'; return $false }
  return $true
}
function Load-Profile([string]$Path) {
  if (-not (Test-Path $Path)) { return $false }
  $script:KProfile = @{ ROLE_LABEL=''; TOOLS=''; GWS_SCOPES=''; VSCODE_EXTENSIONS=''; NEEDS_CLAUDE_CHROME='0'; NOTE='' }
  foreach ($line in [IO.File]::ReadAllLines($Path)) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    if ($line -notmatch '^([A-Z_]+)=(.*)$') { return $false }
    if (-not $script:KProfile.ContainsKey($Matches[1])) { return $false }
    $script:KProfile[$Matches[1]] = $Matches[2]
  }
  if ($script:KProfile.NEEDS_CLAUDE_CHROME -notmatch '^[01]$') { return $false }
  if ($script:KProfile.TOOLS -notmatch '^[A-Za-z0-9_ .-]*$') { return $false }
  if ($script:KProfile.VSCODE_EXTENSIONS -notmatch '^[A-Za-z0-9_ .-]*$') { return $false }
  if ($script:KProfile.GWS_SCOPES -notmatch '^[a-z, -]*$') { return $false }
  return $true
}
function Needs([string]$Name) { return @(($script:KProfile.TOOLS -split ' ') | Where-Object { $_ -eq $Name }).Count -gt 0 }
function Get-StateStep([string]$Name) {
  try { if (-not (Test-Path $script:KState)) { return $null }; $s = Get-Content $script:KState -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json; if ($s.role -eq $script:KRole) { return $s.steps.$Name } } catch { }
  return $null
}
function Set-StateStep([string]$Name,[string]$Result) {
  if (Is-DryRun) { return }
  $dir = Split-Path $script:KState -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $s = $null
  try { if (Test-Path $script:KState) { $s = Get-Content $script:KState -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json } } catch { }
  if (-not $s) { $s = [pscustomobject]@{role=$script:KRole;steps=[pscustomobject]@{};lastRun=''} }
  elseif ($s.role -ne $script:KRole) { $s.role=$script:KRole; $s.steps=[pscustomobject]@{} }
  $s.steps | Add-Member -NotePropertyName $Name -NotePropertyValue $Result -Force
  $s.lastRun = [DateTime]::UtcNow.ToString('o')
  $json = $s | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText($script:KState,$json + "`n",(New-Object Text.UTF8Encoding($false)))
}
function Test-NpmCi([string]$Repo) {
  if (-not (Test-Path $Repo)) { return $true }
  $lock=Join-Path $Repo 'package-lock.json'
  if (-not (Test-Path (Join-Path $Repo 'node_modules\pg')) -or -not (Test-Path $lock)) { return $false }
  return ((Get-StateStep 'npm-lock-hash') -eq (Get-FileHash $lock -Algorithm SHA256).Hash)
}
function Install-NpmCi([string]$Repo) {
  $lock=Join-Path $Repo 'package-lock.json'
  if (-not (Test-Path $lock)) { return $false }
  Push-Location $Repo
  try { Invoke-Cli npm @('ci') | Out-Null; $rc=$LASTEXITCODE } finally { Pop-Location }
  if ($rc -ne 0) { return $false }
  Set-StateStep 'npm-lock-hash' (Get-FileHash $lock -Algorithm SHA256).Hash
  return $true
}
function Run-Step([string]$Name,[scriptblock]$Check,[scriptblock]$Action) {
  if (Is-DryRun) { Say "予定: $Name"; return }
  if ((Is-Update) -and $Name -ne 'hub-update' -and $Name -ne 'npm-ci' -and $Name -ne 'skills') { return }
  $result = 'fail'
  try {
    $r=@(& $Check)
    $checked=($r.Count -gt 0 -and $r[-1] -eq $true)
    if ($checked) { $result='skip'; Ok "$Name は済み" }
    else {
      $r=@(& $Action)
      $ok=($r.Count -gt 0 -and $r[-1] -eq $true)
      if ($ok) { $result='ok'; Ok "$Name 完了" }
      else { Warn "$Name を完了できませんでした" }
    }
  } catch { Warn "$Name を完了できませんでした" }
  try { Set-StateStep $Name $result } catch { Warn 'state.json を書けませんでした' }
}
function Refresh-Path {
  if ($env:OS -ne 'Windows_NT') { return }
  $machine=[Environment]::GetEnvironmentVariable('Path','Machine')
  $user=[Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = @($machine,$user,$env:Path) -ne '' -join ';'
}
function Resolve-Cli([string]$Name) {
  $cmd = Get-Command "$Name.exe","$Name.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1 }
  return $cmd
}
function Have-Cli([string]$Name) { return [bool](Resolve-Cli $Name) }
function Invoke-Cli([string]$Name,[string[]]$CliArgs) {
  $cmd = Resolve-Cli $Name
  if (-not $cmd) { throw "$Name が見つかりません" }
  & $cmd.Source @CliArgs
}
function Invoke-Gws([string[]]$GwsArgs) {
  $params='{"pageSize":1,"fields":"files(id)"}'
  if ($PSVersionTable.PSVersion.Major -lt 7) { $params=$params.Replace('"','\"') }
  Invoke-Cli gws ($GwsArgs + @('--params',$params))
}
function Test-OpReady {
  if (-not (Have-Cli 'op')) { return $false }
  $doctor=Join-Path $HOME '.claude\skills\op-secrets\scripts\op-doctor.sh'
  if (-not (Test-Path $doctor)) { return $false }
  $bash=Get-GitBash
  if (-not $bash) { $bashCmd=Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1; if ($bashCmd) { $bash=$bashCmd.Source } }
  if (-not $bash) { return $false }
  $out=@(& $bash ($doctor -replace '\\','/') 2>$null)
  return ($LASTEXITCODE -eq 0 -and $out.Count -gt 0 -and $out[-1] -eq 'OP_DOCTOR: PASS')
}
function Get-GitBash {
  $git=Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($git) {
    $candidate=Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) 'bin\bash.exe'
    if (Test-Path $candidate) { return $candidate }
  }
  if (Test-Path 'C:\Program Files\Git\bin\bash.exe') { return 'C:\Program Files\Git\bin\bash.exe' }
  return $null
}
function Get-RemoteScript([string]$Url) {
  $client=New-Object Net.WebClient
  try { $client.Encoding=New-Object Text.UTF8Encoding($false); return $client.DownloadString($Url).TrimStart([char]0xFEFF) }
  finally { $client.Dispose() }
}
function Get-OpRef {
  $vault=$env:OP_VAULT
  $config=Join-Path $HOME '.config\daimaru-op\config'
  if (-not $vault -and (Test-Path $config)) {
    foreach ($line in [IO.File]::ReadAllLines($config,[Text.Encoding]::UTF8)) { if ($line.StartsWith('OP_VAULT=')) { $vault=$line.Substring(9); break } }
  }
  if (-not $vault) { $vault=$script:KOpVaultDefault }
  if ($vault -notmatch '^[A-Za-z0-9-]+$') { throw 'invalid vault' }
  return 'op://' + $vault + '/' + $script:KOpItem + '/' + $script:KOpField
}
function Get-OpAccount {
  $account=$env:OP_ACCOUNT
  $config=Join-Path $HOME '.config\daimaru-op\config'
  if (-not $account -and (Test-Path $config)) {
    foreach ($line in [IO.File]::ReadAllLines($config,[Text.Encoding]::UTF8)) { if ($line.StartsWith('OP_ACCOUNT=')) { $account=$line.Substring(11); break } }
  }
  if (-not $account) { $account='daimaruenterprise.1password.com' }
  return $account
}
function Install-GwsSecret([string]$SecretFile) {
  if (-not (Have op)) { Hint '管理者に 1Password の招待を頼んでください'; return $false }
  $dir=Split-Path $SecretFile -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Clear-GwsTemps
  if (-not (Set-PrivateAcl $dir $true)) { return $false }
  $tmp=Join-Path $dir ('.client_secret-' + [guid]::NewGuid().ToString('N'))
  $errFile=Join-Path $dir '.op-error.tmp'
  $opCmd=(Get-Command op.exe,op -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $opCmd) { return $false }
  $argsList=@('read',(Get-OpRef))
  if (-not $env:OP_SERVICE_ACCOUNT_TOKEN) { $argsList=@('--account',(Get-OpAccount)) + $argsList }
  try {
    $p=Start-Process -FilePath $opCmd.Source -ArgumentList $argsList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmp -RedirectStandardError $errFile
    if ($p.ExitCode -ne 0) { Hint '管理者に 1Password の招待を頼んでください'; return $false }
    $j=[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not ($j.installed.client_id -and $j.installed.client_secret)) { return $false }
    if (-not (Set-PrivateAcl $tmp $false)) { return $false }
    Move-Item -Force $tmp $SecretFile
    return $true
  } catch { return $false }
  finally { Remove-Item $tmp,$errFile -Force -ErrorAction SilentlyContinue }
}
function Set-PrivateAcl([string]$Path,[bool]$Directory) {
  try {
    $acl=Get-Acl -Path $Path -ErrorAction Stop
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleSpecific($rule) }
    $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($Directory) { $rule=[System.Security.AccessControl.FileSystemAccessRule]::new($sid,[System.Security.AccessControl.FileSystemRights]::FullControl,([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),[System.Security.AccessControl.PropagationFlags]::None,[System.Security.AccessControl.AccessControlType]::Allow) }
    else { $rule=[System.Security.AccessControl.FileSystemAccessRule]::new($sid,[System.Security.AccessControl.FileSystemRights]::FullControl,[System.Security.AccessControl.AccessControlType]::Allow) }
    [void]$acl.AddAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop
    return $true
  } catch { return $false }
}
function Get-RoleWorkspace([string]$Hub,[string]$Role) {
  $workspace=Join-Path (Join-Path (Join-Path $env:APPDATA 'daimaru-setup') 'workspaces') $Role
  if ((Test-Path (Join-Path $Hub "profiles\$Role.json")) -and (Test-Path (Join-Path $workspace '.ready'))) { return $workspace }
  if (Test-Path (Join-Path $Hub "profiles\$Role.json")) { return $null }
  return $Hub
}
function Clear-GwsTemps {
  $dir=if ($env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR) { $env:GOOGLE_WORKSPACE_CLI_CONFIG_DIR } else { Join-Path $HOME '.config\gws' }
  if (Test-Path $dir) { Get-ChildItem $dir -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.client_secret-*' -or $_.Name -eq '.op-error.tmp' } | Remove-Item -Force -ErrorAction SilentlyContinue }
}
function Allow-WorkspaceRepos([string]$Workspace,[string]$Hub) {
  $path=Join-Path $Workspace '.claude\settings.local.json'
  $repos=(Join-Path $Hub 'repos').Replace('\','/')
  try {
    if (Test-Path $path) { $settings=Get-Content $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    else { $settings=[pscustomobject]@{} }
  } catch { Warn 'settings.local.json の JSON が壊れているため変更しません'; return $true }
  if ($null -eq $settings -or $settings -isnot [pscustomobject]) { Warn 'settings.local.json の形式が正しくないため変更しません'; return $true }
  if ($null -eq $settings.permissions -or $settings.permissions -isnot [pscustomobject]) { $settings | Add-Member -NotePropertyName permissions -NotePropertyValue ([pscustomobject]@{}) -Force }
  $dirs=@($settings.permissions.additionalDirectories | Where-Object { $null -ne $_ })
  if ($dirs -contains $repos) { return $true }
  $settings.permissions | Add-Member -NotePropertyName additionalDirectories -NotePropertyValue @($dirs + $repos) -Force
  try { [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $settings -Depth 20) + "`n",(New-Object Text.UTF8Encoding($false))); return $true }
  catch { return $false }
}
function Copy-RoleSkills([string]$Hub,[string]$Role) {
  $file = Join-Path $Hub "profiles\$Role.json"
  if (-not (Test-Path $file)) { return $true }
  $workspace=Join-Path (Join-Path (Join-Path $env:APPDATA 'daimaru-setup') 'workspaces') $Role
  $ready=Join-Path $workspace '.ready'
  Remove-Item $ready -Force -ErrorAction SilentlyContinue
  try { $data = Get-Content $file -Raw | ConvertFrom-Json } catch { return $false }
  if ($null -eq $data.skills -or $data.skills -is [string]) { return $false }
  foreach ($name in $data.skills) { if ($name -isnot [string] -or $name -notmatch '^[A-Za-z0-9-]+$') { return $false } }
  $config=Join-Path $workspace '.claude'
  $dest=Join-Path $config 'skills'
  $ready=Join-Path $workspace '.ready'
  try {
    New-Item -ItemType Directory -Force -Path $config | Out-Null
    Remove-Item $ready -Force -ErrorAction SilentlyContinue
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction Stop }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($item in Get-ChildItem (Join-Path $Hub '.claude') -Force) {
      if ($item.Name -eq 'skills') { continue }
      $target=Join-Path $config $item.Name
      if ($item.Name -eq 'settings.local.json' -and (Test-Path $target)) { continue }
      if (Test-Path $target) { Remove-Item $target -Recurse -Force -ErrorAction Stop }
      Copy-Item -Path $item.FullName -Destination $target -Recurse -Force -ErrorAction Stop
    }
    foreach ($name in $data.skills) {
      $source=Join-Path $Hub ".claude\skills\$name"
      if (-not (Test-Path $source -PathType Container)) { return $false }
      Copy-Item -Path $source -Destination (Join-Path $dest $name) -Recurse -Force -ErrorAction Stop
    }
    $claude=Join-Path $Hub 'CLAUDE.md'
    if (Test-Path $claude) { Copy-Item $claude (Join-Path $workspace 'CLAUDE.md') -Force -ErrorAction Stop }
    $repos=Join-Path $Hub 'repos'
    if (Test-Path $repos -PathType Container) {
      $link=Join-Path $workspace 'repos'
      if (Test-Path $link) {
        $existing=Get-Item $link -Force -ErrorAction Stop
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { [IO.Directory]::Delete($link) }
        else { Remove-Item $link -Recurse -Force -ErrorAction Stop }
      }
      try { New-Item -ItemType Junction -Path $link -Target $repos -ErrorAction Stop | Out-Null; if (-not (Test-Path $link)) { throw 'junction unavailable' } }
      catch { Copy-Item $repos $link -Recurse -Force -ErrorAction Stop }
      if (-not (Allow-WorkspaceRepos $workspace $Hub)) { return $false }
    }
    New-Item -ItemType File -Path $ready -Force | Out-Null
    return $true
  } catch { return $false }
}
function Find-ClaudeChrome {
  $root = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if (-not (Test-Path $root)) { return $false }
  foreach ($f in Get-ChildItem $root -Filter manifest.json -Recurse -ErrorAction SilentlyContinue) {
    if ($f.FullName -notmatch '[\\/]Extensions[\\/]') { continue }
    try { $m=Get-Content $f.FullName -Raw | ConvertFrom-Json; if ($m.name -notlike '__MSG_*' -and $m.name -match 'Claude') { return $true } } catch { }
  }
  return $false
}
function Chrome-Installed {
  $paths=@((Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'))
  if (${env:ProgramFiles(x86)}) { $paths += Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe' }
  foreach ($path in $paths) { if (Test-Path $path) { return $true } }
  return (Have chrome.exe)
}
