<#
.SYNOPSIS
FAST newsletter "read" report:
1) Exchange Online Message Trace V2 -> who actually received the message (Delivered)
2) Microsoft Graph -> check IsRead per recipient mailbox by internetMessageId

.DESCRIPTION
Designed for large orgs. Avoids scanning every mailbox.
Uses Message Trace V2 to identify real recipients (Delivered) and then queries Graph per mailbox
to check IsRead for the message identified by internetMessageId.

.NOTES
Modules required:
- ExchangeOnlineManagement
- Microsoft.Graph

Auth model:
- App-only / certificate-based for both EXO PowerShell and Microsoft Graph.

Permissions (minimum, high level):
Exchange Online (app-only):
- Access to run Get-MessageTraceV2 and mailbox/recipient queries (Get-EXOMailbox / Get-EXORecipient).

Microsoft Graph (app-only):
- Mail.Read (Application) with admin consent.

Before running:
- Replace placeholders in the CONFIG section (ClientId/TenantId/Thumbprints/Org).

.EXAMPLE
.\Get-MailReadReport.ps1 -SenderAddress sender@contoso.com -StartDate 2026-01-14 -EndDate 2026-01-16

.EXAMPLE
.\Get-MailReadReport.ps1 -SenderAddress sender@contoso.com -StartDate 2026-01-14 -EndDate 2026-01-16 -Subject "Newsletter"

.EXAMPLE
.\Get-MailReadReport.ps1 -SenderAddress sender@contoso.com -StartDate 2026-01-14 -EndDate 2026-01-16 -Report

.LINK
    https://azure365addict.com/2026/03/06/exchange-online-mail-read-status-report/
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SenderAddress,

    [string] $Subject,

    [Parameter(Mandatory)]
    [string] $StartDate,

    [Parameter(Mandatory)]
    [string] $EndDate,

    [int]    $TopPerRecipient = 3,
    [int]    $ThrottleMs = 50,

    [switch] $SummaryOnly,
    [switch] $Report,

    # Defaults to ON when -Report is used (unless explicitly provided)
    [switch] $Quiet
)

Set-StrictMode -Version Latest

# =============================================================================
# CONFIG (REPLACE THESE VALUES)
# =============================================================================
# Graph (app-only)
$GraphClientId              = "<GRAPH_APP_CLIENT_ID>"
$GraphTenantId              = "<TENANT_ID>"
$GraphCertificateThumbprint = "<GRAPH_CERT_THUMBPRINT>"

# Exchange Online (app-only)
$ExoClientId              = "<EXO_APP_ID>"
$ExoCertificateThumbprint = "<EXO_CERT_THUMBPRINT>"
$ExoOrganization          = "<tenant>.onmicrosoft.com"

