<#
Description:
Script connects to Microsoft Graph and search for apps with specific permissions

Requirements:
- Microsoft.Graph PowerShell module

Version:
1.0

More details:
https://azure365addict.com/2025/02/25/migrating-from-exchange-web-services-to-microsoft-graph-a-practical-guide/
#>

# Connect to Graph
$Scopes = "Application.Read.All, Directory.Read.All"
Connect-MgGraph -Scopes $Scopes

# Specify permissions
$permissionsToCheck = @("EWS.AccessAsUser.All", "full_access_as_app")

# Get all Apps
$apps = Get-MgServicePrincipal -All
$results = @()

# Loop through all Apps
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
