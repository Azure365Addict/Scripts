# Description:
# Script connects to Microsoft Graph and search for apps with specific permissions
#
# Requirements:
# - Microsoft Graph PowerShell Module

# This script is https://github.com/Azure365Addict/Scripts/edit/main/Azure-Get-Apps-With-Specific-Permissions.ps1
# See https://365ScriptJunkie.com/ for more information.
# V1.0 26-February-2025

# Connect to Graph
Connect-MgGraph -Scopes "Application.Read.All, Directory.Read.All"

# Specify permissions
$permissionsToCheck = @("EWS.AccessAsUser.All", "full_access_as_app")

# Get all Apps
$apps = Get-MgServicePrincipal -All
$results = @()

foreach ($app in $apps) {
    $permissions = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $app.Id
    foreach ($permission in $permissions) {
        if ($permissionsToCheck -contains $permission.Scope) {
            $results += [PSCustomObject]@{
                AppName = $app.DisplayName
                AppId = $app.AppId
                Permission = $permission.Scope
            }
        }
    }
}

# Display results
$results
