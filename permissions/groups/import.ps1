####################################################################
# HelloID-Conn-Prov-Target-Caseware-Permissions-Groups-Import
# PowerShell V2
####################################################################

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

try {
    $pageSize = 50
    $page = 1

    Write-Information "Starting Caseware permission entitlement import with pagesize set to: $($pageSize)"

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

    Write-Information 'Retrieving Caseware users'
    $userList = [System.Collections.Generic.List[object]]::new()
    do {
        Write-Information "Getting page: $page"
        $splatRestParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/users?pageSize=$pageSize&page=$page"
            Method  = 'GET'
            Headers = @{
                Authorization = "Bearer $($responseToken.Token)"
            }
        }
        $responseUsers = Invoke-RestMethod @splatRestParams
        if ($null -ne $responseUsers -and $responseUsers.Count -gt 0) {
            $userList.AddRange($responseUsers)
            $page++
        }
        else {
            break
        }
    } while ($true)

    Write-Information 'Retrieving Caseware roles'
    do {
        Write-Information "Getting page: $page"
        $splatRestParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/groups?pageSize=$pageSize&page=$page"
            Method  = 'GET'
            Headers = @{
                Authorization = "Bearer $($responseToken.Token)"
            }
        }
        $responseRoles = Invoke-RestMethod @splatRestParams
        if ($null -ne $responseRoles -and $responseRoles.Count -gt 0) {
            foreach ($role in $responseRoles) {
                $roleMembers = foreach ($user in $userList) {
                    if ($role.Id -in $user.FirmWideRoleIds) { $user.CWGuid }
                }

                if ($roleMembers.Count -eq 0) { continue }

                $permission = @{
                    PermissionReference = @{
                        Reference = $role.CWGuid
                    }
                    Description       = "$($role.Description)"
                    DisplayName       = "$($role.Name)"
                    AccountReferences = @()
                }

                $batchSize = 100
                $batches = 0..($roleMembers.Count - 1) | Group-Object { [math]::Floor($_ / $batchSize) }
                foreach ($batch in $batches) {
                    $permission.AccountReferences = [array]($batch.Group | ForEach-Object { $roleMembers[$_] })
                    Write-Output $permission
                }
            }
            $page++
        }
        else {
            break
        }
    } while ($true)
    Write-Information 'Caseware permission group entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Caseware permission group entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Caseware permission group entitlements. Error: $($ex.Exception.Message)"
    }
}