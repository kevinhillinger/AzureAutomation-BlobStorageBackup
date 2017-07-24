

# Overview

# Azure Subscription Setup

## 1. Create Blob Storage Backup
All backups will go to a single blob storage account ([https://docs.microsoft.com/en-us/azure/storage/storage-scalability-targets](500 TB limit)). Each source account will have a matching Blob Container in the Backup Account.

1. Create a Resource Group called "blob-storage-backups"
2. Create a uniquely named Blob Storage Account. Be mindful of region.

## 2. Create Automation Account
### Create Resource Group and Account
In the portal, create an Automation Account and call it "blob-storage-backups". Assign it to the Resourge Group "blob-storage-backups"

### Import Modules
In the Automation account, go to the Modules section and Import.

* Locate the zip files in scripts/modules
* Upload each file to the Automation Account's Modules

The Modules will be unpacked and made available (2-3 minutes).

### Create Automation Variables
Create the following automation variables, setting the value to the Backup Account

* [String] BackupStorageAccountName - The Name of the Backup Acccount
* [String] BackupResourceGroupName - The resource group that the Backup Account belongs to

### Import Runbook
In the Automation Account, import the ps1 files in scripts/runbooks as Runbooks.


# Restoring a backup

1. Using Microsoft Azure Storage Explorer or the Portal, locate the Backup Account
2. Identify the target location you'd like to restore from the Backup Account
3. Choose the Restore Point, e.g. "account/daily/2017-01-17_13:30:00" to input as the parameter "RestorePoint" to the "BlobStorageBackup-Restore" Runbook
4. Executing the restore will overwrite any matching blobs.