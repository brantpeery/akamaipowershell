#Requires -Version 3.0
<#
  Copyright 2019 Akamai Technologies, Inc. All Rights Reserved.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

  Author: Stuart Macleod
  Senior Technical Project Manager
  Akamai Technologies Inc.

  Adapted from Invoke-AkamaiOpen (https://github.com/akamai/AkamaiOPEN-edgegrid-powershell/blob/master/Invoke-AkamaiOPEN.ps1)

  Author: Josh Hicks
  Solutions Architect
  Akamai Technologies Inc.
  Copyright 2016
#>

<#
.SYNOPSIS
EdgeGrid Powershell
.DESCRIPTION
Authorization wrapper around Invoke-RestMethod for use with Akamai's OPEN API initiative.
.PARAMETER Method
Request method. Valid values are GET, POST, PUT, and DELETE
.PARAMETER Path
Request path without hostname or scheme, but including any request parameters
.PARAMETER EdgeRCFile
File-based Auth - Authorization file to read credentials from. Defaults to ~/.edgerc
.PARAMETER Section
File-based Auth - Section in EdgeRC file to read credentials from. Defaults to [default]
.PARAMETER Body
Should contain the POST/PUT Body. The body should be structured like a JSON object. Example: $Body = '{ "name": "botlist2", "type": "IP", "list": ["201.22.44.12", "8.7.6.0/24"] }'
.PARAMETER AdditionalHeaders
Hashtable of additional request headers to add
.PARAMETER Staging
Image Manager requests only. Changes IM host from production to staging. For non-IM requests does nothing.
.EXAMPLE
Invoke-AkamaiRestMethod -Method GET -Path '/path/to/api?withParams=true' -EdgeRCFile ~/my.edgerc -Section 'papi'
.LINK
developer.akamai.com
#>
function Invoke-AkamaiRestMethod {
    param(
        [Parameter(Mandatory = $false)] [ValidateSet("GET", "PUT", "POST", "DELETE", "PATCH")] [string] $Method = "GET",
        [Parameter(Mandatory = $true)]  [string] $Path,
        [Parameter(Mandatory = $false)] $Body,
        [Parameter(Mandatory = $false)] [string] $InputFile,
        [Parameter(Mandatory = $false)] [string] $EdgeRCFile = '~\.edgerc',
        [Parameter(Mandatory = $false)] [string] $Section = 'default',
        [Parameter(Mandatory = $false)] [hashtable] $AdditionalHeaders,
        [Parameter(Mandatory = $false)] [boolean] $Staging,
        [Parameter(Mandatory = $false)] [string] $MaxBody = 131072,
        [Parameter(Mandatory = $false)] [string] $ResponseHeadersVariable
    )

    if ($Script:AkamaiSession -ne $null -and $Script:AkamaiSession.Auth.$Section -ne $null) {
        #Use the script session auth instead of a file
        $Auth = $Script:AkamaiSession.Auth
        $authSource = "cached Akamai session credential" #Used in error messages
    }
    else {
        ### Get .edgrc credentials
        $Auth = Parse-EdgeRCFile -EdgeRCFile $EdgeRCFile -Section $Section

        #Cache the results so subsiquent calls don't have to read the file again
         Set-AkamaiSession -AuthProperty $Auth
        $authSource = "$EdgeRCFile file" #Used in error messages
    }

    # Validate auth contents
    if ($null -eq $Auth.$Section) {
        throw "Error: Config section [$Section] not found in the $authSource"
    }
    if ($null -eq $Auth.$Section.ClientToken -or $null -eq $Auth.$Section.ClientAccessToken -or $null -eq $Auth.$Section.ClientSecret -or $null -eq $Auth.$Section.Host) {
        throw "Error: Some necessary auth elements missing from section $Section. Please check the $authSource"
    }
   Write-Debug "Obtained credentials from section '$Section'"

    # Set IM staging host if switch present
    if ($Auth.$Section.Host.Contains('.imaging.') -and $Staging) {
        $Auth.$Section.Host = $Auth.$Section.Host.Replace(".imaging.", ".imaging-staging.")
    }

    # Sanitise query string
    if ($Path.Contains("?")) {
        $PathElements = $Path.Split("?")
        $PathOnly = $PathElements[0]
        $QueryString = $PathElements[1]
        $SanitisedQuery = Sanitise-QueryString -QueryString $QueryString
        Write-Debug "Original Query = $QueryString"
        Write-Debug "Sanitised Query = $SanitisedQuery"
        # Reconstruct Path
        if ($SanitisedQuery) {
            $Path = $PathOnly + "?" + $SanitisedQuery
        }
        else {
            $Path = $PathOnly
        }
    }

    # Set ReqURL from host and provided path
    $ReqURL = "https://" + $Auth.$Section.Host + $Path

    # ReqURL Verification
    If ($null -eq ($ReqURL -as [System.URI]).AbsoluteURI -or $ReqURL -notmatch "akamaiapis.net") {
        throw "Error: Invalid Request URI"
    }
    Write-Debug "Request URL = $ReqURL"

    # Sanitize Method param
    $Method = $Method.ToUpper()

    # Timestamp for request signing
    $TimeStamp = [DateTime]::UtcNow.ToString("yyyyMMddTHH:mm:sszz00")

    # GUID for request signing
    $Nonce = [GUID]::NewGuid()

    # Build data string for signature generation
    $SignatureData = $Method + "`thttps`t"
    $SignatureData += $Auth.$Section.Host + "`t" + $Path

    # Add body to signature. Truncate if body is greater than max-body (Akamai default is 131072). PUT Method does not require adding to signature.
    if ($Method -eq "POST") {
        if ($Body) {
            $Body_SHA256 = [System.Security.Cryptography.SHA256]::Create()
            if ($Body.Length -gt $MaxBody) {
                $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Body.Substring(0, $MaxBody))))
            }
            else {
                $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Body)))
            }

            $SignatureData += "`t`t" + $Body_Hash + "`t"
        }
        elseif ($InputFile) {
            $Body_SHA256 = [System.Security.Cryptography.SHA256]::Create()
            $Bytes = Get-Content -AsByteStream $InputFile
            $Body_Hash = [System.Convert]::ToBase64String($Body_SHA256.ComputeHash($Bytes))
            $SignatureData += "`t`t" + $Body_Hash + "`t"
            Write-Debug "Signature generated from input file $InputFile"
        }
        else {
            $SignatureData += "`t`t`t"
        }
    }
    else {
        $SignatureData += "`t`t`t"
    }

    $SignatureData += "EG1-HMAC-SHA256 "
    $SignatureData += "client_token=" + $Auth.$Section.ClientToken + ";"
    $SignatureData += "access_token=" + $Auth.$Section.ClientAccessToken + ";"
    $SignatureData += "timestamp=" + $TimeStamp + ";"
    $SignatureData += "nonce=" + $Nonce + ";"

    Write-Debug "SignatureData = $SignatureData"

    # Generate SigningKey
    $SigningKey = Crypto -secret $Auth.$Section.ClientSecret -message $TimeStamp

    # Generate Auth Signature
    $Signature = Crypto -secret $SigningKey -message $SignatureData

    # Create AuthHeader
    $AuthorizationHeader = "EG1-HMAC-SHA256 "
    $AuthorizationHeader += "client_token=" + $Auth.$Section.ClientToken + ";"
    $AuthorizationHeader += "access_token=" + $Auth.$Section.ClientAccessToken + ";"
    $AuthorizationHeader += "timestamp=" + $TimeStamp + ";"
    $AuthorizationHeader += "nonce=" + $Nonce + ";"
    $AuthorizationHeader += "signature=" + $Signature

    # Create IDictionary to hold request headers
    $Headers = @{}

    ## Calculate custom UA
    if($PSVersionTable.PSVersion.Major -ge 6){ #< 6 is missing the OS member of PSVersionTable, so we use env variables
        $UserAgent = "AkamaiPowershell/$($Env:AkamaiPowershellVersion) (Powershell $PSEdition $($PSVersionTable.PSVersion) $PSCulture, $($PSVersionTable.OS))"
    }
    else{
        $UserAgent = "AkamaiPowershell/$($Env:AkamaiPowershellVersion) (Powershell $PSEdition $($PSVersionTable.PSVersion) $PSCulture, $($Env:OS))"
    }
    
    # Add headers
    $Headers.Add('Authorization',$AuthorizationHeader)
    $Headers.Add('Accept','application/json')
    $Headers.Add('Content-Type', 'application/json; charset=utf-8')
    $Headers.Add('User-Agent', $UserAgent)

    # Add additional headers
    if ($AdditionalHeaders) {
        $AdditionalHeaders.Keys | foreach {
            $Headers[$_] = $AdditionalHeaders[$_]
        }
    }

    # Set ContentType param from Content-Type header. This is sent along with bodies to fix string encoding issues in IRM
    $ContentType = $Headers['Content-Type']

    # Add additional headers if POSTing or PUTing
    If ($Body) {
        # turn off the "Expect: 100 Continue" header
        # as it's not supported on the Akamai side.
        [System.Net.ServicePointManager]::Expect100Continue = $false
    }

    # Set TLS version to 1.2
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12


    # Check for Proxy Env variable and use if present
    if ($null -ne $ENV:https_proxy) {
        $UseProxy = $true
    }

    # Differentiate on PS 5 and later as PS 5's Invoke-RestMethod doesn't behave the same as the later versions
    if ($PSVersionTable.PSVersion.Major -le 5) { 
        if ($Method -eq "PUT" -or $Method -eq "POST" -or $Method -eq "PATCH") {
            try {
                if ($Body) {
                    if ($UseProxy) {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -Body $Body -Proxy $ENV:https_proxy
                    }
                    else {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -Body $Body
                    }
                }
                elseif ($InputFile) {
                    if ($UseProxy) {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -InFile $InputFile -Proxy $ENV:https_proxy
                    }
                    else {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -InFile $InputFile
                    }
                    
                }
                else {
                    if ($UseProxy) {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -Proxy $ENV:https_proxy
                    }
                    else {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType
                    }
                }
            }
            catch {
                throw $_
            }
        }
        else {
            # GET requests typically
            try {
                if ($UseProxy) {
                    $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -MaximumRedirection 0 -ErrorAction SilentlyContinue -Proxy $ENV:https_proxy
                }
                else {
                    $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -MaximumRedirection 0 -ErrorAction SilentlyContinue
                }
    
                # Redirects aren't well handled due to signatures needing regenerated
                if ($null -ne ($Response.PSObject.members | where { $_.Name -eq "redirectLink" }) ) {
                    Write-Debug "Redirecting to $($Response.redirectLink)"
                    $Response = Invoke-AkamaiRestMethod -Method $Method -Path $Response.redirectLink  -AdditionalHeaders $AdditionalHeaders -EdgeRCFile $EdgeRCFile -Section $Section
                }
            }
            catch {
                throw $_
            }
        }
    }
    # PS 6+, the .net versions
    else {
        if ($Method -eq "PUT" -or $Method -eq "POST" -or $Method -eq "PATCH") {
            try {
                if ($Body) {
                    if ($UseProxy) {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -Body $Body -ResponseHeadersVariable $ResponseHeadersVariable -Proxy $ENV:https_proxy
                    }
                    else {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -Body $Body -ResponseHeadersVariable $ResponseHeadersVariable
                    }
                    
                }
                elseif ($InputFile) {
                    if ($UseProxy) {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -InFile $InputFile -ResponseHeadersVariable $ResponseHeadersVariable -Proxy $ENV:https_proxy
                    }
                    else {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -InFile $InputFile -ResponseHeadersVariable $ResponseHeadersVariable
                    }
                }
                else {
                    if ($UseProxy) {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -ResponseHeadersVariable $ResponseHeadersVariable -Proxy $ENV:https_proxy
                    }
                    else {
                        $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -ResponseHeadersVariable $ResponseHeadersVariable
                    }
                }
            }
            catch {
                throw $_.ErrorDetails
            }
        }
        else {
            # GET requests typically
            try {
                if ($UseProxy) {
                    $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -ResponseHeadersVariable $ResponseHeadersVariable -MaximumRedirection 0 -ErrorAction Stop -Proxy $ENV:https_proxy
                }
                else {
                    $Response = Invoke-RestMethod -Method $Method -Uri $ReqURL -Headers $Headers -ContentType $ContentType -ResponseHeadersVariable $ResponseHeadersVariable -MaximumRedirection 0 -ErrorAction Stop
                }
            }
            catch {
                # Redirects aren't well handled due to signatures needing regenerated
                if ($_.Exception.Response.StatusCode.value__ -eq 301 -or $_.Exception.Response.StatusCode.value__ -eq 302) {
                    try {
                        $NewPath = $_.Exception.Response.Headers.Location.PathAndQuery
                        Write-Debug "Redirecting to $NewPath"
                        $Response = Invoke-AkamaiRestMethod -Method $Method -Path $NewPath -AdditionalHeaders $AdditionalHeaders -EdgeRCFile $EdgeRCFile -Section $Section -ResponseHeadersVariable $ResponseHeadersVariable
                    }
                    catch {
                        throw $_
                    }
                }
                else {
                    throw $_.ErrorDetails
                }
            }
        }
        
        # Set ResponseHeadersVariable to be passed back to requesting function
        if ($ResponseHeadersVariable) {
            Set-Variable -name $ResponseHeadersVariable -Value (Get-Variable -Name $ResponseHeadersVariable -ValueOnly) -Scope Script
        }
    }
    
    Return $Response
}