# Read-only VFS extraction and work-directory staging. This script never installs
# or launches the game. Dot-source it from the manually invoked coordinator.
$script:VfsReaderDirectory = Join-Path $PSScriptRoot 'reader'
function Initialize-VfsReader {
    [CmdletBinding()] param([string]$ReaderDirectory = $script:VfsReaderDirectory)
    if ('AnimeStudio.Endfield.EndfieldVfsLoader' -as [type]) { return }
    if ($PSVersionTable.PSEdition -ne 'Core' -or [Environment]::Version.Major -lt 9) { throw 'PowerShell 7 with .NET 9 or newer is required.' }
    $sources = @(Get-ChildItem -LiteralPath $ReaderDirectory -Filter '*.cs' -File -ErrorAction Stop).FullName
    if (-not $sources.Count) { throw 'Bundled VFS reader source is missing.' }
    $references = @((Get-ChildItem -LiteralPath (Join-Path $PSHOME 'ref') -Filter '*.dll' -File).FullName) + (Join-Path $PSHOME 'Newtonsoft.Json.dll')
    Add-Type -Path $sources -ReferencedAssemblies $references -CompilerOptions '/nowarn:1701' -ErrorAction Stop
}
function Get-VfsSHA256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}
function Write-VfsJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
}
function Get-VfsTableView {
    param([Parameter(Mandatory)][string]$GameData, [string]$AssetsRoot, [string]$FallbackAssetsRoot)
    Initialize-VfsReader
    $game = [IO.Path]::GetFullPath($GameData)
    $primary = if ($AssetsRoot) { [IO.Path]::GetFullPath($AssetsRoot) } else { Join-Path $game 'Persistent' }
    $fallback = if ($FallbackAssetsRoot) { [IO.Path]::GetFullPath($FallbackAssetsRoot) } elseif ($AssetsRoot) { $null } else { Join-Path $game 'StreamingAssets' }
    $loader = [AnimeStudio.Endfield.EndfieldVfsLoader]::new($primary, $fallback)
    $type = [AnimeStudio.Endfield.EndfieldVfsBlockType]::Table
    $hash = $loader.BlockDirectoryName($type)
    $primaryMetadata = Join-Path (Join-Path (Join-Path $primary 'VFS') $hash) ($hash + '.blc')
    $fallbackMetadata = if ($fallback) { Join-Path (Join-Path (Join-Path $fallback 'VFS') $hash) ($hash + '.blc') } else { $null }
    foreach ($candidate in @($primaryMetadata, $fallbackMetadata)) {
        if (-not $candidate) { continue }
        $directory = [IO.Path]::GetDirectoryName($candidate)
        if (Test-Path -LiteralPath $directory -PathType Container) {
            $metas = @(Get-ChildItem -LiteralPath $directory -Filter '*.blc' -File)
            if ($metas.Count -ne 1 -or $metas[0].FullName -ne $candidate) { throw "Missing/ambiguous Table metadata: $directory" }
        }
    }
    $p = if (Test-Path -LiteralPath $primaryMetadata -PathType Leaf) { ([AnimeStudio.Endfield.EndfieldVfsLoader]::new($primary)).LoadBlockInfo($type) } else { $null }
    $f = if (-not $AssetsRoot -and $fallbackMetadata -and (Test-Path -LiteralPath $fallbackMetadata -PathType Leaf)) { ([AnimeStudio.Endfield.EndfieldVfsLoader]::new($fallback)).LoadBlockInfo($type) } else { $null }
    if (-not $p -and -not $f) { throw 'Table metadata is missing from both asset roots.' }
    if ($p -and $f) {
        $pp = [LocalVfsCodec]::MetadataPlain([IO.File]::ReadAllBytes($primaryMetadata))
        $fp = [LocalVfsCodec]::MetadataPlain([IO.File]::ReadAllBytes($fallbackMetadata))
        $same = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pp)) -eq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($fp))
        $pEmpty = $p.GroupFileInfoNum -eq 0 -and $p.GroupChunksLength -eq 0 -and $p.Chunks.Count -eq 0
        $fEmpty = $f.GroupFileInfoNum -eq 0 -and $f.GroupChunksLength -eq 0 -and $f.Chunks.Count -eq 0
        $replacement = $p.Version -gt $f.Version -and $p.BlockTypeValue -eq $f.BlockTypeValue -and $p.GroupConfigName -ceq $f.GroupConfigName -and $p.GroupConfigHashName -eq $f.GroupConfigHashName
        if ($same) { $state = 'Identical' }
        elseif ($pEmpty -and -not $fEmpty) { $state = 'ShadowedEmpty' }
        elseif ((-not $pEmpty -and $fEmpty) -or $replacement) { $state = 'Replaced' }
        else { throw 'Conflicting Table metadata: same/lower version with different contents. No work files were applied.' }
        $block = $p; $metadata = $primaryMetadata; $canonical = $primary
    } elseif ($p) { $state = 'PrimaryOnly'; $block = $p; $metadata = $primaryMetadata; $canonical = $primary }
    else { $state = 'FallbackOnly'; $block = $f; $metadata = $fallbackMetadata; $canonical = $fallback }
    [pscustomobject]@{ GameData=$game; PrimaryRoot=$primary; FallbackRoot=$fallback; CanonicalRoot=$canonical; MetadataPath=$metadata; HashDirectory=$hash; State=$state; Loader=$loader; Block=$block }
}
function Resolve-VfsChunk {
    param([Parameter(Mandatory)]$View, [Parameter(Mandatory)][string]$ChunkName, [switch]$IncludeGameFallbacks)
    if ($ChunkName -notmatch '^[0-9A-Fa-f]{32}\.chk$') { throw 'Invalid chunk identity filename.' }
    $roots = @($View.CanonicalRoot)
    if ($View.State -ne 'FallbackOnly' -and $View.FallbackRoot) { $roots += $View.FallbackRoot }
    if ($IncludeGameFallbacks) { $roots += (Join-Path $View.GameData 'Persistent'); $roots += (Join-Path $View.GameData 'StreamingAssets') }
    foreach ($root in @($roots | Select-Object -Unique)) {
        $candidate = Join-Path (Join-Path (Join-Path $root 'VFS') $View.HashDirectory) $ChunkName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    throw "Required chunk is unavailable: $ChunkName"
}
function Read-VfsLogicalFile {
    param([Parameter(Mandatory)]$View, [Parameter(Mandatory)]$Chunk, [Parameter(Mandatory)]$File, [switch]$IncludeGameFallbacks)
    $path = Resolve-VfsChunk -View $View -ChunkName $Chunk.FileName -IncludeGameFallbacks:$IncludeGameFallbacks
    $memory = [IO.MemoryStream]::new()
    try {
        [void]$View.Loader.ExtractFileFromPath($path, $Chunk, $File, $memory, $true)
        return ,$memory.ToArray()
    } finally { $memory.Dispose() }
}
function Get-VfsContext {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$GameData, [string]$AssetsRoot, [string]$FallbackAssetsRoot)
    $view = Get-VfsTableView -GameData $GameData -AssetsRoot $AssetsRoot -FallbackAssetsRoot $FallbackAssetsRoot
    $pairs = @(foreach ($chunk in $view.Block.Chunks) { foreach ($file in $chunk.Files) { if ($file.FileName -ceq 'Data/TableCfg/I18nTextTable_EN.bytes') { [pscustomobject]@{Chunk=$chunk; File=$file} } } })
    if ($pairs.Count -ne 1) { throw 'English logical table is missing or ambiguous.' }
    $pair = $pairs[0]
    $chunkPath = Resolve-VfsChunk -View $view -ChunkName $pair.Chunk.FileName -IncludeGameFallbacks:([bool]$AssetsRoot)
    [pscustomobject]@{
        Version=$view.Block.Version; CodeVersion=$view.Block.CodeVersion; Chunk=$pair.Chunk.FileName; FileName=$pair.File.FileName
        IvSeed=$pair.File.IvSeed.ToString(); Encrypted=$pair.File.UseEncrypt; Offset=$pair.File.Offset; Length=$pair.File.Length; ChunkLength=$pair.Chunk.Length
        MetadataPath=$view.MetadataPath; ChunkPath=$chunkPath; Metadata=$view.MetadataPath; Source=$chunkPath
        GameMetadataPath=$view.MetadataPath; GameChunkPath=$chunkPath; GameData=$view.GameData
        AssetsRoot=$view.CanonicalRoot; PrimaryAssetsRoot=$view.PrimaryRoot; FallbackAssetsRoot=$view.FallbackRoot
        HashDirectory=$view.HashDirectory; CanonicalState=$view.State
        CurrentChunkSHA256=(Get-VfsSHA256 $chunkPath); CurrentMetaSHA256=(Get-VfsSHA256 $view.MetadataPath)
    }
}
function Export-VfsSnapshot {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$GameData, [Parameter(Mandatory)][string]$Destination, [Parameter(Mandatory)]$Context)
    Initialize-VfsReader
    $dest = [IO.Path]::GetFullPath($Destination)
    $game = [IO.Path]::GetFullPath($GameData)
    if ($dest -eq $game -or $dest.StartsWith($game + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Snapshot must be outside the game tree.' }
    if ((Test-Path -LiteralPath $dest) -and @(Get-ChildItem -LiteralPath $dest -Force).Count) { throw 'Snapshot destination must be new or empty.' }
    if ((Get-VfsSHA256 $Context.MetadataPath) -ne $Context.CurrentMetaSHA256 -or (Get-VfsSHA256 $Context.ChunkPath) -ne $Context.CurrentChunkSHA256) { throw 'Source files changed after discovery.' }
    $view = Get-VfsTableView -GameData $game -AssetsRoot $Context.PrimaryAssetsRoot -FallbackAssetsRoot $Context.FallbackAssetsRoot
    if ($view.Block.Version -ne $Context.Version -or $view.MetadataPath -ne $Context.MetadataPath) { throw 'Metadata changed after discovery.' }
    $tableDir = Join-Path $dest 'tables'; $original = Join-Path $dest 'original'
    $vfsDir = Join-Path (Join-Path $original 'VFS') $view.HashDirectory
    [void][IO.Directory]::CreateDirectory($vfsDir); [void][IO.Directory]::CreateDirectory($tableDir)
    $metaCopy = Join-Path $vfsDir ($view.HashDirectory + '.blc'); $chunkCopy = Join-Path $vfsDir $Context.Chunk
    Copy-Item -LiteralPath $Context.MetadataPath -Destination $metaCopy
    Copy-Item -LiteralPath $Context.ChunkPath -Destination $chunkCopy
    if ((Get-VfsSHA256 $metaCopy) -ne $Context.CurrentMetaSHA256 -or (Get-VfsSHA256 $chunkCopy) -ne $Context.CurrentChunkSHA256) { throw 'Snapshot copy hash mismatch.' }
    $snapshotContext = $Context.PSObject.Copy()
    $snapshotContext.MetadataPath=$metaCopy; $snapshotContext.ChunkPath=$chunkCopy; $snapshotContext.Metadata=$metaCopy; $snapshotContext.Source=$chunkCopy
    $snapshotContext.PrimaryAssetsRoot=$original; $snapshotContext.AssetsRoot=$original; $snapshotContext.FallbackAssetsRoot=$null; $snapshotContext.CanonicalState='PristineSnapshot'
    $englishBytes=$null; $englishParsed=$null; $exports=[Collections.Generic.List[object]]::new()
    foreach ($chunk in $view.Block.Chunks) { foreach ($file in $chunk.Files) {
        if ($file.FileName -match '/I18nTextTable_' -and $file.FileName -cne $Context.FileName) { continue }
        try {
            $data = Read-VfsLogicalFile -View $view -Chunk $chunk -File $file -IncludeGameFallbacks
            $parsed = [AnimeStudio.Endfield.EndfieldSparkBuffer]::ParseBytes($data)
            if ($parsed.Name -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Invalid parsed table filename.' }
            if ($file.FileName -ceq $Context.FileName) {
                if ($parsed.Name -cne 'I18nTextTable_EN') { throw 'Unexpected English table root.' }
                $englishBytes=$data; $englishParsed=$parsed
            } else {
                $path=Join-Path $tableDir ($parsed.Name + '.json')
                if (Test-Path -LiteralPath $path) { throw 'Duplicate parsed table root.' }
                [IO.File]::WriteAllText($path, $parsed.Data.ToString(), [Text.UTF8Encoding]::new($false))
            }
            $exports.Add([pscustomobject]@{Source=$file.FileName; Table=$parsed.Name; Status='OK'; Chunk=$chunk.FileName; Offset=$file.Offset; Length=$file.Length})
        } catch {
            if ($file.FileName -ceq $Context.FileName) { throw }
            $exports.Add([pscustomobject]@{Source=$file.FileName; Table=[IO.Path]::GetFileNameWithoutExtension($file.FileName); Status='ERROR'; Error=$_.Exception.Message})
        }
    } }
    if ($null -eq $englishBytes -or $null -eq $englishParsed) { throw 'English table was not exported.' }
    [IO.File]::WriteAllBytes((Join-Path $dest 'original.bytes'), $englishBytes)
    [IO.File]::WriteAllText((Join-Path $dest 'source.json'), $englishParsed.Data.ToString(), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllBytes((Join-Path $dest 'metadata.original.plain'), [LocalVfsCodec]::MetadataPlain([IO.File]::ReadAllBytes($metaCopy)))
    Write-VfsJson -Path (Join-Path $dest 'table_export.json') -Value $exports
    Write-VfsJson -Path (Join-Path $dest 'context.json') -Value $snapshotContext
    if ((Get-VfsSHA256 $Context.MetadataPath) -ne $Context.CurrentMetaSHA256 -or (Get-VfsSHA256 $Context.ChunkPath) -ne $Context.CurrentChunkSHA256) { throw 'Game files changed during snapshot export.' }
    return $snapshotContext
}
function Invoke-VfsEncrypt {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Snapshot, [Parameter(Mandatory)][string]$BuildOutput)
    Initialize-VfsReader
    $context = Get-Content -LiteralPath (Join-Path $Snapshot 'context.json') -Raw | ConvertFrom-Json
    $payload = [IO.File]::ReadAllBytes((Join-Path $BuildOutput 'translated.bytes'))
    $encrypted = if ($context.Encrypted) { [LocalVfsCodec]::FileCrypt($payload, [long]$context.IvSeed) } else { $payload }
    $path=Join-Path $BuildOutput 'translated.encrypted.bin'
    if (Test-Path -LiteralPath $path) { throw 'Encrypted output already exists.' }
    [IO.File]::WriteAllBytes($path, $encrypted)
    return $path
}
function Complete-VfsStage {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Snapshot, [Parameter(Mandatory)][string]$BuildOutput)
    Initialize-VfsReader
    $context = Get-Content -LiteralPath (Join-Path $Snapshot 'context.json') -Raw | ConvertFrom-Json
    $stage=Join-Path $BuildOutput 'stage'; $dir=Join-Path (Join-Path $stage 'VFS') $context.HashDirectory
    if (Test-Path -LiteralPath $stage) { throw 'Stage output already exists.' }
    [void][IO.Directory]::CreateDirectory($dir)
    Copy-Item -LiteralPath (Join-Path $BuildOutput 'translated.chk') -Destination (Join-Path $dir $context.Chunk)
    $plain=[IO.File]::ReadAllBytes((Join-Path $BuildOutput 'metadata.translated.plain'))
    $packed=[LocalVfsCodec]::MetadataPack([IO.File]::ReadAllBytes($context.MetadataPath), $plain)
    [IO.File]::WriteAllBytes((Join-Path $dir ($context.HashDirectory + '.blc')), $packed)
    return (Test-VfsStage -Snapshot $Snapshot -BuildOutput $BuildOutput)
}
function Test-VfsStage {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Snapshot, [Parameter(Mandatory)][string]$BuildOutput, [string]$GameData)
    Initialize-VfsReader
    $context = Get-Content -LiteralPath (Join-Path $Snapshot 'context.json') -Raw | ConvertFrom-Json
    $stage=Join-Path $BuildOutput 'stage'
    if ($GameData) {
        # Installation verification uses the exact two files whose prepared
        # SHA256 values were checked. This also supports equal-version fallback
        # roots: the intentional patched primary differs from pristine fallback.
        $expectedDir=Join-Path (Join-Path (Join-Path $stage 'VFS') $context.HashDirectory) ''
        $expectedChunk=Join-Path $expectedDir $context.Chunk
        $expectedMeta=Join-Path $expectedDir ($context.HashDirectory+'.blc')
        $gameRoot=[IO.Path]::GetFullPath($GameData).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
        foreach($target in @($context.GameMetadataPath,$context.GameChunkPath)){
            if(-not [IO.Path]::GetFullPath($target).StartsWith($gameRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Installed verification target outside game data.'}
        }
        if((Get-VfsSHA256 $context.GameMetadataPath)-ne (Get-VfsSHA256 $expectedMeta) -or (Get-VfsSHA256 $context.GameChunkPath)-ne (Get-VfsSHA256 $expectedChunk)){throw 'Installed files differ from prepared exact targets.'}
        $assets=[IO.Directory]::GetParent([IO.Directory]::GetParent([IO.Path]::GetDirectoryName($context.GameMetadataPath)).FullName).FullName
        $loader=[AnimeStudio.Endfield.EndfieldVfsLoader]::new($assets)
        $block=$loader.LoadBlockInfo([AnimeStudio.Endfield.EndfieldVfsBlockType]::Table)
    } else {
        $loader=[AnimeStudio.Endfield.EndfieldVfsLoader]::new($stage)
        $block=$loader.LoadBlockInfo([AnimeStudio.Endfield.EndfieldVfsBlockType]::Table)
    }
    if ($block.Version -ne $context.Version) { throw 'Verified build differs from prepared snapshot.' }
    $pairs=@(foreach($chunk in $block.Chunks){foreach($file in $chunk.Files){if($file.FileName -ceq $context.FileName){[pscustomobject]@{Chunk=$chunk;File=$file}}}})
    if ($pairs.Count -ne 1 -or $pairs[0].Chunk.FileName -ne $context.Chunk) { throw 'Verified logical location is ambiguous or changed.' }
    $pair=$pairs[0]
    if ($GameData) {
        $memory=[IO.MemoryStream]::new();try{[void]$loader.ExtractFileFromPath($context.GameChunkPath,$pair.Chunk,$pair.File,$memory,$true);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
    }
    else { $bytes=$loader.ExtractFileToBytes([AnimeStudio.Endfield.EndfieldVfsBlockType]::Table, $pair.Chunk, $pair.File, $true) }
    $payload=Join-Path $BuildOutput 'translated.bytes'
    if ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -ne (Get-VfsSHA256 $payload)) { throw 'Verified payload hash mismatch.' }
    $parsed=[AnimeStudio.Endfield.EndfieldSparkBuffer]::ParseBytes($bytes)
    $source=[Newtonsoft.Json.Linq.JObject]::Parse([IO.File]::ReadAllText((Join-Path $Snapshot 'source.json')))
    $selected=[Newtonsoft.Json.Linq.JObject]::Parse([IO.File]::ReadAllText((Join-Path $BuildOutput 'selected_translations.json')))
    foreach($property in $selected.Properties()) { $source[$property.Name]=[Newtonsoft.Json.Linq.JValue]::new([string]$property.Value) }
    if (-not [Newtonsoft.Json.Linq.JToken]::DeepEquals($source,$parsed.Data)) { throw 'Verified values do not exactly match source plus selected translations.' }
    $stageChunk=Join-Path (Join-Path (Join-Path $stage 'VFS') $context.HashDirectory) $context.Chunk
    $stageMetadata=Join-Path ([IO.Path]::GetDirectoryName($stageChunk)) ($context.HashDirectory + '.blc')
    if ($GameData) {
        $chunkPath=$context.GameChunkPath
        $metaPath=$context.GameMetadataPath
        if ((Get-VfsSHA256 $chunkPath) -ne (Get-VfsSHA256 $stageChunk) -or (Get-VfsSHA256 $metaPath) -ne (Get-VfsSHA256 $stageMetadata)) { throw 'Installed physical files differ from the verified stage.' }
        $status='VERIFIED_INSTALLED'; $reportName='installed_verification.json'
    } else { $chunkPath=$stageChunk; $metaPath=$stageMetadata; $status='VERIFIED_NOT_INSTALLED'; $reportName='stage_report.json' }
    $report=[pscustomobject]@{Status=$status;Version=$block.Version;Translations=@($selected.Properties()).Count;ChunkPath=$chunkPath;MetadataPath=$metaPath;ChunkSHA256=(Get-VfsSHA256 $chunkPath);MetadataSHA256=(Get-VfsSHA256 $metaPath);PayloadSHA256=(Get-VfsSHA256 $payload);IndependentParse=$true;CRCandMD5=$true}
    Write-VfsJson -Path (Join-Path $BuildOutput $reportName) -Value $report
    return $report
}
