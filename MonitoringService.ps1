Param(
	[string[]]$nodenames,
	[PsObject]$MSConfig
)

$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))

set-location $confpath

If ($nodenames.count -eq 0) { $nodenames = (read-host "Enter Node names"); $pauseflag = $true }
$nodenames = $nodenames.split(", ", [System.StringSplitOptions]"RemoveEmptyEntries")

$MonitoringServiceKey = "admin/Scripts/MonitoringService"

try {
	$MSConfig = (Invoke-WebRequest -Method GET -UseBasicParsing -Uri "http://localhost:8500/v1/kv/$MonitoringServiceKey`?raw=1" | ConvertFrom-Json)
}
catch {
	Write-Warning "Error while returning MS config info from Consul."
}

Configuration $confname
{

	Param(
        [array]$MSConfig
	)

	Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node $nodename
    {
		Script MonitoringService
		{
			GetScript = {return $null}
			SetScript = {
                Import-Module 1xModule -Verbose:$false
				[string]$serviceName = "MonitoringService"

				if (test-path c:\MonitoringService\MonitoringService.exe){
					$process = Get-process -name $serviceName 2>$null
					if ($process) {
						stop-service $serviceName 2>$null
						while (!$process.HasExited){start-sleep 1}
					}
					& .\sc.exe delete $serviceName 2>$null
					While ((Get-service $serviceName 2>$null) -ne $null){start-sleep 1}
				}
				Stop-Process -name procexp -force 2>$null
				Stop-Process -name procexp64 -force 2>$null
				start-sleep 3
				Copy-Item "\\$($env:USERDOMAIN).lan\dfs\DSC\Sources\MonitoringService" c:\ -Recurse -Force

				New-Service -Name $serviceName -BinaryPathName C:\MonitoringService\MonitoringService.exe -DisplayName $serviceName -StartupType Automatic -Description "1xMonitoringService"
				start-sleep 1

				if ($MSConfig) {
					$serviceAccount = $MSConfig.ServiceAccount
				}

				if ($serviceAccount) {
					Get-CimInstance win32_service -filter "name='MonitoringService'" | Invoke-CimMethod -Name Change -Arguments @{StartName="$env:USERDOMAIN\$serviceAccount";StartPassword=""}
				}

				<#
					устанавливаем зависимость от консула

				$DependsOn = @('consul-agent','')
				$Service = Get-WmiObject win32_Service -filter "Name='MonitoringService'"
				$Service.Change($null,$null,$null,$null,$null,$null,$null,$null,$null,$null,$DependsOn)
				#>

				#& sc config 'MonitoringService' obj=$($env:USERDOMAIN)\Teamcity$

				& Sc.exe failure $serviceName actions=restart/1000/restart/1000/restart/1000 reset=2
				Start-Service $serviceName 2>$null

                <#
				[array]$ipAddress = (Get-NetIPAddress "192.168.*").IPAddress

				$tags = @(
					@{ProjectType = "win_service"} | ConvertTo-Json
				)
				$body = @{
					name = $serviceName;
					tags = $tags;
					Address = "$($ipAddress[0])";
					EnableTagOverride = $false;
					Checks = @(
						@{
							notes = "Critical functions check";
							HTTP = "http://127.0.0.1:2433/check?Type=Ping";
							Interval = "5s";
							DeregisterCriticalServiceAfter = "168h";
						};
					);
				}
				#>

				$consulRegisterParam = @{
					ProjectName=$serviceName;
					ProjectType='win_service';
					AdvancedParams=@{HealthPort=2434};
					Check='HTTP';
					UriCheckHTTP='http://127.0.0.1:2433/check?Type=Ping'
				}

				[string]$serverType = $null
				if($env:COMPUTERNAME -match "^.*(teamcity|tc|hv|adds|build).*$") {
					$serverType = 'manage'
					$consulRegisterParam += @{ServerType=$serverType}
				}

				$consulRequest = Register-ProjectToConsul @consulRegisterParam -Force -Quiet -NotFullTags -Verbose
				if($consulRequest) {
					Write-Verbose "The `"$serviceName`" service was successfully registered with the Consul"
				} else {
					$Host.UI.WriteErrorLine("Error regressing service `"$serviceName`" in Consul"); exit 1
				}
			}
			TestScript = {return $false}
		}
	}
}

$TargetServers = $null
$ADComputers = (Get-ADComputer -filter *).name
# Поиск DC
$DCComputers = (Get-ADDomainController -Filter *).Name
# Возвращение массива без DC
$ADComputers = $ADComputers | ? { $DCComputers -notcontains $_ }

ForEach ($nodename in $nodenames){
	switch -regex ($nodename) {
		"^renew$" { $TargetServers = Get-ChildItem -path $confpath\$confname -filter "*.mof" |% {$_.basename} }
		"^all$" { $TargetServers = $ADComputers }
		"\*" { $TargetServers += $ADComputers | ? {$_ -like $nodename} }
		DEFAULT { $TargetServers += $nodename }
	}
}

ForEach ($s in $TargetServers) {

	if ($ADComputers -notcontains $s) {
		if (Test-Path "$confpath\$confname\$s.mof") {
			remove-item -path "$confpath\$confname\$s.mof" -force
			write-verbose -message "Computer $s is not found in AD. MOF file was removed."
		} else {
			write-verbose -message "Computer $s is not found in AD. Nothing to do."
		}
	} else {
		$nodename = $s
		&$confname -MSConfig $MSConfig
	}
}

if ($pauseflag) { pause }