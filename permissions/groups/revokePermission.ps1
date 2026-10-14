################################################################
# HelloID-Conn-Prov-Target-Caseware-RevokePermission-Group
# PowerShell V2
################################################################

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
            $httpErrorObj.FriendlyMessage = ($errorDetailsObject.errors | Select-Object -First 1).message
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails 
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    #Retrieving token
    Write-Information 'Retrieving bearer token'

    $maxRetry = 10
    $retryCount = 0

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

    do {
        try {
            $retryCount++
            $responseToken = Invoke-RestMethod @splatRetrieveTokenParams
        }
        catch {
            #wait 3 seconds before retry
            if ($_.exception.response.statuscode -eq "429") {
                start-sleep 3
            }
            else {
                throw "$($_)"
            }
        }
    } until (
        #Retry x times or until responsetoken is returned
        ($retryCount -gt $maxRetry) -OR ($null -ne $responseToken)
    )        

    #Throw error when failed within max retries
    if ($null -eq $responseToken) {
        Throw "Failed to retrieve bearer token after $retryCount retries."
    }

    Write-Information 'Verifying if a Caseware account exists'
    $splatRestParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = @{
            Authorization = "Bearer $($responseToken.Token)"
        }
    }
    try{
        $correlatedAccount = Invoke-RestMethod @splatRestParams
    }catch{
        if ($_.exception.response.statuscode -eq "404") {
            $correlatedAccount = $null
        }
        else {
            throw "$($_)"
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'RevokePermission'
    }
    else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'RevokePermission' {
            if (-not($actionContext.DryRun -eq $True)) {
                try {
                    Write-Information "Revoking Caseware permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)]"
                    $peoplearraylist = @($actionContext.References.Account)
                    $splatRestParams = @{
                        Uri         = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/groups/$($actionContext.References.Permission.Reference)/user-assignments"
                        Method      = 'PATCH'
                        Body        = @{
                            isRemove = $true
                            people   = $peoplearraylist
                        } | ConvertTo-Json
                        ContentType = 'application/json'
                        Headers     = @{
                            Authorization = "Bearer $($responseToken.Token)"
                        }
                    }
                    $null = Invoke-RestMethod @splatRestParams 
                  

                    $outputContext.Success = $true
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Revoke permission [$($actionContext.PermissionDisplayName)] was successful"
                            IsError = $false
                        })

                }
                catch {
                    if ($_.Exception.Response.StatusCode -eq 404) {
                        $outputContext.Success = $true
                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Message = "Revoke permission [$($actionContext.PermissionDisplayName)] was already Revokeed."
                                IsError = $false
                            })
                    }
                    else {
                        throw $_
                    }  
                }
            }   else {
                        Write-Information "[DryRun] Revoke Caseware permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)], will be executed during enforcement"
                          $outputContext.Success = $true
                          $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Message = "Revoke permission [$($actionContext.PermissionDisplayName)] will be Revokeed."
                                IsError = $false
                            })
                    }
        }

        'NotFound' {
            Write-Information "Caseware account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Caseware account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        $auditMessage = "Could not Revoke Caseware permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not Revoke Caseware permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}