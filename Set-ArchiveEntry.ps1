[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [System.IO.FileInfo]
    $Archive,
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]
    $SourceFile,
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
    $newContent = $null
    if ($CheckContent) {
        $newContentReader = [System.IO.StreamReader]::new($SourceFile.FullName)
        $newContent = Using-Object ($newContentReader) {
            return $newContentReader.ReadToEnd();
        }
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
                if ($null -eq $newContent) {                    
                    $newContentReader = [System.IO.StreamReader]::new($SourceFile.FullName)
                    $newContent = Using-Object ($newContentReader) {
                        return $newContentReader.ReadToEnd();
                    }
                }
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