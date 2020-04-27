Import-module WebAdministration
$dt = Get-Date -Format "dd-MM-yyyy"
New-Item -ItemType directory D:\publish\logs -Force | out-null #Create directory for logs

$global:DeploymentOption = [Environment]::GetEnvironmentVariable("AWS_Topic_Name", "Machine")

$global:logfilename = "D:\Publish\Logs\" + $dt + "_setup.log"
[int]$global:errorcount = 0 #Error count
[int]$global:warningcount = 0 #Warning count

function Write-log {
    param($message, [string]$type = "info", [string]$logfile = $global:logfilename, [switch]$silent)
    $dt = Get-Date -Format "dd.MM.yyyy HH:mm:ss:fff"
    $msg = $dt + "`t" + $type + "`t" + $message
    Out-File -FilePath $logfile -InputObject $msg -Append -encoding unicode
    if (-not $silent.IsPresent) {
        switch ( $type.toLower() ) {
            "error" {
                $global:errorcount++
                write-host $msg -ForegroundColor red
            }
            "warning" {
                $global:warningcount++
                write-host $msg -ForegroundColor yellow
            }
            "completed" {
                write-host $msg -ForegroundColor green
            }
            "info" {
                write-host $msg
            }
            default {
                write-host $msg
            }
        }
    }
}

function Setup_Bindings([string]$bn, [string]$fn, [string]$awspath, [string]$destpath, [string]$sitepath, [string]$hostname) {
    if ((Test-Path $destpath) -eq $False) {
        New-Item -Force -ItemType Directory -Path $destpath
    }
    $destfile = $destpath + "\" + $fn;
    if ((Test-Path $destfile) -eq $True) {
        Remove-Item -Force -Path $destfile;
    }

    Write-log "Starting of download package: $destfile"
    $bucket_path = "s3://" + $bn + "/" + $awspath + "/" + $fn
    $res = aws s3 cp $bucket_path $destpath --output text
    Write-log $res

    if ((Test-Path $sitepath) -eq $False) {
        New-Item -Force -ItemType Directory -Path $sitepath
    }
    else {
        Set-Location $sitepath
        Remove-Item -Recurse -Force *
    }
    $shell_app = New-Object -ComObject shell.application
    $zip_file = $shell_app.NameSpace($destfile)
    $dest = $shell_app.NameSpace($sitepath)
    $dest.CopyHere($zip_file.Items())

    Write-log "Creating of application pool for the Bindings"
    if (Test-Path IIS:\\AppPools\bindings) {
        Remove-Item IIS:\\AppPools\bindings -Force -Recurse
    }
    $ds_app_pool = New-Item IIS:\\AppPools\bindings
    $ds_app_pool.managedRuntimeVersion = "v4.0"
    $ds_app_pool.processModel.identityType = "LocalSystem"
    $ds_app_pool.ManagedPipelineMode = 'Classic'
    $ds_app_pool | Set-Item

    Write-log "Creating of web site for the bindings"
    Set-Location IIS:\
    set-webconfigurationproperty "/system.applicationHost/sites/siteDefaults[1]/limits[1]" -name connectionTimeout -value (New-TimeSpan -sec 1200)
    set-webconfigurationproperty "/system.webServer/proxy" -name timeout -value (New-TimeSpan -sec 1200)
    if (Test-Path IIS:\Sites\bindings) {
        Remove-Website -Name "bindings" -Confirm:$false
    }
    Set-WebConfiguration -filter '/system.webServer/rewrite/allowedServerVariables' -Value (@{Name="HTTP_X_ORIGINAL_HOST"},@{Name="TEMP_URL"})
    New-Website -Name "bindings" -Port 81 -IPAddress "*" -PhysicalPath $sitepath -ApplicationPool "bindings" -Force
    #New-WebBinding -Name "bindings" -IP "*" -Port 443 -Protocol https
    #makecert -r -pe -n "CN=LocalNew" -b 01/01/2018 -e 07/01/2030 -eku 1.3.6.1.5.5.7.3.1 -ss my -sr localMachine -sky exchange -sp "Microsoft RSA SChannel Cryptographic Provider" -sy 12
    #Set-Location IIS:\SslBindings
    #Get-ChildItem cert:\LocalMachine\MY | Where-Object {$_.Subject -match "LocalNew"} | Select-Object -First 1 | New-Item 0.0.0.0!443

    #check if mode is classic
    Write-log "check if mode is classic"
    $name = 'IIS:\\AppPools\bindings'
    $ClassicManagedPipelineMode = 'Classic'

    $CurrentManagedPipelineMode = Get-ItemProperty $name -name ManagedPipelineMode
    if (-Not( $CurrentManagedPipelineMode -eq $ClassicManagedPipelineMode)) {
        Write-log  ("Error: Name of ManagedPipelineMode: " + $CurrentManagedPipelineMode)
        $appPool = Get-Item $name
        $appPool | set-itemproperty -Name "managedPipelineMode" -Value "Classic"     
        Write-log  ("Name of ManagedPipelineMode was converted to: " + (Get-ItemProperty $name -name ManagedPipelineMode).ToString())
    }
    else {
        Write-log  ("Name of ManagedPipelineMode: " + $CurrentManagedPipelineMode)
    }
}

