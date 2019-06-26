
#=================================================================
param (
    [int]$sleepTime = 10, #sec
    [bool]$pause = $true
)

#$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
[string]$type=$null
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))
$types =  Get-ChildItem -Path "$confpath\Features" -Directory -Name
$i=0
Write-Output "-> Available configurations:"
Foreach ($type in $types)
{$i++
Write-Output " $i. $type"
$type=$null
}

 do  {
    $conf = Read-host "Enter configuration name/number or 'exit'"
    if ($conf -eq "exit") { exit 0 }
    switch -regex  ($conf)
     {
        "^\d+$" { $type = $types[$($conf-1)] }
        DEFAULT { $type = $conf}
     }   
    if ($types -notcontains $type) { $type = $null }

} until ($type)

$pathtoconf =  "$confpath\Features\$type"

[bool]$processWaitContinue = $True
[int[]]$process = $null

[array]$nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries")
if ($nodenames[0].IndexOf('*') -ne -1){
    [string[]]$nodenames = Get-childitem -path "$confpath\Features\$type" -name | % {($_ -split ".MOF")[0]} | ? {$_ -like $nodenames[0]}
}


[string[]]$TargetServers = $null
ForEach ($node in $nodenames) {
    switch -regex ($node) {
        "^all$|^\*$" { $TargetServers = Get-childitem -path "$confpath\Features\$type" -name | % {($_ -split ".MOF")[0]} }
        DEFAULT { $TargetServers += $node }
    }
}

$i = 0
ForEach ($a in $TargetServers) {
    $i += 1
    Write-Progress -Activity "Push DSC Configuration" -Status "Host: $a ($i/$(@($TargetServers).count))" -percentcomplete $(($i/@($TargetServers).count)*100) 
    switch -regex ($type) {
        "^(?:.+)?LCMConfig$" { $command = "Set-DscLocalConfigurationManager -ComputerName $a -Path $pathtoconf -verbose" }
        DEFAULT { $command = "Start-DscConfiguration -ComputerName $a -Path $pathtoconf -wait -verbose -force"; if ($pause) { $command += "; pause" }}
    }

    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    $curproc = (Start-process  powershell.exe -ArgumentList "-encodedCommand $encodedCommand" -PassThru).Id
    $process += $curproc

    $timer = 0
    while ($timer -lt $sleepTime) {
        if (Get-Process -Id $curproc 2>$null) {
            Start-Sleep 1
            $timer += 1
        } else {
            $timer = $sleepTime+1
        }
    }
}

