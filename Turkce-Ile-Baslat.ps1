[CmdletBinding()]
param([string]$GameData,[ValidateSet('Epic','Steam','Direct')][string]$Platform,[string]$Catalog,[switch]$NoLaunch,[switch]$NoRemote,[switch]$NoMonitor,[switch]$FunctionsOnly)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion -lt [Version]'7.5'){throw 'PowerShell 7.5 veya yenisi gerekiyor (.NET 9 veya yenisi).'}
$repositoryRoot=$PSScriptRoot
. (Join-Path $repositoryRoot 'bin\Find-Endfield.ps1')
. (Join-Path $repositoryRoot 'bin\Update-TranslationCatalog.ps1')

function Get-EndfieldConfigValue($Config,[string]$Name,$Default){
 if($Config -and $Config.PSObject.Properties.Name -contains $Name){return $Config.$Name};return $Default
}
function Invoke-EndfieldApplyChecked {
 param([string]$Root,[string]$Data,[string]$SelectedCatalog)
 $script=Join-Path $Root 'Yenile-Ceviri.ps1';if(-not [IO.File]::Exists($script)){throw 'Yerel çeviri uygulama komutu bulunamadı.'}
 $pwsh=(Get-Process -Id $PID).Path
 $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$pwsh;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 foreach($arg in @('-NoProfile','-File',$script,'-Mode','Apply','-GameData',$Data,'-Catalog',$SelectedCatalog)){[void]$psi.ArgumentList.Add($arg)}
 $p=[Diagnostics.Process]::new();$p.StartInfo=$psi
 try{
  if(-not $p.Start()){throw 'Çeviri komutu başlatılamadı.'};$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync();$p.WaitForExit();$out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
  if($out){Write-Host $out.TrimEnd()};if($p.ExitCode -ne 0){throw ('Çeviri kontrolü/uygulaması başarısız: '+$err.TrimEnd())};if($err){Write-Verbose $err.TrimEnd()}
 }finally{$p.Dispose()}
}
function Get-EndfieldSessionProcesses {
 param([string]$InstallRoot,[string]$Data,[string]$OfficialLauncher)
 $roots=@([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/'),[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Data)))|Select-Object -Unique
 foreach($p in @(Get-Process -Name Endfield,Games,Launcher -ErrorAction SilentlyContinue)){
  try{$path=$p.Path}catch{if($p.ProcessName -eq 'Endfield'){throw 'Oyun süreci güvenle denetlenemiyor.'};continue}
  if(-not $path){if($p.ProcessName -eq 'Endfield'){throw 'Oyun sürecinin yolu doğrulanamıyor.'};continue}
  if($OfficialLauncher -and $path -eq $OfficialLauncher){$p;continue}
  foreach($root in $roots){if($path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){$p;break}}
 }
}
function Wait-EndfieldSessionAndRefresh {
 param([string]$Root,$Installation,[string]$SelectedCatalog,[string]$OfficialLauncher,[int]$StartupTimeoutSeconds=120,[int]$IdleSeconds=10,[int]$PollSeconds=2,[int]$MaxSessionHours=24)
 $start=[DateTime]::UtcNow;$seen=$false;$idleSince=$null
 Write-Host 'Oyun/başlatıcı oturumu izleniyor. Kapandıktan sonra güncelleme çevirisi yeniden kontrol edilecek.'
 while(([DateTime]::UtcNow-$start).TotalHours -lt $MaxSessionHours){
  $active=@(Get-EndfieldSessionProcesses $Installation.InstallRoot $Installation.GameData $OfficialLauncher)
  if($active.Count){$seen=$true;$idleSince=$null}
  elseif($seen){
   if(-not $idleSince){$idleSince=[DateTime]::UtcNow}
   elseif(([DateTime]::UtcNow-$idleSince).TotalSeconds -ge $IdleSeconds){Invoke-EndfieldApplyChecked $Root $Installation.GameData $SelectedCatalog;Write-Host 'Oturum sonrası çeviri kontrolü tamamlandı.';return}
  }elseif(([DateTime]::UtcNow-$start).TotalSeconds -ge $StartupTimeoutSeconds){Write-Warning 'Oyun/başlatıcı süreci görülmedi; ek dosya yazımı yapılmadı.';return}
  Start-Sleep -Seconds $PollSeconds
 }
 Write-Warning 'Oturum izleme süresi doldu. Bir sonraki Türkçe başlatmada kontrol yeniden yapılacak.'
}
if($FunctionsOnly){return}
$configPath=Join-Path $repositoryRoot 'config.json';$config=if([IO.File]::Exists($configPath)){Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json}else{$null}
if(-not $GameData){$GameData=Get-EndfieldConfigValue $config 'GameData' $null}
if(-not $Platform){$Platform=Get-EndfieldConfigValue $config 'Platform' $null}
$found=@(Get-EndfieldInstallations -GameData $GameData)
if($Platform){$found=@($found|Where-Object Platform -eq $Platform)}
if($found.Count -ne 1){
 if($found.Count){$found|Select-Object Platform,GameData|Format-Table|Out-Host}
 throw 'Oyun konumu belirsiz. config.json GameData/Platform veya -GameData ile bir kurulum seç.'
}
$install=$found[0];if($install.Platform -eq 'Ambiguous'){throw 'Aynı kurulum birden fazla platforma ait görünüyor; platform kanıtını kontrol et.'}
$approved=if($Catalog){$Catalog}else{Get-EndfieldConfigValue $config 'ApprovedCatalog' 'translations\catalog.json'}
if(-not [IO.Path]::IsPathRooted($approved)){$approved=Join-Path $repositoryRoot $approved}
$repo=Get-EndfieldConfigValue $config 'UpdateRepository' 'simulasyoncan91/endfield-turkce-yama';$branch=Get-EndfieldConfigValue $config 'UpdateBranch' 'main';$enabled=[bool](Get-EndfieldConfigValue $config 'CheckTranslationUpdates' $true)
if($NoRemote){$enabled=$false}
$release=Update-EndfieldTranslationCatalog -RepositoryRoot $repositoryRoot -LocalCatalog $approved -Repository $repo -Branch $branch -Enabled $enabled
Write-Host ("Çeviri kataloğu: {0} ({1})" -f $release.Version,$release.Status)
Invoke-EndfieldApplyChecked $repositoryRoot $install.GameData $release.CatalogPath
if($NoLaunch){Write-Host 'Kontrol tamamlandı; -NoLaunch nedeniyle oyun başlatılmadı.';return}
$official=Get-EndfieldConfigValue $config 'OfficialLauncher' $install.OfficialLauncher
if($install.Platform -eq 'Steam'){
 Write-Host 'Steam Endfield başlatılıyor.';Start-Process -FilePath 'steam://rungameid/4732690'|Out-Null
}else{
 if(-not $official -or -not [IO.Path]::IsPathRooted($official) -or -not [IO.File]::Exists($official) -or [IO.Path]::GetExtension($official) -ne '.exe'){throw 'Resmi başlatıcının yolu bulunamadı; config.json OfficialLauncher alanını ayarla.'}
 Write-Host ("Resmi {0} başlatıcısı açılıyor." -f $install.Platform);Start-Process -FilePath $official -WorkingDirectory ([IO.Path]::GetDirectoryName($official)) -WindowStyle Normal|Out-Null
}
if(-not $NoMonitor){Wait-EndfieldSessionAndRefresh $repositoryRoot $install $release.CatalogPath $official}
