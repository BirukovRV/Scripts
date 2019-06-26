#Скрипт принимает имя проекта и сервера, в качестве второго принимает local или all. Разворачивает проект скриптом DeployOnServers.ps1, при указании в качестве имени сервера "all", в зависимости от типа проекта определяет и передает в скрипт соответствующие проекту имена серверов
param(
$projectname,
$servername
)
#повторяем запрос имени проекта до получения корректного ввода
if (!$projectname){while(!$projectname){$projectname = Read-host "ProjectName"; $pauseflag = $true}}

$localdeploy = $false
if ($servername -eq 'local'){ #если разворачиваем проект на текущем сервере, взводим флаг локального развертывания
<#
    if($env:COMPUTERNAME -like "lux-*") {
        exit 0
    }
#>
    $localdeploy = $true
    $servername = $env:COMPUTERNAME
    $usermask = ($servername -split "[-1-9]", 3)[1]
    if ($usermask -eq "winprox"){$usermask = "prox"}
    if ($usermask -eq "social"){$usermask = "GUI"}
    $cp = Get-date
    while (!$flaggoodsession){
        #проверяем, корректно ли работает сессия пользователя
        $FlagProcesses = (Get-WMIObject -Class Win32_Process -filter 'name="explorer.exe"')
        $count = 0
        foreach ($c in $FlagProcesses){if ($c.getowner().user -like "$usermask*"){$count = $count +1}}
        if($count -ge 5 -or (get-date) -gt $cp.AddMinutes(10)){$flaggoodsession = $true}
    }
    Start-Sleep -Seconds 3
}
#повторяем запрос имени сервера до получения корректного ввода
if (!$servername){while(!$servername){$servername = Read-host "Servername"; $pauseflag = $true}}

workflow DeployProjects {
param($projectlist, $servernames, $localdeploy)

foreach -parallel($projectname in $projectlist){
    foreach -parallel($serv in $servernames){
        inlineScript {
        #Берем последний коммит проекта в репозитории
        [Array]$folders = Get-ChildItem \\$($env:USERDOMAIN).lan\dfs\BinStorage\$($using:projectname) | sort LastWriteTime -Descending
        $lastcommitfolder = $folders[0]
        #определяем его тип
        $projecttype =  (Get-Content "$($lastcommitfolder.FullName)\_BuildProperty.txt")[0].split("=")[1]
        if($using:localdeploy){
            #если тип проекта - консольное приложение, разворачиваем его скриптом DeployOnServers.ps1 и заносим имя проекта в C:\autodeploy.log
            if ($projecttype -eq "console"){ 

                $using:projectname >> C:\autodeploy.log
                & \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\DeployOnServers.ps1 -commit $lastcommitfolder.name -projectname $Using:projectname -ServersSettings "#$using:serv#" -rollback
            }
        }else{ 
            #иначе, просто разворачиваем его скриптом DeployOnServers.ps1
            & \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\DeployOnServers.ps1 -commit $lastcommitfolder.name -projectname $Using:projectname -ServersSettings "#$using:serv#" -rollback 
        }
}}}}

