Enable-PSRemoting
## CONFIGURE WINRM CLIENT ###
$host_name = $env:computername
New-SelfSignedCertificate -DnsName $host_name  -CertStoreLocation Cert:\LocalMachine\My
$thumbprint = Get-childitem cert:\LocalMachine\My\ | Where-Object -Property Subject -EQ "CN=$host_name" | select Thumbprint -ExpandProperty Thumbprint

# Export certificate
$cert = (Get-Item -Path cert:\LocalMachine\My\$thumbprint)
Export-Certificate -Cert $cert -FilePath .\$host_name.crt

# ADD Cert to trusted ROOT store
$certificate = ( Get-ChildItem -Path .\$host_name.crt )
$certificate | Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root


# Configure winrm with HTTPS

Write-Host "Delete any existing WinRM listeners"
winrm delete winrm/config/listener?Address=*+Transport=HTTP  2>$Null
winrm delete winrm/config/listener?Address=*+Transport=HTTPS 2>$Null

Write-Host "Create a new WinRM listener and configure"
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$ComputerName`"; CertificateThumbprint=`"$Thumbprint`"}"
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="0"}'
winrm set winrm/config '@{MaxTimeoutms="7200000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="12000"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

Write-Host "Configure UAC to allow privilege elevation in remote shells"
$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$Setting = 'LocalAccountTokenFilterPolicy'
Set-ItemProperty -Path $Key -Name $Setting -Value 1 -Force

Write-Host "turn off PowerShell execution policy restrictions"
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine
New-Item                                                                       `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Network\NewNetworkWindowOff" `
    -Force

Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value True
Set-Item WSMan:\localhost\Service\Auth\Basic       -Value True
Write-Host "Configure and restart the WinRM Service; Enable the required firewall exception"
Stop-Service -Name WinRM
Set-Service -Name WinRM -StartupType Automatic
netsh advfirewall firewall set rule name="Windows Remote Management (HTTPS-In)" new action=allow localip=any remoteip=any
Start-Service -Name WinRM