function Setup_DepSvc([string]$bn, [string]$fn, [string]$awspath, [string]$destpath, [string]$sitepath, [string]$hostname) {
    if ((Test-Path $destpath) -eq $False) {
        New-Item -Force -ItemType Directory -Path $destpath
    }
    $destfile = $destpath + "\" + $fn;
    if ((Test-Path $destfile) -eq $True) {
        Remove-Item -Force -Path $destfile;
    }
    Write-log "Starting of download package: $destfile"
    $bucket_path = "s3://" + $bn + "/" + $awspath + "/" + $fn
    $res = aws s3 cp $bucket_path $destpath --output text
    Write-log $res
    if ((Test-Path $sitepath) -eq $False) {
        New-Item -Force -ItemType Directory -Path $sitepath
    }
    else {
        Set-Location $sitepath
        Remove-Item -Recurse -Force *
    }
    $shell_app = New-Object -ComObject shell.application
    $zip_file = $shell_app.NameSpace($destfile)
    $dest = $shell_app.NameSpace($sitepath)
    $dest.CopyHere($zip_file.Items())
    Write-log "Creating of application pool for the DeploymentService2"
    if (Test-Path IIS:\\AppPools\DeploymentService2) {
        Remove-Item IIS:\\AppPools\DeploymentService2 -Force -Recurse
    }
    $ds_app_pool = New-Item IIS:\\AppPools\DeploymentService2
    $ds_app_pool.managedRuntimeVersion = "v4.0"
    $ds_app_pool.processModel.identityType = "LocalSystem"
    $ds_app_pool | Set-Item


    Write-log "changing configuration file for " + $global:DeploymentOption
    $WebConfigFile = $sitepath + "\web.config"
    [xml] $xml = Get-Content $WebConfigFile
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='DeploymentOption']").value = $global:DeploymentOption
    $xml.Save($WebConfigFile)

    Write-log "Creating of web site for the DeploymentService2"
    if (Test-Path IIS:\Sites\DeploymentService2) {
        Remove-Website -Name "DeploymentService2" -Confirm:$false
    }
    New-Website -Name "DeploymentService2" -Port 33000 -IPAddress "*" -PhysicalPath $sitepath -ApplicationPool "DeploymentService2" -Force

    #Init deployment service site
    Invoke-WebRequest http://localhost:33000/DeploymentService2.svc
}

function Setup_VersionWatcher([string]$bn,
    [string]$fn,
    [string]$awspath,
    [string]$destpath,
    [string]$apppath) {
    if ((Test-Path $destpath) -eq $False) {
        New-Item -Force -ItemType Directory -Path $destpath
    }
    $destfile = $destpath + "\" + $fn;
    if ((Test-Path $destfile) -eq $True) {
        Remove-Item -Force -Path $destfile;
    }
    Write-log "Starting of download package: $destfile"
    $bucket_path = "s3://" + $bn + "/" + $awspath + "/" + $fn
    aws s3 cp $bucket_path $destpath
    if ((Test-Path $apppath) -eq $False) {
        New-Item -Force -ItemType Directory -Path $apppath
    }
    else {
        Set-Location $apppath
        Remove-Item -Recurse -Force *
    }
    $shell_app = New-Object -ComObject shell.application
    $filename = $destpath + "\" + $fn
    $zip_file = $shell_app.NameSpace($filename)
    $dest = $shell_app.NameSpace($apppath)
    $dest.CopyHere($zip_file.Items())
    $versionWatcherPath = $apppath + "\" + "VersionWatcher.exe"
    Write-log "VersionWatcher utility was extracted"
    & $versionWatcherPath $global:DeploymentOption
    Write-log "VersionWatcher finished"
}
function Setup_HealthChecker([string]$s3Backet, [string]$s3Folder, [string]$fileName, [string]$tmpDestPath, [string]$appPath) {
    try {
        Write-log "HealthCheckService setup has started"
        $destFile = $tmpDestPath + $fileName;
        $bucket_path = "s3://" + $s3Backet + "/" + $s3Folder + "/" + $fileName
        $serviceName = "RazorSync.HealthCheckService"
        $serviceFilePath = $appPath + "HealthCheckService.exe" 

        if ((Test-Path $tmpDestPath) -eq $False) {
            New-Item -Force -ItemType Directory -Path $tmpDestPath
        }

        if ((Test-Path $destFile) -eq $True) {
            Remove-Item -Force -Path $destFile;
        }

        Write-log "Starting of download package: $fileName"
        aws s3 cp $bucket_path $tmpDestPath
        Write-log "Download of package has completed"

        if ((Test-Path $appPath) -eq $False) {
            New-Item -Force -ItemType Directory -Path $appPath
        }
        else {
            if (Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'") {
                Write-log "Start to uninstall $serviceName" 
                Stop-Service $serviceName
                Start-Sleep -s 10
                & 'c:\Windows\Microsoft.NET\Framework\v4.0.30319\installutil.exe' /u /servicename=$serviceName $serviceFilePath
            }
            Set-Location $appPath
            Remove-Item -Recurse -Force *
        }

        Write-log "Start to extract package: $destFile to $appPath"

        #Expand-Archive -LiteralPath $destFile -DestinationPath $appPath -Force
        $shell_app = New-Object -ComObject shell.application
        $zip_file = $shell_app.NameSpace($destFile)
        $dest = $shell_app.NameSpace($appPath)
        $dest.CopyHere($zip_file.Items())

        Write-log "Extracting of package has been completed"


        Write-log "Start to install $serviceName"

        & 'c:\Windows\Microsoft.NET\Framework\v4.0.30319\installutil.exe' /servicename=$serviceName $serviceFilePath
        Start-Sleep -s 10
        Start-Service RazorSync.HealthCheckService

        Write-log "$serviceName installation has completed"

        #Clean up
        $destFile = $tmpDestPath + $fileName;
        if ((Test-Path $destFile) -eq $True) {
            Remove-Item -Force -Path $destFile;
        }


        Write-log "HealthCheckService setup has finished"
    }
    catch {
        $msg = "Can not set up HealthCheckService: " + $_.Exception.GetType().Name + $_.Exception.GetType().Message
        Write-log $msg "error"
    }
}