$projectinfo = Import-Csv -Path \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\GoogleSheetChecker\projectsinfo.txt -Delimiter ","
#если в качесте имени сервера указано all,проверяем, не относится ли проект к криптовалютным
If($servername -eq "all"){ 
    [array]$serverstype = ($projectinfo | where {$_.ProjectName -eq $projectname}).serverstype.split(";",[System.StringSplitOptions]::RemoveEmptyEntries)

    Foreach ($p in $serverstype) {
        #Если проект работает с криптой, выбираем соответствующие ему сервера, заносим в $servername
        if($p -eq "CoinsPool1") {
            [string[]]$servername = (Get-ADComputer -Filter *  -SearchBase ("OU=PRODUCTION,OU=SERVERS,DC=$($env:USERDOMAIN),DC=lan")).name | ? {($_ -eq "wn-coins1") -or ($_ -eq "wn-coins2")} | sort
        } elseif($p -eq "CoinsPool2") {
            [string[]]$servername = (Get-ADComputer -Filter *  -SearchBase ("OU=PRODUCTION,OU=SERVERS,DC=$($env:USERDOMAIN),DC=lan")).name | ? {($_ -eq "wn-coins3") -or ($_ -eq "wn-coins4")} | sort
        } elseif($p -eq "CoinsPool3") {
            [string[]]$servername = (Get-ADComputer -Filter *  -SearchBase ("OU=PRODUCTION,OU=SERVERS,DC=$($env:USERDOMAIN),DC=lan")).name | ? {($_ -eq "lux-coins1") -or ($_ -eq "lux-coins2")} | sort
        } elseif($p -eq "CoinsPool4") {
            [string[]]$servername = (Get-ADComputer -Filter *  -SearchBase ("OU=PRODUCTION,OU=SERVERS,DC=$($env:USERDOMAIN),DC=lan")).name | ? {($_ -eq "lux-coins3") -or ($_ -eq "lux-coins4")} | sort
        } else {
            [string[]]$servername += (Get-ADComputer -Filter *  -SearchBase ("OU=PRODUCTION,OU=SERVERS,DC=$($env:USERDOMAIN),DC=lan")).name | ? {$_ -like "wn-$p*"} | sort
        } 
    }
    $projectlist = $projectname
#иначе, если указаны конкретные имена серверов и выставлен флаг локального развертывания
}elseif($localdeploy){ 
    $servnum = $env:COMPUTERNAME -replace "\D"
    $servermask = ($env:COMPUTERNAME -split "[-1-9]", 3)[1]
    $dcmask = [Regex]::Match($env:COMPUTERNAME, "^(\w+)-.*$").Groups[1].Value
    #проверяем, не относится ли сервер к криптовалютным
    if($servermask -like "*Coins*") {
        if(($env:COMPUTERNAME -eq "wn-coins1") -or ($env:COMPUTERNAME -eq "wn-coins2")) {
            
            $projectlist = ($projectinfo | ? {$_.ServersType -like "CoinsPool1" -and ($_.ServersNum -ge $servnum -or $_.ServersNum -lt 1)}).ProjectName
        } 
        elseif(($env:COMPUTERNAME -eq "wn-coins3") -or ($env:COMPUTERNAME -eq "wn-coins4")) {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "CoinsPool2" -and (($_.ServersNum -ge ($servnum - 2)) -or $_.ServersNum -lt 1)}).ProjectName
        } 
        elseif(($env:COMPUTERNAME -eq "lux-coins1") -or ($env:COMPUTERNAME -eq "lux-coins2")) {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "CoinsPool3" -and (($_.ServersNum -ge ($servnum - 2)) -or $_.ServersNum -lt 1)}).ProjectName
        }
        elseif(($env:COMPUTERNAME -eq "lux-coins3") -or ($env:COMPUTERNAME -eq "lux-coins4")) {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "CoinsPool4" -and (($_.ServersNum -ge ($servnum - 2)) -or $_.ServersNum -lt 1)}).ProjectName
        }
        
    } else {
        #иначе, проверяем на принадлежность к домену Lux
        if($dcmask -eq "lux") {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "*$servermask*" -and ($_.ServersNum -lt 1)}).ProjectName
        } else {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "*$servermask*" -and (($_.ServersNum -ge $servnum) -or ($_.ServersNum -lt 1))}).ProjectName
        }
        
    }
}else{ #иначе проверяем, не является ли сервер контроллером домена
    $servertype = ((Get-ADComputer $servername).DistinguishedName.split(",", 3)[1]).split("=")[1] 2>$null
    if ($servertype -eq "Domain Controllers"){Write-Warning "You stupid! It's a domain controller. Check parameters!"; pause; exit 1}
    #и существует ли он вообще
    if (!$servername){Write-Error "Server is not found!"; pause; exit 1}
	if ($projectname -eq "All"){
        $servnum = $servername -replace "\D"
        $servermask = ($servername -split "[-1-9]", 3)[1]
        $dcmask = [Regex]::Match($env:COMPUTERNAME, "^(\w+)-.*$").Groups[1].Value
        if($dcmask -eq "lux") {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "*$servermask*" -and ($_.ServersNum -lt 1)}).ProjectName
        } else {
            $projectlist = ($projectinfo | ? {$_.ServersType -like "*$servermask*" -and (($_.ServersNum -ge $servnum) -or ($_.ServersNum -lt 1))}).ProjectName
        }
    }else{
		$projectlist = $projectname
	}
}

Echo "`n`n`n`n`n"
Echo $projectlist
Echo "-----------------"
echo $servername
Echo "-----------------"

if (!$pauseflag){"Deployed projects:`n" > C:\autodeploy.log;}
#выполняем деплой
DeployProjects $projectlist $servername $localdeploy

