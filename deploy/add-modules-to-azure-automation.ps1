function zipFiles($zipFileName, $folderPath) {
   Add-Type -Assembly System.IO.Compression.FileSystem

   $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
   $includeBaseDir = $false

   if ((Test-Path -Path $zipFileName) -eq $true) {
        Remove-Item $zipFileName
   }
   [System.IO.Compression.ZipFile]::CreateFromDirectory($folderPath, $zipFileName, $compressionLevel, $includeBaseDir)
}


Write-Output "Creating distro of scripts"
#xcopy ..\src\common ..\* /Y /S

# TODO: create a zip of the modules, upload to blob storage, and then push to azure automation modules