#скрипт проверяет установленную на сервере версию  NetFramework и обновляет ее до 4.7.1, если необходимо
$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\')) #путь к файлу конфигурации определяется по папке, откуда запущен скрипт
set-location $confpath
[string[]]$nodenames = $args
#если  имена серверов не были переданы в аргументах, запрашиваем у пользователя
If ($nodenames.count -eq 0)
{
	$nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries");
	$pauseflag = $true
}

Configuration $confname
{
    Node $nodename
    {
		Script Install_NetFramework
		{
		    GetScript = {return $null}
            TestScript = {return $false}
            SetScript = {
				[array]$NetFramework = "4.7.1"
				[string]$Path = "\\$env:USERDOMAIN.lan\dfs\Repository\NetFramework"
				[switch]$Restart = $false
				$listFilePath = $null
				$sourceNetFramework = @{}
			#Проверяем доступность шары с дистрибутивами
				if(Test-Path $Path) {
					Write-Verbose "Directory `"$Path`" found"
					$Path = (Get-Item -Path $Path).FullName
			#получаем список файлов в папке с дистрибами
					$listFilePath = Get-ChildItem $Path -File
					if(!$listFilePath) {
						Write-Error "No NetFramework files were found in the directory `"$Path`" - [0x10]" -ErrorAction Stop
					} else {
						Write-Verbose "In the `"$Path`" directory files are found"
					}
				} else {Write-Error "Directory `"$Path`" is not found - [0x21]" -ErrorAction Stop}
				#заносим в массив все имена файлов дистрибов NetFramework
				$listFilePath | foreach {
					if($_.Name -match "^\(NetFramework.+\)-(\d.\d(.\d)?).exe$") {
						$sourceNetFramework += @{"$($Matches[1])"="$($Matches[0])"}
					}
				}
				#Выводим данный список на экран и определяем установленный пакет NetFramework
				if($sourceNetFramework) {
					Write-Verbose "Found the following `"NetFramework $([string]::Join(", ", $($sourceNetFramework.Keys)))`""
					[int]$installedNetFramework = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
					$installedNetFrameworkVersion = $null

					switch -Wildcard ($installedNetFramework) {
						"4613*" {$installedNetFrameworkVersion = "4.7.1"}
						"460*" {$installedNetFrameworkVersion = "4.7"}
						"39480*" {$installedNetFrameworkVersion = "4.6.2"}
						"3942*" {$installedNetFrameworkVersion = "4.6.1"}
						"39329*" {$installedNetFrameworkVersion = "4.6"}
						"379893" {$installedNetFrameworkVersion = "4.5.2"}
						"378675" {$installedNetFrameworkVersion = "4.5.1"}
						"378758" {$installedNetFrameworkVersion = "4.5.1"}
						"378389" {$installedNetFrameworkVersion = "4.5"}
					}
					#если не найдена установленная версия 4.7.1, устанавливаем
					$NetFramework | foreach {
						if($installedNetFrameworkVersion -notcontains $_) {
							Write-Verbose "`"NetFramework $_`" not found on the host, installation will be performed"
							if($sourceNetFramework.Keys -contains $_) {
								$pathNetFramework = $null; $pathNetFramework = $sourceNetFramework[$_]
								[string]$argsInstall = "/q$(if(!$Restart){" /norestart"})"
								Start-Process "$Path\$pathNetFramework" -ArgumentList "$argsInstall" -Wait
							} else {
							#если дистриб данной версии не найден в шаре, сообщаем пользователю
								Write-Error "NetFramework file for `"NetFramework `"$_`" not found in directory `"$Path`""
							}
						} else {
							Write-Verbose "`"NetFramework $_`" is already installed on this host"
						}
					}
					#если в шаре нет дистрибов NetFramework, выводим сообщение, останавливаем выполнение скрипта
				} else {
					Write-Error "The files found in the directory `"$Path`" are not NetFramework files - [0x11]" -ErrorAction Stop
				}
			}
		}
	}
}
#Проверяем наличие в домене компьютеров, полученных во входных данных и создаем конфигурацию только для существующих
$comps = (get-adcomputer -filter *).name
Foreach ($nodename in $nodenames){

	if ($nodename -eq "renew"){
		[string[]]$TargerServers = Get-childitem -path $confpath\$confname -name | ForEach-Object {($_ -split ".mof")[0]}
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