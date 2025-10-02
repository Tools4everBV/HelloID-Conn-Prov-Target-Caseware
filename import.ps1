#################################################
# HelloID-Conn-Prov-Target-Caseware-Import
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
#endregion
try {
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
    $pageSize = 50
    $page = 1
    Write-Information "Starting Caseware account entitlement import with pagesize set to: $($pageSize)"
    do {
        Write-Information "Getting page: $page"
        $splatRestParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users?pageSize=$pageSize&page=$page"
            Method  = 'GET'
            Headers = @{
                Authorization = "Bearer $($responseToken.Token)"
            }
        }
        $response = Invoke-RestMethod @splatRestParams
        if ($null -ne $response -and $response.Count -gt 0) {
            foreach ($importedAccount in $response) {
                # Making sure only fieldMapping fields are imported
                $data = @{}
                foreach ($field in $actionContext.ImportFields) {
                    $data[$field] = $importedAccount.$field
                }
                # Set Enabled based on importedAccount status
                $isEnabled = $false
                if ($importedAccount.CanLogin -eq $true) {
                    $isEnabled = $true
                }

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.FirstName) $($importedAccount.LastName)".trim()
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.Email
                }

                # Make sure the userName has a value
                if ([string]::IsNullOrEmpty($importedAccount.UserName)) {
                    $importedAccount.UserName = $importedAccount.CWGuid
                }

                # Return the result
                Write-Output @{
                    AccountReference = $importedAccount.CWGuid
                    displayName      = $displayName
                    UserName         = $importedAccount.UserName
                    Enabled          = $isEnabled
                    Data             = $data
                }
            }

            $page++
        }
        else {
            break
        }
    } while ($true)
    Write-Information "Caseware account entitlement import completed. Total accounts imported: $($importedAccounts.Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Caseware account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Caseware account entitlements. Error: $($ex.Exception.Message)"
    }
}