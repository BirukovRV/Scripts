Function IS-InSubnet() 
{ 
    <#
        .Synopsis
			Определить являится ли IP частью заданной подсети            
        .Parameter ipaddress 
            Исходный адрес сети
        .Parameter Cidr 
            Подсеть
        .Example
            IS-InSubnet -ipaddress 192.168.0.1 -cidr 192.168.0.0/24
    #>
[CmdletBinding()] 
[OutputType([bool])] 
Param( 
                    [Parameter(Mandatory=$true, 
                     ValueFromPipelineByPropertyName=$true, 
                     Position=0)] 
                    [validatescript({([System.Net.IPAddress]$_).AddressFamily -match 'InterNetwork'})] 
                    [string]$ipaddress="", 
                    [Parameter(Mandatory=$true, 
                     ValueFromPipelineByPropertyName=$true, 
                     Position=1)] 
                    [validatescript({(([system.net.ipaddress]($_ -split '/'|select -first 1)).AddressFamily -match 'InterNetwork') -and (0..32 -contains ([int]($_ -split '/'|select -last 1) )) })] 
                    [string]$Cidr="" 
    ) 

        if ([string]$ipaddress -eq "") {
            return $false
        }
        
        [int]$BaseAddress=[System.BitConverter]::ToInt32((([System.Net.IPAddress]::Parse(($cidr -split '/'|select -first 1))).GetAddressBytes()),0) 
        [int]$Address=[System.BitConverter]::ToInt32(([System.Net.IPAddress]::Parse($ipaddress).GetAddressBytes()),0) 
        [int]$mask=[System.Net.IPAddress]::HostToNetworkOrder(-1 -shl (32 - [int]($cidr -split '/' |select -last 1))) 

        if( ($BaseAddress -band $mask) -eq ($Address -band $mask)) 
        { 
 
            $status=$True 
        }else { 
 
            $status=$False 
        } 
        if ($ipaddress -eq "") {
            $status = $False
        }
return $status  
} 

function IS-INvSwitch {
	<#
		.Synopsis
			Определить, является ли сетевой интерфейс частью виртуального свича
		.Parameter name 
			Имя сетевого интерфейса
		.Example
			IS-INvSwitch -name "Microsoft Network Adapter Multiplexor Driver #2"
		.Notes
			Copyright © 2018 Oleg Gassak aka Ledzhy
	#>
    param (
        [string]$name = ""
    )
    
    #$description = Get-NetLbfoTeamNic -name $name | Select InterfaceDescription
    
    try {
        #$res = Get-VMSwitch -ErrorAction Stop| Where-Object {$_.NetAdapterInterfaceDescriptions -like $description.InterfaceDescription }
        $res = Get-VMSwitch -ErrorAction Stop| Where-Object {$_.NetAdapterInterfaceDescription -like $name }
    }
    catch {
        return $False       
    }

    if ($res) {
        return $True
    }
    else {
        return $False
    }    
}

function Get-NICTeams {
	<#
		.Synopsis
			Получить список NIC интерфейсов (вынесено в функцию из-за возможного расширения логики)
		.Notes
			Copyright © 2018 Oleg Gassak aka Ledzhy
	#>
    param (
        [string]$type=""
    )

    #[string]$query = 'SELECT * FROM MSFT_NetLbfoTeam'
    #[array] $intList = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2
    $intList = Get-NetLbfoTeam
    return $intList
}

function Get-InterfaceIP {
	<#
		.Synopsis
			Получить IP адрес сетевого интерфейса (запилен косталь, ибо если интерфейс выключен руками, запросить по нем данные не получается)
		.Parameter name 
            Имя сетевого интерфейса
		.Parameter index 
			Индекс сетевого интерейса            
		.Example
			Get-InterfaceIP -name "aggi"
		.Notes
			Copyright © 2018 Oleg Gassak aka Ledzhy
	#>
    param (
        [string]$name="",
        [int]$index = 0
    )
      
    try {
        $ip = Get-NetIPAddress -InterfaceAlias $name -AddressFamily IPv4 -ErrorAction Stop | Select IPAddress
        #$ip = Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4 -ErrorAction Stop | Select IPAddress
        return $ip
    }
    catch  {        
        # это костыли
        return @{IPAddress="0.0.0.0"} 
    }  
    
}

function Get-IPv4SubnetMask {
	<#
		.Synopsis
			Переобразовать маску формата 24 в ip адрес 255.255.255.0
		.Parameter prefix
			Имя сетевого интерфейса
		.Example
			Get-IPv4SubnetMask -prefix 22
		.Notes
			Copyright © 2018 Oleg Gassak aka Ledzhy
	#>
    param (
        [int]$prefix=24
    )
    $maskBinary = ('1' * $prefix).PadRight(32, '0')
    $DottedMaskBinary = $maskBinary -replace '(.{8}(?!\z))', '${1}.'
    $SubnetMask = ($DottedMaskBinary.Split('.') | foreach { [Convert]::ToInt32($_, 2) }) -join '.'
    return $SubnetMask
}


