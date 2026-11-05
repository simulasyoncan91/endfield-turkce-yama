[CmdletBinding()]
param(
 [ValidateSet('Check','Prepare','Apply','Restore')][string]$Mode='Check',
 [string]$GameData,[string]$Catalog,[string]$PreparedPlan,
 [string]$StateRoot
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion -lt [Version]'7.5'){throw 'PowerShell 7.5 veya yenisi gerekiyor.'}
$runtimeRoot=$PSScriptRoot
if(-not $StateRoot){$StateRoot=Join-Path $runtimeRoot 'state'}
$StateRoot=[IO.Path]::GetFullPath($StateRoot)
$configPath=Join-Path $runtimeRoot 'config.json'
$config=if(Test-Path -LiteralPath $configPath){Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json}else{$null}
if(-not $GameData -and $config){$GameData=$config.GameData}
if(-not $GameData){
 . (Join-Path $runtimeRoot 'bin\Find-Endfield.ps1')
 $found=@(Get-EndfieldInstallations)
 if($found.Count -ne 1){throw 'Oyun konumu belirsiz. -GameData ile Endfield_Data klasorunu secin.'}
 $GameData=$found[0].GameData
}
$GameData=[IO.Path]::GetFullPath($GameData)
if(-not(Test-Path -LiteralPath (Join-Path $GameData 'StreamingAssets\VFS'))){throw 'Gecerli Endfield_Data/VFS bulunamadi.'}
if($StateRoot.StartsWith($GameData+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or $StateRoot -eq $GameData){throw 'Ceviri durumu oyun klasorunun disinda olmali.'}
if(-not $Catalog){$Catalog=if($config -and $config.ApprovedCatalog){Join-Path $runtimeRoot $config.ApprovedCatalog}else{Join-Path $runtimeRoot 'translations\catalog.json'}}
$Catalog=(Resolve-Path -LiteralPath $Catalog).Path
[void][IO.Directory]::CreateDirectory($StateRoot)
$lockPath=Join-Path $StateRoot 'update.lock'
$lock=$null
function Read-Json([string]$Path){if(Test-Path -LiteralPath $Path){return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json};return $null}
function Hash([string]$Path){if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()};return 'MISSING'}
function Save-Json([string]$Path,$Value){
 $tmp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
 if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,[NullString]::Value)}else{[IO.File]::Move($tmp,$Path)}
}
function Assert-Target([string]$Path){
 $full=[IO.Path]::GetFullPath($Path)
 if(-not $full.StartsWith($GameData+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Oyun hedefi Endfield_Data disina cikiyor.'}
 if([IO.Path]::GetExtension($full)-notin '.blc','.chk'){throw 'Beklenmeyen oyun hedefi turu.'}
}
function Assert-GameClosed{
 $install=[IO.Directory]::GetParent($GameData).FullName
 $roots=[Collections.Generic.List[string]]::new();$roots.Add([IO.Path]::GetFullPath($install))
 $officialPaths=[Collections.Generic.List[string]]::new()
 $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 foreach($name in @('Endfield','Games','Launcher')){[void]$names.Add($name)}
 if(-not (Get-Command Get-EndfieldInstallations -ErrorAction SilentlyContinue)){. (Join-Path $runtimeRoot 'bin\Find-Endfield.ps1')}
 # Only installation evidence whose validated GameData is this exact selected
 # directory may broaden the guard. A manifest for another copy is not used.
 foreach($candidate in @(Get-EndfieldInstallations -GameData $GameData)){
  if([IO.Path]::GetFullPath($candidate.GameData) -ne [IO.Path]::GetFullPath($GameData)){continue}
  $root=[IO.Path]::GetFullPath($candidate.InstallRoot).TrimEnd('\','/')
  if([IO.Directory]::GetParent($root)){$roots.Add($root)}
  if($candidate.OfficialLauncher){$officialPaths.Add([IO.Path]::GetFullPath($candidate.OfficialLauncher))}
 }
 if($config -and $config.PSObject.Properties.Name -contains 'OfficialLauncher' -and $config.OfficialLauncher){
  if(-not [IO.Path]::IsPathRooted([string]$config.OfficialLauncher)){throw 'Resmi baslatici ayari mutlak yol olmali.'}
  $officialPaths.Add([IO.Path]::GetFullPath([string]$config.OfficialLauncher))
 }
 foreach($path in $officialPaths){[void]$names.Add([IO.Path]::GetFileNameWithoutExtension($path))}
 foreach($p in @(Get-Process -Name @($names|ForEach-Object {$_}) -ErrorAction SilentlyContinue)){
  try{$processPath=$p.Path}catch{throw 'Oyun sureci guvenle denetlenemiyor.'}
  if(-not $processPath -or $p.ProcessName -eq 'Endfield'){throw 'Oyunu ve oyunun resmi baslaticisini kapatip yeniden deneyin.'}
  $processPath=[IO.Path]::GetFullPath($processPath)
  foreach($path in $officialPaths){if($processPath -eq $path){throw 'Oyunun resmi baslaticisini kapatip yeniden deneyin.'}}
  foreach($root in $roots){if($processPath.StartsWith($root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Oyunu ve oyunun resmi baslaticisini kapatip yeniden deneyin.'}}
 }
}
function Replace-Checked([string]$Source,[string]$Target,[string]$ExpectedBefore,[string]$ExpectedAfter){
 Assert-Target $Target
 if((Hash $Target)-ne $ExpectedBefore.ToLowerInvariant()){throw 'Oyun dosyasi hazirliktan sonra degisti; uzerine yazilmadi.'}
 $tmp=$Target+'.endfield-tr-'+[Guid]::NewGuid().ToString('N')+'.tmp'
 try{
  Copy-Item -LiteralPath $Source -Destination $tmp
  if((Hash $tmp)-ne $ExpectedAfter.ToLowerInvariant()){throw 'Gecici kopya ozeti farkli.'}
  [IO.File]::Replace($tmp,$Target,[NullString]::Value)
  if((Hash $Target)-ne $ExpectedAfter.ToLowerInvariant()){throw 'Kurulum sonrasi ozet farkli.'}
 }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
function Recover-Transaction($Journal){
 foreach($f in $Journal.files){
  Assert-Target $f.target
  $actual=Hash $f.target
  if($actual -notin @($f.before_sha256,$f.after_sha256)){throw 'Yarim islemden sonra oyun farkli degisti. Otomatik geri alma durduruldu.'}
  if((Hash $f.rollback)-ne $f.before_sha256){throw 'Islem yedegi dogrulanamadi.'}
 }
 Assert-GameClosed
 foreach($f in $Journal.files){if((Hash $f.target)-eq $f.after_sha256){Replace-Checked $f.rollback $f.target $f.after_sha256 $f.before_sha256}}
 if($Journal.PSObject.Properties['previous_receipt']){if($Journal.previous_receipt){Save-Json (Join-Path $StateRoot 'last_install.json') $Journal.previous_receipt}elseif(Test-Path -LiteralPath (Join-Path $StateRoot 'last_install.json')){Remove-Item -LiteralPath (Join-Path $StateRoot 'last_install.json')}}
 $Journal.status='ROLLED_BACK';Save-Json (Join-Path $StateRoot 'transaction.json') $Journal
}
function Invoke-Python([string]$Script,[object[]]$Arguments){
 $py=Get-Command python -ErrorAction SilentlyContinue
 if($py){& $py.Source $Script @Arguments}else{$py=Get-Command py -ErrorAction Stop;& $py.Source -3 $Script @Arguments}
 if($LASTEXITCODE -ne 0){throw 'Python dogrulama/derleme islemi basarisiz. Oyun dosyalarina uygulanmadi.'}
}
try{
 $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $receiptPath=Join-Path $StateRoot 'last_install.json';$journalPath=Join-Path $StateRoot 'transaction.json'
 $receipt=Read-Json $receiptPath;$journal=Read-Json $journalPath
 if($journal -and $journal.status -notin @('COMMITTED','ROLLED_BACK')){
  if($Mode -eq 'Check'){throw 'Yarim kalmis islem bulundu. Apply veya Restore ile kontrollu geri alma yapilmali.'}
  Recover-Transaction $journal
  $receipt=Read-Json $receiptPath
 }
 $known=$false
 if($receipt -and $receipt.files.Count -gt 0){
  $known=$true
  foreach($f in $receipt.files){Assert-Target $f.target;if((Hash $f.target)-ne $f.installed_sha256.ToLowerInvariant()){$known=$false}}
 }
 $catalogHash=Hash $Catalog
 if($known -and $receipt.status -eq 'APPLIED' -and $receipt.catalog_sha256 -eq $catalogHash -and $Mode -ne 'Restore'){
  [pscustomobject]@{Status='CURRENT';Build=$receipt.game_build;TranslatedRecords=$receipt.translated_records;GameWrites=0;CatalogSHA256=$catalogHash}|ConvertTo-Json
  return
 }
 if($Mode -eq 'Check'){
  [pscustomobject]@{Status=if($known -and $receipt.status -eq 'RESTORED'){'ORIGINAL_RESTORED'}elseif($known){'CATALOG_CHANGED'}else{'GAME_CHANGED_OR_NOT_PATCHED'};GameWrites=0;Action='Apply';CatalogSHA256=$catalogHash}|ConvertTo-Json
  return
 }
 Assert-GameClosed
 if($Mode -eq 'Restore'){
  if(-not $known -or -not $receipt){throw 'Kurulu dosyalar bilinen yama kaydiyla eslesmiyor; eski yedek yazilmadi.'}
  $snapshot=Join-Path $runtimeRoot $receipt.snapshot
  foreach($f in $receipt.files){$original=Join-Path $snapshot $f.original_relative;if((Hash $original)-ne $f.original_sha256){throw 'Ozgün surum yedegi dogrulanamadi.'}}
  $restoreRun=Join-Path $StateRoot ('restore-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($restoreRun)
  $restoreFiles=foreach($f in $receipt.files){
   $rollback=Join-Path $restoreRun ([IO.Path]::GetFileName($f.target));Copy-Item -LiteralPath $f.target -Destination $rollback
   [pscustomobject]@{target=$f.target;prepared=(Join-Path $snapshot $f.original_relative);before_sha256=$f.installed_sha256;after_sha256=$f.original_sha256;rollback=$rollback}
  }
  $restoreJournal=[pscustomobject]@{schema='endfield.local_transaction.v1';status='PREPARED';files=@($restoreFiles);previous_receipt=$receipt}
  Save-Json $journalPath $restoreJournal
  try{
   foreach($f in $restoreFiles){Replace-Checked $f.prepared $f.target $f.before_sha256 $f.after_sha256}
   $receipt.status='RESTORED';foreach($f in $receipt.files){$f.installed_sha256=$f.original_sha256};Save-Json $receiptPath $receipt
   $restoreJournal.status='COMMITTED';Save-Json $journalPath $restoreJournal
   [pscustomobject]@{Status='RESTORED';Build=$receipt.game_build;GameWrites=$receipt.files.Count}|ConvertTo-Json;return
  }catch{Recover-Transaction $restoreJournal;throw}
 }
 . (Join-Path $runtimeRoot 'bin\VfsBridge.ps1')
 Initialize-VfsReader
 $run=Join-Path $StateRoot ('runs\'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'-'+[Guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($run)
 if($known -and $receipt){
  $originalSnapshot=Join-Path $runtimeRoot $receipt.snapshot
  foreach($f in $receipt.files){if((Hash (Join-Path $originalSnapshot $f.original_relative))-ne $f.original_sha256){throw 'Ozgün kaynak yedegi hasarli.'}}
  $ctx=Get-VfsContext -GameData $GameData -AssetsRoot (Join-Path $originalSnapshot 'original')
  $ctx.GameChunkPath=($receipt.files|Where-Object { [IO.Path]::GetExtension($_.target) -eq '.chk' }).target
  $ctx.GameMetadataPath=($receipt.files|Where-Object { [IO.Path]::GetExtension($_.target) -eq '.blc' }).target
 }else{
  $ctx=Get-VfsContext -GameData $GameData
 }
 $snapshot=Join-Path $run 'source'
 $snapshotContext=Export-VfsSnapshot -GameData $GameData -Destination $snapshot -Context $ctx
 Invoke-Python (Join-Path $runtimeRoot 'bin\build_references.py') @('--tables',(Join-Path $snapshot 'tables'),'--source',(Join-Path $snapshot 'source.json'),'--output',(Join-Path $snapshot 'references.json'))
 $build=Join-Path $run 'build'
 Invoke-Python (Join-Path $runtimeRoot 'bin\translation_core.py') @('prepare','--original-bytes',(Join-Path $snapshot 'original.bytes'),'--source-json',(Join-Path $snapshot 'source.json'),'--metadata-plain',(Join-Path $snapshot 'metadata.original.plain'),'--context',(Join-Path $snapshot 'context.json'),'--references',(Join-Path $snapshot 'references.json'),'--catalog',$Catalog,'--output',$build)
 $selection=Read-Json (Join-Path $build 'selection_report.json')
 Invoke-VfsEncrypt -Snapshot $snapshot -BuildOutput $build
 Invoke-Python (Join-Path $runtimeRoot 'bin\translation_core.py') @('finalize','--plan',(Join-Path $build 'build_plan.json'),'--encrypted-file',(Join-Path $build 'translated.encrypted.bin'),'--original-chunk',$snapshotContext.ChunkPath)
 $stage=Complete-VfsStage -Snapshot $snapshot -BuildOutput $build
 $snapshotContext=Read-Json (Join-Path $snapshot 'context.json')
 $targets=@(
  [pscustomobject]@{target=$snapshotContext.GameChunkPath;prepared=$stage.ChunkPath},
  [pscustomobject]@{target=$snapshotContext.GameMetadataPath;prepared=$stage.MetadataPath}
 )
 foreach($f in $targets){Assert-Target $f.target;if(-not(Test-Path -LiteralPath $f.prepared)){throw 'Dogrulanmis cikti dosyasi bulunamadi.'}}
 $files=@();$rollbackDir=Join-Path $run 'rollback';[void][IO.Directory]::CreateDirectory($rollbackDir)
 foreach($f in $targets){
  $before=Hash $f.target
  $expected=if($known){($receipt.files|Where-Object target -eq $f.target).installed_sha256}else{if($f.target -eq $snapshotContext.GameChunkPath){$ctx.CurrentChunkSHA256}else{$ctx.CurrentMetaSHA256}}
  if($before -ne $expected.ToLowerInvariant()){throw 'Guncelleme dosyasi hazirlik sirasinda degisti; yama uygulanmadi.'}
  $rollback=Join-Path $rollbackDir ([IO.Path]::GetFileName($f.target));Copy-Item -LiteralPath $f.target -Destination $rollback
  $files+=[pscustomobject]@{target=$f.target;prepared=$f.prepared;before_sha256=$before;after_sha256=Hash $f.prepared;rollback=$rollback}
 }
 Save-Json (Join-Path $run 'prepared_install.json') ([pscustomobject]@{files=$files;build=$snapshotContext.Version;catalog_sha256=$catalogHash})
 if($Mode -eq 'Prepare'){
  [pscustomobject]@{Status='PREPARED';Build=$snapshotContext.Version;Plan=(Join-Path $run 'prepared_install.json');NeedsReview=(Join-Path $build 'needs_review.json');GameWrites=0}|ConvertTo-Json;return
 }
 $transaction=[pscustomobject]@{schema='endfield.local_transaction.v1';status='PREPARED';files=$files;build=$snapshotContext.Version;catalog_sha256=$catalogHash;previous_receipt=$receipt}
 Save-Json $journalPath $transaction
 try{
  Assert-GameClosed
  foreach($f in $files){Replace-Checked $f.prepared $f.target $f.before_sha256 $f.after_sha256}
  Test-VfsStage -Snapshot $snapshot -BuildOutput $build -GameData $GameData
  $snapRelative=[IO.Path]::GetRelativePath($runtimeRoot,$snapshot)
  $receiptFiles=foreach($f in $files){
   $orig=if($f.target -eq $snapshotContext.GameChunkPath){$snapshotContext.ChunkPath}else{$snapshotContext.MetadataPath}
   [pscustomobject]@{target=$f.target;installed_sha256=$f.after_sha256;original_sha256=Hash $orig;original_relative=[IO.Path]::GetRelativePath($snapshot,$orig)}
  }
  $selected=Read-Json (Join-Path $build 'selected_translations.json')
  $translatedCount=@($selected.PSObject.Properties).Count
  $newReceipt=[pscustomobject]@{schema='endfield.local_receipt.v1';status='APPLIED';game_build=$snapshotContext.Version;catalog_sha256=$catalogHash;translated_records=$translatedCount;snapshot=$snapRelative;files=@($receiptFiles);needs_review=[IO.Path]::GetRelativePath($runtimeRoot,(Join-Path $build 'needs_review.json'));runtime_status='not_tested'}
  Save-Json $receiptPath $newReceipt
  $transaction.status='COMMITTED';Save-Json $journalPath $transaction
  [pscustomobject]@{Status='APPLIED';Build=$snapshotContext.Version;TranslatedRecords=$translatedCount;NeedsReview=$newReceipt.needs_review;GameWrites=$files.Count}|ConvertTo-Json
 }catch{Recover-Transaction $transaction;throw}
}finally{if($lock){$lock.Dispose()}}
