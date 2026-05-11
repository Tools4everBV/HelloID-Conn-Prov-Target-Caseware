#################################################
# HelloID-Conn-Prov-Target-Caseware-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-CasewareError {
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
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($httpErrorObj.ErrorDetails)]"
            Write-Warning $_.Exception.Message
        }
        Write-Output $httpErrorObj
    }
}

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        $CaseWareAccountObject
    )
    $helloIDAccountObject = [PSCustomObject]@{
        LastName   = $CaseWareAccountObject.LastName
        FirstName  = $CaseWareAccountObject.FirstName
        MiddleName = $CaseWareAccountObject.MiddleName
        Email      = $CaseWareAccountObject.Email
        Title      = $CaseWareAccountObject.Title
        CWGuid     = $CaseWareAccountObject.CWGuid
        OwnerType  = $CaseWareAccountObject.OwnerType
   
    }
    Write-Output $helloIDAccountObject
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    Write-Information 'Retrieving bearer token'
    $splatRetrieveTokenParams = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/auth/token"
        Method      = 'POST'
        ContentType = 'application/json'
        Body        = @{
            ClientId     = $($actionContext.Configuration.ClientId)
            ClientSecret = $($actionContext.Configuration.ClientSecret)
            Language     = 'en'
        } | ConvertTo-Json
    }
    $responseToken = Invoke-RestMethod @splatRetrieveTokenParams

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Try to correlate existing account
        $queryUri = ("$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users?search=" + ([System.Web.HTTPUtility]::UrlEncode("Email='$($correlationValue)'")));
        $splatRestParams = @{
            Uri     = $queryUri
            Method  = 'GET'
            Headers = @{
                Authorization = "Bearer $($responseToken.Token)"
            }
        }
        $response = Invoke-RestMethod @splatRestParams
        $correlatedAccount = $null
        if ($response) {
            $correlatedAccount = ConvertTo-HelloIDAccountObject -CaseWareAccountObject $response | Select-Object -First 1
        }

        if (-not $correlatedAccount) {
            # Account not found, create new account
            $action = 'CreateAccount'
        }
        elseif ($correlatedAccount -is [array] -and $correlatedAccount.Count -gt 1) {
            throw "Multiple accounts found for person where email address is: [$correlationValue]"
        }
        else {
            $action = 'CorrelateAccount'
        }
    }
    else {
        throw 'Correlation must be enabled for this connector to work'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users"
                Method = 'POST'
                Headers = @{
                    Authorization = "Bearer $($responseToken.Token)"
                    'Content-Type' = 'application/json'
                }
                Body   = $actionContext.Data | ConvertTo-Json
            }
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Caseware account'
                $createdAccount = Invoke-RestMethod @splatCreateParams
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.CWGuid
                $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            } else {
                Write-Information '[DryRun] Create and correlate Caseware account, will be executed during enforcement'
                $auditLogMessage = "DryRun: Create account would be executed."
            }
            break
        }
        'CorrelateAccount' {
            Write-Information 'Correlating Caseware account'
            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.CWGuid
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Action  = $action
        Message = $auditLogMessage
        IsError = $false
    })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate Caseware account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line).Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate Caseware account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditLogMessage
        IsError = $true
    })
}
