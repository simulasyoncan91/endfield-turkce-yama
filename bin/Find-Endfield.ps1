function ConvertFrom-EndfieldValveKeyValues {
    param([Parameter(Mandatory)][string]$Text)
    $parts = [regex]::Matches($Text, '(?m)//[^\r\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+')
    $tokens = [Collections.Generic.List[string]]::new()
    foreach ($part in $parts) { if (-not $part.Value.StartsWith('//')) { $tokens.Add($part.Value) } }
    $cursor = @{ Index = 0 }
    function Read-EndfieldVdfAtom([string]$Value) {
        if ($Value.StartsWith('"')) { return $Value.Substring(1,$Value.Length-2).Replace('\\','\').Replace('\"','"') }
        return $Value
    }
    function Read-EndfieldVdfObject([bool]$Nested) {
        $result = @{}
        while ($cursor.Index -lt $tokens.Count) {
            $key = $tokens[$cursor.Index]; $cursor.Index++
            if ($key -eq '}') { if (-not $Nested) { throw 'Unexpected VDF closing brace' }; return $result }
            if ($key -eq '{' -or $cursor.Index -ge $tokens.Count) { throw 'Invalid VDF key/value pair' }
            $key = Read-EndfieldVdfAtom $key
            if ($result.ContainsKey($key)) { throw 'Duplicate VDF key' }
            $value = $tokens[$cursor.Index]; $cursor.Index++
            if ($value -eq '{') { $result[$key] = Read-EndfieldVdfObject $true }
            elseif ($value -eq '}') { throw 'Missing VDF value' }
            else { $result[$key] = Read-EndfieldVdfAtom $value }
        }
        if ($Nested) { throw 'Unterminated VDF object' }
        return $result
    }
    return Read-EndfieldVdfObject $false
}

function Resolve-EndfieldGameData {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.Directory]::Exists($Path)) { return }
    $root = [IO.Path]::GetFullPath($Path)
    $paths = @($root)
    foreach ($rel in @('Endfield_Data','games\Arknights Endfield\Endfield_Data','Arknights Endfield\Endfield_Data','Game\Endfield_Data','Client\Endfield_Data')) { $paths += Join-Path $root $rel }
    foreach ($candidate in $paths | Select-Object -Unique) {
        if ([IO.Path]::GetFileName($candidate.TrimEnd('\','/')) -ne 'Endfield_Data') { continue }
        $parent = [IO.Path]::GetDirectoryName($candidate)
        if ([IO.Directory]::Exists((Join-Path $candidate 'StreamingAssets\VFS')) -and [IO.File]::Exists((Join-Path $parent 'GameAssembly.dll')) -and [IO.File]::Exists((Join-Path $parent 'UnityPlayer.dll'))) { [IO.Path]::GetFullPath($candidate) }
    }
}

function Get-EndfieldInstallations {
    [CmdletBinding()]
    param(
        [string]$GameData,
        [string]$EpicManifestDirectory = (Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'),
        [string[]]$SteamRoots = @(),
        [string[]]$DirectRoots = @(),
        [switch]$SkipRegistry,
        [switch]$SkipKnownRoots
    )
    $found = [Collections.Generic.List[object]]::new()
    function Add-EndfieldCandidate([string]$Candidate,[string]$Platform,[string]$Evidence,[string]$Manifest,[string]$SteamRoot) {
        foreach ($data in @(Resolve-EndfieldGameData $Candidate)) {
            $launch = $null
            $ancestors = @([IO.Path]::GetFullPath($Candidate),[IO.Path]::GetDirectoryName($data))
            $a = [IO.Path]::GetDirectoryName($data)
            for ($i=0; $i -lt 3 -and $a; $i++) { $ancestors += $a; $a = [IO.Path]::GetDirectoryName($a) }
            foreach ($a in $ancestors | Select-Object -Unique) { $exe=Join-Path $a 'Launcher.exe'; if ([IO.File]::Exists($exe)) { $launch=[IO.Path]::GetFullPath($exe); break } }
            $found.Add([pscustomobject]@{Platform=$Platform;GameData=$data;InstallRoot=[IO.Path]::GetFullPath($Candidate);OfficialLauncher=$launch;LaunchUri=$(if($Platform -eq 'Steam'){'steam://rungameid/4732690'}else{$null});Evidence=$Evidence;Manifest=$Manifest;SteamRoot=$SteamRoot})
        }
    }
    if ([IO.Directory]::Exists($EpicManifestDirectory)) {
        foreach ($file in Get-ChildItem -LiteralPath $EpicManifestDirectory -File -Filter '*.item' -ErrorAction SilentlyContinue) {
            try {
                $m=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                if ($m.DisplayName -match 'Arknights.*Endfield' -and $m.InstallLocation) {
                    if ($m.PSObject.Properties.Name -contains 'bIsIncompleteInstall' -and $m.bIsIncompleteInstall) { continue }
                    Add-EndfieldCandidate $m.InstallLocation 'Epic' 'Epic installed manifest' $file.FullName ''
                }
            } catch { Write-Verbose "Skipped invalid Epic manifest: $($file.Name)" }
        }
    }
    $steamCandidates=[Collections.Generic.List[string]]::new()
    foreach($root in $SteamRoots){if($root){$steamCandidates.Add($root)}}
    $directCandidates=[Collections.Generic.List[string]]::new()
    foreach($root in $DirectRoots){if($root){$directCandidates.Add($root)}}
    if(-not $SkipRegistry){
        foreach($key in @('Registry::HKEY_CURRENT_USER\Software\Valve\Steam','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam')){
            try{$v=Get-ItemProperty -LiteralPath $key -ErrorAction Stop;foreach($name in @('SteamPath','InstallPath')){if($v.PSObject.Properties.Name -contains $name -and $v.$name){$steamCandidates.Add([string]$v.$name)}}}catch{}
        }
        foreach($key in @('Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
            foreach($child in Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue){
                try{$v=Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction Stop;if($v.PSObject.Properties.Name -contains 'DisplayName' -and $v.DisplayName -match 'Arknights.*Endfield' -and $v.PSObject.Properties.Name -contains 'InstallLocation' -and $v.InstallLocation){$directCandidates.Add([string]$v.InstallLocation)}}catch{}
            }
        }
    }
    if(-not $SkipKnownRoots){
        foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramW6432)){
            if(-not $base){continue}
            $steamCandidates.Add((Join-Path $base 'Steam'))
            foreach($rel in @('Epic Games\ArknightsEndfieldgowoU','Arknights Endfield','GRYPHLINK\games\Arknights Endfield','Hypergryph\Arknights Endfield')){$directCandidates.Add((Join-Path $base $rel))}
        }
    }
    $libraries=[Collections.Generic.List[string]]::new()
    foreach($steam in $steamCandidates | Select-Object -Unique){
        if(-not [IO.Directory]::Exists($steam)){continue};$libraries.Add([IO.Path]::GetFullPath($steam))
        $vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
        if([IO.File]::Exists($vdf)){
            try{$map=ConvertFrom-EndfieldValveKeyValues ([IO.File]::ReadAllText($vdf));if($map.ContainsKey('libraryfolders')){foreach($k in $map.libraryfolders.Keys){$v=$map.libraryfolders[$k];if($v -is [hashtable] -and $v.ContainsKey('path')){$libraries.Add([string]$v.path)}elseif($v -is [string] -and $k -match '^\d+$'){$libraries.Add($v)}}}}catch{Write-Verbose 'Skipped malformed Steam library list'}
        }
    }
    foreach($library in $libraries | Select-Object -Unique){
        $acf=Join-Path $library 'steamapps\appmanifest_4732690.acf';if(-not [IO.File]::Exists($acf)){continue}
        try{$map=ConvertFrom-EndfieldValveKeyValues ([IO.File]::ReadAllText($acf));$app=$map.AppState;if($app.appid -ne '4732690' -or -not $app.installdir){continue};$rel=[string]$app.installdir;if([IO.Path]::IsPathRooted($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)' -or $rel.Contains(':')){continue};$folder=Join-Path (Join-Path $library 'steamapps\common') $rel;Add-EndfieldCandidate $folder 'Steam' 'Steam appmanifest 4732690' $acf $library}catch{Write-Verbose 'Skipped invalid Endfield Steam manifest'}
    }
    foreach($root in $directCandidates | Select-Object -Unique){Add-EndfieldCandidate $root 'Direct' 'Direct registry/known root' '' ''}
    $explicit=@()
    if($GameData){$explicit=@(Resolve-EndfieldGameData $GameData);if($explicit.Count -ne 1){throw 'Belirtilen yolda tek bir doğrulanmış Endfield_Data bulunamadı.'};if(-not @($found | Where-Object GameData -eq $explicit[0]).Count){Add-EndfieldCandidate $GameData 'Direct' 'Explicit GameData' '' ''}}
    $result=@()
    foreach($group in $found | Group-Object { $_.GameData.ToLowerInvariant() }){
        if($explicit.Count -and $group.Group[0].GameData -ne $explicit[0]){continue}
        $strong=@($group.Group | Where-Object Platform -ne 'Direct')
        $platforms=@($strong | ForEach-Object { $_.Platform } | Select-Object -Unique)
        if($platforms.Count -gt 1){$one=$group.Group[0];$one.Platform='Ambiguous';$one.LaunchUri=$null;$one.Evidence='Multiple platform manifests identify the same GameData';$result+=$one}
        elseif($strong.Count){$result+=$strong[0]}
        else{$result+=$group.Group[0]}
    }
    return $result
}
