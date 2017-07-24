
# ========================================================================================
# Utilities 
# ========================================================================================

<#
.SYNOPSIS
Tests whether the executing script is running in Azure Automation.

.NOTES
useful for running locally and in Azure Automation
#>
function Test-IsRunningInAzureAutomation() {
   return $PSPrivateMetadata.JobId -ne $null
}

# ========================================================================================
# Authentication 
# ========================================================================================

<#
.SYNOPSIS
Authenticates using an Azure Automation Account Connection.

.PARAMETER ConnectionName
The name of the Azure Automation Connection
#>
function Add-AzureAutomationAccount {
   [CmdletBinding()]
   Param (
      [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
      [string]$ConnectionName = "AzureRunAsConnection"
   )

   try
   {
      # Get the connection "AzureRunAsConnection"
      $servicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName         

      "Logging in to Azure using connection [$ConnectionName]..."
      Add-AzureRmAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
      "`n"
   }
   catch {
      if (!$servicePrincipalConnection)
      {
         $ErrorMessage = "Connection $ConnectionName not found."
         throw $ErrorMessage
      } else{
         Write-Error -Message $_.Exception
         throw $_.Exception
      }
   }
}

<#
.SYNOPSIS
Performs authentication against Azure to get a security context for an executing script

.PARAMETER AzureAutomationConnectionName
(Optional) Azure Automation connection name to acquire a security context.

.PARAMETER UseInteractiveLogin
Whether to use an interative login (instead of azure automation)

.EXAMPLE
Add-SecurityContext -AzureAutomationConnectionName "AzureRunAsConnection"
#>
function Add-AzureSecurityContext($UseInteractiveLogin, $AzureAutomationConnectionName) {
  # "InteractiveLogin `t : $UseInteractiveLogin"

   if ($UseInteractiveLogin) {
      if ((Get-AzureRmContext -ErrorAction SilentlyContinue).Account -eq $null) {
         Login-AzureRmAccount
      }
   } else {
      Add-AzureAutomationAccount -ConnectionName $AzureAutomationConnectionName
   }
}


# ========================================================================================
# Storage Account Context
# ========================================================================================

<# Gets the storage account context, either ASM or ARM (if the RG is set) #>
function Get-StorageContext($StorageAccountName, $ResourceGroupName) {
	$key = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
   $context = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key
   
	return $context
}

# ========================================================================================
# Containers
# ========================================================================================


<#
.SYNOPSIS
Creates a new command object for Execute-EnsureContainer
#>
function New-EnsureStorageContainerCommand($StorageContext, $ContainerName) {
   return (New-Object -TypeName PSObject -Prop ([ordered]@{ 
      StorageContext = $StorageContext; #context of the storage account
      Name = $ContainerName; #name of the container
      Permission = "Off"; #assume to Off.
   }))
}


<#
.SYNOPSIS
Ensures that a container exists in the destination storage context

.PARAMETER Command
use Cmdlet New-EnsureContainerCommand to get a command to pass as an argument

.EXAMPLE
$cmd = New-EnsureContainerCommand -StorageContext $context -ContainerName $containerName
Execute-EnsureContainer -Command $cmd

#>
function Invoke-EnsureStorageContainer($Command) {
   $context = $Command.StorageContext

   $container = $context | Get-AzureStorageContainer -Name $Command.ContainerName -ErrorAction SilentlyContinue
   $exists = $container -ne $null

   if ($exists) {
      Write-Output "Storage container $($Command.Name) in $($context.StorageAccountName) already exists."
      return
   }

   do {
      $created = $false
      try {
         Write-Output "Creating container $($Command.Name)."
         New-AzureStorageContainer -Context $context -Permission $Command.Permission -Name $Command.Name -ErrorAction Stop
         $container = Get-AzureStorageContainer -Context $context -Name $Command.Name -ErrorAction Stop
         $created = $true
         Write-Output "Container $($container.Name) created."
      }
      catch {
      }
   } until ($created -eq $true)
}

<#
.SYNOPSIS
Gets all containers for a storage account
#>
function Get-StorageContainers($StorageAccountName, $ResourceGroupName) {
   $context = Get-StorageContext -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName
   $containers = $context | Get-AzureStorageContainer
   
	return $containers
}

# ========================================================================================
# Storage Accounts
# ========================================================================================



# ========================================================================================
# Blobs
# ========================================================================================


# ========================================================================================
# Exports
# ========================================================================================

Export-ModuleMember -Function Test-IsRunningInAzureAutomation
Export-ModuleMember -Function Add-AzureAutomationAccount 
Export-ModuleMember -Function Add-AzureSecurityContext
Export-ModuleMember -Function Get-StorageContext
Export-ModuleMember -Function New-EnsureStorageContainerCommand
Export-ModuleMember -Function Invoke-EnsureStorageContainer
Export-ModuleMember -Function Get-StorageContainers
