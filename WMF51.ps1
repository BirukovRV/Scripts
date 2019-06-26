#скрипт устанавливает обновление KB3191564 - Windows Management Framework 5.1
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
		Script install_hotfix
		{
		    GetScript = {return $null}
            TestScript = {return $false}
            SetScript = {
				[array]$HotFix = "KB3191564"
				[string]$Path = "\\$env:USERDOMAIN.lan\dfs\Repository\HotFix"
				[switch]$Restart = $false
				$listFilePath = $null
				$sourceHotFix = @{}
				#если существует шара с обновлениями
				if(Test-Path $Path) {
					Write-Verbose "Directory `"$Path`" found"
					$Path = "$((Get-Item -Path $Path).FullName)\Windows-"
					#определяем версию windows
					$hostInfo = Get-WmiObject -Class Win32_OperatingSystem
					#в соответстсвии с ней, дополняем путь к файлу обновления
					switch -Wildcard ($hostInfo.Version) {
						"10.0.*" {$Path += "(Server2016)-(10)"; Write-Verbose "HotFix OS Version `"Windows Server 2016`" or `"Windows 10`""}
						"6.3.*" {$Path += "(Server2012R2)-(8.1)"; Write-Verbose "HotFix OS Version `"Windows Server 2012 R2`" or `"Windows 8.1`""}
						"6.2" {$Path += "(Server2012)-(8)"; Write-Verbose "HotFix OS Version `"Windows Server 2012`" or `"Windows 8`""}
						"6.1" {$Path += "(Server2008R2)-(7)"; Write-Verbose "HotFix OS Version `"Windows Server 2008`" R2 or `"Windows 7`""}
					}
					#проверяем полученный путь
					if(Test-Path $Path) {
						Write-Verbose "Directory `"$Path`" found"
						$listFilePath = Get-ChildItem $Path -File
						#проверяем наличие файла
						if(!$listFilePath) {
							Write-Error "No HotFix files were found in the directory `"$Path`" - [0x10]" -ErrorAction Stop
						} else {
							Write-Verbose "For the selected OS in the `"$Path`" directory files are found"
						}
					} else {Write-Error "Directory `"$Path`" is not found - [0x20]" -ErrorAction Stop}
				} else {Write-Error "Directory `"$Path`" is not found - [0x21]" -ErrorAction Stop}
				#
				$listFilePath | foreach {
					if($_.Name -match "^\(.+\)-(KB[\d]+).msu$") {
						$sourceHotFix += @{"$($Matches[1])"="$($Matches[0])"}
					}
				}

				if($sourceHotFix) {
					Write-Verbose "Found the following HotFix `"$([string]::Join(", ", $($sourceHotFix.Keys)))`""
					$installedHotFix = Get-HotFix
					$HotFix | foreach {
						if($installedHotFix.HotFixID -notcontains $_) {
							Write-Verbose "HotFix `"$_`" not found on the host, installation will be performed"
							if($sourceHotFix.Keys -contains $_) {
								$pathHotFix = $null; $pathHotFix = $sourceHotFix[$_]
								[string]$argsInstall = "/quiet$(if(!$Restart){" /norestart"})"
								Start-Process "$Path\$pathHotFix" -ArgumentList "$argsInstall" -Wait
							} else {
								Write-Error "HotFix file for HotFix `"$_`" not found in directory `"$Path`""
							}
						} else {
							Write-Verbose "HotFix `"$_`" is already installed on this host"
						}
					}
				} else {
					Write-Error "The files found in the directory `"$Path`" are not HotFix files - [0x11]" -ErrorAction Stop
				}
			}
		}
	}
}

#Проверяем наличие в домене компьютеров, полученных во входных данных и создаем конфигурацию только для существующих
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