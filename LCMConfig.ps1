#скрипт включает Local Configuration Manager на сервере(ах), чье имя передается в аргументах или, при их отсутствии, запрашивается у пользователя
#путь к mof-файлу конфигурации определяется по папке, откуда запущен скрипт, имя-по имени скрипта
$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))
set-location $confpath
[string[]]$nodenames = $args
#Если в аргументах не передано имя сервера(ов0, запрашиваем у пользователя, ввод через запятую
If ($nodenames.count -eq 0){$nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries"); $pauseflag = $true}

Configuration $confname
{
    Node $nodename
    {
	LocalConfigurationManager
        {
            ConfigurationModeFrequencyMins = 15
            ConfigurationMode = "ApplyOnly"
            RefreshMode = "Push"
            RebootNodeIfNeeded = $false
            AllowModuleOverwrite = $false
        }		
    }
} 
#получаем список компьютеров домена
$comps = (get-adcomputer -filter *).name
Foreach ($nodename in $nodenames){
	#если в качестве имени сервера введено "all"
	if ($nodename -eq "all"){
		#по именам mof-файлов получаем список серверов, на которые необходима установка
		[string[]]$TargerServers = Get-childitem -path $confpath\$confname -name | % {($_ -split ".meta.mof")[0]}
			Foreach ($a in $TargerServers){
			#удаляем mof-файл, если сервера с соответствующим имнеенм нет в домене
			if ($comps -notcontains $a){
				write-host "Computer $a is not found in AD. MOF file was removed."
				remove-item -path "$confpath\$confname\$a.meta.mof" -force
			}else{
				#иначе применяем конфигурацию
				$nodename = $a
				&$confname
			}
		}
	#иначе, если в качестве имени сервера введены конкретные имена, проверяем их наличие в домене, при наличии, применяем конфигурацию
	}else{
		if ($comps -notcontains $nodename){
			write-host "Computer $a is not found in AD. Nothing to do."
		}else{	
			&$confname
		}
	}
}
if ($pauseflag){pause}