$LCMState = (Get-DscLocalConfigurationManager).LCMState
if ($LCMState -ne "Idle" -and $LCMState -ne "PendingConfiguration"){Write-Host "LCM is not idle. Check state!"; pause; exit}

$Domain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
$SRVname = read-host "host Name"
$IpAddress = read-host "$SRVname Ip Address"
$IpMask = read-host "$SRVname Ip Mask in prefix format, like 24"
$NextHop = read-host "$SRVname NextHopAddress"
$DNSAddresses = Read-host "Enter $SRVname dns server addresses, like 192.168.15.2, 192.168.15.3"
$DNSAddresses = $DNSAddresses.Split(", ", [System.StringSplitOptions]::RemoveEmptyEntries)
$pass = read-host "New local Administrator pass"
$DomainCred = Get-Credential -UserName "Administrator@$Domain" -Message "Enter domain credential"

Write-Host "Copying $SRVname.vhdx..." -ForegroundColor Cyan -NoNewline

Copy-Item "D:\Source\VM\VHD\Syspreped\Syspreped-Server2016GUI.vhdx" E:\VHD\$SRVname.vhdx

Write-Host " Done." -ForegroundColor Green

Write-Host "Creating $SRVname..." -ForegroundColor Cyan -NoNewline
New-VM -Name $SRVname -MemoryStartupBytes 8589934592 -SwitchName VS-int -VHDPath E:\VHD\$SRVname.vhdx -Path E:\VMs -Generation 2 | Out-Null
Disable-VMIntegrationService -Name "Time Synchronization" -VMName $SRVname
Enable-VMIntegrationService -Name "Guest Service Interface" -VMName $SRVname
Set-VM -Name $SRVname -ProcessorCount 2 -AutomaticStartAction Start -AutomaticStopAction ShutDown
Set-VMFirmware -VMName $SRVname -FirstBootDevice (Get-VMHardDiskDrive -VMName $SRVname)
Start-VM $SRVname
$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "Administrator", (ConvertTo-SecureString -AsPlainText "Qq123123" -Force)
While ((Invoke-Command -VMName $SRVname -Credential $cred -ScriptBlock {Get-host} 2>$null) -eq $null){start-sleep 5}
Write-Host " Done." -ForegroundColor Green

Write-Host "Setting $SRVname interfaces..." -ForegroundColor Cyan -NoNewline
Invoke-Command -VMName $SRVname -Credential $cred -ScriptBlock {
	$IfIndex = (Get-NetAdapter).ifIndex
	Remove-NetIPAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -Confirm:$false | Out-Null
	New-NetIPAddress -IPAddress $using:IpAddress -PrefixLength $using:IpMask -InterfaceIndex $IfIndex | Out-Null
	New-NetRoute -DestinationPrefix 0.0.0.0/0 -InterfaceIndex $IfIndex -AddressFamily IPv4 -NextHop $using:NextHop -RouteMetric 10 | Out-Null
	Foreach ($inf in Get-NetIPInterface -AddressFamily IPv6 | ? {$_.InterfaceAlias -notlike "isatap*" -and $_.InterfaceAlias -notlike "Loopback*"}){
		Disable-NetAdapterBinding -ComponentID ms_tcpip6 -InterfaceAlias $inf.InterfaceAlias 2>$null
	}
	Set-DnsClientServerAddress -InterfaceIndex $IfIndex -ServerAddresses $using:DNSAddresses | Out-Null
}
Write-Host " Done." -ForegroundColor Green

Write-Host "Setting $SRVname LocalAdmin..." -ForegroundColor Cyan -NoNewline
Invoke-Command -VMName $SRVname -Credential $cred -ScriptBlock {
    ([ADSI]"WinNT://./Administrator").SetPassword($using:pass)
    wmic useraccount where "Name='Administrator'" set PasswordExpires=false
}
Write-Host " Done." -ForegroundColor Green

$cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "Administrator", (ConvertTo-SecureString -AsPlainText $pass -Force)

Invoke-Command -VMName $SRVname -Credential $cred -ScriptBlock {
    Rename-Computer -NewName $using:SRVname -Force -Restart

} | Out-Null
Start-sleep 10
While ((Invoke-Command -VMName $SRVname -Credential $cred -ScriptBlock {Get-host} 2>$null) -eq $null){start-sleep 5}
Write-Host "Done." -ForegroundColor Green

$Domain = (Get-WmiObject -Class Win32_ComputerSystem).Domain
Write-Host "Adding VM to $Domain ..." -ForegroundColor Cyan -NoNewline
Invoke-Command -VMName $SRVname -Credential $cred -ScriptBlock {
    Add-Computer -DomainName $using:Domain -Credential $using:DomainCred -Restart
}
Write-Host " Done." -ForegroundColor Green