schtasks.exe /tn:RazorEnvSetup /Create /XML d:\scripts\RazorEnvSetup.xml

$nw = New-Object -ComObject WScript.Network 
$password = ConvertTo-SecureString 'zxzxZX12' -AsPlainText -Force
$username = "CLOUD\DomainAdmin"
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$domain = "cloud.razorsync.com"
Add-Computer -DomainName $domain -ComputerName $nw.ComputerName -Credential $credential -Force -Restart
