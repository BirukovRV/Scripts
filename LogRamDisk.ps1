#скрипт монтирует RAM-диск L: для хранения логов IIS, используя протокол iSCSI
$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))#путь к файлу конфигурации определяется по папке, откуда запущен скрипт
set-location $confpath
[string[]]$nodenames = $args
#если  имена сервера(ов) не были переданы в аргументах, запрашиваем у пользователя
If ($nodenames.count -eq 0){$nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries"); $pauseflag = $true}

Configuration $confname
{
    Node $nodename
    {
		Script iis_logs_and_Ram_Disk
        {
            GetScript = {return $null}
            TestScript = {
				if(Get-Partition -DriveLetter L 2>$null){return $true} else {return $false}
			}
            SetScript = {
				#получаем IP сервера
				$ipadr = (Get-NetIPAddress 192.168*).IPAddress
				$ErrorActionPreference = "SilentlyContinue"
				#удаляем предыдущий раздел
				Remove-Partition -DriveLetter L -Confirm:$false 2>$null
				Get-Disk -FriendlyName "MSFT Virtual HD SCSI Disk Device" 2>$null | Set-Disk -IsOffline $true 2>$null
				Disconnect-IscsiTarget -NodeAddress "iqn.1991-05.com.microsoft:$($env:COMPUTERNAME)-localhost-target" -Confirm:$false 2>$null
				Remove-IscsiTargetPortal -TargetPortalAddress ($ipadr) -Confirm:$false 2>$null
				Remove-IscsiServerTarget -TargetName localhost 2>$null
				Remove-IscsiVirtualDisk -Path ramdisk:IIS_LOGS.vhdx 2>$null
				$ErrorActionPreference = "Continue"
				#создаем новый
				New-IscsiServerTarget -TargetName localhost -ComputerName $env:COMPUTERNAME
				New-IscsiVirtualDisk -Path ramdisk:IIS_LOGS.vhdx -Size 6144MB -ComputerName $env:COMPUTERNAME
				Add-IscsiVirtualDiskTargetMapping -TargetName localhost -Path ramdisk:IIS_LOGS.vhdx -ComputerName $env:COMPUTERNAME
				Set-IscsiServerTarget -InitiatorIds ("IQN:" + (Get-InitiatorPort).NodeAddress) -TargetName localhost -ComputerName $env:COMPUTERNAME
				New-IscsiTargetPortal -TargetPortalAddress $ipadr
				Connect-IscsiTarget -NodeAddress (Get-IscsiTarget | ? {$_.nodeaddress -like "*localhost*"}).NodeAddress
				Register-IscsiSession -SessionIdentifier (Get-IscsiSession).SessionIdentifier
				#инициализируем диск, присваиваем букуву L, даем права на доступ
				$diskNUM = (Get-Disk -FriendlyName "MSFT Virtual HD SCSI Disk Device").Number
				if ($diskNUM -and !(Get-Partition -DriveLetter L 2>$null)){
    				Set-Disk -Number $diskNUM -IsOffline $false
    				Initialize-Disk -Number $diskNUM -PartitionStyle MBR 2>$null
    				New-Partition -DiskNumber $diskNUM -UseMaximumSize -AssignDriveLetter:$False
    				Get-Partition -DiskNumber $diskNUM | Format-Volume -Confirm:$false
    				Get-Partition -DiskNumber $diskNUM | Set-Partition -NewDriveLetter L
    				New-PSDrive -Name L -PSProvider FileSystem -Root L:\ 2>$null
    				icacls L:\ /grant ("$($env:USERDOMAIN)\Programmers" + ":(OI)(CI)(R)")
    				New-SmbShare -CachingMode None -Name IIS_Logs -path L:\ -ReadAccess "$($env:USERDOMAIN)\Programmers" -FullAccess "Administrators" 2>$null
				}
				#создаем папки для логов по именам проектов IIS
				$sites = Get-ChildItem -Path C:\inetpub\wwwroot -Directory -Name | ? {$_ -ne "Default" -and  $_ -ne "Default Web Site"}
				Foreach ($site in $sites){New-item -ItemType Directory -Path L:\$site -force 2>$null}
			}
		}
	}
}
#Проверяем наличие в домене компьютеров, полученных во входных данных и создаем конфигурацию только для существующих
$comps = (get-adcomputer -filter *).name
Foreach ($nodename in $nodenames){

	if ($nodename -eq "all"){
		[string[]]$TargerServers = Get-childitem -path $confpath\$confname -name | % {($_ -split ".mof")[0]}
		Foreach ($a in $TargerServers){
			if ($comps -notcontains $a){
				write-host "Computer $a is not found in AD. MOF file was removed."
				remove-item -path "$confpath\$confname\$a.mof" -force
			}else{
				$nodename = $a
				&$confname
			}
        }
	}else{
		if ($comps -notcontains $nodename){
			write-host "Computer $a is not found in AD. Nothing to do."
		}else{
			&$confname
		}
	}
}
if ($pauseflag){pause}