# =============================================================================
# Helpers
# =============================================================================
function Convert-ToDateTime([string]$s) {
    try { [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { throw "Invalid date: '$s'. Use YYYY-MM-DD, e.g. 2026-01-14" }
}

function Assert-Config {
    $missing = @()

    if (-not $GraphClientId              -or $GraphClientId              -like "<*") { $missing += "GraphClientId" }
    if (-not $GraphTenantId              -or $GraphTenantId              -like "<*") { $missing += "GraphTenantId" }
    if (-not $GraphCertificateThumbprint -or $GraphCertificateThumbprint -like "<*") { $missing += "GraphCertificateThumbprint" }

    if (-not $ExoClientId                -or $ExoClientId                -like "<*") { $missing += "ExoClientId" }
    if (-not $ExoCertificateThumbprint   -or $ExoCertificateThumbprint   -like "<*") { $missing += "ExoCertificateThumbprint" }
    if (-not $ExoOrganization            -or $ExoOrganization            -like "<*") { $missing += "ExoOrganization" }

    if ($missing.Count -gt 0) {
        throw ("Missing config values: {0}. Update placeholders in CONFIG section." -f ($missing -join ", "))
    }
}

# =============================================================================
# Connections
# =============================================================================
function Ensure-MgGraphConnection {
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($ctx -and $ctx.TenantId -eq $GraphTenantId -and $ctx.ClientId -eq $GraphClientId) { return }

    Connect-MgGraph `
        -ClientId $GraphClientId `
        -TenantId $GraphTenantId `
        -CertificateThumbprint $GraphCertificateThumbprint `
        -NoWelcome `
        -ErrorAction Stop | Out-Null
}

function Ensure-ExchangeOnlineConnection {
    try {
        Get-EXORecipient -ResultSize 1 -ErrorAction Stop | Out-Null
        return
    } catch {}

    Connect-ExchangeOnline `
        -AppId $ExoClientId `
        -CertificateThumbprint $ExoCertificateThumbprint `
        -Organization $ExoOrganization `
        -ShowBanner:$false `
        -ErrorAction Stop | Out-Null
}

function Test-SenderAddressExists {
    param([Parameter(Mandatory)][string]$SenderAddress)

    Ensure-ExchangeOnlineConnection
    try {
        $null = Get-EXORecipient -Identity $SenderAddress -ResultSize 1 -ErrorAction Stop
        $true
    } catch {
        $false
    }
}

# =============================================================================
# CSV report
# =============================================================================
$CsvInitialized = $false
$CsvPath = $null
$CsvSummaryPath = $null

function Initialize-CsvReportIfNeeded {
    if (-not $Report) { return }

    if (-not $CsvPath) {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $CsvPath = Join-Path -Path $PSScriptRoot -ChildPath "MailReadReport_$ts.csv"
    }

    if (-not $CsvSummaryPath) {
        $base = (Split-Path $CsvPath -Leaf) -replace '\.csv$',''
        $CsvSummaryPath = Join-Path -Path $PSScriptRoot -ChildPath "${base}_summary.csv"
    }
}

function New-ReportRow {
    param(
        [Parameter(Mandatory)][string]$RunDate,
        [Parameter(Mandatory)][string]$Recipient,
        [string]$SenderAddress,
        [string]$Subject,
        [string]$InternetMessageId,
        [Nullable[datetime]]$ReceivedDate,
        [Nullable[bool]]$IsRead,
        [Parameter(Mandatory)][string]$Status
    )

    [PSCustomObject]([ordered]@{
        RunDate           = $RunDate
        Recipient         = $Recipient
        SenderAddress     = $SenderAddress
        Subject           = $Subject
        InternetMessageId = $InternetMessageId
        ReceivedDate      = $ReceivedDate
        IsRead            = $IsRead
        Status            = $Status
    })
}

function Write-ResultToCsv {
    param([Parameter(Mandatory)][pscustomobject]$Row)

    if (-not $Report) { return }

    Initialize-CsvReportIfNeeded

    # Safety net: ensure path is always set
    if (-not $CsvPath) {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $CsvPath = Join-Path -Path $PSScriptRoot -ChildPath "MailReadReport_$ts.csv"
    }

    if (-not $CsvInitialized) {
        if (Test-Path $CsvPath) { Remove-Item $CsvPath -Force }
        $Row | Export-Csv -Path $CsvPath -Delimiter ';' -NoTypeInformation
        $CsvInitialized = $true
        return
    }

    $Row | Export-Csv -Path $CsvPath -Delimiter ';' -NoTypeInformation -Append
}

# =============================================================================
# Message Trace V2 (Delivered only) - SIMPLE & RELIABLE
# =============================================================================
function Get-TraceRecipientsDeliveredMailboxes {
    param(
        [Parameter(Mandatory)][string]   $SenderAddress,
        [Parameter(Mandatory)][datetime] $Start,
        [Parameter(Mandatory)][datetime] $EndExclusive,
        [string] $Subject,
        [int]    $ResultSize = 5000
    )

    Ensure-ExchangeOnlineConnection
    Write-Host "Running message trace (Delivered)..." -ForegroundColor Cyan

    $trace = @(
        Get-MessageTraceV2 `
            -StartDate $Start `
            -EndDate $EndExclusive `
            -Status Delivered `
            -SenderAddress $SenderAddress `
            -ResultSize $ResultSize
    )

    if ($Subject) {
        $trace = @($trace | Where-Object { $_.Subject -like "*$Subject*" })
    }

    $rows = @(
        $trace |
        Where-Object { $_.RecipientAddress -and $_.MessageId } |
        Select-Object RecipientAddress, MessageId, Subject, Received
    )

    # Dedup
    $rows = @($rows | Sort-Object RecipientAddress, MessageId -Unique)

    # Normalize RecipientAddress
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in $rows) {
        $rcpt = ([string]$r.RecipientAddress).Trim()
        if (-not $rcpt) { continue }

        $out.Add([PSCustomObject]@{
            RecipientAddress = $rcpt
            MessageId        = $r.MessageId
            Subject          = $r.Subject
            Received         = $r.Received
        })
    }

    Write-Host ("Found {0} delivered recipients (from trace)." -f $out.Count) -ForegroundColor Green
    $out
}

# =============================================================================
# Graph: read status by internetMessageId
# =============================================================================
function Get-RecipientReadStatusByInternetMessageId {
    param(
        [Parameter(Mandatory)][string] $RecipientUpn,
        [Parameter(Mandatory)][string] $InternetMessageId,
        [int]$Top = 3
    )

    $safe = $InternetMessageId.Replace("'","''")
    $filter = "internetMessageId eq '$safe'"

    $msgs = Get-MgUserMessage -UserId $RecipientUpn -Filter $filter -Top $Top `
        -Property Id,Subject,IsRead,ReceivedDateTime,InternetMessageId `
        -ErrorAction Stop |
        Sort-Object ReceivedDateTime -Descending

    $msgs | Select-Object -First 1
}

# =============================================================================
# Validate inputs / defaults
# =============================================================================
Assert-Config

if ($Report -and -not $PSBoundParameters.ContainsKey('Quiet')) { $Quiet = $true }

$startDay = (Convert-ToDateTime $StartDate).Date
$endDay   = (Convert-ToDateTime $EndDate).Date

# TRACE WINDOW:
# Start = StartDate 00:00
# EndExclusive = (EndDate + 1 day) 00:00
# This matches how you tested manually (e.g. 2026-03-05 -> End 2026-03-06).
$traceStart = $startDay
$traceEndExclusive = $endDay.AddDays(1)

Ensure-MgGraphConnection

if (-not (Test-SenderAddressExists -SenderAddress $SenderAddress)) {
    Write-Error @"
Sender address '$SenderAddress' was not found in Exchange Online.

Check:
- It must be an internal mailbox (not a distribution group).
- Use primary SMTP address if possible.
"@
    return
}

Initialize-CsvReportIfNeeded

# =============================================================================
# Execute
# =============================================================================
$cntTotal    = 0
$cntRead     = 0
$cntUnread   = 0
$cntNotFound = 0
$cntError    = 0

$runDate = Get-Date -Format g

$traceRows = @(
    Get-TraceRecipientsDeliveredMailboxes `
        -SenderAddress $SenderAddress `
        -Start $traceStart `
        -EndExclusive $traceEndExclusive `
        -Subject $Subject
)

$idx = 0
$total = $traceRows.Count

foreach ($row in $traceRows) {
    $idx++
    $cntTotal++

    if (($idx % 25) -eq 0 -or $idx -eq 1 -or $idx -eq $total) {
        $pct = if ($total -gt 0) { [int](($idx / [double]$total) * 100) } else { 0 }
        Write-Progress -Activity "Processing recipients" -Status "Recipient $idx of $total" -PercentComplete $pct
    }

    $recipient = ([string]$row.RecipientAddress).Trim()
    $imid      = $row.MessageId

    if (-not $recipient) { continue }
    if ($ThrottleMs -gt 0) { Start-Sleep -Milliseconds $ThrottleMs }

    try {
        $msg = Get-RecipientReadStatusByInternetMessageId -RecipientUpn $recipient -InternetMessageId $imid -Top $TopPerRecipient

        if (-not $msg) {
            $cntNotFound++

            if (-not $SummaryOnly) {
                $out = New-ReportRow -RunDate $runDate -Recipient $recipient -SenderAddress $SenderAddress `
                    -Subject $row.Subject -InternetMessageId $imid -ReceivedDate $null -IsRead $null -Status "NotFoundInMailbox"
                Write-ResultToCsv -Row $out
                if (-not $Quiet) { $out }
            }
            continue
        }

        $isRead = [bool]$msg.IsRead
        if ($isRead) { $cntRead++ } else { $cntUnread++ }

        if (-not $SummaryOnly) {
            $out = New-ReportRow -RunDate $runDate -Recipient $recipient -SenderAddress $SenderAddress `
                -Subject $msg.Subject -InternetMessageId $msg.InternetMessageId -ReceivedDate ($msg.ReceivedDateTime.ToLocalTime()) `
                -IsRead $isRead -Status "OK"
            Write-ResultToCsv -Row $out
            if (-not $Quiet) { $out }
        }
    }
    catch {
        $cntError++

        if (-not $SummaryOnly) {
            $out = New-ReportRow -RunDate $runDate -Recipient $recipient -SenderAddress $SenderAddress `
                -Subject $row.Subject -InternetMessageId $imid -ReceivedDate $null -IsRead $null -Status ("Error: " + $_.Exception.Message)
            Write-ResultToCsv -Row $out
            if (-not $Quiet) { $out }
        }
    }
}

Write-Progress -Activity "Processing recipients" -Completed

# =============================================================================
# Summary
# =============================================================================
$checked = $cntTotal
$readPct = if ($checked -gt 0) { [math]::Round(($cntRead / $checked) * 100, 2) } else { 0 }

$summary = [PSCustomObject]@{
    RecipientsFound    = $checked
    Read              = $cntRead
    Unread            = $cntUnread
    NotFoundInMailbox = $cntNotFound
    Errors            = $cntError
    ReadPercentage    = $readPct
}

if ($Report) {
    Initialize-CsvReportIfNeeded

    if (-not $CsvSummaryPath) {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $CsvSummaryPath = Join-Path -Path $PSScriptRoot -ChildPath "MailReadReport_${ts}_summary.csv"
    }

    $summary | Export-Csv -Path $CsvSummaryPath -Delimiter ';' -NoTypeInformation
}

$summary

if ($Report -and $CsvPath) {
    Write-Host "CSV report saved to: $CsvPath" -ForegroundColor Cyan
    if (Test-Path $CsvSummaryPath) {
        Write-Host "Summary CSV saved to: $CsvSummaryPath" -ForegroundColor Cyan
    }

}
