#скрипт создает конфигурацию, устанавливающую все актуальные обновления windows с автоперезагрузкой сервера
$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\')) #путь к сохраняемому файлу конфигурации, определяется по папке, откуда запущен скрипт
set-location $confpath
[string[]]$nodenames = $args
#если  имена сервера(ов) не были переданы в аргументах, запрашиваем у пользователя
If ($nodenames.count -eq 0){$nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries"); $pauseflag = $true}

Configuration $confname
{
    Node $nodename
    {
		Script WinU1pdateAll
		{ 	#в конфигурации устанавливаем все доступные обновления с автоперезагрузкой
			GetScript = {return $null}
			SetScript = {
				if ((Get-PackageProvider nuget 2 > $null) -eq $null){ Install-PackageProvider nuget -Force -Confirm:$false }
                if ((Get-Package -Name PSWindowsUpdate 2 > $null) -eq $null) { Install-Package -Name PSWindowsUpdate -Force }
				Get-WUInstall -Install -AcceptAll -IgnoreUserInput -AutoReboot -Confirm:$false
			}
			TestScript = {return $false}
		}
	}
}

$comps = (get-adcomputer -filter *).name
if ($nodenames[0] -eq "All"){ [string[]]$nodenames = $comps }
if ($nodenames[0].IndexOf('*') -ne -1){
	[string[]]$nodenames = $comps | ? {$_ -like $nodenames[0]}
}
#Если передано all,применяем конфигурацию на компьютерах домена, в случае передач аргумента rebuild,
# проверяем актуальность хранящихся конфигураций, удаляем mof-файлы для несуществующих серверов, применяем конфигурацию для остальных
Foreach ($nodename in $nodenames){
	if ($nodename -eq "all"){ Foreach ($comp in $comps){ $nodename = $comp; &$confname}}
	elseif ($nodename -eq "rebuild"){
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

$comps = (get-adcomputer -filter *).name
Foreach ($nodename in $nodenames){

	if ($nodename -eq "renew"){
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
	}elseif ($nodename -eq "All"){
		Foreach ($a in $comps){
			$nodename = $a
			&$confname
		}
	}elseif ($nodenames[0].IndexOf('*') -ne -1){
		Foreach ($a in $($comps | ? {$_ -like $nodenames[0]})){
			$nodename = $a
			&$confname
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