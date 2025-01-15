<#
Description:
Script assigns extension attributes for Entra ID devices.

Requirements:
- Microsoft.Graph.Beta PowerShell module
- Directory.ReadWrite.All and Device.Read.All permissions

Version:
1.0

More details:
https://azure365addict.com/2025/01/15/assign-extension-attributes-to-entra-id-devices-using-graph-and-powershell/
#>

# Connect Microsoft Graph
$Scopes = "Directory.ReadWrite.All, Device.Read.All"
Connect-MgGraph -Scopes $Scopes

# Get device
$Device = Get-MgBetaDevice -Filter "displayName eq 'DeviceDisplayName'" # Change 'DeviceDisplayName'

# Set variables for extensionAttributes
$DeviceRegion = "Europe"
$DeviceCountry = "France"
$DeviceCity = "Paris"

# Assign extensionAttributes
$Attributes = @{
            ExtensionAttributes = @{
                extensionAttribute1 = $DeviceRegion
                extensionAttribute2 = $DeviceCountry
                extensionAttribute3 = $DeviceCity }
                } | ConvertTo-Json
      
             Update-MgBetaDevice -DeviceId $Device.Id -BodyParameter $Attributes

# Clear extensionAttributes        
$Attributes = @{
            ExtensionAttributes = @{
                extensionAttribute1 = ""
                extensionAttribute2 = ""
                extensionAttribute3 = "" }
                } | ConvertTo-Json
      
Update-MgBetaDevice -DeviceId $Device.Id -BodyParameter $Attributes

Write-Host `n"*** Please visit " -NoNewline -ForegroundColor Green; Write-Host "azure365addict.com" -ForegroundColor Yellow -NoNewline; Write-Host " to get access to the latest PowerShell related blog entries. ***" -ForegroundColor Green
