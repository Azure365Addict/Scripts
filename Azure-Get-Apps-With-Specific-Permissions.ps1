<#
.SYNOPSIS
    Searches Microsoft Graph for applications with specific delegated or application permissions.

.DESCRIPTION
    This script connects to Microsoft Graph and scans all service principals (apps) in the tenant
    to identify those with specific permissions (e.g., EWS or full access). It uses Microsoft Graph PowerShell SDK.

.PARAMETER None
    All required values are defined within the script itself.

.REQUIREMENTS
    - Microsoft.Graph PowerShell module
    - Directory.Read.All and Application.Read.All Graph permissions
    - Admin consent for the above permissions

.LINK
    https://azure365addict.com/2025/02/25/migrating-from-exchange-web-services-to-microsoft-graph-a-practical-guide/
#>

# Connect to Graph
$Scopes = "Application.Read.All, Directory.Read.All"
Connect-MgGraph -Scopes $Scopes

# Specify permissions
$permissionsToCheck = @("EWS.AccessAsUser.All", "full_access_as_app") # Permissions to check

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

