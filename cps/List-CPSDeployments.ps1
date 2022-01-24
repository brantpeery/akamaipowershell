<#
.SYNOPSIS
Lists the deployments for an enrollment

.DESCRIPTION
Gets the deployments for an enrollment in both staging and production. Can be limited to either network
If a network name is passed in, a single object will be returned with information from that network. 
.PARAMETER EnrollmentID
Akamai Enrollment Identifier. Ex 123456

.PARAMETER EdgeRCFile
The edgerc file to use for authentication

.PARAMETER Section
Authentication section to use (environment)

.PARAMETER Network
The deployment network to get the certificate from. Valid values are 'Production' and 'Staging'.
If no value is sent in to the Network parameter, the function return information from both networks

.PARAMETER AccountSwitchKey
Key used to act as a different user for this call

.EXAMPLE
List-CPSDeployments -EnrollmentID 123456 -Network Production

.NOTES
The function will return a hashtable with keys for both networks if a network is not specified
@{
    production=@{...}
    staging=@{...}
} 
Otherwise a single deployment object is returned.

@{
    certificate = "string",
    networkConfiguration = @{
        mustHaveCiphers = "string",
        networkType = "string",
        preferredCiphers = "string",
        sni = @{
            cloneDnsNames = true,
            dnsNames = @(
                "string"
            )
        }
    },
    signatureAlgorithm = "string",
    trustChain = "string"
}
.Link
https://techdocs.akamai.com/cps/reference/get-deployments
.Link
https://techdocs.akamai.com/cps/reference/get-deployments-production
.Link
https://techdocs.akamai.com/cps/reference/get-deployment-staging
#>
function List-CPSDeployments
{
    Param(
        [Parameter(Mandatory=$true, Position=1)]  [string] $EnrollmentID,
        [Parameter(Mandatory=$false)] [string] $EdgeRCFile = '~\.edgerc',
        [Parameter(Mandatory=$false)] [string] $Section = 'default',
        [Parameter(Mandatory=$false, Position=2)]
        [ValidateSet("Production", "Staging")] [string] $Network,
        [Parameter(Mandatory=$false)] [string] $AccountSwitchKey
    )
    $networkPath=""
    $accepts='application/vnd.akamai.cps.deployments.v6+json'
    if($network){
        $networkPath="/$($network.ToLower())"
        $accepts = "application/vnd.akamai.cps.deployment.v1+json"
    }
    $Path = "/cps/v2/enrollments/$EnrollmentID/deployments$($networkPath)?accountSwitchKey=$AccountSwitchKey"
    $AdditionalHeaders = @{
        'Accept' = $accepts
    }

    try {
        $Result = Invoke-AkamaiRestMethod -Method GET -Path $Path -AdditionalHeaders $AdditionalHeaders -EdgeRCFile $EdgeRCFile -Section $Section
        return $Result
    }
    catch {
        throw $_.Exception
    }  
}