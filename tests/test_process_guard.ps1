$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$file=Join-Path $workspace 'Yenile-Ceviri.ps1'
[void][IO.Directory]::CreateDirectory((Join-Path $workspace 'state\tests\review'))
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
$definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-GameClosed'},$true)
if(-not $definition){throw 'Guard definition missing'}
# Only the guard's AST is evaluated. No root installer, recovery, game writer,
# process termination or launch command is evaluated by this test.
. ([scriptblock]::Create($definition.Extent.Text))
$GameData='C:\Fixture\Endfield\games\Arknights Endfield\Endfield_Data';$runtimeRoot=Split-Path $file;$config=$null
$script:fakeProcesses=@()
function Get-EndfieldInstallations{param($GameData);[pscustomobject]@{GameData=$GameData;InstallRoot='C:\Fixture\Endfield';OfficialLauncher='C:\Fixture\Endfield\Launcher.exe'}}
function Get-Process{param($Name,$ErrorAction);return $script:fakeProcesses}
function Must-Block([string]$Name,[string]$Path){$script:fakeProcesses=@([pscustomobject]@{ProcessName=$Name;Path=$Path});$blocked=$false;try{Assert-GameClosed}catch{$blocked=$true};if(-not $blocked){throw "Guard did not block $Name at $Path"}}
$script:fakeProcesses=@();Assert-GameClosed
Must-Block 'Endfield' 'C:\Unrelated\Endfield.exe'
Must-Block 'Launcher' 'C:\Fixture\Endfield\Launcher.exe'
Must-Block 'Games' 'C:\Fixture\Endfield\1.6.0\Games.exe'
Must-Block 'Launcher' ''
$config=[pscustomobject]@{OfficialLauncher='D:\Official\GRYPHLink.exe'};Must-Block 'GRYPHLink' 'D:\Official\GRYPHLink.exe'
$config=$null;$script:fakeProcesses=@([pscustomobject]@{ProcessName='Launcher';Path='C:\UnrelatedApp\Launcher.exe'});Assert-GameClosed
@{status='PASS';test_cases=7;actual_root_installer_invoked=$false;actual_processes_terminated=0;actual_game_writes=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $workspace 'state\tests\review\process_guard_test_result.json')
Write-Output 'PASS: isolated guard AST, seven mocked process cases, no installer execution.'
