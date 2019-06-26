$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))
set-location $confpath
[string[]]$nodenames = $args

if ($nodenames.count -eq 0) {
    $nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries");
    $pauseflag = $true;
}

Configuration $confname
{
    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'

    Node $nodename
    {
        Script install_Vault {
            GetScript  = {return $null}
            TestScript = {return $false}
            SetScript  = {
                # Локальный путь
                [string]$localPath = "C:\Vault";
                # Хранение токенов для Vault
                $vaultKeysPath = "vault-keys.json";
                # Имя файла
                $fileName = "vault.exe";
                # Имя сервиса
                [string]$serviceName = "vault-server";
                $Domain = (Get-WmiObject -Class Win32_ComputerSystem).Domain;
                # Источник файлов
                [string]$sourcePath = "\\$Domain\DFS\Source\Vault";
                # Параметры конфига
                $vaultConfig = @{};
                # Токен для Vault
                [string]$vaultToken = "";
                # Заголовок для Vault
                $header = @{};
                # Vault keys
                $vaultKeysData = @{};

                function Set-NssmProperty {
                    # Расположение Nssm
                    $nssmPath = "$localPath\nssm.exe";
                    # Логи
                    $nssmLogsPath = "$localPath\logs";
                    # Создание папки для логов
                    New-Item $nssmLogsPath -ItemType Directory -Force -Confirm:$false;
                    # Параметры nssm для службы Consul
                    $nssmProperty = @{
                        "AppDirectory"                 = "$localPath";
                        "AppNoConsole"                 = 1;
                        "AppPriority"                  = "HIGH_PRIORITY_CLASS";
                        "AppStopMethodSkip"            = 0;
                        "AppStopMethodConsole"         = 1500;
                        "AppStopMethodWindow"          = 1500;
                        "AppStopMethodThreads"         = 1500;
                        "AppThrottle"                  = 1500;
                        "AppParameters"                = "$argsLaunchVault";
                        "AppRestartDelay"              = 0;
                        "AppStdout"                    = "$nssmLogsPath\vault-output.log";
                        "AppStderr"                    = "$nssmLogsPath\vault-output.log"
                        "AppStdoutCreationDisposition" = 2;
                        "AppStderrCreationDisposition" = 2;
                        "AppRotateFiles"               = 1;
                        "AppRotateOnline"              = 1;
                        "AppRotateBytes"               = 104857600;
                    };
                    foreach ($item in $nssmProperty.GetEnumerator()) {
                        if ((& $nssmPath get $serviceName $item.Name) -ne $item.Value) {
                            & $nssmPath set $serviceName $item.Name $item.Value;
                            Write-Verbose "For the service `"nssm`", the property `"$($item.Name)`" is set to `"$($item.Value)`""
                        }
                    }
                    # Действие по умолчанию при выходе из службы
                    if ((& $nssmPath get $serviceName AppExit Default) -ne "Restart") {
                        & $nssmPath set $serviceName AppExit Default Restart;
                    }
                    Start-Sleep 2
                }
                # Создать политику Vault
                function CreatePolicy {
                    param (
                        [string]$PolicyName,
                        [hashtable]$header,
                        [hashtable]$Data
                    )
                    $uri = "http://127.0.0.1:8200/v1/sys/policy/$PolicyName";

                    Write-Verbose "Create policy `"$PolicyName`"";
                    Invoke-WebRequest -Uri $uri -Headers $header -Method Put -Body $($Data | ConvertTo-Json) -UseBasicParsing;
                }
                # Создать токен Vault
                function CreateToken {
                    param (
                        [string]$TokenName,
                        [hashtable]$header,
                        [hashtable]$Data
                    )
                    $uri = "http://127.0.0.1:8200/v1/auth/token/create";

                    Write-Verbose "Create token `"$TokenName`"";
                    Invoke-WebRequest -Uri $uri -Headers $header -Method Put -Body $($Data | ConvertTo-Json) -UseBasicParsing;
                }

                # Если сервис не установлен
                if ((Get-Service -Name $serviceName 2>$null).count -eq 0) {

                    # Проверка на наличие папки по пути
                    if (Test-Path -Path $localPath) {
                        Write-Verbose -Message "Folder `"$localPath`" is created!";
                    }
                    else {
                        New-Item -Path "$localPath\data\audit" -Type Directory -Force
                        New-Item -Path "$localPath\cert" -Type Directory -Force
                        Write-Verbose -Message "New folder created `"$localPath`"";
                    }

                    # Копирование файлов в папку из источника
                    try {
                        foreach ($file in $(Get-ChildItem -Path $sourcePath -Force)) {
                            Write-Verbose -Message "Copy file: `"$file`"...";
                            Copy-Item -Path "$sourcePath\$file" -Destination "$localPath\$file" -Force -Confirm:$false;
                        }
                    }
                    catch {
                        Write-Verbose -Message "Failed to copy files from `"$sourcePath`" в `"$localPath`"";
                    }

                    try {
                        # Получаем токен для доступа к API Consul
                        $adsiObj = [adsisearcher]::new();
                        $adsiObj.Filter = "name=SecretInfo";
                        $adsiObj.SearchRoot.Path = "LDAP://OU=SecretInfo,OU=Custom_Accounts,DC=$env:USERDOMAIN,DC=loc";
                        [string]$masterToken = $adsiObj.FindAll().Properties.admindescription 2>$null;

                        if (!$masterToken) {
                            Write-Error "ACL Master Token not found" -ErrorAction Stop;
                        }
                    }
                    catch {
                        Write-Error "Please check param: `"$adsiObj.Filter`" and `"$adsiObj.SearchRoot.Path`"" -ErrorAction Stop;
                    }

                    # Получение токена из Consul для Vault
                    $headerConsul = @{"X-CONSUL-TOKEN" = $masterToken; }
                    $vaultAccessorID = "";
                    $vaultTokenForConsul = "";

                    $consulTokens = (Invoke-WebRequest -Uri "http://127.0.0.1:8500/v1/acl/tokens" -Method Get -Headers $headerConsul -UseBasicParsing) | ConvertFrom-Json;

                    foreach ($token in $consulTokens) {
                        if ($token.Description -eq "VaultToken") {
                            $vaultAccessorID = $token.AccessorID;
                            $vaultTokenForConsul = $((Invoke-WebRequest -Uri "http://127.0.0.1:8500/v1/acl/token/$vaultAccessorID" -Method Get -Headers $headerConsul -UseBasicParsing) | ConvertFrom-Json).SecretID;
                        }
                    }

                    $vaultConfig = @{
                        "storage"           = @{
                            "consul" = @{
                                "address" = "127.0.0.1:8500";
                                "path"    = "vault/";
                                "token"   = $vaultTokenForConsul;
                            }
                        };
                        "listener"          = @{
                            "tcp" = @{
                                "address"            = "0.0.0.0:8200";
                                "tls_disable"        = $true;
                                "tls_client_ca_file" = "";
                            }
                        };
                        "default_lease_ttl" = "876000h";
                        "max_lease_ttl"     = "876000h";
                        "ui"                = $true;
                        "api_addr"          = "http://127.0.0.1:8200";
                    };

                    $configName = "config.json";
                    $vaultConfig | ConvertTo-Json | Out-File -FilePath "$localPath\$configName" -Encoding default;
                    Write-Verbose "Config file CREATED";

                    # Параметры запуска
                    $argsLaunchVault = "server -config $localPath\$configName";
                    # Установка vault
                    & "$localPath\nssm.exe" install $serviceName $localPath\$fileName $argsLaunchVault;

                    while ((Get-Service).Name -notcontains $serviceName) {
                        Write-Verbose "Waiting for installation $serviceName";
                        Start-Sleep 1;
                    }
                    Write-Verbose ("The `"$serviceName`" service was successfully installed");

                    Set-NssmProperty
                    # Запуск Vault
                    Start-Service $serviceName;
                    # Ожидание запуска службы Vault
                    while ((Get-Service -Name $serviceName).Status -ne "Running") {
                        $launchCounter++
                        Write-Verbose "Waiting to start `"$serviceName`""
                        Start-Sleep 1
                        if ($launchCounter -gt 30) {
                            Write-Error "Error restart `"$serviceName`"" -ErrorAction Stop
                        }
                    }

                    try {
                        Write-Verbose "Start to initialize Vault...";
                        $vaultKeysData = (Invoke-WebRequest -Uri "http://127.0.0.1:8200/v1/sys/init" -Method Put -Body $(@{"secret_shares" = 3; "secret_threshold" = 3; } | ConvertTo-Json) -UseBasicParsing) | ConvertFrom-Json;
                        # Запись json в файл
                        $vaultKeysData | ConvertTo-Json | Out-File -FilePath $localPath\$vaultKeysPath -Encoding default;
                        Write-Verbose "Vault initialized successfully";
                    }
                    catch {
                        Write-Warning "Vault already initialized!"
                    }

                    # Проверить статут инициализации
                    #$init = ((Invoke-WebRequest -Uri "http://127.0.0.1:8200/v1/sys/init" -Method Get -UseBasicParsing) | ConvertFrom-Json).initialized;

                    if (Test-Path -Path $localPath\$vaultKeysPath) {
                        # Читаем файл с ключами и токенами
                        $vaultJsonData = Get-Content -Path $localPath\$vaultKeysPath | Out-String | ConvertFrom-Json

                        # Unseal Vault
                        Write-Verbose "Unseal Vault...";
                        foreach ($key in $vaultJsonData.keys) {
                            Invoke-WebRequest -Uri "http://127.0.0.1:8200/v1/sys/unseal" -Method Put -Body $(@{"key" = $key; } | ConvertTo-Json) -UseBasicParsing;
                        }

                        # Статус печати vault
                        $sealed = $true;

                        while ($sealed) {
                            Write-Verbose "Waiting to unsleal Vault..."
                            Start-Sleep 1
                            $sealed = ((Invoke-WebRequest -Uri "http://127.0.0.1:8200/v1/sys/seal-status" -Method Get -UseBasicParsing) | ConvertFrom-Json).sealed;
                        }

                        # Vault токен
                        $vaultToken = $vaultJsonData.root_token;

                        # Установка заголовка для управления Vault через API
                        $header = @{
                            "X-Vault-Token" = $vaultToken;
                        };

                        Write-Verbose "Start creating policies of Vault..."
                        # Политики
                        $policies = New-Object System.Collections.ArrayList;
                        $admin_policy = @{ "name" = "admin-policy"; "data" = @{"policy" = "path `"secret/servers/*`" {capabilities = [`"create`", `"read`", `"update`", `"delete`", `"list`"]}`r`npath `"sys/policy/admin-policy`" {capabilities = [`"read`"]}"}};
                        # server-guiaccount-prod-secure-read-policy
                        $prod_secure = @{ "name" = "server-guiaccount-prod-secure-read-policy"; "data" = @{"policy" = "path `"secret/secureservers/guiaccounts/~prod`" {capabilities = [`"read`", `"list`"]}"}};
                        # server-guiaccount-prod-read-policy
                        $prod_read = @{ "name" = "server-guiaccount-prod-read-policy"; "data" = @{"policy" = "path `"secret/servers/guiaccounts/~prod`" {capabilities = [`"read`", `"list`"]}"}};
                        # server-guiaccount-test-secure-read-policy
                        $test_secure = @{ "name" = "server-guiaccount-test-secure-read-policy"; "data" = @{"policy" = "path `"secret/secureservers/guiaccounts/~test`" {capabilities = [`"read`", `"list`"]}"}};
                        # server-guiaccount-test-read-policy
                        $test_read = @{ "name" = "server-guiaccount-test-read-policy"; "data" = @{"policy" = "path `"secret/servers/guiaccounts/~test`" {capabilities = [`"read`", `"list`"]}"}};

                        $policies.AddRange(@($admin_policy, $prod_secure, $prod_read, $test_secure, $test_read));

                        foreach ($policy in $policies) {
                            CreatePolicy -PolicyName $policy.name -header $header -Data $policy.data
                            Write-Verbose "Policy `"$policy.name`", successfuly created";
                        }

                        Write-Verbose "Start creating tokens of Vault..."
                        # Токены
                        $tokensPolicies = New-Object System.Collections.ArrayList;
                        $prod = @{
                            "policies"     = @("server-guiaccount-prod-read-policy");
                            "display_name" = "GUI Accounts Prod";
                            "renewable"    = "true";
                        };
                        $test = @{
                            "policies"     = @("server-guiaccount-test-read-policy");
                            "display_name" = "GUI Accounts Test";
                            "renewable"    = "true";
                        };
                        $prod_secur = @{
                            "policies"     = @("server-guiaccount-prod-secure-read-policy");
                            "display_name" = "GUI Accounts Prod Secure";
                            "renewable"    = "true";
                        };
                        $test_secur = @{
                            "policies"     = @("server-guiaccount-test-secure-read-policy");
                            "display_name" = "GUI Accounts Test Secure";
                            "renewable"    = "true";
                        };

                        $tokensPolicies.AddRange(@($prod, $test, $prod_secur, $test_secur));

                        # Создание токенов
                        foreach ($token in $tokensPolicies) {
                            CreateToken -TokenName $token.display_name -header $header -Data $token
                            Write-Verbose "Token `"$token.display_name`", created!";
                        }
                        # Включение аудита в vault
                        $auditData = @{
                            "options" = @{
                                "path" = "C:\Vault\data\audit\vault_audit.log"
                            }; "type" = "file"
                        } | ConvertTo-Json
                        Invoke-WebRequest -Uri "http://localhost:8200/v1/sys/audit/audit_file" -Body $auditData -Headers $header -UseBasicParsing -Method Put;
                    }
                    else {
                        Write-Verbose "Cannot find a file with vault keys"
                    }
                    Write-Verbose "Vault installed successfuly!";
                }
                else {
                    # Хэш локального Vault
                    $localHash = Get-FileHash $localPath\$fileName -Algorithm MD5;
                    # Хэш Vault на сервере
                    $remoteHash = Get-FileHash $sourcePath\$fileName -Algorithm MD5;

                    if (!(($localHash.Hash).Equals($remoteHash.Hash))) {
                        Write-Warning "New file of Vault detected on server!";
                        Write-Verbose "Start updating!";
                        # Остановка Vault
                        Stop-Service -Name $serviceName;

                        $serviceStatus = (Get-Service -Name $serviceName).status;

                        while ($serviceStatus -ne "Stopped") {
                            Write-Verbose "Waiting for `"$serviceName`" to stop";
                            Start-Sleep 1;
                        }

                        Write-Verbose "Starting copy files from server";

                        try {
                            Copy-Item -Path $sourcePath\$fileName -Destination $localPath\$fileName -Force -Confirm:$false;
                        }
                        catch {
                            Write-Error -Message "Failed to copy files from `"$sourcePath`" in to `"$localPath`"" -ErrorAction Stop;
                        }

                        Write-Verbose "Files copied successfully!";

                        Write-Verbose "Starting `"$serviceName`"";
                        Start-Service -Name $serviceName;
                    }
                    else {
                        Write-Warning "Vault is installed and files version are same.";
                    }
                }
            }
        }
    }
}

$comps = (get-adcomputer -filter *).name
Foreach ($nodename in $nodenames) {

    if ($nodename -eq "renew") {
        [string[]]$TargerServers = Get-childitem -path $confpath\$confname -name | % {($_ -split ".mof")[0]}
        Foreach ($a in $TargerServers) {
            if ($comps -notcontains $a) {
                write-host "Computer $a is not found in AD. MOF file was removed."
                remove-item -path "$confpath\$confname\$a.mof" -force
            }
            else {
                $nodename = $a
                &$confname
            }
        }
    }
    elseif ($nodename -eq "All") {
        Foreach ($a in $comps) {
            $nodename = $a
            &$confname
        }
    }
    elseif ($nodenames[0].IndexOf('*') -ne -1) {
        Foreach ($a in $($comps | ? {$_ -like $nodenames[0]})) {
            $nodename = $a
            &$confname
        }
    }
    else {
        if ($comps -notcontains $nodename) {
            write-host "Computer $a is not found in AD. Nothing to do."
        }
        else {
            &$confname
        }
    }
}
if ($pauseflag) {pause}