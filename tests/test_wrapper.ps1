$ErrorActionPreference='Stop'
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
[void][IO.Directory]::CreateDirectory((Join-Path $workspace 'state\tests\review'))
. "$workspace\Turkce-Ile-Baslat.ps1" -FunctionsOnly
$root=Join-Path $workspace ('state\tests\remote_fixture_'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory((Join-Path $root 'translations'))
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Throws([scriptblock]$Block,[string]$Message){$failed=$false;try{& $Block|Out-Null}catch{$failed=$true};if(-not $failed){throw $Message}}
function Catalog-Bytes([string]$Tr){return ,[Text.Encoding]::UTF8.GetBytes((@{schema='endfield.translation_catalog.compact.v1';source_build=27533267;records=@(@{id='1';translation_tr=$Tr;source_sha256=('a'*64);references=@();protected_tokens=@()})}|ConvertTo-Json -Depth 10 -Compress))}
function Descriptor([string]$Version,[byte[]]$Bytes){return @{schema='endfield.translation_release.v1';version=$Version;catalog_path='translations/catalog.json';catalog_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant();catalog_bytes=$Bytes.Length}}
$local=Join-Path $root 'translations\catalog.json';$one=Catalog-Bytes 'Bir';[IO.File]::WriteAllBytes($local,$one);$d1=Descriptor '0.1.0' $one;$d1|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'translations\latest.json')
$valid=Test-EndfieldReleaseDescriptor $d1 'simulasyoncan91/endfield-turkce-yama' 'main';Assert-True ($valid -eq 'https://raw.githubusercontent.com/simulasyoncan91/endfield-turkce-yama/main/translations/catalog.json') 'Descriptor did not bind repository'
Assert-Throws {Test-EndfieldRepository '../repo' 'main'} 'Repository traversal accepted'
Assert-Throws {Test-EndfieldRepository 'owner/repo' '../main'} 'Branch traversal accepted'
foreach($badPath in @('../catalog.json','https://example.com/x','translations/code.ps1')){$d=@{}+$d1;$d.catalog_path=$badPath;Assert-Throws {Test-EndfieldReleaseDescriptor $d 'owner/repo' 'main'} 'Invalid catalog path accepted'}
foreach($size in @(-1,33554433,1.5,$true)){$d=@{}+$d1;$d.catalog_bytes=$size;Assert-Throws {Test-EndfieldReleaseDescriptor $d 'owner/repo' 'main'} 'Invalid catalog size accepted'}
Assert-Throws {Get-EndfieldHttpsBytes 'http://raw.githubusercontent.com/owner/repo/main/x' 10} 'HTTP accepted'
Assert-Throws {Get-EndfieldHttpsBytes 'https://example.com/x' 10} 'Foreign host accepted'
$bad=[Text.Encoding]::UTF8.GetBytes('{"schema":"endfield.translation_catalog.compact.v1","source_build":1,"records":[{"id":"1","translation_tr":"Bir","source_en":"One","source_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}');Assert-Throws {Test-EndfieldCompactCatalogBytes $bad} 'English source accepted in remote compact catalog'
$two=Catalog-Bytes 'İki';$script:descriptor=Descriptor '0.2.0' $two;$script:remoteCatalogBytes=$two;$script:offline=$false;$script:calls=[Collections.Generic.List[string]]::new()
function Get-EndfieldHttpsBytes([string]$Uri,[long]$MaxBytes){$script:calls.Add($Uri);if($script:offline){throw 'Synthetic offline'};if($Uri.EndsWith('latest.json')){return ,[Text.Encoding]::UTF8.GetBytes(($script:descriptor|ConvertTo-Json -Compress))};return ,$script:remoteCatalogBytes}
$r=Update-EndfieldTranslationCatalog -RepositoryRoot $root -LocalCatalog $local;Assert-True ($r.Status -eq 'DOWNLOADED_VERIFIED_DATA' -and $r.Version -eq '0.2.0') 'New data catalog was not cached'
$cached=$r.CatalogPath;$hash=(Get-FileHash -LiteralPath $cached).Hash;$script:calls.Clear()
$r=Update-EndfieldTranslationCatalog -RepositoryRoot $root -LocalCatalog $local -Enabled $false;Assert-True ($r.Status -eq 'LOCAL_ONLY' -and $r.CatalogPath -eq $local -and $script:calls.Count -eq 0) 'Explicit local catalog was overridden by cache or network'
$r=Update-EndfieldTranslationCatalog -RepositoryRoot $root -LocalCatalog $local;Assert-True ($r.Status -eq 'CURRENT' -and $script:calls.Count -eq 1) 'Repeat check downloaded or downgraded catalog'
$script:descriptor=Descriptor '0.0.9' $one;$script:calls.Clear();$r=Update-EndfieldTranslationCatalog -RepositoryRoot $root -LocalCatalog $local;Assert-True ($r.Status -eq 'REMOTE_OLDER_IGNORED' -and $r.CatalogPath -eq $cached -and $script:calls.Count -eq 1) 'Downgrade not blocked'
$script:offline=$true;$r=Update-EndfieldTranslationCatalog -RepositoryRoot $root -LocalCatalog $local;Assert-True ($r.Status -eq 'OFFLINE_OR_REMOTE_REJECTED' -and $r.CatalogPath -eq $cached) 'Offline cache not retained'
$script:offline=$false;$script:descriptor=Descriptor '0.3.0' $one;$script:remoteCatalogBytes=Catalog-Bytes 'Yanlış';$r=Update-EndfieldTranslationCatalog -RepositoryRoot $root -LocalCatalog $local;Assert-True ($r.CatalogPath -eq $cached -and (Get-FileHash -LiteralPath $cached).Hash -eq $hash) 'Bad remote hash altered current catalog'
$script:applyCalls=0;$script:iterations=0
function Invoke-EndfieldApplyChecked{param($Root,$Data,$SelectedCatalog);$script:applyCalls++}
function Get-EndfieldSessionProcesses{param($InstallRoot,$Data,$OfficialLauncher);$script:iterations++;if($script:iterations -eq 1){[pscustomobject]@{Name='SyntheticEndfield'}}}
function Start-Sleep{param([int]$Seconds)}
Wait-EndfieldSessionAndRefresh -Root $root -Installation ([pscustomobject]@{InstallRoot=$root;GameData=$root}) -SelectedCatalog $local -OfficialLauncher '' -StartupTimeoutSeconds 1 -IdleSeconds 0 -PollSeconds 0
Assert-True ($script:applyCalls -eq 1) 'Session close refresh count differs'
$script:iterations=1;$script:applyCalls=0
Wait-EndfieldSessionAndRefresh -Root $root -Installation ([pscustomobject]@{InstallRoot=$root;GameData=$root}) -SelectedCatalog $local -OfficialLauncher '' -StartupTimeoutSeconds 0 -IdleSeconds 0 -PollSeconds 0
Assert-True ($script:applyCalls -eq 0) 'Never-seen game triggered repair'
@{status='PASS';test_groups=14;fixture=$root;actual_network_requests=0;actual_game_launches=0;actual_game_writes=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $workspace 'state\tests\review\wrapper_test_result.json')
Write-Output 'PASS: descriptor guards, data-only remote cache, offline/no-downgrade/hash rejection and session lifecycle synthetic checks.'
