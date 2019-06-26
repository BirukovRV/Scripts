
                    [CmdletBinding()]
                    Param(
                        [Parameter(Mandatory=$true)][string]$pathConfig,
                        [Parameter(Mandatory=$true)][string]$nameService
                    )
                    
                    [array]$listConsulServer = $null

                    [CimInstance]$computerSystemInfoCimObj = Get-CimInstance -ClassName CIM_ComputerSystem

                    [string]$fqdnDnsNameHost = "{0}.{1}" -f $env:COMPUTERNAME, $computerSystemInfoCimObj.Domain
                    [array]$ipAddress += (Resolve-DnsName -Name $fqdnDnsNameHost -Type A -DnsOnly -NoHostsFile).IPAddress
                    
                    $listConsulServer = Resolve-DnsName -Name "consul.service.consul" -DnsOnly -NoHostsFile -TcpOnly -ErrorAction Stop | Where-Object {($_.QueryType -eq 'A') -and ($_.Section -eq 'Answer') -and ($_.IPAddress -notin $ipAddress)}
                    $listConsulServer = $listConsulServer.IPAddress
                    
                    if($listConsulServer.Count -eq 0) {exit 1} else {
                        if(Test-Path -Path $pathConfig) {
                            $configContent = Get-Content -Path $pathConfig | ConvertFrom-Json
                            if(Compare-Object $configContent.retry_join $listConsulServer){
                                $configContent.retry_join = $listConsulServer
                                $configContent | ConvertTo-Json | Out-File -FilePath $pathConfig -Encoding default
                                [string]$consulPath = (Get-Item -Path $pathConfig).DirectoryName
                                & "$consulPath\nssm.exe" restart "$nameService"
                            } {exit 0}  
                        } else {exit 1}   
                    }
                
