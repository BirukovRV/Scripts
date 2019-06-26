#скрипт создает конфигурацию, включающую компоненты windows, необходимые для продакшен-сервера
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
		WindowsFeature 1 { Ensure = "Present"; Name = "FileAndStorage-Services" }
        WindowsFeature 2 { Ensure = "Present"; Name = "Storage-Services" }
        WindowsFeature 3 { Ensure = "Present"; Name = "Web-Server" }
		WindowsFeature 4 { Ensure = "Present"; Name = "Web-WebServer" }
		WindowsFeature 5 { Ensure = "Present"; Name = "Web-Common-Http" }
		WindowsFeature 6 { Ensure = "Present"; Name = "Web-Default-Doc" }
		WindowsFeature 7 { Ensure = "Present"; Name = "Web-Dir-Browsing" }
		WindowsFeature 8 { Ensure = "Present"; Name = "Web-Http-Errors" }
		WindowsFeature 9 { Ensure = "Present"; Name = "Web-Static-Content" }
		WindowsFeature 10 { Ensure = "Present"; Name = "Web-Health" }
		WindowsFeature 11 { Ensure = "Present"; Name = "Web-Http-Logging" }
		WindowsFeature 12 { Ensure = "Present"; Name = "Web-Performance" }
		WindowsFeature 13 { Ensure = "Present"; Name = "Web-Stat-Compression" }
		WindowsFeature 14 { Ensure = "Present"; Name = "Web-Security" }
		WindowsFeature 15 { Ensure = "Present"; Name = "Web-Filtering" }
		WindowsFeature 16 { Ensure = "Present"; Name = "Web-App-Dev" }
		WindowsFeature 17 { Ensure = "Present"; Name = "Web-Net-Ext45" }
		WindowsFeature 18 { Ensure = "Present"; Name = "Web-Asp-Net45" }
		WindowsFeature 19 { Ensure = "Present"; Name = "Web-ISAPI-Ext" }
		WindowsFeature 20 { Ensure = "Present"; Name = "Web-ISAPI-Filter" }
		WindowsFeature 21 { Ensure = "Present"; Name = "Web-Mgmt-Tools" }
		WindowsFeature 22 { Ensure = "Present"; Name = "Web-Mgmt-Console" }
		WindowsFeature 2_2 { Ensure = "Present"; Name = "Web-WebSockets" }
		WindowsFeature 2_3 { Ensure = "Present"; Name = "NET-Framework-Core" }
		WindowsFeature 2_4 { Ensure = "Present"; Name = "NET-Framework-Features" }
		WindowsFeature 23 { Ensure = "Present"; Name = "NET-Framework-45-Features" }
		WindowsFeature 24 { Ensure = "Present"; Name = "NET-Framework-45-Core" }
		WindowsFeature 25 { Ensure = "Present"; Name = "NET-Framework-45-ASPNET" }
		WindowsFeature 26 { Ensure = "Present"; Name = "NET-WCF-Services45" }
		WindowsFeature 27 { Ensure = "Present"; Name = "NET-WCF-HTTP-Activation45" }
		WindowsFeature 28 { Ensure = "Present"; Name = "NET-WCF-MSMQ-Activation45" }
		WindowsFeature 29 { Ensure = "Present"; Name = "NET-WCF-Pipe-Activation45" }
 		WindowsFeature 30 { Ensure = "Present"; Name = "NET-WCF-TCP-Activation45" }
 		WindowsFeature 31 { Ensure = "Present"; Name = "NET-WCF-TCP-PortSharing45" }
		WindowsFeature 32 { Ensure = "Present"; Name = "MSMQ" }
		WindowsFeature 33 { Ensure = "Present"; Name = "MSMQ-Services" }
		WindowsFeature 34 { Ensure = "Present"; Name = "MSMQ-Server" }
		WindowsFeature 35 { Ensure = "Present"; Name = "RSAT" }
		WindowsFeature 36 { Ensure = "Present"; Name = "RSAT-Role-Tools" }
		WindowsFeature 37 { Ensure = "Present"; Name = "RSAT-AD-Tools" }
		WindowsFeature 38 { Ensure = "Present"; Name = "RSAT-AD-PowerShell" }
		WindowsFeature 39 { Ensure = "Present"; Name = "FS-SMB1" }
		WindowsFeature 40 { Ensure = "Present"; Name = "User-Interfaces-Infra" }
		WindowsFeature 41 { Ensure = "Present"; Name = "Server-Gui-Mgmt-Infra" }
		WindowsFeature 42 { Ensure = "Present"; Name = "Server-Gui-Shell" }
		WindowsFeature 43 { Ensure = "Present"; Name = "PowerShellRoot" }
		WindowsFeature 44 { Ensure = "Present"; Name = "PowerShell" }
		WindowsFeature 45 { Ensure = "Present"; Name = "PowerShell-ISE" }
		WindowsFeature 46 { Ensure = "Present"; Name = "WAS" }
		WindowsFeature 47 { Ensure = "Present"; Name = "WAS-Process-Model" }
		WindowsFeature 48 { Ensure = "Present"; Name = "WAS-Config-APIs" }
		WindowsFeature 49 { Ensure = "Present"; Name = "WoW64-Support" }
		WindowsFeature 50 { Ensure = "Present"; Name = "Web-Custom-Logging" }
		WindowsFeature 51 { Ensure = "Present"; Name = "Web-Log-Libraries" }
		WindowsFeature 52 { Ensure = "Present"; Name = "Web-ODBC-Logging" }
		WindowsFeature 53 { Ensure = "Present"; Name = "Web-Request-Monitor" }
		WindowsFeature 54 { Ensure = "Present"; Name = "Web-Http-Tracing" }
		WindowsFeature 55 { Ensure = "Present"; Name = "Web-Scripting-Tools" }
		WindowsFeature 56 { Ensure = "Present"; Name = "Web-Mgmt-Service" }
		WindowsFeature 57 { Ensure = "Present"; Name = "Telnet-Client" }
		WindowsFeature 58 { Ensure = "Present"; Name = "Web-Dyn-Compression" }
		WindowsFeature 59 { Ensure = "Present"; Name = "Remote-Desktop-Services" }
		WindowsFeature 60 { Ensure = "Present"; Name = "RDS-RD-Server" }
		WindowsFeature 62 { Ensure = "Present"; Name = "RSAT-RDS-Tools" }
		WindowsFeature 63 { Ensure = "Present"; Name = "RSAT-RDS-Licensing-Diagnosis-UI" }
		WindowsFeature 64 { Ensure = "Present"; Name = "FS-DFS-Replication" }
		WindowsFeature 65 { Ensure = "Present"; Name = "FS-iSCSITarget-Server" }
		WindowsFeature 66 { Ensure = "Present"; Name = "Web-AppInit" }
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