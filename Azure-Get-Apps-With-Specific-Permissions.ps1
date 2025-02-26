Connect-MgGraph -Scopes "Application.Read.All, Directory.Read.All"

$permissionsToCheck = @("EWS.AccessAsUser.All", "full_access_as_app")
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

$results