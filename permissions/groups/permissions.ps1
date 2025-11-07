############################################################
# HelloID-Conn-Prov-Target-Caseware-Permissions-Group
# PowerShell V2
############################################################

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

 $splatRestParams = @{
            #Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/roles?pageSize=$pageSize&page=$page"
            Uri     = "$($actionContext.Configuration.BaseUrl)/$($actionContext.Configuration.CustomerId)/ms/caseware-cloud/api/v2/groups"
            Method  = 'GET'
            Headers = @{
                Authorization = "Bearer $($responseToken.Token)"
            }
        }
        $response = Invoke-RestMethod @splatRestParams
           
            foreach ($group in $response) {
                        $outputContext.Permissions.Add(
                            @{
                                DisplayName    = $group.briefdescription
                                Identification = @{
                                    Reference = $group.CWGuid
                                }
                            }
                        )
                    }
        
        } catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-CasewareError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
