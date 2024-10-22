# Description:
# Script connects to Az and gets all users with Eligible roles assigned within all (Enabled) subscriptions.
#
# Requirements:
# - Az.Accounts PowerShell module
# - Az.Resources PowerShell module

# This script is https://github.com/365ScriptJunkie/Scripts/Azure-Get-Eligible-Role-Assignments.ps1
# See https://365ScriptJunkie.com/ for more information.
# V1.0 22-October-2024

# Connect Az
$TenantId = "xxxxxxxxxx" # Add your Tenant Id here
Connect-AzAccount -Tenant $TenantId

# Get all enabled subscriptions
$Subscriptions = Get-AzSubscription | Where-Object {$_.State -eq "Enabled"}

# Get All Eligible Azure Assignments
$EligibleAzureUserData = @()

foreach ($Subscription in $Subscriptions)

        {
        $Scope = $Subscription.Id
        Set-AzContext -Subscription $Scope | Out-Null
        $RoleEligibilitySchedules = Get-AzRoleEligibilitySchedule -Scope "/subscriptions/$Scope"

        $EligibleAzureUserData += $RoleEligibilitySchedules 
        
        }

$EligibleAzureUserData | Select PrincipalDisplayName, PrincipalEmail, PrincipalId, ScopeDisplayName, RoleDefinitionDisplayName | Out-GridView

# Export to CSV (unhash and change $Path if needed)
#$Path = "C:\Temp\Azure-Get-Eligible-Role-Assignments.csv"
#$EligibleAzureUserData | Select PrincipalDisplayName, PrincipalEmail, PrincipalId, ScopeDisplayName, RoleDefinitionDisplayName | Export-Csv -Path $Path -NoTypeInformation