function Net-Discovery {
	<#
		.Synopsis
			Сфомировать JSON Discovery для Zabbix
            Данные хранят обнаруженные интерфейсы по различным критериям
            На данный момент используем только active (все активные интерфейсы)
		.Parameter type
			Тип определяет алгоритм обнаружения          
		.Notes
			Copyright © 2018 Oleg Gassak aka Ledzhy
	#>
    param (
        [string]$type=""
    )

    switch ($type) {
        <# 
            permitted - все разрешенные: внутренняя сеть
        #>
        permitted {
            $filled = $false
            $teamList = Get-NICTeams

            if ($teamList.Count -eq 0) {
                exit
            }
            foreach ($member in $teamList) {
                $ip = Get-InterfaceIP  -name $member.name
                              
                $description = Get-NetLbfoTeamNic -name $member.name | Select InterfaceDescription
                if ((IS-InSubnet -ipaddress $ip.IPAddress -Cidr 192.168.0.0/16)  -Or (IS-INvSwitch -name $description.InterfaceDescription)) {
                    $jsonPOST += '{"{#PERMITTED}":"' + $member.name + '"}, '
                    $filled = $true
                }                         
            }     

            if ($filled) {
                $jsonPOST = $jsonPOST.Substring(0, $jsonPOST.length -2)
                $jsonPOST = '{ "data":[' + $jsonPOST + ']}'   
                return $jsonPOST 
            }
            else {
                #break # заменить на exit
                exit
            }
        }
        <#
            forbidden - все запрещенные: внешняя сеать, без IP
        #>
        forbidden  {

            [string]$query = 'SELECT Name, InterfaceIndex, InterfaceDescription FROM MSFT_NetAdapter WHERE State=2'
            $adapterList = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2
            [System.Collections.ArrayList]$tmpList = $adapterList

            foreach ($adapter in $adapterList) {
                
                $address = Get-InterfaceIP -name $adapter.Name
                
                
                #$address.IPAddress
                if (IS-INvSwitch -name $adapter.InterfaceDescription) {
                    $tmpList.Remove($adapter)
                    continue
                }
            
               if (IS-InSubnet -ipaddress $address.IPAddress -Cidr 192.168.0.0/16) {
                    $tmpList.Remove($adapter)    
                    continue
                    #$exclude += @{Name=$adapter.Name; InterfaceIndex=$adapter.InterfaceIndex; InterfaceDescription=$adapter.InterfaceDescription}  
                }
            
                if (Get-NetLbfoTeamMember | WHERE InterfaceDescription -EQ $adapter.InterfaceDescription) {
                    $tmpList.Remove($adapter)    
                    continue    
                }                
            }        

            if ($tmpList.Count -gt 0) {
                foreach($index in $tmpList) {
                    $jsonPOST += '{"{#FORBIDDEN}":"' + $index.name + '"}, '
                }
                $jsonPOST = $jsonPOST.Substring(0, $jsonPOST.length -2)
                $jsonPOST = '{ "data":[' + $jsonPOST + ']}'   
                return $jsonPOST 
            }  
            else {
                exit
            }                                        
        }
        <#
            ipv6 - все активные с включенным протоколом IPv6
        #>
        ipv6 {
            [string]$query = 'SELECT Name, InterfaceIndex, InterfaceDescription FROM MSFT_NetAdapter WHERE State=2'
            $adapterList = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2    
            $filled = $false
            foreach ($adapter in $adapterList) {
                #Get-NetAdapterBinding -Name $adapter.Name -DisplayName "*IPv6*" | Where Enabled -eq $True
                if (Get-NetAdapterBinding -Name $adapter.Name -ComponentID "ms_tcpip6" | Where Enabled -eq $True) {
                    $jsonPOST += '{"{#IPV6}":"' + $adapter.Name + '"}, '
                    $filled = $True
                }
            }
            if ($filled) {
                $jsonPOST = $jsonPOST.Substring(0, $jsonPOST.length -2)
                $jsonPOST = '{ "data":[' + $jsonPOST + ']}'   
                return $jsonPOST                 
            }
            else {
                exit
            }
        }
        <#
            active - все активные сетевые интерфейсы
        #>
        active {

            [string]$query = 'SELECT Name, InterfaceIndex, InterfaceDescription FROM MSFT_NetAdapter WHERE State=2'
            $adapterList = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2

			if(-not $adapterList) {
				exit
			}

			# хак
            try {
				[System.Collections.ArrayList]$tmpList = $adapterList
            }
            catch {
				$tmpList = New-Object System.Collections.ArrayList
                $res = $tmpList.Add($adapterList)          
            }


            foreach ($adapter in $adapterList) {
                
                $address = Get-InterfaceIP -name $adapter.Name
                
                #$address.IPAddress
                <#if (IS-INvSwitch -name $adapter.InterfaceDescription) {
                    $tmpList.Remove($adapter)
                    continue
                }#>
                     
                if (Get-NetLbfoTeamMember | WHERE InterfaceDescription -EQ $adapter.InterfaceDescription) {
                    $tmpList.Remove($adapter)    
                    continue    
                }                
            }        

            if ($tmpList.Count -gt 0) {
                foreach($index in $tmpList) {
                    $jsonPOST += '{"{#NAME}":"' + $index.name + '","{#INDEX}":"' + $index.InterfaceIndex + '"}, '
                }
                $jsonPOST = $jsonPOST.Substring(0, $jsonPOST.length -2)
                $jsonPOST = '{ "data":[' + $jsonPOST + ']}'   
                return $jsonPOST 
            }  
            else {
                exit
            }              
        }
    }

}

