
Set-Variable -Name "testVar" -Value (New-Object -TypeName 'System.Management.Automation.PSObject' -Prop (@{ "value" = 2; })) -Option None -Visibility Private -Scope Global -Force


function Get-ObjectFromJsonFile($FilePath) {
	$file = Resolve-Path $FilePath | select -ExpandProperty Path
	$json = Get-Content $file	
	$object = $json | Out-String | ConvertFrom-Json
	
	return $object
}

function Write-ObjectToJsonFile($Object, $FilePath) {
	$Object | ConvertTo-Json | Out-File -FilePath $FilePath -Encoding utf8 -Force:$true
}


Export-ModuleMember -function Get-ObjectFromJsonFile
Export-ModuleMember -function Write-ObjectToJsonFile