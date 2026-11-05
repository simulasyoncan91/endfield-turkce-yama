[CmdletBinding()]
param([string]$GameData,[ValidateSet('Epic','Steam','Direct')][string]$Platform,[switch]$CreateShortcut)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion -lt [Version]'7.5'){throw 'PowerShell 7.5 veya yenisi gerekiyor: https://github.com/PowerShell/PowerShell/releases'}
if(-not(Get-Command python -ErrorAction SilentlyContinue)-and-not(Get-Command py -ErrorAction SilentlyContinue)){throw 'Python 3.9+ gerekiyor: https://www.python.org/downloads/windows/'}
$root=$PSScriptRoot
. (Join-Path $root 'bin\Find-Endfield.ps1')
$installs=@(Get-EndfieldInstallations -GameData $GameData)
if($Platform){$installs=@($installs|Where-Object Platform -eq $Platform)}
if($installs.Count -ne 1){$installs|Select-Object Platform,GameData|Format-Table|Out-Host;throw 'Bir kurulum secmek icin -GameData ve gerekirse -Platform kullanin.'}
$chosen=$installs[0]
$configPath=Join-Path $root 'config.json'
$config=[ordered]@{GameData=$chosen.GameData;Platform=$chosen.Platform;OfficialLauncher=$chosen.OfficialLauncher;ApprovedCatalog='translations/catalog.json';UpdateRepository='simulasyoncan91/endfield-turkce-yama';UpdateBranch='main';CheckTranslationUpdates=$true}
if(Test-Path -LiteralPath $configPath){
 $old=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
 if($old.GameData -and [IO.Path]::GetFullPath($old.GameData) -ne [IO.Path]::GetFullPath($chosen.GameData)){throw 'Mevcut ayar baska kuruluma ait; ayari yedekleyip acikca yeni kurulumu secin.'}
 Copy-Item -LiteralPath $configPath -Destination ($configPath+'.'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.bak')
}
[IO.File]::WriteAllText($configPath,($config|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
& (Join-Path $root 'Yenile-Ceviri.ps1') -Mode Apply -GameData $chosen.GameData
if($CreateShortcut){
 $desktop=[Environment]::GetFolderPath('Desktop')
 $shortcut=Join-Path $desktop 'Endfield Turkce.lnk'
 if(Test-Path -LiteralPath $shortcut){throw 'Ayni adli kisayol zaten var; uzerine yazilmadi.'}
 $shell=New-Object -ComObject WScript.Shell
 $link=$shell.CreateShortcut($shortcut);$link.TargetPath=(Get-Process -Id $PID).Path
 $link.Arguments='-NoProfile -File "'+(Join-Path $root 'Turkce-Ile-Baslat.ps1')+'"'
 $link.WorkingDirectory=$root;$link.Description='Oyunu acmadan once Turkce ceviri guncelligini denetler';$link.Save()
 Write-Host ('Kisayol olusturuldu: '+$shortcut)
}
Write-Host 'Kurulum/yenileme tamamlandi. Oyun acilisi icin Turkce-Ile-Baslat.cmd kullanabilirsiniz.'
