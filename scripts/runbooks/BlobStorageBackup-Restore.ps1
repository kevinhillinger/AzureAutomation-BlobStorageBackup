<#
   .DESCRIPTION
        Runbook that restores a storage account (full) or a storage account's container
   .NOTES
        the location of the backup to restore, e.g. "account/daily/2017-01-17_13:30:00"
#>
param
(
   [Parameter (Mandatory = $true)]
   [String] $SourceAccountName,
   [Parameter (Mandatory = $true)]
   [String] $SourceResourceGroupName,
   [Parameter (Mandatory = $false)]
   [String] $SourceContainerName,
   [Parameter (Mandatory = $true)]
   [String] $RestorePoint
)

# ========================================================================================
# Imports
# ========================================================================================

if ($PSPrivateMetadata.JobId -eq $null) {
   $verbose = $false

   Import-Module -Name ..\modules\BlobStorageBackup.Common.psm1 -Force -Verbose:$verbose -WarningAction SilentlyContinue
   Import-Module -Name ..\modules\BlobStorageBackup.Backup.psm1 -Force -Verbose:$verbose -WarningAction SilentlyContinue
}

# ========================================================================================
# Variables
# ========================================================================================

$BackupStorageAccountName = ""
$BackupResourceGroupName = ""
$BackupType = if ([string]::IsNullOrEmpty($SourceContainerName)) { "account" } else { "container" }

if (Test-IsRunningInAzureAutomation) {
   $BackupStorageAccountName = Get-AutomationVariable -Name "BackupStorageAccountName"
   $BackupResourceGroupName = Get-AutomationVariable -Name "BackupResourceGroupName"
}

# ========================================================================================
# Functions
# ========================================================================================

# Private 
# --------------

function establishSecurityContext() {
   $useInteractiveLogin = (Test-IsRunningInAzureAutomation) -eq $false
   $azureAutomationConnectionName = "AzureRunAsConnection"
   Add-AzureSecurityContext -UseInteractiveLogin $useInteractiveLogin -AzureAutomationConnectionName $azureAutomationConnectionName
}

function getBackupStorageContext() {
   $context = Get-StorageContext -StorageAccountName $BackupStorageAccountName -ResourceGroupName $BackupResourceGroupName
   return $context
}

function getSourceStorageContext() {
   $context = Get-StorageContext -StorageAccountName $SourceAccountName -ResourceGroupName $SourceResourceGroupName
   return $context
}

function getContainer($context, $name) {
   return ($context | Get-AzureStorageContainer -Name $name -ErrorAction SilentlyContinue)
}

function getSourceContainerNames() {
   $backupStorageContext = getBackupStorageContext 
   $sourceContainerNames = Get-BackupSourceContainerNames -BackupStorageContext $backupStorageContext -SourceAccountName $SourceAccountName -RestorePoint $RestorePoint

   return $sourceContainerNames
}

function ensureSourceContainers($sourceContainerNames) {
   $sourceStorageContext = getSourceStorageContext

   foreach($name in $sourceContainerNames) {
      $command = New-EnsureStorageContainerCommand -StorageContext $sourceStorageContext -ContainerName $name
      Invoke-EnsureStorageContainer -Command $command
   }
}

function restoreBlobsToSourceContainers($sourceContainerNames) {
   $backupStorageContext = getBackupStorageContext 
   $sourceStorageContext = getSourceStorageContext

   # for each container, copy the blobs back to the destination container
   foreach ($name in $sourceContainerNames) {
      "`nRestoring blobs to $name"

      $command = New-RestoreBlobsToSourceContainerCommand
      $command.BackupStorageContext = $backupStorageContext
      $command.SourceStorageContext = $sourceStorageContext
      $command.RestorePoint = $RestorePoint
      $command.SourceContainerName = $name

      Invoke-RestoreBlobsToSourceContainer -Command $command
   }
}

function printConfig() {
   "Automation Env `t`t : $(Test-IsRunningInAzureAutomation)"
   "Backup Type `t`t : $BackupType"
   "Backup Account `t`t : $BackupResourceGroupName/$BackupStorageAccountName"
   "Backup Target  `t`t : $RestorePoint `n"
}

function restoreStorageAccount() {
   "Full restore of $SourceAccountName...`n"
   "Identified containers`n----------------------"
   $sourceContainerNames = getSourceContainerNames
   $sourceContainerNames

   "`nEnsuring containers exist in $SourceAccountName..."
   ensureSourceContainers -sourceContainerNames $sourceContainerNames

   "`nRestoring blobs..."
   restoreBlobsToSourceContainers -sourceContainerNames $sourceContainerNames
}

# ========================================================================================
# Main
# ========================================================================================

printConfig
establishSecurityContext

if ($BackupType -eq "account") {
   restoreStorageAccount
} else {
   "Container restore [not implemented]"
}

"`nRestore Complete.`n"