<#
.SYNOPSIS
Exports Microsoft Entra ID (Azure AD) sign-in logs for specific applications 
where devices are unmanaged and running Windows 10.

.DESCRIPTION
This script uses Microsoft Graph PowerShell to query the auditLogs/signIns endpoint
and export sign-in data matching these conditions:
- Time range: Last N days (default: 30)
- Device management: IsManaged = false
- Operating system: Windows10 (exact match)
- Application: One or more specified App IDs or App Display Names

The script handles paging (more than 999 rows), explicitly selects relevant fields
to avoid trimmed results, and flattens nested JSON objects (deviceDetail, status, location)
into simple CSV columns.

.PARAMETER AppIds
One or more Azure AD application IDs (GUID) to filter on. This is the fastest filter method.

.PARAMETER AppNames
One or more Azure AD application display names to filter on.
Less efficient than AppIds but can be used when IDs are not known.

.PARAMETER DaysBack
Number of days back from today to query sign-in logs. Default: 30.

.PARAMETER OutCsv
The full file path for the exported CSV. Default: ".\SignInLogs_Win10_Unmanaged.csv"

.EXAMPLE
# Export last 30 days of sign-ins for two applications by ID
.\GetSignInLogsForParticularApp.ps1 -AppIds "00000002-0000-0ff1-ce00-000000000000","00000003-0000-0000-c000-000000000000"

.EXAMPLE
# Export last 7 days of sign-ins for Microsoft Teams by name
.\GetSignInLogsForParticularApp.ps1 -AppNames "Microsoft Teams" -DaysBack 7 -OutCsv "C:\Temp\Teams_Unmanaged_Win10.csv"

.NOTES
Requires: Microsoft Graph PowerShell SDK v2, AuditLog.Read.All permission
Compatible with: Windows PowerShell 5.1 and PowerShell 7+
#>

param(
  [string[]] $AppIds   = @("00000002-0000-0ff1-ce00-000000000000"),  # App IDs here
  [string[]] $AppNames = @(),                                        # Optional names
  [int]      $DaysBack = 30,
  [string]   $OutCsv   = ".\SignInLogs_Win10_Unmanaged.csv"
)

# Connect to Graph if not already connected
if (-not (Get-MgContext)) {
  Connect-MgGraph -Scopes "AuditLog.Read.All" | Out-Null
}

# Build time range
$end   = (Get-Date).ToUniversalTime().ToString("o")
$start = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("o")

# Build app filter clauses
$appClauses = @()
if ($AppIds.Count -gt 0)   { $appClauses += '(' + ( ($AppIds   | ForEach-Object { "appId eq '$_'" }) -join ' or ' ) + ')' }
if ($AppNames.Count -gt 0) { $appClauses += '(' + ( ($AppNames | ForEach-Object { "appDisplayName eq '" + ($_ -replace "'","''") + "'" }) -join ' or ' ) + ')' }
if ($appClauses.Count -eq 0) { throw "Provide at least one AppId or AppName." }

# OS & Managed filters
$osFilter = "deviceDetail/operatingSystem eq 'Windows10'"
$managed  = "deviceDetail/isManaged eq false"

# Full filter
$filter = @(
  "createdDateTime ge $start"
  "createdDateTime le $end"
  $managed
  $osFilter
  '(' + ($appClauses -join ' or ') + ')'
) -join ' and '

# Endpoint and $select fields
$base   = "https://graph.microsoft.com/v1.0/auditLogs/signIns"
$select = @(
  "id","createdDateTime","userDisplayName","userPrincipalName","userId",
  "appDisplayName","appId","resourceDisplayName","ipAddress","clientAppUsed",
  "conditionalAccessStatus","riskDetail","riskLevelAggregated","riskLevelDuringSignIn",
  "status","deviceDetail","location","correlationId"
) -join ","

$uri = "$base`?`$filter=$([uri]::EscapeDataString($filter))&`$select=$select&`$top=999"

# Retrieve all pages
$all = @()
while ($uri) {
  $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
  $all  += $resp.value
  $uri   = $resp.'@odata.nextLink'
}

# Flatten nested objects for CSV export
$rows = $all | ForEach-Object {
  [pscustomobject]@{
    createdDateTime         = $_.createdDateTime
    userPrincipalName       = $_.userPrincipalName
    userDisplayName         = $_.userDisplayName
    userId                  = $_.userId
    appDisplayName          = $_.appDisplayName
    appId                   = $_.appId
    resourceDisplayName     = $_.resourceDisplayName
    ipAddress               = $_.ipAddress
    clientAppUsed           = $_.clientAppUsed
    conditionalAccessStatus = $_.conditionalAccessStatus
    riskDetail              = $_.riskDetail
    riskLevelAggregated     = $_.riskLevelAggregated
    riskLevelDuringSignIn   = $_.riskLevelDuringSignIn
    OperatingSystem         = $_.deviceDetail.operatingSystem
    Browser                 = $_.deviceDetail.browser
    IsManaged               = $_.deviceDetail.isManaged
    TrustType               = $_.deviceDetail.trustType
    City                    = $_.location.city
    State                   = $_.location.state
    CountryOrRegion         = $_.location.countryOrRegion
    CorrelationId           = $_.correlationId
    ErrorCode               = $_.status.errorCode
    FailureReason           = $_.status.failureReason
    AdditionalDetails       = $_.status.additionalDetails
  }
}

# Export results
$rows | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8

Write-Host "Done. Exported $($rows.Count) rows to $OutCsv"
