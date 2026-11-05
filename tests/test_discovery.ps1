$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
[void][IO.Directory]::CreateDirectory((Join-Path $workspace 'state\tests\review'))
. "$workspace\bin\Find-Endfield.ps1"
$root=Join-Path $workspace ('state\tests\discovery_fixture_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Assert-True([bool]$condition,[string]$message){if(-not $condition){throw $message}}
function New-FakeGame([string]$folder){$data=Join-Path $folder 'Endfield_Data';[void][IO.Directory]::CreateDirectory((Join-Path $data 'StreamingAssets\VFS'));[IO.File]::WriteAllBytes((Join-Path $folder 'GameAssembly.dll'),[byte[]]@());[IO.File]::WriteAllBytes((Join-Path $folder 'UnityPlayer.dll'),[byte[]]@());return $data}
$noEpic=Join-Path $root 'no_epic';$direct=Join-Path $root 'Direct';$data=New-FakeGame $direct
$x=@(Get-EndfieldInstallations -EpicManifestDirectory $noEpic -DirectRoots @($direct) -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 1 -and $x[0].Platform -eq 'Direct') 'Direct discovery failed'
$x=@(Get-EndfieldInstallations -GameData $data -EpicManifestDirectory $noEpic -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 1 -and $x[0].GameData -eq $data) 'Explicit discovery failed'
$epic=Join-Path $root 'epic';[void][IO.Directory]::CreateDirectory($epic);@{DisplayName='Arknights: Endfield';InstallLocation=$direct;bIsIncompleteInstall=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $epic 'endfield.item')
$x=@(Get-EndfieldInstallations -EpicManifestDirectory $epic -DirectRoots @($direct) -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 1 -and $x[0].Platform -eq 'Epic') 'Epic evidence/dedup failed'
$steam=Join-Path $root 'Steam';$lib=Join-Path $root 'OtherLibrary';$steamGame=Join-Path $lib 'steamapps\common\Endfield';$steamData=New-FakeGame $steamGame;[void][IO.Directory]::CreateDirectory((Join-Path $steam 'steamapps'))
$escaped=$lib.Replace('\','\\');[IO.File]::WriteAllText((Join-Path $steam 'steamapps\libraryfolders.vdf'),('"libraryfolders" { "0" { "path" "'+$escaped+'" } }'))
[IO.File]::WriteAllText((Join-Path $lib 'steamapps\appmanifest_4732690.acf'),'"AppState" { "appid" "4732690" "installdir" "Endfield" }')
$x=@(Get-EndfieldInstallations -EpicManifestDirectory $noEpic -SteamRoots @($steam) -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 1 -and $x[0].Platform -eq 'Steam' -and $x[0].LaunchUri -eq 'steam://rungameid/4732690') 'Steam VDF/library discovery failed'
$x=@(Get-EndfieldInstallations -EpicManifestDirectory $epic -SteamRoots @($steam) -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 2) 'Multiple installs silently selected'
$x=@(Get-EndfieldInstallations -GameData $steamData -EpicManifestDirectory $epic -SteamRoots @($steam) -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 1 -and $x[0].Platform -eq 'Steam') 'Explicit multi-install selection failed'
[IO.File]::WriteAllText((Join-Path $lib 'steamapps\appmanifest_4732690.acf'),'"AppState" { "appid" "4732690" "installdir" "..\\..\\escape" }')
$x=@(Get-EndfieldInstallations -EpicManifestDirectory $noEpic -SteamRoots @($steam) -SkipRegistry -SkipKnownRoots);Assert-True ($x.Count -eq 0) 'Steam traversal not refused'
$threw=$false;try{ConvertFrom-EndfieldValveKeyValues '"x" { "key" "a" "key" "b" }'|Out-Null}catch{$threw=$true};Assert-True $threw 'Duplicate VDF key not refused'
@{status='PASS';tests=8;fixture=$root;game_launches=0;game_writes=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $workspace 'state\tests\review\discovery_test_result.json')
Write-Output 'PASS: 8 synthetic discovery checks; no launcher/game executed.'
