<#
.SYNOPSIS
Check which certificates and client secrets were actually used by a Microsoft Entra ID application.

.DESCRIPTION
When an app registration has multiple certificates or client secrets, it is not always obvious
which credential is still in use and which one can be safely retired.

This script helps with that by:
- reading certificate and client secret metadata from the app registration
- collecting service principal sign-in logs for the selected application
- matching sign-in events to individual credential Key IDs
- showing either a full overview or a focused drill-down for one certificate or one secret

The script uses the best available matching method:
- first, it looks for an exact match in servicePrincipalCredentialKeyId
- if that field is not present, it falls back to a safe JSON search for the selected GUID

Because sign-in records are not always equally detailed, the output is split into:
- VerifiedHits   -> events that contain useful attribution data such as timestamp, IP, status, or resource
- SuspectMatches -> events where the GUID matched, but the record is too incomplete to treat as a strong hit

This makes the script useful when reviewing old credentials, preparing for secret or certificate rotation,
or checking whether a newly added credential is already being used.

.PARAMETER AppId
Application (client) ID of the target app registration.

.PARAMETER CertificateId
Optional certificate Key ID used for drill-down mode.

.PARAMETER SecretId
Optional client secret Key ID used for drill-down mode.

.PARAMETER DaysBack
How many days back to query sign-ins. Default: 30.

.PARAMETER Export
Exports results to CSV and, where applicable, suspect matches to JSON.

.PARAMETER ExportFolder
Folder used for exports. Default: .\Exports

.EXAMPLE
.\Get-AppCredentialSignInUsage.ps1 -AppId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
.\Get-AppCredentialSignInUsage.ps1 -AppId "00000000-0000-0000-0000-000000000000" -CertificateId "11111111-1111-1111-1111-111111111111"

.EXAMPLE
.\Get-AppCredentialSignInUsage.ps1 -AppId "00000000-0000-0000-0000-000000000000" -SecretId "22222222-2222-2222-2222-222222222222" -DaysBack 90 -Export

.NOTES
Requirements:
- Microsoft Graph PowerShell SDK
- Delegated Microsoft Graph permissions:
  - AuditLog.Read.All
  - Application.Read.All
#>

param(
    [Parameter(Mandatory)]
    [string]$AppId,

    [string]$CertificateId,

    [string]$SecretId,

    [int]$DaysBack = 30,

    [switch]$Export,

    [string]$ExportFolder = "$PWD\Exports"
)

