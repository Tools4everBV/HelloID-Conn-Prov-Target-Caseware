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
        $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
        $httpErrorObj.FriendlyMessage = ($errorDetailsObject.errors | Select-Object -First 1).message
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

        # Determine if the user account can be correlated
        $queryUri = ("$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users?search=" + ([System.Web.HTTPUtility]::UrlEncode("Email='$($correlationValue)'")));
        $splatRestParams = @{
            Uri     = $queryUri
            Method  = 'GET'
            Headers = @{
                Authorization = "Bearer $($responseToken.Token)"
            }
        }
        $response = Invoke-RestMethod @splatRestParams
        $correlatedAccount = ConvertTo-HelloIDAccountObject -CaseWareAccountObject $response | Select-Object -First 1
        if (-not $correlatedAccount) {
            throw "An account with email address: [$correlationValue] could not be found."
        }
        elseif ($correlatedAccount -is [array] -and $correlatedAccount.Count -gt 1) {
            throw "Multiple accounts found for person where email address is: [$correlationValue]"
        }
    }
    else {
        throw 'Correlation must be enabled for this connector to work'
    }

    # Process
    Write-Information 'Correlating Caseware account'
    $outputContext.Data = $correlatedAccount
    $outputContext.AccountReference = $correlatedAccount.CWGuid
    $outputContext.AccountCorrelated = $true

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Caseware account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create or correlate Caseware account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}