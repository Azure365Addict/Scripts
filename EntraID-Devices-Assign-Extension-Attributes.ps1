# Description:
# Script assigns extension attributes for Entra ID devices.
#
# Requirements:
# - Microsoft.Graph.Beta PowerShell module
# - Directory.ReadWrite.All and Device.Read.All permissions

# For detailed script execution:: https://github.com/Azure365Addict/Scripts/edit/main/EntraID-Devices-Assign-Extension-Attributes.ps1
# V1.0 24-January-2025

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