function Get-AppCredentialUsage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [string]$CertificateId,

        [string]$SecretId,

        [int]$DaysBack = 30,

        [switch]$Export,

        [string]$ExportFolder = "$PWD\Exports"
    )

    if (-not [string]::IsNullOrWhiteSpace($CertificateId) -and -not [string]::IsNullOrWhiteSpace($SecretId)) {
        throw "Use only one drill-down parameter at a time: -CertificateId or -SecretId."
    }

    function Get-GraphPaged {
        param(
            [Parameter(Mandatory)]
            [string]$Uri
        )

        $all = @()

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $Uri
            if ($response.value) {
                $all += $response.value
            }
            $Uri = $response.'@odata.nextLink'
        } while ($Uri)

        return $all
    }

    function Get-UtcSinceIso {
        param([int]$Days)
        return (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    function Get-SafeFileNamePart {
        param([string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return "UnknownApp"
        }

        return ($Value -replace '[^\w\.-]', '_')
    }

    function Test-GuidLike {
        param([string]$Value)

        return ($Value -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
    }

    function Convert-ToGuidString {
        param([object]$Value)

        if ($null -eq $Value) { return $null }
        if ($Value -is [guid]) { return $Value.ToString() }

        $stringValue = [string]$Value
        if ([string]::IsNullOrWhiteSpace($stringValue)) { return $null }

        $guidValue = [guid]::Empty
        if ([guid]::TryParse($stringValue, [ref]$guidValue)) {
            return $guidValue.ToString()
        }

        return $null
    }

    function Get-PropertyValue {
        param(
            [object]$Object,
            [string]$Name
        )

        if ($null -eq $Object) { return $null }

        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) {
                return $Object[$Name]
            }
            return $null
        }

        $property = $Object.PSObject.Properties[$Name]
        if ($property) {
            return $property.Value
        }

        return $null
    }

    function Get-NestedPropertyValue {
        param(
            [object]$Object,
            [string]$Parent,
            [string]$Child
        )

        $parentValue = Get-PropertyValue -Object $Object -Name $Parent
        return Get-PropertyValue -Object $parentValue -Name $Child
    }

    function Normalize-SignInEvents {
        param($Events)

        $Events | ForEach-Object {
            [pscustomobject]@{
                CreatedDateTime                  = Get-PropertyValue $_ 'createdDateTime'
                IpAddress                        = Get-PropertyValue $_ 'ipAddress'
                ResourceDisplayName              = Get-PropertyValue $_ 'resourceDisplayName'
                StatusErrorCode                  = Get-NestedPropertyValue $_ 'status' 'errorCode'
                StatusFailureReason              = Get-NestedPropertyValue $_ 'status' 'failureReason'
                CorrelationId                    = Get-PropertyValue $_ 'correlationId'
                ClientCredentialType             = Get-PropertyValue $_ 'clientCredentialType'
                ServicePrincipalCredentialKeyId  = Get-PropertyValue $_ 'servicePrincipalCredentialKeyId'
                CredentialThumbprint             = Get-PropertyValue $_ 'servicePrincipalCredentialThumbprint'
            }
        }
    }

    function Get-EventOutcomeCounts {
        param($Events)

        $successCount = ($Events | Where-Object { $_.StatusErrorCode -eq 0 }).Count
        $failureCount = $Events.Count - $successCount

        [pscustomobject]@{
            Success = $successCount
            Failure = $failureCount
        }
    }

    function Test-VerifiedEvent {
        param($Event)

        if (-not $Event.CreatedDateTime) {
            return $false
        }

        $hasIp       = -not [string]::IsNullOrWhiteSpace([string]$Event.IpAddress)
        $hasStatus   = ($null -ne $Event.StatusErrorCode -and [string]$Event.StatusErrorCode -ne "")
        $hasResource = -not [string]::IsNullOrWhiteSpace([string]$Event.ResourceDisplayName)

        return ($hasIp -or $hasStatus -or $hasResource)
    }

    function Get-ExpectedCredentialLogType {
        param([string]$CredentialType)

        switch ($CredentialType) {
            "Certificate" { return "certificate" }
            "Secret"      { return "clientSecret" }
            default       { return $null }
        }
    }

    function Get-CredentialHits {
        param(
            [Parameter(Mandatory)]
            [string]$CredentialId,

            [Parameter(Mandatory)]
            [string]$CredentialType,

            [Parameter(Mandatory)]
            [array]$SignIns
        )

        if ([string]::IsNullOrWhiteSpace($CredentialId)) {
            return @()
        }

        $expectedLogType = Get-ExpectedCredentialLogType -CredentialType $CredentialType
        $matches = New-Object System.Collections.Generic.List[object]

        foreach ($event in $SignIns) {
            $isMatch = $false

            $eventKeyId = Get-PropertyValue -Object $event -Name 'servicePrincipalCredentialKeyId'
            if ($eventKeyId) {
                if ($eventKeyId.ToString() -ieq $CredentialId) {
                    $isMatch = $true
                }
            }
            else {
                try {
                    $json = $event | ConvertTo-Json -Depth 60 -Compress
                    if ($json -and ($json -match [regex]::Escape($CredentialId))) {
                        $isMatch = $true
                    }
                }
                catch {
                    continue
                }
            }

            if (-not $isMatch) {
                continue
            }

            $matches.Add($event)
        }

        return $matches
    }

    Connect-MgGraph -Scopes "AuditLog.Read.All", "Application.Read.All" | Out-Null

    $app = Get-MgApplication -Filter "appId eq '$AppId'" -Property "id,appId,displayName,keyCredentials,passwordCredentials" -ErrorAction Stop
    $appName = $app.DisplayName

    $credentials = @()

    foreach ($certificate in ($app.KeyCredentials | Where-Object { $_ })) {
        $credentials += [pscustomobject]@{
            CredentialType = "Certificate"
            CredentialId   = Convert-ToGuidString $certificate.KeyId
            DisplayName    = $certificate.DisplayName
            StartDateTime  = $certificate.StartDateTime
            EndDateTime    = $certificate.EndDateTime
        }
    }

    foreach ($secret in ($app.PasswordCredentials | Where-Object { $_ })) {
        $credentials += [pscustomobject]@{
            CredentialType = "Secret"
            CredentialId   = Convert-ToGuidString $secret.KeyId
            DisplayName    = $secret.DisplayName
            StartDateTime  = $secret.StartDateTime
            EndDateTime    = $secret.EndDateTime
        }
    }

    $since = Get-UtcSinceIso -Days $DaysBack
    $uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=" +
           "appId eq '$AppId' and createdDateTime ge $since and signInEventTypes/any(t:t eq 'servicePrincipal')"

    $signIns = @(Get-GraphPaged -Uri $uri | Where-Object { $_ -ne $null })

    Write-Host ""
    Write-Host "=== App Sign-In Scope ==="
    Write-Host "Application : $appName"
    Write-Host "AppId       : $AppId"
    Write-Host "Since (UTC) : $since"
    Write-Host "Sign-ins    : $($signIns.Count)"
    Write-Host ""

    $targetCredentialId = $null
    $targetCredentialType = $null

    if (-not [string]::IsNullOrWhiteSpace($CertificateId)) {
        $targetCredentialId = $CertificateId
        $targetCredentialType = "Certificate"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SecretId)) {
        $targetCredentialId = $SecretId
        $targetCredentialType = "Secret"
    }

    if (-not [string]::IsNullOrWhiteSpace($targetCredentialId)) {
        if (-not (Test-GuidLike -Value $targetCredentialId)) {
            Write-Warning "$targetCredentialType ID does not look like a GUID. Continuing anyway."
        }

        $credential = $credentials | Where-Object {
            $_.CredentialType -eq $targetCredentialType -and $_.CredentialId -eq $targetCredentialId
        } | Select-Object -First 1

        if (-not $credential) {
            Write-Warning "$targetCredentialType ID was not found in the current app registration."
            $credential = [pscustomobject]@{
                CredentialType = $targetCredentialType
                CredentialId   = $targetCredentialId
                DisplayName    = "(not found in app object)"
                StartDateTime  = $null
                EndDateTime    = $null
            }
        }

        $rawHits = @(Get-CredentialHits -CredentialId $targetCredentialId -CredentialType $targetCredentialType -SignIns $signIns)
        $normalizedHits = @(Normalize-SignInEvents -Events $rawHits)

        $verifiedHits = @($normalizedHits | Where-Object { Test-VerifiedEvent $_ })
        $suspectMatches = @($normalizedHits | Where-Object { -not (Test-VerifiedEvent $_) })

        $outcomes = Get-EventOutcomeCounts -Events $verifiedHits

        Write-Host "=== Credential Drill-Down ==="
        [pscustomobject]@{
            AppName          = $appName
            AppId            = $AppId
            CredentialType   = $credential.CredentialType
            CredentialId     = $credential.CredentialId
            DisplayName      = $credential.DisplayName
            StartDateTime    = $credential.StartDateTime
            EndDateTime      = $credential.EndDateTime
            ExpectedLogType  = Get-ExpectedCredentialLogType -CredentialType $credential.CredentialType
            VerifiedHits     = $verifiedHits.Count
            SuccessHits      = $outcomes.Success
            FailureHits      = $outcomes.Failure
            SuspectMatches   = $suspectMatches.Count
            FirstHitUtc      = if ($verifiedHits.Count) { ($verifiedHits | Sort-Object CreatedDateTime | Select-Object -First 1).CreatedDateTime } else { $null }
            LastHitUtc       = if ($verifiedHits.Count) { ($verifiedHits | Sort-Object CreatedDateTime -Descending | Select-Object -First 1).CreatedDateTime } else { $null }
        } | Format-List | Out-Host

        "`nSummary: VerifiedHits=$($verifiedHits.Count) | Success=$($outcomes.Success) | Failure=$($outcomes.Failure) | SuspectMatches=$($suspectMatches.Count)`n" | Out-Host

        if ($verifiedHits.Count -gt 0) {
            Write-Host "Top Source IPs"
            $verifiedHits |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_.IpAddress) } |
                Group-Object IpAddress |
                Sort-Object Count -Descending |
                Select-Object -First 20 |
                Select-Object @{n='IpAddress';e={$_.Name}}, @{n='Count';e={$_.Count}} |
                Format-Table -AutoSize | Out-Host

            Write-Host "`nCredential Type Seen In Logs"
            $verifiedHits |
                Group-Object ClientCredentialType |
                Sort-Object Count -Descending |
                Select-Object @{n='ClientCredentialType';e={$_.Name}}, @{n='Count';e={$_.Count}} |
                Format-Table -AutoSize | Out-Host

            Write-Host "`nStatus Breakdown"
            $verifiedHits |
                Group-Object StatusErrorCode |
                Sort-Object Count -Descending |
                Select-Object @{n='StatusErrorCode';e={$_.Name}}, @{n='Count';e={$_.Count}} |
                Format-Table -AutoSize | Out-Host

            Write-Host "`nLatest Matching Sign-Ins"
            $verifiedHits |
                Sort-Object CreatedDateTime -Descending |
                Select-Object -First 20 |
                Format-Table CreatedDateTime, IpAddress, ResourceDisplayName, ClientCredentialType, StatusErrorCode -AutoSize | Out-Host
        }
        else {
            Write-Host "No verified sign-in events were found for this credential in the selected time window."
            if ($suspectMatches.Count -gt 0) {
                Write-Warning "Some suspect matches were found, but they lack useful attribution fields."
            }
        }

        if ($Export) {
            if (-not (Test-Path $ExportFolder)) {
                New-Item -ItemType Directory -Path $ExportFolder | Out-Null
            }

            $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
            $safeAppName = Get-SafeFileNamePart -Value $appName

            if ($verifiedHits.Count -gt 0) {
                $csvPath = Join-Path $ExportFolder "credential_hits_${safeAppName}_${credential.CredentialType}_$timestamp.csv"
                $verifiedHits | Export-Csv -NoTypeInformation -Encoding UTF8 $csvPath
                Write-Host ""
                Write-Host "Export created:"
                Write-Host " - $csvPath"
            }
            else {
                Write-Host ""
                Write-Host "Export note: no CSV created because there were no verified hits."
            }

            if ($suspectMatches.Count -gt 0 -and $rawHits.Count -gt 0) {
                $suspectRawEvents = @()

                foreach ($rawEvent in $rawHits) {
                    $normalized = Normalize-SignInEvents -Events @($rawEvent) | Select-Object -First 1
                    if ($normalized -and -not (Test-VerifiedEvent $normalized)) {
                        $suspectRawEvents += $rawEvent
                    }
                }

                if ($suspectRawEvents.Count -gt 0) {
                    $jsonPath = Join-Path $ExportFolder "credential_suspects_${safeAppName}_${credential.CredentialType}_$timestamp.json"
                    $suspectRawEvents | ConvertTo-Json -Depth 60 | Out-File -Encoding UTF8 $jsonPath
                    Write-Host " - $jsonPath (suspect raw events)"
                }
            }
        }

        return
    }

    Write-Host "=== App Credential Inventory ==="
    Write-Host "Credentials found: $($credentials.Count)"
    Write-Host ""

    if ($credentials.Count -eq 0) {
        Write-Host "No certificates or secrets were found on this app registration."
        return
    }

    $invalidIds = $credentials | Where-Object { [string]::IsNullOrWhiteSpace($_.CredentialId) }
    if ($invalidIds.Count -gt 0) {
        Write-Warning "Some credentials have an empty or invalid Key ID and will be skipped during matching."
    }

    $credentials |
        Sort-Object CredentialType, EndDateTime |
        Format-Table CredentialType, CredentialId, DisplayName, StartDateTime, EndDateTime -AutoSize | Out-Host

    Write-Host "`n=== Credential Usage Overview ==="

    $usage = foreach ($credential in ($credentials | Where-Object { -not [string]::IsNullOrWhiteSpace($_.CredentialId) })) {
        $rawHits = @(Get-CredentialHits -CredentialId $credential.CredentialId -CredentialType $credential.CredentialType -SignIns $signIns)
        $normalizedHits = @(Normalize-SignInEvents -Events $rawHits)

        $verifiedHits = @($normalizedHits | Where-Object { Test-VerifiedEvent $_ })
        $suspectMatches = @($normalizedHits | Where-Object { -not (Test-VerifiedEvent $_) })

        $outcomes = Get-EventOutcomeCounts -Events $verifiedHits

        $topIp = $verifiedHits |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.IpAddress) } |
            Group-Object IpAddress |
            Sort-Object Count -Descending |
            Select-Object -First 1

        $topLogType = $verifiedHits |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.ClientCredentialType) } |
            Group-Object ClientCredentialType |
            Sort-Object Count -Descending |
            Select-Object -First 1

        [pscustomobject]@{
            CredentialType   = $credential.CredentialType
            CredentialId     = $credential.CredentialId
            DisplayName      = $credential.DisplayName
            EndDateTime      = $credential.EndDateTime
            VerifiedHits     = $verifiedHits.Count
            SuccessHits      = $outcomes.Success
            FailureHits      = $outcomes.Failure
            SuspectMatches   = $suspectMatches.Count
            TopIpAddress     = $topIp.Name
            TopLogType       = $topLogType.Name
        }
    }

    $usage |
        Sort-Object `
            @{Expression='VerifiedHits'; Descending=$true}, `
            @{Expression='CredentialType'; Descending=$false}, `
            @{Expression='EndDateTime'; Descending=$false} |
        Format-Table CredentialType, CredentialId, DisplayName, EndDateTime, VerifiedHits, SuccessHits, FailureHits, SuspectMatches, TopIpAddress, TopLogType -AutoSize | Out-Host

    $activeCredentials = $usage | Where-Object { $_.VerifiedHits -gt 0 }

    Write-Host ""
    Write-Host "Active credentials in this window: $($activeCredentials.Count)"
    if ($activeCredentials.Count -gt 0) {
        Write-Host "Tip: use -CertificateId or -SecretId to inspect one credential in detail."
    }

    if ($Export) {
        if (-not (Test-Path $ExportFolder)) {
            New-Item -ItemType Directory -Path $ExportFolder | Out-Null
        }

        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $safeAppName = Get-SafeFileNamePart -Value $appName
        $csvPath = Join-Path $ExportFolder "credential_usage_${safeAppName}_$timestamp.csv"

        $usage | Export-Csv -NoTypeInformation -Encoding UTF8 $csvPath

        Write-Host ""
        Write-Host "Export created:"
        Write-Host " - $csvPath"
    }
}

Get-AppCredentialUsage `
    -AppId $AppId `
    -CertificateId $CertificateId `
    -SecretId $SecretId `
    -DaysBack $DaysBack `
    -Export:$Export `
    -ExportFolder $ExportFolder