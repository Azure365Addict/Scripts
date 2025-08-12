<#
.SYNOPSIS
Scans all user mailboxes in Exchange Online to identify and export hidden inbox rules.

.DESCRIPTION
The script connects to Exchange Online and enumerates all user mailboxes.
It identifies hidden inbox rules (rules that do not appear in the standard Get-InboxRule output)
by comparing the list of visible rules against the complete list retrieved with the -IncludeHidden switch.
Default system rules are excluded from the results.
The script also detects broken rules, cleans rule descriptions, and exports the findings to a CSV file.

.PARAMETER None
The script takes no parameters. Configuration is done within the code by modifying variables such as $excludedNames.

.EXAMPLE
# Run the script interactively to produce a report:
.\Exchange-Get-Hidden-Inbox-Rules.ps1

.NOTES
Requirements:
- ExchangeOnlineManagement module installed and imported
- Appropriate permissions to access all user mailboxes in Exchange Online

More information:
https://azure365addict.com/2025/05/22/detecting-hidden-inbox-rules-in-exchange-online/
#>

# Connect to Exchange Online
Connect-ExchangeOnline

# Define rule names to exclude from results
$excludedNames = @(
    "Junk E-mail Rule",
    "Microsoft.Exchange.OOF.InternalSenders.Global",
    "Microsoft.Exchange.OOF.KnownExternalSenders.Global",
    "Microsoft.Exchange.OOF.AllExternalSenders.Global"
)

# Initialize an array to store results
$results = @()

# Get all user mailboxes in the organization
$mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited

foreach ($mbx in $mailboxes) {
    Write-Host "Processing: $($mbx.PrimarySmtpAddress)" -ForegroundColor Cyan

    try {
        # Suppress warnings from Get-InboxRule
        $visibleRules = Get-InboxRule -Mailbox $mbx.PrimarySmtpAddress -ErrorAction SilentlyContinue 3>$null
        $allRules = Get-InboxRule -Mailbox $mbx.PrimarySmtpAddress -IncludeHidden -ErrorAction SilentlyContinue 3>$null

        # Filter only hidden rules by comparing with visible ones and excluding system rules
        $hiddenRules = $allRules | Where-Object {
            $visibleRules.Name -notcontains $_.Name -and
            $excludedNames -notcontains $_.Name
        }

        foreach ($rule in $hiddenRules) {
            $hasErrors = $rule.ToString() -like "*contains errors*"
            $cleanDescription = ($rule.Description -replace '\r?\n', ' ').Trim()

            $results += [PSCustomObject]@{
                Mailbox     = $mbx.PrimarySmtpAddress
                RuleName    = $rule.Name
                Enabled     = $rule.Enabled
                Description = $cleanDescription
                HasErrors   = $hasErrors
            }
        }
    }
    catch {
        Write-Warning "Error while processing $($mbx.PrimarySmtpAddress): $_"
    }
}

# Export the results to a CSV file
$results | Export-Csv -Path ".\HiddenInboxRules_Report.csv" -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host "`nCompleted. Output saved to: HiddenInboxRules_Report.csv" -ForegroundColor Green

