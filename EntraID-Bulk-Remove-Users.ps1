<#
Description:
Script removes users in bulk.

Requirements:
- Microsoft.Graph PowerShell module
- User.ReadWrite.All permission

Version:
1.0

More details:
https://azure365addict.com/2025/03/22/bulk-user-deletion-in-entra-id-with-powershell/
#>

# Connect Microsoft Graph
$Scopes = "User.ReadWrite.All "
Connect-MgGraph -Scopes $Scopes

# Get the list of users
$Users = Import-CSV "C:\Temp\EntraID-Bulk-Remove-Users_SAMPLE.csv" 

foreach ($User in $Users)

        {
        $UPN = $User.UserPrincipalName
                                                 
            try
            {
                $AADUser = Get-MgUser -UserId $UPN -ErrorAction Stop #Check if user exists
                Remove-MgUser -UserId $UPN
                Write-Host "Deleted user $UPN" -ForegroundColor Green
            }
    
                catch
                {
                Write-Host "WARNING: Could not delete user $UPN - User does not exist in Entra ID" -ForegroundColor Yellow
                }


        }

Write-Host `n"*** Please visit " -NoNewline -ForegroundColor Green; Write-Host "azure365addict.com" -ForegroundColor Yellow -NoNewline; Write-Host " to get access to the latest PowerShell related blog entries. ***" -ForegroundColor Green
