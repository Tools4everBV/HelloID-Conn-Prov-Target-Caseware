##################################################
# HelloID-Conn-Prov-Target-Caseware-Delete
# PowerShell V2
##################################################

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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

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

    Write-Information 'Verifying if a Caseware account exists'
    $splatRestParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = @{
            Authorization = "Bearer $($responseToken.Token)"
        }
    }
    $correlatedAccount = Invoke-RestMethod @splatRestParams

    if ($null -ne $correlatedAccount) {
        $action = 'DeleteAccount'
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'DeleteAccount' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Deleting Caseware account with accountReference: [$($actionContext.References.Account)]"
                $splatRestParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users/$($actionContext.References.Account)"
                    Method  = 'DELETE'
                    Headers = @{
                        Authorization = "Bearer $($responseToken.Token)"
                    }
                }
                $null = Invoke-RestMethod @splatRestParams
            } else {
                Write-Information "[DryRun] Delete Caseware account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Delete account [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Caseware account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Caseware account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        $auditMessage = "Could not delete Caseware account. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not delete Caseware account. Error: $($_.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}