if ($pauseflag){pause}else{"`n`nErrors:`n" >> C:\autodeploy.log; $Error>>C:\autodeploy.log}
# SIG # Begin signature block
# MIIIUwYJKoZIhvcNAQcCoIIIRDCCCEACAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2omEdsvjMeEiK0zg3sYoLtrt
# 5LygggW9MIIFuTCCBKGgAwIBAgITPQAAAJOiOe8wPOdkYQAAAAAAkzANBgkqhkiG
# 9w0BAQUFADBIMRMwEQYKCZImiZPyLGQBGRYDbGFuMRUwEwYKCZImiZPyLGQBGRYF
# d3NlcnYxGjAYBgNVBAMTEXdzZXJ2LUFERFMyLVdOLUNBMB4XDTE3MDkyNjE3MTA0
# M1oXDTE5MDkyNjE3MjA0M1owWTETMBEGCgmSJomT8ixkARkWA2xhbjEVMBMGCgmS
# JomT8ixkARkWBXdzZXJ2MRgwFgYDVQQLDA9DdXN0b21fQWNjb3VudHMxETAPBgNV
# BAMTCEZpcmVSYWluMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAol/2
# ZLzVug86E8aLVYM8b8bFwDXCw+akms8tNcSH8gzxGK3kYIgkdvuQGrofPrOD2nVk
# MTPMdpn4CPs5CKZSJT0oZgErvCAMmVhjHWlF/393O0j+vwO0Pb8M2NHQUzkIPF+5
# dNzSiInNNhXS48ZZNLgOjZmjW/f1CmL2IAtt4eY0z6qDc53ILuXDUaUndBnko5Zd
# Z+8lgsKMkRjVnppFRs36bqOGgvvgwFL5TcYMIQTWQyYtoKnT7BLgPaS8D1JH8BU1
# 98SwcnJjo20CKjgHnmaZ2erV6qv2Iya+c8bB4JXO+SMOvSxXyEA7/SkD6sGBrX1C
# 04FNVup9CZcrgn6TcQIDAQABo4ICiTCCAoUwPQYJKwYBBAGCNxUHBDAwLgYmKwYB
# BAGCNxUIgqrNTIG4kT+BxYc/h426EsTaZoFFgqGuWIOOqgECAWQCAQUwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwDgYDVR0PAQH/BAQDAgeAMBsGCSsGAQQBgjcVCgQOMAww
# CgYIKwYBBQUHAwMwHQYDVR0OBBYEFNMlzTFZUKjGAoEW9KNWnMmP+u/gMB8GA1Ud
# IwQYMBaAFORHEsxvI9aBIYvkrkzmwixOGD9LMIHOBgNVHR8EgcYwgcMwgcCggb2g
# gbqGgbdsZGFwOi8vL0NOPXdzZXJ2LUFERFMyLVdOLUNBLENOPWFkZHMyLXduLENO
# PUNEUCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1D
# b25maWd1cmF0aW9uLERDPXdzZXJ2LERDPWxhbj9jZXJ0aWZpY2F0ZVJldm9jYXRp
# b25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwgcEG
# CCsGAQUFBwEBBIG0MIGxMIGuBggrBgEFBQcwAoaBoWxkYXA6Ly8vQ049d3NlcnYt
# QUREUzItV04tQ0EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENO
# PVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9d3NlcnYsREM9bGFuP2NBQ2Vy
# dGlmaWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5
# MC0GA1UdEQQmMCSgIgYKKwYBBAGCNxQCA6AUDBJGaXJlUmFpbkB3c2Vydi5sYW4w
# DQYJKoZIhvcNAQEFBQADggEBAB6WYJYOs5ocVjXXhP0eJtGhjL+jI1X6uoLshWE5
# 6ob+mfvMWR0HPtIZvmO6Z1B39Yu6or/4c0RWZvlhhppxGZTt18HA9mRqrC61PX96
# 6EmQ3MJ0XuFsbBKIqNrNvmdKq4T8lCCcG11Srl+t1FqOMTJFwt0BQgVXXVCRt2sz
# pFim4RTH5vGnUrWoJ3O7QzhzaM6JtyD2nSPJJCG8rDEDrzXwQcHFrwEJQxSJwiCL
# 7aYr09xkr1Qcqgw4ktvvqchsf1aqqNzgoWcSaYY0ErD+Phd5RaP3uwKJArqrLYBZ
# Hq+f+FYh0c2AcTsowqvdK1euWkGrfp9FGJyqWcoEPlNNbmwxggIAMIIB/AIBATBf
# MEgxEzARBgoJkiaJk/IsZAEZFgNsYW4xFTATBgoJkiaJk/IsZAEZFgV3c2VydjEa
# MBgGA1UEAxMRd3NlcnYtQUREUzItV04tQ0ECEz0AAACTojnvMDznZGEAAAAAAJMw
# CQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcN
# AQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUw
# IwYJKoZIhvcNAQkEMRYEFHINxaC55gXvAL0dlrCowXVW52z9MA0GCSqGSIb3DQEB
# AQUABIIBAEX8aMkLBwaSrrfwN627dxOPoXIAkr8bm8ChhpLH7JohdFu4vb3ZD5ov
# lgf4ESPWru+MjwspownrkcArfnSaNfDU4POE1RYMpK6QR51UaxEqaXxhcb89M9Dd
# y+xYXOkX19skX37BuH1oJPpRPt5QWIJHSf5IHrUqAapiM8CWBmZ0f4HwkPgf9fi4
# RzVM2DkZ5JxFrQIU4018zgK1BeAmB3QBI69JFJg2fKqvTQoZjNFGz535XU+RGOWV
# xFiunoDYnpk3Jwms9Daj21uRUjx+MAWgxm3lGTcI+DS2T/yXnhGmBDQlLUkNbERe
# Ih5ukHEbsRiXEf+2q2XceBhm+NrdL70=
# SIG # End signature block
