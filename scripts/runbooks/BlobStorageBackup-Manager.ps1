<#
   .DESCRIPTION
      Runbook that performs management of the backups
   .NOTES
      we're treating every source backup the same. A backup container equals the source storage account
      Every backed up storage account is being treated the same. If there needs to be different rules per account,
      then add $SourceAccountName as a parameter to the runbook, and you'll have to do one for each account
#>
param
(
   [Parameter (Mandatory = $false)]
   [String] $HourlyRetention = 3,
   [Parameter (Mandatory = $false)]
   [String] $DailyRetention = 3,
   [Parameter (Mandatory = $false)]
   [String] $WeeklyRetention = 3,
   [Parameter (Mandatory = $false)]
   [String] $MonthlyRetention = 3,
   [Parameter (Mandatory = $false)]
   [String] $YearlyRetention = 2
)

# ========================================================================================
# Imports
# ========================================================================================

if ($PSPrivateMetadata.JobId -ne $null) {
   $verbose = $false

   Import-Module -Name ..\modules\BlobStorageBackup.Common.psm1 -Force -Verbose:$verbose -WarningAction SilentlyContinue
   Import-Module -Name ..\modules\BlobStorageBackup.Backup.psm1 -Force -Verbose:$verbose -WarningAction SilentlyContinue
}

# ========================================================================================
# Variables
# ========================================================================================

$BackupStorageAccountName = ""
$BackupResourceGroupName = ""

if (Test-IsRunningInAzureAutomation) {
   $BackupStorageAccountName = Get-AutomationVariable -Name "BackupStorageAccountName"
   $BackupResourceGroupName = Get-AutomationVariable -Name "BackupResourceGroupName"
}

$BackupInterval = (New-Object -TypeName PSObject -Prop ([ordered]@{ 
      Types = @{ Hourly = "hourly"; Daily = "daily"; Weekly = "weekly"; Monthly = "monthly"; Yearly = "yearly" };
      Limits = @{ Hourly = $HourlyRetention; Daily = $DailyRetention; Weekly = $WeeklyRetention; Monthly = $MonthlyRetention; Yearly = $YearlyRetention };
   }))

$BackupTypes = @("account", "container")

# ========================================================================================
# Functions
# ========================================================================================
function establishSecurityContext() {
   $useInteractiveLogin = (Test-IsRunningInAzureAutomation) -eq $false
   $azureAutomationConnectionName = "AzureRunAsConnection"
   Add-AzureSecurityContext -UseInteractiveLogin $useInteractiveLogin -AzureAutomationConnectionName $azureAutomationConnectionName
}

function getBackupContainers() {
   $backupStorageContext = Get-StorageContext -StorageAccountName $BackupStorageAccountName -ResourceGroupName $BackupResourceGroupName
   $backupContainers = $backupStorageContext | Get-AzureStorageContainer 

   return $backupContainers
}
function getBackupDates($backups) {
   $backupDates = $backups | select -ExpandProperty Prefix
   $backupDates = $backupDates | % { $_.TrimEnd("/") } 
   $backupDates = $backupDates | % { $_.Substring($_.LastIndexOf("/") + 1) }
   $backupDates = $backupDates | % { [datetime]$_.Replace("_", " ") }
   $backupDates = @($backupDates | sort)

   return ([System.Collections.ArrayList](,$backupDates))
}

function deleteBlobs($containerName, $prefix) {
   $backupStorageContext = Get-StorageContext -StorageAccountName $BackupStorageAccountName -ResourceGroupName $BackupResourceGroupName

   # handle very large accounts by limiting the amount of blobs we retrieve at one time
   $maxCount = 10000
   $totalBlobs = 0
   $continuationToken = $null

   do
   {
      $blobs = $backupStorageContext | Get-AzureStorageBlob -Container $containerName -Prefix $prefix -MaxCount $maxCount -ContinuationToken $continuationToken
      $totalBlobs += $blobs.Count

      if($blobs.Length -le 0) { 
         break;
      }

      foreach($blob in $blobs) {
         $blob | Remove-AzureStorageBlob
      }

      $continuationToken = $blobs[$blobs.Count -1].ContinuationToken;
   }
   while ($continuationToken -ne $null)
}

function enforceBackupLimit($container, $rootBackupFolderPath, $backupLimit) {
   $backups = ($container.CloudBlobContainer.GetDirectoryReference($rootBackupFolderPath)).ListBlobs()
   $backupDates = getBackupDates -backups $backups

   $currentNumberOfBackups = $backupDates.Count
   "  Backup Count : $currentNumberOfBackups"

   if ($currentNumberOfBackups -eq 0) {
      continue;
   }

   if ($currentNumberOfBackups -gt $backupLimit) {
      #start removing the oldest up to the difference
      $backupCountDifference = $currentNumberOfBackups - $backupLimit
      
      "    Backups to Remove: $backupCountDifference"

      for ($i=0; $i -lt $backupCountDifference; $i++) {
         $backupFolder = $backupDates[$i].ToString("yyyy-MM-dd_HH:mm:ss")
         $backupFolderPath = "$rootBackupFolderPath/$backupFolder"

         "    Removing $backupFolderPath"

         deleteBlobs -containerName $container.Name -prefix $backupFolderPath
      }
   }
}

function limitBackups() {
   $backupContainers = getBackupContainers

   "`nSource Accounts`n-------------------------"
   $backupContainers | select -ExpandProperty Name
   ""

   foreach ($container in $backupContainers) {
      "Sweeping Backups in [$($container.Name)]`n"

      foreach ($backupType in $BackupTypes) {
         "`n$backupType`n---------"

         foreach ($backupIntervalType in $BackupInterval.Types.GetEnumerator()) {
            $backupIntervalTypeName = $backupIntervalType.Value
            $rootBackupFolderPath = "$backupType/$backupIntervalTypeName"
            $backupLimit = $BackupInterval.Limits[$backupIntervalType.Key]
            
            "Limit $backupLImit backups in $backupIntervalTypeName"

            enforceBackupLimit -container $container -rootBackupFolderPath $rootBackupFolderPath -backupLimit $backupLimit
         }  
      }
   }
}

# ========================================================================================
# Main
# ========================================================================================

establishSecurityContext
limitBackups