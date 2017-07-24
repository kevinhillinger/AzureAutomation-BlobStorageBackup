
#Set-Variable -Name "_BackupContext" -Value (New-Object -TypeName PSObject -Prop (@{ 'BlobTotal'= $null; })) -Option None -Visibility Public -Scope Global -Force


<#
.SYNOPSIS
Gets the container names of the backup source storage account

.DESCRIPTION
Gets the container names that exist in the backup account that represent the containers from the original
blob storage account (the source account).

.PARAMETER BackupStorageContext
The backup storage account context

.PARAMETER RestorePoint
The restore point (located in the backup storage account) to use to get the list of container names 

.PARAMETER SourceAccountName
The backup container name (which is the source storage account name)
#>
function Get-BackupSourceContainerNames($BackupStorageContext, $RestorePoint, $SourceAccountName) {

   # backup container is the name of the source storage account
   $backupContainer = ($BackupStorageContext | Get-AzureStorageContainer -Name $SourceAccountName)
   $backupFolder = $backupContainer.CloudBlobContainer.GetDirectoryReference($RestorePoint)

   # rebuild source container list from sub folders
   $subFolders = $backupFolder.ListBlobs() 
   $subFolders = $subFolders | select -ExpandProperty Prefix
   $subFolders = $subFolders | % { $_.TrimEnd("/") } 

   $sourceContainerNames = $subFolders | % { $_.Substring($_.LastIndexOf("/") + 1) }

   return $sourceContainerNames
}

function newRestoreBlobsCommand() {
   return (New-Object -TypeName PSObject -Prop ([ordered]@{ 
      SrcContext = $null;
      SrcContainer = "";
      DestContext = $null;
      DestContainer = "";
      BlobPrefix = "";
      Blobs = $null;
   }))
}

