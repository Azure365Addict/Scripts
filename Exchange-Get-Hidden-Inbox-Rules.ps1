<#
Description:
This PowerShell script scans all user mailboxes in Exchange Online to identify and export hidden inbox rules — often overlooked yet potentially risky. 
It filters out default system rules, flags broken entries, and formats descriptions for CSV export

Requirements:
- ExchangeOnlineManagement module

More details:
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
