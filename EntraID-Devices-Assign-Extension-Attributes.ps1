# Description:
# Script assigns extension attributes for Entra ID registered devices.
#
# Requirements:
# - Microsoft.Graph.Beta PowerShell module
# - Directory.ReadWrite.All and Device.Read.All permissions

# This script is https://github.com/a365junkie/Scripts/EntraID-Devices-Assign-Extension-Attributes.ps1
# See https://a365junkie.com/ for more information.
# V1.0 23-October-2024

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