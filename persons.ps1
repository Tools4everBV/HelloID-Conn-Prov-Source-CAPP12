##################################################
# HelloID-Conn-Prov-Source-CAPP12-Persons
#
# Version: 1.0.0
##################################################
# Initialize default value's

$config = $configuration | ConvertFrom-Json
# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Get-Capp12AuthorizationTokenAndCreateHeaders {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]
        $Configuration = $config        
    )
    try {
        Write-Information 'Creating Access Token'
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

        $accessToken = Invoke-RestMethod @splatInvoke

        Write-Information 'Adding Authorization headers'
        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add('Authorization', "$($accessToken.token_type) $($accessToken.access_token)")
        $headers.Add('Accept', 'text/csv')
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
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.error
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}

function ConvertTo-Date() {
    [CmdletBinding()]
    param(
        [String]
        $datefield
    )
    if ([string]::IsNullOrEmpty($datefield)) { $null }
    else {
        $culture = [Globalization.CultureInfo]::InvariantCulture    
        
        [datetime]::ParseExact($datefield, 'yyyy-MM-dd HH:mm:ss', $culture).ToUniversalTime()
    }
}
#endregion

try {

    $historicalDate = (Get-Date).ToUniversalTime().AddDays( - $($config.HistoricalDays))       
    $headers = Get-Capp12AuthorizationTokenAndCreateHeaders -Configuration $config
    
    $splatGetPersons = @{
        Uri     = "$($config.BaseUrl)/api/v1/users"
        Headers = $headers
        Method  = 'GET'
    } 

    $Users = Invoke-RestMethod @splatGetPersons -Verbose:$false | ConvertFrom-Csv -Delimiter ';'
    $splatGetComplianceStatus = @{
        Uri     = "$($config.BaseUrl)/api/v3/compliance_status.csv"
        Headers = $headers
        Method  = 'GET'
    } 

    $ComplianceStatusList = Invoke-RestMethod @splatGetComplianceStatus -Verbose:$false | ConvertFrom-Csv -Delimiter ';'
    [System.Collections.Generic.SortedList[string, System.Collections.Generic.List[object]]]$UserCompliance = [System.Collections.Generic.SortedList[string, System.Collections.Generic.List[object]]]::new()
   
    foreach ($ComplianceStatus in $ComplianceStatusList) {
        if ($null -ne $ComplianceStatus.user_code) {

            $complianceExpirationDate = ConvertTo-Date($ComplianceStatus.valid_until)

            if (($null -eq $complianceExpirationDate) -or ($complianceExpirationDate -ge $historicalDate)) {                
                if (-not $UserCompliance.ContainsKey($ComplianceStatus.user_code)) {
                    $UserCompliance.Add($ComplianceStatus.user_code, [System.Collections.Generic.List[object]]::new())
                }
                $ComplianceStatus | Add-Member -NotePropertyMembers @{ ExternalId = "$($ComplianceStatus.user_code)-$($ComplianceStatus.certificate_code)" }
                $UserCompliance[$ComplianceStatus.user_code].Add($ComplianceStatus)  
            }     
        }
    }
    if ($Config.RequiredCertificatesOnly -eq $false) {
    
        $splatGetAchievementStatus = @{
            Uri     = "$($config.BaseUrl)/api/v3/achievement_status.csv"
            Headers = $headers
            Method  = 'GET'
        } 
        $AchievementStatusList = Invoke-RestMethod @splatGetAchievementStatus -Verbose:$false | ConvertFrom-Csv -Delimiter ';'
        foreach ($AchievementStatus in $AchievementStatusList) {
            if ($null -ne $AchievementStatus.user_code) {               

                $achievementExpirationDate = ConvertTo-Date($AchievementStatus.valid_until)

                if (($null -eq $achievementExpirationDate) -or ($achievementExpirationDate -ge $historicalDate)) {                
                    if (-not $UserCompliance.ContainsKey($AchievementStatus.user_code)) {
                        $UserCompliance.Add($AchievementStatus.user_code, [System.Collections.Generic.List[object]]::new())
                    }
                    if (-not ($UserCompliance[$AchievementStatus.user_code].certificate_code -contains $AchievementStatus.certificate_code)) {
                        $AchievementStatus | Add-Member -NotePropertyMembers @{ ExternalId = "$($AchievementStatus.user_code)-$($AchievementStatus.certificate_code)" }
                        $UserCompliance[$AchievementStatus.user_code].Add($AchievementStatus)  
                    }
                }
            }
        }
    }
   
    foreach ($User in $Users) {       
       
        $person = $User
        $person | Add-Member -NotePropertyMembers @{ DisplayName = "$($User.first_name) $($User.last_name)".trim(' ') }
        $person | Add-Member -NotePropertyMembers @{ ExternalId = $User.code }        
        $person | Add-Member -NotePropertyMembers @{ Contracts = [System.Collections.Generic.List[Object]]::new() }      
        if ($null -ne $User.code) {
            [System.Collections.Generic.List[object]] $complianceStatusForUser = $UserCompliance[$User.code]       
            if ($null -ne $complianceStatusForUser) {

                $person.Contracts.AddRange($complianceStatusForUser)
                Write-Output $person | ConvertTo-Json -Depth 10    
            }
        }   
    }
        
    
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CAPP12Error -ErrorObject $ex
        Write-Verbose "Could not import $Name persons. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import $Name persons. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Verbose "Could not import $Name persons. Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import $Name persons. Error: $($ex.Exception.Message )"
    }
}
    