function Handle-Intreface() {
	<#
		.Synopsis
            Обработка конекретно интефейса по заданному критерию                
		.Parameter name
            Имя сетевого интерфейс - не используется   
		.Parameter index
            Индекс сетевого интерфейса      
		.Parameter action
			Action определяет алгоритм проверки                              
		.Notes
			Copyright © 2018 Oleg Gassak aka Ledzhy
	#>    
    param (
        [string]$name = "",
        [int]$index = 0,
        [string]$action = ""
    )
    switch ($action) {
        # вывести результат, является ли интерфейс запрещенным
        forbidden {
         
            #[string]$query = "SELECT Name, InterfaceIndex, InterfaceDescription, State FROM MSFT_NetAdapter WHERE Name='$($name)'"
            [string]$query = "SELECT Name, InterfaceIndex, InterfaceDescription, State FROM MSFT_NetAdapter WHERE InterfaceIndex=$($index)"
            $adapter = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2              
            $address = Get-InterfaceIP -name $adapter.Name                        

            if (-not $adapter) {
                return 999               
            }
            # проверить состояние до всех действий, чтобы выключить тригер в zabbix
            if ($adapter.State -eq 3) {
                return 0
            }

            if (IS-INvSwitch -name $adapter.InterfaceDescription) {
                return 0
            }        
            elseif (IS-InSubnet -ipaddress $address.IPAddress -Cidr 192.168.0.0/16) {
                return 0
            }       
            elseif (Get-NetLbfoTeamMember | WHERE InterfaceDescription -EQ $adapter.InterfaceDescription) {
                return 0
            }
            else {
                return 1
            } 
          
        }
        # вывести результат по состоянию агрегированного интерфейса
        # в проверку может попасть не агрегированный интерфейс, тогда статус будет 999, на который тригер в zabbix не сработает
        # 999 не является ошибкой, просто не подходит по критерию
        perm_agg_status {
            <#
                статус определяется только у агрегированного интерфейса внутренней сети
            #>
            try {
                [string]$query = "SELECT Name, InterfaceIndex, InterfaceDescription, State FROM MSFT_NetAdapter WHERE InterfaceIndex=$($index)"
                $adapter = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2   
                $nic = Get-NetLbfoTeam -name $adapter.Name -ErrorAction stop
            }
            catch {
                return 999
            }
            
            if ($nic) {
                $ip = Get-InterfaceIP  -name $adapter.Name              
                $description = Get-NetLbfoTeamNic -name $adapter.Name | Select InterfaceDescription
                if ((IS-InSubnet -ipaddress $ip.IPAddress -Cidr 192.168.0.0/16)  -Or (IS-INvSwitch -name $description.InterfaceDescription)) {
                    [string]$query = "SELECT Status FROM MSFT_NetLbfoTeam WHERE Name='$($adapter.Name)'"
                    [array] $statusList = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2
                    return $statusList.Status
                }
                else {
                    return 999 # not defined
                }
            }
            else {
                return 999
            }
        }
        # вывести результат, включен ли протокол IPv6 на на разрешенном интерфейсе
        # # 999 не является ошибкой, просто не подходит по критерию
        perm_ipv6_status {
            [string]$query = "SELECT Name, InterfaceIndex, InterfaceDescription, State FROM MSFT_NetAdapter WHERE InterfaceIndex=$($index)"
            $adapter = Get-WmiObject -ComputerName "." -Query $query -Namespace ROOT\StandardCimv2   
            $address = Get-InterfaceIP -name $adapter.Name
            
            if (-not $adapter) {
                return 999               
            }

            if (IS-InSubnet -ipaddress $address.IPAddress -Cidr 192.168.0.0/16) {
                if (Get-NetAdapterBinding -Name $adapter.Name -ComponentID "ms_tcpip6" | Where Enabled -eq $True) {
                    return 1
                }           
                else {
                    return 0
                }   
            }
            else {
                return 999
            }
        }
    }
}


if ($args[1] -and -not $args[2]) {
    Net-Discovery -type $args[1]
}

if ($args[1] -and $args[2]) {
    Handle-Intreface -index $args[1] -action $args[2]
}
