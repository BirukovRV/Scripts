#Скрипт перезапускает пул приложений IIS, имя проекта и сайта запрашивается у пользователя, в кач-ве имени сервера принимает также "all"
param(
$projectname,
$servername,
[switch]$nogui
)
#повторяем запрос имени проекта и сервера до получения корректного ввода
if (!$projectname){while(!$projectname){$projectname = Read-host "ProjectName"; $pauseflag = $true}}
if (!$servername){while(!$servername){$servername = Read-host "Servername"; $pauseflag = $true}}

#если в качестве имени сервера передано all
If($servername -eq "all"){
    #считываем информацию о проекте из файла
    $projectinfo = Import-Csv -Path \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\GoogleSheetChecker\projectsinfo.txt -Delimiter ","
    $servername = $null
    #выбираем из нее тип сервера
    $serverstype = ($projectinfo | ? {$_.projectname -eq $projectname}).serverstype
    if(!$serverstype){Write-Error "Project is not found!"; pause; exit 1}
    Foreach ($p in [array]$serverstype.split(";",[System.StringSplitOptions]::RemoveEmptyEntries)){
        #заносим в переменную имена всех серверов домена, соответствующих данному типу
        [string[]]$servername += (Get-ADComputer -Filter *  -SearchBase ("OU=PRODUCTION,OU=SERVERS,DC=$($env:USERDOMAIN),DC=lan")).name | ? {$_ -like "*$p*"} | sort
    }
}

[array]$folders = dir \\$($env:USERDOMAIN).lan\dfs\BinStorage\$projectname | sort LastWriteTime -Descending
if ($folders){
        $files = Get-childitem -path ($folders[0].FullName + "\DeployPackage") -Recurse
        #получаем полное имя файла конфига
        $configpath = ($files | ? {$_.name -like "*.SetParameters.xml"}).fullname        
        #parsing XML
        $string = (Get-Content $configpath | Select-String '<setParameter name="IIS Web Application Name" value=').line.split(" ") | ? {if ($_ -like "value=*"){$_}}
        #получаем из конфига имя сайта
        $sitename =  $string.split('"')[1]
}

Echo "`n`n"
Echo $sitename
Echo "-----------------"
echo $servername
Echo "-----------------"
#Выполняем рестарт для каждого сервера в
foreach ($serv in $servername){
    Write-Output "Sending Restart $sitename pool on $serv"
    Invoke-Command -ComputerName $serv -ScriptBlock {Restart-webapppool -name $using:sitename -verbose}
    Start-Sleep -Seconds 3
}

if (!$nogui){pause}
# SIG # Begin signature block
# MIIIUwYJKoZIhvcNAQcCoIIIRDCCCEACAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPP/15wvBG5b0umRBidePOMrZ
# IlegggW9MIIFuTCCBKGgAwIBAgITPQAAAJOiOe8wPOdkYQAAAAAAkzANBgkqhkiG
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
# IwYJKoZIhvcNAQkEMRYEFN3zTwm4th5CoRopYjGHfxspU9aHMA0GCSqGSIb3DQEB
# AQUABIIBAHdGClCILnx+DW+nI/6J4tgxlLjpBCKGK7LfBAWz5C84EcVPhYn+6eQ5
# KKz1yzLraMljBfhrC4ghmBkzvpCGwbTbpDkDIKFeKJfCuDjl+zuuC4nzkz39sy3K
# 5LXqjzD4tfErVFzpHHZ8vkqbm4Jp3xLrE19Vd6z9+cfIsZ0w+GPdrCFsgQASCM97
# YByG28SbaDpWmdanBIRuhWEm08Dpy1gIh0xqjgb0LShmC+PU+HSSTUfL15EYu2LZ
# Ae3FdtfqL6v7YURxaeH+sRqwnvWUVFg8Jt2OSIBSfxarq44RB2G2K+zwUB1GmE1S
# rWzpiiiRcpIeo2CIAzhsCKWhqBfslo0=
# SIG # End signature block
