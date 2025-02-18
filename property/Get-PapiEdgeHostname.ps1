function Get-PapiEdgeHostname
{
    Param(
        [Parameter(Mandatory=$true)]  [string] $EdgeHostnameID,
        [Parameter(Mandatory=$true)]  [string] $GroupID,
        [Parameter(Mandatory=$true)]  [string] $ContractId,
        [Parameter(Mandatory=$false)] [string] $Options,
        [Parameter(Mandatory=$false)] [string] $EdgeRCFile = '~\.edgerc',
        [Parameter(Mandatory=$false)] [string] $Section = 'default',
        [Parameter(Mandatory=$false)] [string] $AccountSwitchKey
    )

    $Path = "/papi/v1/edgehostnames/$EdgeHostnameID`?contractId=$ContractId&groupId=$GroupID&options=$Options&accountSwitchKey=$AccountSwitchKey"

    try {
        $Result = Invoke-AkamaiRestMethod -Method GET -Path $Path -EdgeRCFile $EdgeRCFile -Section $Section
        return $Result.edgehostnames.items
    }
    catch {
        throw $_.Exception
    }
}

