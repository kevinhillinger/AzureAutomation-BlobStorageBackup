<#
    .DESCRIPTION
        Runbook that backups a storage account (full) or a storage account's container

   .EXAMPLE

#>
param
(
    [Parameter (Mandatory = $true)]
    [String] $SourceAccountName,

    [Parameter (Mandatory = $false)]
    [String] $SourceContainerName,

    [Parameter (Mandatory = $true)]
    [String] $SourceResourceGroupName,

    [Parameter (Mandatory = $true)]
    [ValidateScript({
       $types = @{ Hourly = "hourly"; Daily = "daily"; Weekly = "weekly"; Monthly = "monthly"; Yearly = "yearly" };
        if ($types.ContainsValue($_)) { $true } else { Throw "`n---------------------------------------------------------`nInvalid backup interval '$_'. Available are: $($types.Values).`n---------------------------------------------------------" }
    })]
    [String] $BackupIntervalType
)

# ========================================================================================
# Imports
# ========================================================================================

if ($PSPrivateMetadata.JobId -eq $null) {
   $verbose = $false
   "Loading modules..."

   Import-Module -Name ..\modules\BlobStorageBackup.Common.psm1 -Force -Verbose:$verbose
   Import-Module -Name ..\modules\BlobStorageBackup.Backup.psm1 -Force -Verbose:$verbose 
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

$BackupType = if ([string]::IsNullOrEmpty($SourceContainerName)) { "account" } else { "container" }
$BackupTimestamp = (Get-Date).ToString("yyyy-MM-dd_HH:mm:ss")
[long]$script:blobBackupCount = 0

$BackupInterval = (New-Object -TypeName PSObject -Prop ([ordered]@{ 
   Types = @{ Hourly = "hourly"; Daily = "daily"; Weekly = "weekly"; Monthly = "monthly"; Yearly = "yearly" };
}))


if ($BackupInterval.Types.ContainsValue($BackupIntervalType) -ne $true)
{
    Write-Error "ABORT: Incorrect backup interval specified: $BackupIntervalType"
    exit
}

# --------------------------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------------------------

function establishSecurityContext() {
   "Getting security context..."

   $useInteractiveLogin = (Test-IsRunningInAzureAutomation) -eq $false
   $azureAutomationConnectionName = "AzureRunAsConnection"
   Add-AzureSecurityContext -UseInteractiveLogin $useInteractiveLogin -AzureAutomationConnectionName $azureAutomationConnectionName
}

function getSourceStorageContext() {
   $context = Get-StorageContext -StorageAccountName $SourceAccountName -ResourceGroupName $SourceResourceGroupName
   return $context
}

function getBackupStorageContext() {
   $context = Get-StorageContext -StorageAccountName $BackupStorageAccountName -ResourceGroupName $BackupResourceGroupName
   return $context
}

function backupStorageAccount() {

   $command = New-StorageAccountBackupCommand
   $command.SrcContext = getSourceStorageContext
   $command.DestContext = getBackupStorageContext
   $command.DestPrefix = "$BackupType/$BackupIntervalType/$BackupTimestamp"

   "Backup To `t`t: [$BackupStorageAccountName]/$SourceAccountName/$($command.DestPrefix)`n"

   Invoke-StorageAccountBackup -Command $command
}

function backupStorageContainer() {

   $command = New-StorageContainerBackupCommand
   $command.SrcContext = getSourceStorageContext;
   $command.SrcContainer = $SourceContainerName;
   $command.DestContext = getBackupStorageContext;
   $command.DestPrefix = "$BackupType/$BackupIntervalType/$BackupTimestamp"; 
   $command.EnsureDestContainer = $true;

   Write-Output "Backup: [$BackupStorageAccountName]/$SourceAccountName/$($command.DestPrefix)`n"

   Invoke-StorageContainerBackup -Command $command
}

# --------------------------------------------------------------------------------------
# MAIN
# --------------------------------------------------------------------------------------

establishSecurityContext

"`nTimestamp `t`t: $BackupTimestamp"
"Interval `t`t: $backupIntervalType"
"Backup Type `t`t: $BackupType"
"Account `t`t: $SourceAccountName"
"Container `t`t: $(if ($SourceContainerName -eq '') { '[empty]' }) "

if ($BackupType -eq "account") {
   backupStorageAccount
} else {
   backupStorageContainer
}


"`nBackup of completed at: $((Get-Date).ToString("yyyy-MM-dd_HH:mm:ss"))"