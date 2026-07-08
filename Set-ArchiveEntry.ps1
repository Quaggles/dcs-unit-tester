[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [System.IO.FileInfo]
    $Archive,
    [Parameter()]
    [System.IO.FileInfo]
    $SourceFile,
    [Parameter()]
    [string]
    $Content,
    [Parameter(Mandatory = $true)]
    [string]
    $Destination,
    [Parameter()]
    [switch]
    $CheckContent
)
BEGIN {
    function Using-Object {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [AllowEmptyCollection()]
            [AllowNull()]
            [Object]
            $InputObject,

            [Parameter(Mandatory = $true)]
            [scriptblock]
            $ScriptBlock
        )

        try
        {
            . $ScriptBlock
        }
        finally
        {
            if ($null -ne $InputObject -and $InputObject -is [System.IDisposable])
            {
                $InputObject.Dispose()
            }
        }
    }
}
PROCESS {
    $relativeArchivePath = (Get-Item $Archive).Name
    # Checking $PSBoundParameters allows empty strings to be passed to Content
    if (-not $PSBoundParameters.ContainsKey('Content') -and -not $SourceFile){
        throw "Either -Content or -SourceFile must be passed"
    } elseif ($PSBoundParameters.ContainsKey('Content')){
        $newContent = $Content
    } elseif ($SourceFile) {
        $newContentReader = [System.IO.StreamReader]::new($SourceFile.FullName)
        $newContent = Using-Object ($newContentReader) {
            return $newContentReader.ReadToEnd();
        }
    }
    if ($CheckContent) {
        $oldContent = .$PSScriptRoot/Get-ArchiveEntry.ps1 -Path $Archive -EntryPath $Destination
        if ($null -eq $oldContent -or [string]::Equals($newContent, $oldContent)) {
            Write-Host """$relativeArchivePath"" => ""$Destination"" - Entry matched content, skipping..."
            return
        }  
    }
    Using-Object ($zip = [System.IO.Compression.ZipFile]::Open($Archive, [System.IO.Compression.ZipArchiveMode]::Update)) {
        $entry = $zip.GetEntry($Destination)
        if ($entry) {
            if ($PSCmdlet.ShouldProcess($Archive)) {
                $entry.Delete();
                $entry = $zip.CreateEntry($Destination);
                # Zip Epoch is 1980 vs Unix 1970
                $entry.LastWriteTime = ([System.DateTimeOffset]::UnixEpoch).AddYears(10)
                $stream = $entry.Open()
                $stream = [System.IO.StreamWriter]$stream
                Using-Object ($stream) {
                    $stream.Write($newContent)
                }
            }
            Write-Host """$relativeArchivePath"" => ""$Destination"" - Replaced entry in archive"
        } else {
            Write-Host """$relativeArchivePath"" => ""$Destination"" - No existing entry to replace in archive"
        }
    }
}
END {
}