Setup_Bindings razorsyncbuilds bindings.zip Bindings D:\temp D:\publish\sites\bindings deploymentservice2.razor.moc
Setup_HealthChecker razorsyncbuilds HealthCheckService HealthCheckService.zip d:\temp\ d:\publish\WindowsServices\HealthCheckService\
Setup_DepSvc razorsyncbuilds depsvc.zip DeploymentService D:\temp D:\publish\sites\DeploymentService2 deploymentservice2.razor.moc
Setup_VersionWatcher razorsyncbuilds vw.zip VersionWatcher D:\temp D:\Publish\WindowsServices\VersionWatcher


#Open port for health checking
New-NetFirewallRule -DisplayName "Default Web-site" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow

#Initialize the deployment service because this instance was restarted first time
Invoke-WebRequest http://localhost:33000/DeploymentService2.svc

#Add new job into the Task Scheduler in order to Initialize the deployment service during restarts
New-JobTrigger -AtStartup schtasks.exe /tn:InitDeploymentService /Create /XML d:\scripts\InitDeploymentService.xml  
#Add new job into the Task Scheduler in order to send Health Check data to AWS Metrics
Write-log "Creating of HealthCheck job"
switch ( $global:DeploymentOption ) {
    "Portals" {
        schtasks.exe /tn:HealthCheck /Create /XML d:\scripts\HealthCheck_Portals.xml
    }
    "WindowsServices" {
        schtasks.exe /tn:HealthCheck /Create /XML d:\scripts\HealthCheck_WS.xml
    }
    default {
        Write-log "HealthCheck job was not created. DeploymentOption = " + $global:DeploymentOption
    }
}
#Register-ScheduledJob -Name InitDeploymentService -Trigger $trig -ScriptBlock {Invoke-WebRequest http://localhost:33000/DeploymentService2.svc}
#Remove setup instance job from the Task Scheduler
#Unregister-ScheduledJob -Name RazorEnvSetup -Force
schtasks.exe /tn:RazorEnvSetup /Change /Disable
schtasks.exe /tn:RazorEnvSetup4Domain /Change /Disable
#schtasks.exe /tn:RazorEnvSetup /Delete /F
#schtasks.exe /tn:RazorEnvSetup4Domain /Delete /F

try {
    Write-log "IIS: rewrite header start"
    Start-Process -FilePath C:\Windows\System32\inetsrv\appcmd.exe -ArgumentList $('set config -section:system.webServer/proxy /arrResponseHeader:"False"  /commit:apphost') -RedirectStandardOutput D:\logIISUpdateConfig.txt -wait
    Write-Log([Io.File]::ReadAllText('D:\logIISUpdateConfig.txt'), 'info')
    Write-log "IIS: rewrite header complete"
    Start-Process -FilePath C:\Windows\System32\iisreset.exe -ArgumentList /RESTART -RedirectStandardOutput D:\iisreset.txt -wait
    Write-Log([Io.File]::ReadAllText('D:\iisreset.txt'), 'info')
    Write-log "IIS: reset iis success complete"
}
catch {
    $msg = $_.Exception | Format-List -Force | Out-String
    Write-log ("Can not reset iis or rewrite header1: " + $msg + " InvocationInfo.PositionMessage:" + $_.InvocationInfo.PositionMessage) "error"
}