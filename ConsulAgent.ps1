$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))
set-location $confpath
[string[]]$nodenames = $args
If ($nodenames.count -eq 0){$nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries"); $pauseflag = $true}

Configuration $confname {

    Node $nodename {

        Script install_Consul{

            GetScript = { return $null }
            TestScript = { return $false }
            SetScript = {
                # Имя сервиса
                $nameService = "consul-agent";
                # Это сервер или клиент
                $thisServer = $true;
                # Установлена ли служба
                $installStatusService = $false;
                # Путь установки
                $localPathService = "C:\Consul";
                # Путь до шары со службами
                $pathSourceFiles = "\\$env:USERDOMAIN\DFS\Source\Consul";
                # Название домена
                $nameDC = $env:USERDOMAIN;
                # Версия Consul
                [string]$sourceConsulVersion = $null;
                [int]$indexVersion = 0;
                # Название служб
                $nssm = "nssm.exe";
                $consul = "consul.exe";
                # Название конфига
                $nameConfigFile = "config.json";
                # Hash-table для конфига
                $configConsul = @{};
                # Параметры для запуска Consul
                $argsLaunchConsul = "agent -config-file $localPathService\$nameConfigFile";
                # Мастер токен
                $masterToken = "";

                # Получение версии Consul
                $sourceConsulVersion = Invoke-Expression -Command ("{0}\{1} version" -f $pathSourceFiles, $consul)
                if($sourceConsulVersion -match "Consul\sv([\d\.]+)") {
                    [Version]$exeConsulVersion = $Matches[1]
                    if($exeConsulVersion -ge [Version]"1.4.0") {
                        $indexVersion = 1
                    }
                }

                Write-Verbose -Message "Consul version config `"$indexVersion`"";

                # Проверка наличия файлов по пути
                if (Test-Path -Path $pathSourceFiles) {

                        Write-Verbose "`"$pathSourceFiles`" was found";
                        New-Item -Path $localPathService -ItemType Directory -Force;

                        foreach ($file in $(Get-ChildItem -Path $pathSourceFiles).Name) {
                            Copy-Item -Path "$pathSourceFiles\$file" -Destination "$localPathService\$($file)" -Force -Confirm:$false
                        }

                } else {
                    Write-Error "No source directory was found `"$pathSourceFiles`"" -ErrorAction Stop;
                }

                function Set-NssmProperty {
                    # Расположение Nssm
                    $nssmPath = "$localPathService\$nssm";
                    # Логи
                    $nssmLogsPath = "$localPathService\logs";
                    # Создание папки для логов
                    New-Item $nssmLogsPath -ItemType Directory -Force -Confirm:$false;
                    # Параметры nssm для службы Consul
                    $nssmProperty = @{
                        "AppDirectory"="$localPathService";
                        "AppNoConsole"=1;
                        "AppPriority"="HIGH_PRIORITY_CLASS";
                        "AppStopMethodSkip"=0;
                        "AppStopMethodConsole"=1500;
                        "AppStopMethodWindow"=1500;
                        "AppStopMethodThreads"=1500;
                        "AppThrottle"=1500;
                        "AppParameters"="$argsLaunchConsul";
                        "AppRestartDelay"=0;
                        "AppStdout"="$nssmLogsPath\consul-output.log";
                        "AppStderr"="$nssmLogsPath\consul-output.log"
                        "AppStdoutCreationDisposition"=2;
                        "AppStderrCreationDisposition"=2;
                        "AppRotateFiles"=1;
                        "AppRotateOnline"=1;
                        "AppRotateBytes"=104857600;
                    }

                    foreach($item in $nssmProperty.GetEnumerator()) {
                        if((& $nssmPath get $nameService $item.Name) -ne $item.Value) {
                            & $nssmPath set $nameService $item.Name $item.Value; Write-Verbose "For the service `"nssm`", the property `"$($item.Name)`" is set to `"$($item.Value)`""
                        }
                    }
                    # Действие по умолчанию при при выходе из службы
                    if ((& $nssmPath get $nameService AppExit Default) -ne "Restart") {
                        & $nssmPath set $nameService AppExit Default Restart;
                    }
                    Start-Sleep 2
                }

                # Получение IP
                [string]$fqdnDnsNameHost = "{0}.{1}.loc" -f $env:COMPUTERNAME, $env:USERDOMAIN;
                $ipAddress += (Resolve-DnsName -Name $fqdnDnsNameHost -Type A -DnsOnly -NoHostsFile).IPAddress;

                $configConsul = @{
                    "retry_interval"="30s";
                    "retry_max"=0;
                    "disable_remote_exec"=$true;
                    "domain"="consul.";
                    "data_dir"="data";
                    "ui"=$true;
                    "server"=$thisServer;
                    "dns_config"=@{
                        "allow_stale"=$false;
                        "max_stale"="5s";
                        "node_ttl"="0s";
                        "service_ttl"=@{"*"="0s"};
                        "enable_truncate"=$false;
                        "only_passing"=$true;
                    };
                    "log_level"="INFO";
                    "node_name"=($env:COMPUTERNAME).ToUpper();
                    "bind_addr"=$ipAddress;
                    "client_addr"="127.0.0.1";
                    "datacenter"=$nameDC;
                    "ports"=@{
                        "dns"=$dnsPort;
                        "http"=8500;
                        "https"=-1;
                        "serf_lan"=8301;
                        "serf_wan"=8302;
                        "server"=8300;
                    };
                    "rejoin_after_leave"=$true;
                    "leave_on_terminate"=$true;
                }

                if($indexVersion -eq 0) {
                    $configConsul += @{
                        "acl_datacenter"=$nameDC;
                        "acl_default_policy"="allow";
                        "acl_down_policy"="allow";
                    }
                } else {
                    $configConsul += @{
                        "acl"=@{
                            "default_policy"="allow";
                            "down_policy"="allow";
                            "enabled" =  $true;
                        };
                        "primary_datacenter"=$nameDC;
                    }
                }

                if($thisServer) {
                    Write-Verbose "Installing `"$nameService`" in SERVER mode";

                    $adsiObj = [adsisearcher]::new();
                    $adsiObj.Filter = "name=SecretInfo";
                    $adsiObj.SearchRoot.Path="LDAP://OU=SecretInfo,OU=Custom_Accounts,DC=$env:USERDOMAIN,DC=loc";

                    [string]$masterToken = $adsiObj.FindAll().Properties.admindescription 2>$null;

                    if(!$masterToken) {
                        Write-Error "ACL Master Token not found" -ErrorAction Stop;
                    }

                    if($indexVersion -eq 0) {
                        $configConsul += @{
                            "acl_master_token" = $masterToken;
                        }
                    } else {
                        $configConsul.acl += @{
                            "tokens" = @{
                                "master" = $masterToken;
                            }
                        }
                    }

                    $configConsul.leave_on_terminate=$false;

                } else {
                    Write-Verbose "Installing `"$nameService`" in CLIENT mode";
                }

                $nameConfigFile = "config.json";
                $argsLaunchConsul = "agent -config-file $localPathService\$nameConfigFile";

                $configConsul | ConvertTo-Json | Out-File -FilePath "$localPathService\$nameConfigFile" -Encoding default;
                Write-Verbose "Config file UPDATE";

                if(!$installStatusService) {

                    & "$localPathService\nssm.exe" install $nameService "$localPathService\consul.exe" $argsLaunchConsul;

                    while((Get-Service).Name -notcontains $nameService) {
                        Write-Verbose "Waiting for installation $nameService";
                        Start-Sleep 1;
                    }
                    Write-Verbose "Installation `"$nameService`" successfully complited";
                    Set-NssmProperty;

                    Start-Sleep 2;

                    Start-Service $nameService;

                    while((Get-Service -Name $nameService).Status -ne "Running") {
                        $launchCounter++
                        Write-Verbose "Waiting for `"$nameService`" to start"
                        Start-Sleep 1
                        if($launchCounter -gt 30) {
                            Write-Error "Could not restart the service `"$nameService`"" -ErrorAction Stop
                        }
                    }

                    Start-Sleep 2;

                    $headers = @{
                        "X-Consul-Token" = $masterToken;
                    };
                    # Создание политик в Consul для токена Vault
                    $vaultTokenPolicy = @{
                        "Name" = "VaultPolicy";
                        "Rules" = "`rservice `"vault`" { `"policy`" = `"write`" }`r
                        key `"vault/`" { `"policy`" = `"write`" }`r
                        node `"`" { `"policy`" = `"write`" }`r
                        agent `"`" { `"policy`" = `"write`" }`r
                        session `"vault`" { `"policy`" = `"write`" }";
                    } | ConvertTo-Json;

                    $VaultPolicy = (Invoke-WebRequest -Uri "http://127.0.0.1:8500/v1/acl/policy" -Method Put -Body $vaultTokenPolicy -Headers $headers -UseBasicParsing) | ConvertFrom-Json;

                    # Параметры для создания токена в Consul
                    $data = @{
                        "Description" = "VaultToken";
                        "Policies" = @(@{"ID" = $VaultPolicy.ID;});
                     } | ConvertTo-Json;

                    # Создание токена в Consul для Vault и получение его ID
                    Invoke-WebRequest -Uri "http://127.0.0.1:8500/v1/acl/token" -Method Put -Body $data -Headers $headers -UseBasicParsing;

                    # Создать путь в Consul
                    Write-Verbose "Create vault path in Consul";
                    Invoke-WebRequest -Uri "http://127.0.0.1:8500/v1/kv/vault/" -Method Put -UseBasicParsing;

                }

            }
        }
    }
}

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