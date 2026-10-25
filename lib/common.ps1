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
function Select-Role {
  $script:KRole = $env:DAIMARU_ROLE
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
  try { $s = Get-Content $script:KState -Raw | ConvertFrom-Json; if ($s.role -eq $script:KRole) { return $s.steps.$Name } } catch { }
  return $null
}
function Set-StateStep([string]$Name,[string]$Result) {
  if (Is-DryRun) { return }
  $dir = Split-Path $script:KState -Parent
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $s = $null
  try { $s = Get-Content $script:KState -Raw | ConvertFrom-Json } catch { }
  if (-not $s -or $s.role -ne $script:KRole) { $s = [pscustomobject]@{role=$script:KRole;steps=[pscustomobject]@{};lastRun=''} }
  $s.steps | Add-Member -NotePropertyName $Name -NotePropertyValue $Result -Force
  $s.lastRun = [DateTime]::UtcNow.ToString('o')
  $json = $s | ConvertTo-Json -Depth 8
  [IO.File]::WriteAllText($script:KState,$json + "`n",(New-Object Text.UTF8Encoding($false)))
}
function Run-Step([string]$Name,[scriptblock]$Check,[scriptblock]$Action) {
  if (Is-DryRun) { Say "予定: $Name"; return }
  if ((Is-Update) -and $Name -ne 'hub-update' -and $Name -ne 'skills') { return }
  $result = 'fail'
  try {
    if (& $Check) { $result='skip'; Ok "$Name は済み" }
    elseif (& $Action) { $result='ok'; Ok "$Name 完了" }
    else { Warn "$Name を完了できませんでした" }
  } catch { Warn "$Name を完了できませんでした" }
  try { Set-StateStep $Name $result } catch { Warn 'state.json を書けませんでした' }
}
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Invoke-Cli([string]$Name,[string[]]$CliArgs) {
  $cmd = Get-Command "$Name.cmd","$Name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { $cmd = Get-Command $Name -ErrorAction Stop }
  & $cmd.Source @CliArgs
}
function Invoke-Gws([string[]]$GwsArgs) {
  $params='{"pageSize":1,"fields":"files(id)"}'
  if ($PSVersionTable.PSVersion.Major -lt 7) { $params=$params.Replace('"','\"') }
  Invoke-Cli gws ($GwsArgs + @('--params',$params))
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
    foreach ($line in [IO.File]::ReadAllLines($config)) { if ($line.StartsWith('OP_VAULT=')) { $vault=$line.Substring(9); break } }
  }
  if (-not $vault) { $vault=$script:KOpVaultDefault }
  if ($vault -notmatch '^[A-Za-z0-9-]+$') { throw 'invalid vault' }
  return 'op://' + $vault + '/' + $script:KOpItem + '/' + $script:KOpField
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
function Copy-RoleSkills([string]$Hub,[string]$Role) {
  $file = Join-Path $Hub "profiles\$Role.json"
  if (-not (Test-Path $file)) { return $true }
  try { $data = Get-Content $file -Raw | ConvertFrom-Json } catch { return $false }
  if ($null -eq $data.skills -or $data.skills -is [string]) { return $false }
  foreach ($name in $data.skills) { if ($name -isnot [string] -or $name -notmatch '^[A-Za-z0-9-]+$') { return $false } }
  $dest = Join-Path $HOME '.claude\skills'
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  foreach ($name in $data.skills) {
    $source = Join-Path $Hub ".claude\skills\$name"
    if (-not (Test-Path $source -PathType Container)) { return $false }
    $target=Join-Path $dest $name
    if (Test-Path $target) { Remove-Item -Path $target -Recurse -Force }
    Copy-Item -Path $source -Destination $target -Recurse -Force
  }
  return $true
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
