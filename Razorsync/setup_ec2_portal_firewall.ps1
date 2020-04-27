Import-module WebAdministration
$ver = "0.4"
$dt=Get-Date -Format "dd-MM-yyyy"
New-Item -ItemType directory D:\publish\logs -Force | out-null #Create directory for logs

$global:DeploymentOption=[Environment]::GetEnvironmentVariable("AWS_Topic_Name","Machine")

$global:logfilename="D:\Publish\Logs\"+$dt+"_setup.log"
[int]$global:errorcount = 0 #Error count
[int]$global:warningcount = 0 #Warning count

function Write-log
{param($message,[string]$type="info",[string]$logfile=$global:logfilename,[switch]$silent)	
    $dt=Get-Date -Format "dd.MM.yyyy HH:mm:ss"	
    $msg=$dt + "`t" + $type + "`t" + $message 
    Out-File -FilePath $logfile -InputObject $msg -Append -encoding unicode
    if (-not $silent.IsPresent) 
    {
        switch ( $type.toLower() )
        {
            "error"
            {			
                $global:errorcount++
                write-host $msg -ForegroundColor red			
            }
            "warning"
            {			
                $global:warningcount++
                write-host $msg -ForegroundColor yellow
            }
            "completed"
            {			
                write-host $msg -ForegroundColor green
            }
            "info"
            {			
                write-host $msg
            }			
            default 
            { 
                write-host $msg
            }
        }
    }
}

Write-log "Create firewall rule for the Bindings"
try
{

	$firewallRuleName = "Portal site ports"
	$firewallRule = Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue
	if (-not ($firewallRule -eq $null))
	{
		Write-log "Remove old firewall rule $firewallRuleName"  
		Remove-NetFirewallRule -DisplayName $firewallRuleName 
	}

	Write-log "Create firewall rule $firewallRuleName"  
	New-NetFirewallRule -DisplayName $firewallRuleName -Action Allow -Description "Allow external connection to Portal site ports" -Direction Inbound -Enabled True `
		-Encryption NotRequired -LocalPort "20000-65535" -Profile Any -Protocol TCP -RemoteAddress "10.0.0.0/255.255.0.0" -RemotePort "20000-65535" -Service Any

}
catch
{
	$msg = "Can not create firewall rule for the Bindings: " + $_.Exception.GetType().Name + $_.Exception.GetType().Message
	Write-log $msg "error"
}

Write-log "Creation of firewall rule for the Bindings has been completed"