function restoreBlobs($command) {
   $prefix = $command.BlobPrefix

   foreach ($blob in $command.Blobs) {
      $originalBlobName = $blob.Name.Replace("$prefix/", "")
      "[$($blob.Name)] => [$originalBlobName]"

      Start-AzureStorageBlobCopy -Context $command.SrcContext -SrcContainer $command.SrcContainer `
         -SrcBlob $blob.Name -DestContext $command.DestContext -DestContainer $command.DestContainer -DestBlob $originalBlobName -Force:$true | Out-Null
   }
}

function New-RestoreBlobsToSourceContainerCommand() {
   return (New-Object -TypeName PSObject -Prop ([ordered]@{ 
      BackupStorageContext = $null;
      SourceStorageContext = $null;
      RestorePoint = "";
      SourceContainerName = "";
   }))
}

function Invoke-RestoreBlobsToSourceContainer($Command) {
   $prefix = "$($Command.RestorePoint)/$($Command.SourceContainerName)"
   $srcContext = $Command.BackupStorageContext
   $destContext = $Command.SourceStorageContext #the backup source storage account is the destination of the restore
   $srcContainerName = $Command.SourceStorageContext.StorageAccountName
   $destContainer = $Command.SourceContainerName

   # handle very large accounts by limiting the amount of blobs we retrieve at one time
   $maxCount = 10000
   $totalBlobs = 0
   $continuationToken = $null

   do
   {
      $blobs = $srcContext | Get-AzureStorageBlob -Container $srcContainerName -Prefix $prefix -MaxCount $maxCount  -ContinuationToken $continuationToken
      $totalBlobs += $blobs.Count

      if($blobs.Length -le 0) { 
         break;
      }

      $command = newRestoreBlobsCommand
      $command.SrcContext = $srcContext 
      $command.SrcContainer = $srcContainerName
      $command.DestContext = $destContext
      $command.DestContainer = $destContainer
      $command.BlobPrefix = $prefix
      $command.Blobs = $blobs

      restoreBlobs -command $command

      $continuationToken = $blobs[$blobs.Count -1].ContinuationToken;
   }
   while ($continuationToken -ne $null)

}

function New-StorageContainerBackupCommand() {
   return (New-Object -TypeName PSObject -Prop ([ordered]@{ 
      SrcContext = $null;
      SrcContainer = $null;
      DestContext = $null;
      DestPrefix = ""; 
      EnsureDestContainer = $true;
   }))
}

function Invoke-StorageContainerBackup($Command) {
   $srcContext = $Command.SrcContext
   $destContainer = $Command.SrcContext.StorageAccountName

   if ($Command.EnsureDestContainer -eq $true) {
      $cmd = New-EnsureStorageContainerCommand -StorageContext $Command.DestContext -ContainerName $destContainer 
      Invoke-EnsureStorageContainer -Command $cmd
   }

   # handle very large accounts by limiting the amount of blobs we retrieve at one time
   $maxCount = 10000
   $totalBlobs = 0
   $continuationToken = $null

   do
   {
      $blobs = $srcContext | Get-AzureStorageBlob -Container $Command.SrcContainer -MaxCount $maxCount -ContinuationToken $continuationToken | Where-Object {$_.ICloudBlob.IsSnapshot -ne $true}
      $totalBlobs += $blobs.Count

      "`n$($Command.SrcContainer) ($($blobs.Count) blobs)."

      if($blobs.Length -le 0) { 
         break;
      }

      foreach ($blob in $blobs)  {
         $destBlob = "$($Command.DestPrefix)/$($Command.SrcContainer)/$($blob.Name)"

         Start-AzureStorageBlobCopy -Context $srcContext -SrcContainer $Command.SrcContainer -SrcBlob $blob.Name `
            -DestBlob $destBlob -DestContainer $destContainer -DestContext $Command.DestContext | Out-Null
         
         "    [$($blob.Name)] => [$destBlob]"
      } 

      $continuationToken = $blobs[$blobs.Count -1].ContinuationToken;
      $totalBlobs += $blobs.Count
   }
   while ($continuationToken -ne $null)
}

function New-StorageAccountBackupCommand() {
   return (New-Object -TypeName PSObject -Prop ([ordered]@{ 
      SrcContext = $null;
      DestContext = $null;
      DestPrefix = ""; # the path that will be prepended to each blob from the src container
   }))
}

<#
.SYNOPSIS
performs a bulk blob backup of a Source storage account, and backups them up to a single destination Storage Account Container with an optional prefix

.EXAMPLE
   $command = New-StorageAccountBackupCommand
   $command.SrcContext = $sourceAccountContext
   $command.DestContext = $backupAccountContext
   $command.DestPrefix = "account/hourly/2017-07-21_10:00:00"

   Invoke-StorageAccountBackup -Command $command
#>
function Invoke-StorageAccountBackup($Command) {
   $srcContainers = $Command.SrcContext | Get-AzureStorageContainer
   $destContainer = $Command.SrcContext.StorageAccountName

   "Containers`n------------"
   ($srcContainers | select -ExpandProperty Name)
   "`n"

   $cmd = New-EnsureStorageContainerCommand -StorageContext $Command.DestContext -ContainerName $destContainer 
   Invoke-EnsureStorageContainer -Command $cmd

   "`nBacking up containers..."

   foreach ($srcContainer in $srcContainers) {
      $cmd = New-StorageContainerBackupCommand
      $cmd.SrcContext = $Command.SrcContext
      $cmd.SrcContainer = $srcContainer.Name
      $cmd.DestContext = $Command.DestContext
      $cmd.DestPrefix = $Command.DestPrefix
      $cmd.EnsureDestContainer = $false

      Invoke-StorageContainerBackup -Command $cmd
   }
}

Export-ModuleMember -Function Get-BackupSourceContainerNames
Export-ModuleMember -Function New-RestoreBlobsToSourceContainerCommand
Export-ModuleMember -Function Invoke-RestoreBlobsToSourceContainer
Export-ModuleMember -Function New-StorageAccountBackupCommand
Export-ModuleMember -Function Invoke-StorageAccountBackup
Export-ModuleMember -Function New-StorageContainerBackupCommand
Export-ModuleMember -Function Invoke-StorageContainerBackup