if($Type -eq "ZabbixService") {
    do {
        if(!(Get-Process -Id $process 2>$null)) {
            $processWaitContinue = $False
        } else {
            Write-Host "Waiting for the deployment of DSC" -ForegroundColor Green
            Start-Sleep 10
        }
    } while($processWaitContinue)

    $reg_path = "HKLM:\Software\AdminAbiit\Zabbix"
    [string]$keyAPI = Get-ItemPropertyValue -Path $reg_path -Name KeyAPI
    Set-ItemProperty -Path $reg_path -Name KeyAPI -Value 0

    $Pairs = $KeyAPI -split ";"
    ForEach ($P in $Pairs) {
        $ipAddressZabbix,$keyZabbix = $p.split("=")

        $paramRequest = @{
            "Uri"="https://$ipAddressZabbix/api_jsonrpc.php";
            "ContentType"="application/json-rpc"
            "Body"= [ordered]@{
                "jsonrpc"="2.0";
                "method"="user.logout";
                "id"=1;
                "auth"=$keyZabbix;
                "params"=@()
            } | ConvertTo-Json
        }
        $logoutRequest = (Invoke-WebRequest @paramRequest -UseBasicParsing -Method Put).Content | ConvertFrom-Json

        [bool]$checkLogoutAPI = $false
        if($logoutRequest.PSObject.Properties.Name -contains "result") {
            $checkLogoutAPI = $True
            if(!$logoutRequest.result) {
                $checkLogoutAPI = $False
            }
        }
        if($checkLogoutAPI) {
            Write-Host "Exit from Zabbix API @ $ipAddressZabbix was successfully executed. API Key is released." -ForegroundColor Green
        } else {
            $Host.Ui.WriteErrorLine("Error leaving Zabbix API @ $ipAddressZabbix")
        }
    }
}
# SIG # Begin signature block
# MIIIhQYJKoZIhvcNAQcCoIIIdjCCCHICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUDtQ6lv/Te9qdYmqeLwKUNtoB
# GYagggXqMIIF5jCCBM6gAwIBAgITFgAAAIZ0TuEPmaJDNAAAAAAAhjANBgkqhkiG
# 9w0BAQ0FADBNMRMwEQYKCZImiZPyLGQBGRYDbGFuMRcwFQYKCZImiZPyLGQBGRYH
# YW1zc2VydjEdMBsGA1UEAxMUYW1zc2Vydi1BTVMtQUREUzEtQ0EwHhcNMTgxMDAy
# MTEzNDI3WhcNMjAxMDAyMTE0NDI3WjB3MRMwEQYKCZImiZPyLGQBGRYDbGFuMRcw
# FQYKCZImiZPyLGQBGRYHYW1zc2VydjEYMBYGA1UECwwPQ3VzdG9tX0FjY291bnRz
# MRwwGgYDVQQLDBNSb290X0FkbWluaXN0cmF0b3JzMQ8wDQYDVQQDEwZvcmFuZ2Uw
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC1fwhbpo8zzSV/bsHluUA/
# FzVRHU1Lyroeqe/7Sy8hjBCBzKRU0AKs8CLlsICYXhppREu+I88OOXPhMrBLqHLp
# i3lWjg5SNniTY5Ac+JvLstCanJSBMy+WHYGHP9XwSDqajKlXOcdJ1alfecG1kSdX
# KRwWBFK1Z7E/KeAKb3vWw+DJO7vmb4IoVM7PvBR1+bmU1+2pZq0sd4HK7qJUkUGU
# 7tPRe8qlr4k8jl8jBW//7J2dEwlinYLbIGODCttuOfZZ+3P8EYqS/ynM55AQuwWi
# nascaesOievYbyH7uARHBzn7PnGhFHWlYPJsUzUIjp1t6T7GP7brMi3QdxwQc+CJ
# AgMBAAGjggKTMIICjzA8BgkrBgEEAYI3FQcELzAtBiUrBgEEAYI3FQiDrpp7goOB
# Hv2JHYfEuHmFuMAKgU6Hlp1V6cgWAgFkAgEDMBMGA1UdJQQMMAoGCCsGAQUFBwMD
# MA4GA1UdDwEB/wQEAwIHgDAbBgkrBgEEAYI3FQoEDjAMMAoGCCsGAQUFBwMDMB0G
# A1UdDgQWBBQFpYSU0xeZdqnOqGY9xju/afwKyTAfBgNVHSMEGDAWgBRgPn7QLF/8
# yT1XkMqSL04laJEwNTCB1AYDVR0fBIHMMIHJMIHGoIHDoIHAhoG9bGRhcDovLy9D
# Tj1hbXNzZXJ2LUFNUy1BRERTMS1DQSxDTj1hbXMtYWRkczEsQ049Q0RQLENOPVB1
# YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRp
# b24sREM9YW1zc2VydixEQz1sYW4/Y2VydGlmaWNhdGVSZXZvY2F0aW9uTGlzdD9i
# YXNlP29iamVjdENsYXNzPWNSTERpc3RyaWJ1dGlvblBvaW50MIHGBggrBgEFBQcB
# AQSBuTCBtjCBswYIKwYBBQUHMAKGgaZsZGFwOi8vL0NOPWFtc3NlcnYtQU1TLUFE
# RFMxLUNBLENOPUFJQSxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2
# aWNlcyxDTj1Db25maWd1cmF0aW9uLERDPWFtc3NlcnYsREM9bGFuP2NBQ2VydGlm
# aWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MC0G
# A1UdEQQmMCSgIgYKKwYBBAGCNxQCA6AUDBJvcmFuZ2VAYW1zc2Vydi5sYW4wDQYJ
# KoZIhvcNAQENBQADggEBAMxB9mUd/yjGsiKYmiSm2RM2Np2da22zl92KQuRW7Aer
# N1NymvBoZpXjf4IyNH0kBc54Ao/Urcp0l1H0sSP80uRoNLNAhXytCwJ+XUQMPY6w
# 4gKLqltuf9jNw8G4bHqIXFlZlZ4+Zuaze9NwB2AJV8ruJD3dnDm+u+Ae8VnOOQyx
# OGGbRf9JKJRGZYcbFEHO1Lw5W4iU0cz3dw0F1suFOYftwxiFyz47GwAOKfsiCfDC
# Ghl0RtCsJmB8RZF87zyMnDD8Qd/toxoS5jKv6Ph8UspsiyuXSErbn5y2maFO9xL0
# DU+JfK4cCxlwHbqU4a04TMa7iQTKuADvSDWkXi85BOUxggIFMIICAQIBATBkME0x
# EzARBgoJkiaJk/IsZAEZFgNsYW4xFzAVBgoJkiaJk/IsZAEZFgdhbXNzZXJ2MR0w
# GwYDVQQDExRhbXNzZXJ2LUFNUy1BRERTMS1DQQITFgAAAIZ0TuEPmaJDNAAAAAAA
# hjAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG
# 9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIB
# FTAjBgkqhkiG9w0BCQQxFgQUYv0bVyl18NEANphKSqk0BlhX2sEwDQYJKoZIhvcN
# AQEBBQAEggEAG4/H78/deViCUZqNBKnM3n4l1U9DfRLBdgW9Pyu0FOnVeFUScG9L
# ytvFV9KuhTmIPGR+mQfobGWNd+opnGm23W88aM7F7GFfwa14EGtZNSMz2FMaS7vK
# q5qTvOv4s0AiBRMHppVZJ417WPsjWYLkdN85Etl0VnmzvpBV7TAC96rE8RrRho/s
# mIZGBKTxtDr3qEkz0SPfPbhlm7PLDXG9fNpMPX87IwJd/bgsCH9GondzCwUM8ZNj
# FFPwDnHX1fSbNZve0TX3jBmteVYPPHqHV1GS+yMHyRF5fKDImAygji5sj2hcwMm1
# bwUnNFlIXoLPLyYEuAbeC0fv4CacYpyFVg==
# SIG # End signature block
