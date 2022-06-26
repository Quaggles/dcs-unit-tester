[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter()]
    [System.IO.FileInfo]
    $Path,
    [Parameter()]
    [string]
    $EntryPath
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
    if (-not $Path) {
        throw "No path provided"
    }
    Using-Object ($zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Read)) {
        $entry = $zip.GetEntry($EntryPath);
        if ($entry) {
            $stream = $entry.Open()
            $stream = [System.IO.StreamReader]$stream
            Using-Object ($stream) {
                return $stream.ReadToEnd();
            }
        } else {
            Write-Host "No entry to read at ""$EntryPath"" in archive ""$Path"""
        }
    }
}
END {
}