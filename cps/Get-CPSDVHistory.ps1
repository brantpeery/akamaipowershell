function Get-CPSDVHistory
{
    Param(
        [Parameter(Mandatory=$true)]  [string] $EnrollmentID,
        [Parameter(Mandatory=$false)] [string] $EdgeRCFile = '~\.edgerc',
        [Parameter(Mandatory=$false)] [string] $Section = 'default',
        [Parameter(Mandatory=$false)] [string] $AccountSwitchKey
    )

    $Path = "/cps/v2/enrollments/$EnrollmentID/dv-history?accountSwitchKey=$AccountSwitchKey"
    $AdditionalHeaders = @{
        'accept' = 'application/vnd.akamai.cps.dv-history.v1+json'
    }

    try {
        $Result = Invoke-AkamaiRestMethod -Method GET -Path $Path -AdditionalHeaders $AdditionalHeaders -EdgeRCFile $EdgeRCFile -Section $Section
        return $Result.results
    }
    catch {
        throw $_.Exception
    }  
}