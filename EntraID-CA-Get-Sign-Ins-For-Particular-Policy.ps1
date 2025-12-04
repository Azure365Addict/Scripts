<#
.SYNOPSIS
    Reports Conditional Access policy activity (enabled and/or report-only) from Entra ID sign-in logs.

.DESCRIPTION
    This script:
      - Automatically detects the correct Log Analytics workspace containing SigninLogs.
      - Expands ConditionalAccessPolicies for each sign-in.
      - Filters by policy name.
      - Supports both enabled and report-only evaluations.
      - Optionally exports the full dataset to CSV (via -ExportCSV).
      - When not exporting, prints summary + top N entries only (configurable via -Top).

.PARAMETER PolicyName
    Display name of the Conditional Access policy in Entra ID.

.PARAMETER HoursBack
    Lookback window for sign-ins (default: 4h).

.PARAMETER ReportOnly
    Filters only report-only results (reportOnlySuccess/Failure/NotApplied).

.PARAMETER EnabledOnly
    Filters only fully enabled results (success/failure/notApplied).

.PARAMETER ExportCSV
    If specified, exports all matching records to CSV.
    If omitted, only displays summary + top N results (see -Top).

.PARAMETER Top
    Number of rows to display when not exporting (default: 25).

.PARAMETER OutputPath
    Path for CSV output (default: .\CA_Report_<timestamp>.csv).

.EXAMPLE
    .\EntraID-CA-Get-Sign-Ins-For-Particular-Policy.ps1 -PolicyName "CONDITIONAL ACCESS POLICY NAME" -ReportOnly

    Shows report-only CA results (last 4h), prints summary + top N (default 25).

.EXAMPLE
    .\EntraID-CA-Get-Sign-Ins-For-Particular-Policy.ps1 -PolicyName "CONDITIONAL ACCESS POLICY NAME" -EnabledOnly -ExportCSV

    Shows summary + exports full results to CSV.

.NOTES
    Requires Az.Accounts + Az.OperationalInsights modules.
    
.LINK
    https://azure365addict.com/2025/12/04/reporting-conditional-access-policy-activity-from-sign-in-logs/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PolicyName,

    [int]$HoursBack = 4,

    [switch]$ReportOnly,
    [switch]$EnabledOnly,

    [switch]$ExportCSV,

    [int]$Top = 25,

    [string]$OutputPath = ".\CA_Report_$((Get-Date).ToString('yyyyMMdd_HHmm')).csv"
)

# -----------------------------------------------------------
# Validate switches
# -----------------------------------------------------------
if ($ReportOnly -and $EnabledOnly) {
    throw "You cannot use -ReportOnly and -EnabledOnly together."
}

# -----------------------------------------------------------
# Load modules
# -----------------------------------------------------------
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop

# -----------------------------------------------------------
# Ensure Az context & subscription
# -----------------------------------------------------------
$ctx = Get-AzContext -ErrorAction SilentlyContinue

if (-not $ctx) {
    Write-Host "No Az context found. Connecting to Azure..." -ForegroundColor Cyan
    Connect-AzAccount -ErrorAction Stop | Out-Null
    $ctx = Get-AzContext
}

if (-not $ctx.Subscription) {
    Write-Host "No active subscription selected. Resolving subscription..." -ForegroundColor Cyan

    $subs = Get-AzSubscription -ErrorAction Stop

    if ($subs.Count -eq 0) {
        throw "No subscriptions available for the current account."
    }
    elseif ($subs.Count -eq 1) {
        Write-Host ("Using the only available subscription: {0} ({1})" -f $subs[0].Name, $subs[0].Id) -ForegroundColor Green
        Select-AzSubscription -SubscriptionId $subs[0].Id -ErrorAction Stop | Out-Null
    }
    else {
        Write-Host "Multiple subscriptions detected:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $subs.Count; $i++) {
            Write-Host ("[{0}] {1} ({2})" -f ($i + 1), $subs[$i].Name, $subs[$i].Id)
        }

        $choice = Read-Host "Select subscription number to use"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $subs.Count) {
            $selectedSub = $subs[[int]$choice - 1]
            Write-Host ("Using subscription: {0} ({1})" -f $selectedSub.Name, $selectedSub.Id) -ForegroundColor Green
            Select-AzSubscription -SubscriptionId $selectedSub.Id -ErrorAction Stop | Out-Null
        }
        else {
            Write-Warning "Invalid selection. Keeping current context subscription (if any)."
        }
    }
}

