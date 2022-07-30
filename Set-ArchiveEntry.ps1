[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(ValueFromPipeline = $true)]
    [System.IO.FileInfo]
    $Archive,
    [Parameter()]
    [System.IO.FileInfo]
    $SourceFile,
    [Parameter()]
    [string]
    $Destination = "l10n/DEFAULT/OnMissionEnd.lua"
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
    Using-Object ($zip = [System.IO.Compression.ZipFile]::Open($Archive, [System.IO.Compression.ZipArchiveMode]::Update)) {
        $entry = $zip.GetEntry($Destination)
        $relativeArchivePath = $([Path]::GetRelativePath($pwd, $Archive))
        if ($entry) {
            if ($PSCmdlet.ShouldProcess($Archive)) {
                $entry.Delete();
                $entry = $zip.CreateEntry($Destination);
                # Zip Epoch is 1980 vs Unix 1970
                $entry.LastWriteTime = ([System.DateTimeOffset]::UnixEpoch).AddYears(10)
                $stream = $entry.Open()
                $stream = [System.IO.StreamWriter]$stream
                Using-Object ($stream) {
                    $stream.Write([System.IO.File]::ReadAllText($SourceFile))
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