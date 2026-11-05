function Get-EndfieldReleaseVersion {
 param([Parameter(Mandatory)][string]$Text)
 if($Text -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$'){throw 'Çeviri sürümü geçerli değil.'}
 $v=$null;if(-not [Version]::TryParse($Text,[ref]$v)){throw 'Çeviri sürümü okunamadı.'};return $v
}
function Test-EndfieldRepository {
 param([Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$Branch)
 if($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or @($Repository.Split('/')|Where-Object {$_ -in '.','..'}).Count -or $Branch -notmatch '^[A-Za-z0-9_.-]+$' -or $Branch -in '.','..'){throw 'Güncelleme deposu/dalı geçerli değil.'}
 return "https://raw.githubusercontent.com/$Repository/$Branch/"
}
function Test-EndfieldReleaseDescriptor {
 param([Parameter(Mandatory)]$Descriptor,[Parameter(Mandatory)][string]$Repository,[Parameter(Mandatory)][string]$Branch)
 $prefix=Test-EndfieldRepository $Repository $Branch
 if($Descriptor.schema -ne 'endfield.translation_release.v1'){throw 'Çeviri sürüm bildirimi desteklenmiyor.'}
 [void](Get-EndfieldReleaseVersion ([string]$Descriptor.version))
 if($Descriptor.catalog_path -ne 'translations/catalog.json'){throw 'Uzak katalog yolu izinli konumla eşleşmiyor.'}
 if($Descriptor.catalog_sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Uzak katalog SHA-256 geçersiz.'}
 if($Descriptor.catalog_bytes -isnot [long] -and $Descriptor.catalog_bytes -isnot [int]){throw 'Katalog boyutu tam sayı olmalı.'}
 if($Descriptor.catalog_bytes -lt 1 -or $Descriptor.catalog_bytes -gt 33554432){throw 'Uzak katalog boyutu sınırı aşıyor.'}
 $uri=[Uri]($prefix+$Descriptor.catalog_path)
 if($uri.Scheme -ne 'https' -or $uri.Host -ne 'raw.githubusercontent.com' -or -not $uri.AbsoluteUri.StartsWith($prefix,[StringComparison]::Ordinal)){throw 'Uzak katalog depo kökünden çıkıyor.'}
 return $uri.AbsoluteUri
}
function Test-EndfieldCompactCatalogBytes {
 param([Parameter(Mandatory)][byte[]]$Bytes)
 if($Bytes.Length -lt 1 -or $Bytes.Length -gt 33554432){throw 'Katalog boyutu geçersiz.'}
 $obj=[Text.UTF8Encoding]::new($false,$true).GetString($Bytes)|ConvertFrom-Json -Depth 100
 if($obj.schema -ne 'endfield.translation_catalog.compact.v1' -or $obj.source_build -is [bool] -or ($obj.source_build -isnot [long] -and $obj.source_build -isnot [int]) -or $obj.source_build -le 0){throw 'Yalnız kaynak metin içermeyen kompakt katalog desteklenir.'}
 if($null -eq $obj.records -or $obj.records -isnot [array]){throw 'Katalog kayıt listesi yok.'}
 $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
 foreach($row in $obj.records){
  if($row.PSObject.Properties.Name -contains 'source_en'){throw 'Uzak katalog kaynak İngilizce metin içeremez.'}
  if($row.id -isnot [string] -or $row.id -notmatch '^-?(?:0|[1-9]\d*)$' -or -not $seen.Add($row.id)){throw 'Katalog kimliği eksik veya yinelenmiş.'}
  if($row.source_sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Katalog kaynak özeti geçersiz.'}
  $translation=if($row.PSObject.Properties.Name -contains 'translation_tr'){$row.translation_tr}else{$row.tr}
  if($translation -isnot [string] -or $translation.Contains([char]0) -or $translation.Contains([char]0xFFFD)){throw 'Katalog Türkçe karşılığı geçersiz.'}
 }
 return $obj
}
function Get-EndfieldHttpsBytes {
 param([Parameter(Mandatory)][string]$Uri,[Parameter(Mandatory)][long]$MaxBytes)
 $u=[Uri]$Uri;if($u.Scheme -ne 'https' -or $u.Host -ne 'raw.githubusercontent.com' -or $u.UserInfo -or $u.Query -or $u.Fragment){throw 'Güncelleme adresi izinli değil.'}
 $handler=[Net.Http.HttpClientHandler]::new();$handler.AllowAutoRedirect=$false
 $client=[Net.Http.HttpClient]::new($handler);$client.Timeout=[TimeSpan]::FromSeconds(10)
 $response=$null;$stream=$null;$memory=[IO.MemoryStream]::new()
 try{
  $response=$client.GetAsync($u,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  if([int]$response.StatusCode -ge 300 -and [int]$response.StatusCode -lt 400){throw 'Uzak yönlendirme reddedildi.'}
  [void]$response.EnsureSuccessStatusCode()
  if($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -gt $MaxBytes){throw 'Uzak dosya bildirilen boyutu sınırı aşıyor.'}
  $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult();$buffer=[byte[]]::new(65536)
  while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){if($memory.Length+$count -gt $MaxBytes){throw 'Uzak dosya boyut sınırını aştı.'};$memory.Write($buffer,0,$count)}
  return ,$memory.ToArray()
 }finally{if($stream){$stream.Dispose()};if($response){$response.Dispose()};$memory.Dispose();$client.Dispose();$handler.Dispose()}
}
function Save-EndfieldUpdateJson {
 param([string]$Path,$Value)
 $tmp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp';[IO.File]::WriteAllText($tmp,($Value|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
 if([IO.File]::Exists($Path)){[IO.File]::Replace($tmp,$Path,[NullString]::Value)}else{[IO.File]::Move($tmp,$Path)}
}
function Update-EndfieldTranslationCatalog {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$LocalCatalog,[string]$Repository='simulasyoncan91/endfield-turkce-yama',[string]$Branch='main',[bool]$Enabled=$true)
 $local=[IO.Path]::GetFullPath($LocalCatalog);if(-not [IO.File]::Exists($local)){throw 'Yerel onaylı katalog bulunamadı.'}
 [void](Test-EndfieldCompactCatalogBytes ([IO.File]::ReadAllBytes($local)))
 $state=Join-Path $RepositoryRoot 'state\catalog_updates';[void][IO.Directory]::CreateDirectory($state);$pointer=Join-Path $state 'current.json'
 $selected=$local;$currentVersion=[Version]'0.0.0';$currentHash=(Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
 $localDescriptor=Join-Path $RepositoryRoot 'translations\latest.json'
 if([IO.File]::Exists($localDescriptor)){
  try{$d=Get-Content -LiteralPath $localDescriptor -Raw|ConvertFrom-Json;$v=Get-EndfieldReleaseVersion ([string]$d.version);if($d.catalog_sha256 -eq $currentHash){$currentVersion=$v}}catch{Write-Verbose 'Local release descriptor unavailable; catalog itself remains verified.'}
 }
 if([IO.File]::Exists($pointer)){
  try{
   $saved=Get-Content -LiteralPath $pointer -Raw|ConvertFrom-Json;if($saved.repository -ne $Repository -or $saved.branch -ne $Branch){throw 'Cache repository differs'};$v=Get-EndfieldReleaseVersion ([string]$saved.version);$cache=Join-Path $state ([string]$saved.file)
   if([IO.Path]::GetFileName([string]$saved.file) -ne $saved.file -or -not [IO.File]::Exists($cache)){throw 'Cache path invalid'}
   if((Get-FileHash -LiteralPath $cache -Algorithm SHA256).Hash.ToLowerInvariant() -ne $saved.sha256){throw 'Cache hash invalid'}
   [void](Test-EndfieldCompactCatalogBytes ([IO.File]::ReadAllBytes($cache)))
   if($v -ge $currentVersion){$selected=$cache;$currentVersion=$v;$currentHash=$saved.sha256}
  }catch{Write-Warning 'Önbellekteki çeviri sürümü doğrulanamadı; onaylı yerel katalog kullanılacak.'}
 }
 if(-not $Enabled){return [pscustomobject]@{CatalogPath=$selected;Version=$currentVersion.ToString();Status='LOCAL_ONLY'}}
 try{
  $prefix=Test-EndfieldRepository $Repository $Branch
  $bytes=Get-EndfieldHttpsBytes ($prefix+'translations/latest.json') 32768
  $descriptor=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)|ConvertFrom-Json
  $catalogUri=Test-EndfieldReleaseDescriptor $descriptor $Repository $Branch;$next=Get-EndfieldReleaseVersion ([string]$descriptor.version)
  if($next -lt $currentVersion){return [pscustomobject]@{CatalogPath=$selected;Version=$currentVersion.ToString();Status='REMOTE_OLDER_IGNORED'}}
  if($next -eq $currentVersion){if($descriptor.catalog_sha256 -ne $currentHash){throw 'Aynı sürüm numarası farklı içerikle sunuluyor.'};return [pscustomobject]@{CatalogPath=$selected;Version=$currentVersion.ToString();Status='CURRENT'}}
  $catalogBytes=Get-EndfieldHttpsBytes $catalogUri 33554432
  if($catalogBytes.Length -ne $descriptor.catalog_bytes -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($catalogBytes)).ToLowerInvariant() -ne $descriptor.catalog_sha256.ToLowerInvariant()){throw 'İndirilen katalog özeti/boyutu eşleşmiyor.'}
  [void](Test-EndfieldCompactCatalogBytes $catalogBytes)
  $filename='catalog-'+$next.ToString()+'-'+$descriptor.catalog_sha256.ToLowerInvariant()+'.json';$cache=Join-Path $state $filename
  if([IO.File]::Exists($cache)){if((Get-FileHash -LiteralPath $cache -Algorithm SHA256).Hash.ToLowerInvariant() -ne $descriptor.catalog_sha256.ToLowerInvariant()){throw 'Önbellekte farklı içerik var.'}}else{[IO.File]::WriteAllBytes($cache,$catalogBytes)}
  Save-EndfieldUpdateJson $pointer @{version=$next.ToString();sha256=$descriptor.catalog_sha256.ToLowerInvariant();file=$filename;repository=$Repository;branch=$Branch}
  return [pscustomobject]@{CatalogPath=$cache;Version=$next.ToString();Status='DOWNLOADED_VERIFIED_DATA'}
 }catch{
  Write-Warning ('Çeviri güncellemesi alınamadı; doğrulanmış yerel sürüm kullanılacak. '+$_.Exception.Message)
  return [pscustomobject]@{CatalogPath=$selected;Version=$currentVersion.ToString();Status='OFFLINE_OR_REMOTE_REJECTED'}
 }
}