# -----------------------------------------------------------
# Auto-detect workspace containing SigninLogs
# -----------------------------------------------------------
Write-Host "Detecting Log Analytics workspace with SigninLogs..." -ForegroundColor Cyan

$workspaces = Get-AzOperationalInsightsWorkspace
$selectedWorkspace = $null

foreach ($ws in $workspaces) {
    try {
        $probe = Invoke-AzOperationalInsightsQuery -WorkspaceId $ws.CustomerId -Query "SigninLogs | take 1"
        if (-not $probe.Error -and $probe.Results.Count -gt 0) {
            $selectedWorkspace = $ws
            break
        }
    } catch {}
}

if (-not $selectedWorkspace) {
    Write-Error "Could not find a workspace containing the SigninLogs table."
    return
}

Write-Host ("Using workspace: {0} ({1})" -f $selectedWorkspace.Name, $selectedWorkspace.Location) -ForegroundColor Green

# -----------------------------------------------------------
# Build result filter
# -----------------------------------------------------------
$capResultFilter = ""

if ($ReportOnly) {
    $capResultFilter = "| where cap.result startswith 'reportOnly'"
}
elseif ($EnabledOnly) {
    $capResultFilter = "| where cap.result !startswith 'reportOnly'"
}

# -----------------------------------------------------------
# Build final KQL query
# -----------------------------------------------------------
$query = @"
SigninLogs
| where TimeGenerated > ago(${HoursBack}h)
| mv-expand cap = ConditionalAccessPolicies
| where cap.displayName == '$PolicyName'
$capResultFilter
| project
    TimeGenerated,
    UserPrincipalName,
    AppDisplayName,
    cap_displayName = cap.displayName,
    cap_result      = cap.result,
    IPAddress,
    Device_OS       = DeviceDetail.operatingSystem,
    Device_Trust    = DeviceDetail.trustType
| order by TimeGenerated desc
"@

Write-Host "Executing Kusto query..." -ForegroundColor Cyan

$result = Invoke-AzOperationalInsightsQuery -WorkspaceId $selectedWorkspace.CustomerId -Query $query

if ($result.Error) {
    Write-Error "Kusto query error:"
    $result.Error | Format-List *
    return
}

$rows = $result.Results

if (-not $rows -or $rows.Count -eq 0) {
    Write-Host "No results found for policy '$PolicyName' in last $HoursBack hour(s)." -ForegroundColor Yellow
    return
}

# -----------------------------------------------------------
# Summary output
# -----------------------------------------------------------
Write-Host "`nSummary by result type:" -ForegroundColor Green

$rows |
    Group-Object cap_result |
    Select-Object Name, Count |
    Sort-Object Name |
    Format-Table -AutoSize

# -----------------------------------------------------------
# If not exporting CSV → Print TOP N & exit
# -----------------------------------------------------------
if (-not $ExportCSV) {
    Write-Host ("`nTop {0} results:" -f $Top) -ForegroundColor Cyan

    $rows |
        Select-Object TimeGenerated, UserPrincipalName, AppDisplayName, cap_result, IPAddress |
        Select-Object -First $Top |
        Format-Table -AutoSize

    Write-Host "`n(No CSV export performed — use -ExportCSV to save full results.)" -ForegroundColor Yellow
    return
}

# -----------------------------------------------------------
# Export full dataset to CSV
# -----------------------------------------------------------
$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "`nFull report exported to: $OutputPath" -ForegroundColor Cyan


