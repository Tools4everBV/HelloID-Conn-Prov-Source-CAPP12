##################################################
# HelloID-Conn-Prov-Source-CAPP12-Persons
#
# Version: 1.0.0
##################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

#region functions
function Get-Capp12AuthorizationTokenAndCreateHeaders {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]
        $Configuration
    )
    try {
        Write-Verbose 'Creating Access Token'
        $authorizationBody = @{
            grant_type                = 'client_credentials'
            client_id                 = $Configuration.ClientId
            client_secret             = $Configuration.ClientSecret
            token_expiration_disabled = $false
        }
        $splatInvoke = @{
            Uri         = "$($Configuration.BaseUrl)/oauth2/token"
            Method      = 'POST'
            ContentType = 'application/json'
            Body        = $authorizationBody | ConvertTo-Json -Depth 10
        }

        $accessToken = Invoke-RestMethod @splatInvoke -Verbose:$false

        Write-Verbose 'Adding Authorization headers'
        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add('Authorization', "$($accessToken.token_type) $($accessToken.access_token)")
        $headers.Add('Accept', 'application/json,text/csv')
        $headers.Add('Content-Type', 'application/json')

        Write-Output $headers
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-CAPP12Error {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.error
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function ConvertTo-Date {
    [CmdletBinding()]
    param(
        [String]
        $datefield
    )
    if ([string]::IsNullOrEmpty($datefield)) { 
        $null 
    }
    else {
        $culture = [Globalization.CultureInfo]::InvariantCulture    
        [datetime]::ParseExact($datefield, 'yyyy-MM-dd HH:mm:ss', $culture).ToUniversalTime()
    }
}
#endregion functions

Write-Information "Starting person import. Base URL: $($config.BaseUrl)"

# Parse include certificate codes (whitelist)
$includeCertificates = @{}
$includeCertificatesEnabled = $false
if (-not [string]::IsNullOrWhiteSpace($config.IncludeCertificateCodes)) {
    $includeList = $config.IncludeCertificateCodes -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($code in $includeList) {
        $includeCertificates[$code] = $true
    }
    $includeCertificatesEnabled = $true
    Write-Information "Certificate include filter enabled: Only $($includeCertificates.Count) certificate code(s) will be imported (whitelist)"
}

try {
    # Query users
    $actionMessage = "querying users at [$($config.BaseUrl)/api/v1/users]"
    $headers = Get-Capp12AuthorizationTokenAndCreateHeaders -Configuration $config
    
    $splatGetPersons = @{
        Uri     = "$($config.BaseUrl)/api/v1/users"
        Headers = $headers
        Method  = 'GET'
    }
    $usersList = Invoke-RestMethod @splatGetPersons -Verbose:$false | ConvertFrom-Csv -Delimiter ';'

    # Make sure users are unique
    $users = $usersList | Where-Object { $_.code -ne $null } | Sort-Object code -Unique
    Write-Information "Queried users. Result: $(@($users).Count)"

    # Query compliance status
    $actionMessage = "querying compliance status at [$($config.BaseUrl)/api/v3/compliance_status.csv]"
    $splatGetComplianceStatus = @{
        Uri     = "$($config.BaseUrl)/api/v3/compliance_status.csv"
        Headers = $headers
        Method  = 'GET'
    } 
    $complianceStatusList = Invoke-RestMethod @splatGetComplianceStatus -Verbose:$false | ConvertFrom-Csv -Delimiter ';'
    Write-Information "Queried compliance status (required). Result: $(@($complianceStatusList).Count)"

    # Query achievement status (always needed for compliance checking)
    $actionMessage = "querying achievement status at [$($config.BaseUrl)/api/v3/achievement_status.csv]"
    $splatGetAchievementStatus = @{
        Uri     = "$($config.BaseUrl)/api/v3/achievement_status.csv"
        Headers = $headers
        Method  = 'GET'
    } 
    $achievementStatusList = Invoke-RestMethod @splatGetAchievementStatus -Verbose:$false | ConvertFrom-Csv -Delimiter ';'
    Write-Information "Queried achievement status (all). Result: $(@($achievementStatusList).Count)"
    
    if ($config.CompliantCertificatesOnly -eq $true) {
        Write-Information "Filtering enabled: Only compliant certificates (Required & Achieved) will be imported"
    }
    elseif ($config.RequiredCertificatesOnly -eq $true) {
        Write-Information "Filtering enabled: Only required certificates will be imported"
    }

    # Process compliance and achievement data
    $actionMessage = "processing compliance and achievement data"
    $historicalDate = (Get-Date).ToUniversalTime().AddDays( - $($config.HistoricalDays))
    [System.Collections.Generic.SortedList[string, System.Collections.Generic.List[object]]]$userCompliance = [System.Collections.Generic.SortedList[string, System.Collections.Generic.List[object]]]::new()
    
    # Build lookup for achieved certificates
    # IMPORTANT: NO historical filtering applied here!
    # Reason: A required certificate within historical days that was achieved (even if that achievement is now expired)
    #         should still be considered compliant. We only filter required certificates on historical date.
    # Example: Required cert expires 50 days ago (within 60 days) + Achievement expires 70 days ago (outside 60 days)
    #          = Still compliant (was achieved), so should be exported if CompliantCertificatesOnly is enabled
    $achievementLookup = @{}
    foreach ($achievementStatus in $achievementStatusList) {
        if ($null -ne $achievementStatus.user_code) {
            $key = "$($achievementStatus.user_code)|$($achievementStatus.certificate_code)"
            if (-not $achievementLookup.ContainsKey($key)) {
                $achievementLookup[$key] = $achievementStatus
            }
        }
    }
   
    foreach ($complianceStatus in $complianceStatusList) {
        if ($null -ne $complianceStatus.user_code) {
            # Skip certificate codes not in the include list (if whitelist is enabled)
            if ($includeCertificatesEnabled -and -not $includeCertificates.ContainsKey($complianceStatus.certificate_code)) {
                continue
            }
            
            $complianceExpirationDate = ConvertTo-Date($complianceStatus.valid_until)

            # Only process required certificates within historical days
            if (($null -eq $complianceExpirationDate) -or ($complianceExpirationDate -ge $historicalDate)) {
                # Check if this required certificate is also achieved (compliant)
                # Compliant = certificate exists in both compliance_status AND achievement_status
                # Note: Achievement may be expired, but still counts as compliant if it was achieved
                $key = "$($complianceStatus.user_code)|$($complianceStatus.certificate_code)"
                $isCompliant = $achievementLookup.ContainsKey($key)
                
                # Skip non-compliant certificates (required but NOT achieved) if CompliantCertificatesOnly is enabled
                if ($config.CompliantCertificatesOnly -eq $true -and -not $isCompliant) {
                    continue
                }
                
                if (-not $userCompliance.ContainsKey($complianceStatus.user_code)) {
                    $userCompliance.Add($complianceStatus.user_code, [System.Collections.Generic.List[object]]::new())
                }
                $complianceStatus | Add-Member -NotePropertyMembers @{ ExternalId = "$($complianceStatus.user_code)-$($complianceStatus.certificate_code)" }
                $userCompliance[$complianceStatus.user_code].Add($complianceStatus)  
            }     
        }
    }

    if ($config.RequiredCertificatesOnly -eq $false -and $config.CompliantCertificatesOnly -eq $false) {
        foreach ($achievementStatus in $achievementStatusList) {
            if ($null -ne $achievementStatus.user_code) {
                # Skip certificate codes not in the include list (if whitelist is enabled)
                if ($includeCertificatesEnabled -and -not $includeCertificates.ContainsKey($achievementStatus.certificate_code)) {
                    continue
                }
                
                $achievementExpirationDate = ConvertTo-Date($achievementStatus.valid_until)

                if (($null -eq $achievementExpirationDate) -or ($achievementExpirationDate -ge $historicalDate)) {                
                    if (-not $userCompliance.ContainsKey($achievementStatus.user_code)) {
                        $userCompliance.Add($achievementStatus.user_code, [System.Collections.Generic.List[object]]::new())
                    }
                    if (-not ($userCompliance[$achievementStatus.user_code].certificate_code -contains $achievementStatus.certificate_code)) {
                        $achievementStatus | Add-Member -NotePropertyMembers @{ ExternalId = "$($achievementStatus.user_code)-$($achievementStatus.certificate_code)" }
                        $userCompliance[$achievementStatus.user_code].Add($achievementStatus)  
                    }
                }
            }
        }
    }
    Write-Information "Processed compliance and achievement data"

    # Enhance and export person objects to HelloID
    $actionMessage = "enhancing and exporting person objects to HelloID"
    
    # Set counter to keep track of actual exported person objects and certificates
    $exportedPersons = 0
    $exportedCertificates = 0
    $certificateCounts = @{}

    # Enhance the users model with required properties
    $users | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $users | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force
    $users | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force

    foreach ($user in $users) {
        $actionMessage = "enhancing and exporting person with code [$($user.code)]"
        
        # Set required fields for HelloID
        $user.ExternalId = $user.code
        $user.DisplayName = "$($user.first_name) $($user.last_name) ($($user.ExternalId))"
        
        # Create contracts object
        $user.Contracts = [System.Collections.Generic.List[Object]]::new()
        
        if ($null -ne $user.code) {
            [System.Collections.Generic.List[object]]$complianceStatusForUser = $userCompliance[$user.code]
            
            if ($null -ne $complianceStatusForUser) {
                $user.Contracts.AddRange($complianceStatusForUser)
                
                # Sanitize and export the json
                $person = $user | ConvertTo-Json -Depth 10
                $person = $person.Replace("._", "__")
                Write-Output $person
                
                # Update counters to keep track of actual exported person objects and certificates
                $exportedPersons++
                $certificateCount = $complianceStatusForUser.Count
                $exportedCertificates += $certificateCount
                $certificateCounts[$user.code] = $certificateCount
            }
        }
    }

    # Calculate statistics
    $averageCertificates = if ($exportedPersons -gt 0) { [math]::Round($exportedCertificates / $exportedPersons, 2) } else { 0 }
    $maxCertificates = if ($certificateCounts.Count -gt 0) { ($certificateCounts.Values | Measure-Object -Maximum).Maximum } else { 0 }

    Write-Information "Enhanced and exported person objects to HelloID. Total persons: $exportedPersons | Total certificates: $exportedCertificates | Average per person: $averageCertificates | Max per person: $maxCertificates"
    Write-Information "Person import completed"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CAPP12Error -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    
    Write-Warning $warningMessage
    throw $auditMessage
}