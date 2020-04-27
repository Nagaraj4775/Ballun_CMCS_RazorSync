function GetWebSiteStatusCode {
    param (
        [string] $testUri,
        $maximumRedirection = 5
    )
    $request = $null
    try {
        $request = Invoke-WebRequest -Uri $testUri -MaximumRedirection $maximumRedirection -ErrorAction SilentlyContinue
    } 
    catch [System.Net.WebException] {
        $request = $_.Exception.Response
    }
    catch {
        Write-Error $_.Exception
        return $null
    }
    $request.StatusCode
}

import-module "C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1"

Set-AWSCredentials -AccessKey AKIAJFCOPXJPLJZJEOYA -SecretKey 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 -StoreAs AwsCredProfile
Set-AWSCredentials -ProfileName AwsCredProfile
Set-DefaultAWSRegion us-east-1

$dat = New-Object Amazon.CloudWatch.Model.MetricDatum
$dat.Timestamp = (Get-Date).ToUniversalTime() 
$dat.MetricName = "Health Check PM on PROD"
$dat.Value = GetWebSiteStatusCode -testUri " http://localhost:84/"
Write-CWMetricData -Namespace "Deployment Health Check" -MetricData $dat