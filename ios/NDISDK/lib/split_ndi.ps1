$ErrorActionPreference = "Stop"
$inputFile = "f:\iphone\ndi_player_app\ios\NDISDK\lib\libndi_ios.a"
$bufferSize = 49 * 1024 * 1024 # 49MB chunks
$buffer = New-Object byte[] $bufferSize

Try {
    $inStream = [System.IO.File]::OpenRead($inputFile)
    $part = 1
    
    while (($bytesRead = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $outFile = "$inputFile.part$([string]$part.PadLeft(3, '0'))"
        Write-Host "Writing $outFile"
        $outStream = [System.IO.File]::Create($outFile)
        $outStream.Write($buffer, 0, $bytesRead)
        $outStream.Close()
        $part++
    }
    $inStream.Close()
    Write-Host "Splitting completed successfully!"
} Catch {
    Write-Host "Error: $_"
}
