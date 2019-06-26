$confname = $MyInvocation.MyCommand.Name.split(".")[0] #as scriptname
$confpath = $MyInvocation.MyCommand.Path.substring(0, $MyInvocation.MyCommand.Path.lastindexof('\'))
set-location $confpath
[string[]]$nodenames = $args
If ($nodenames.count -eq 0) { $nodenames = (read-host "Enter Node names").split(", ", [System.StringSplitOptions]"RemoveEmptyEntries"); $pauseflag = $true }

Configuration $confname {

    Import-DscResource -ModuleName "PSDesiredStateConfiguration"

    Node $nodename {

        Script Add_Healthcheck_Consul {

            GetScript  = { return $null }
            TestScript = { return $false }
            SetScript  = {
                $consulScriptName = "NodeHealthCheck.ps1"
                $scriptPathFrom = "\\$($env:userdomain).lan\DFS\Scripts\Servers\$consulScriptName"
                $scriptPathTo = "C:\Consul\Scripts"

                $configContent = Get-Content -Path "C:\Consul\config.json" | ConvertFrom-Json

                $confData = @{
                    timeout = "30s";
                    name     = "Node health";
                    id       = "self";
                    args     = @("cmd", "/c", "powershell -ExecutionPolicy Bypass -NoProfile -File  C:/Consul/Scripts/NodeHealthCheck.ps1");
                }

                if ($configContent.PSObject.Properties.Name -notcontains "enable_local_script_checks" -and $configContent.PSObject.Properties.Name -notcontains "check") {
                    $configContent | add-member -Name "enable_local_script_checks" -Value $true -MemberType NoteProperty -Force
                    $configContent | add-member -Name "check" -Value $confData -MemberType NoteProperty -Force
                    $configContent | ConvertTo-Json -depth 32 | Set-Content -Path "C:\Consul\config.json"
                    Write-Host "Member: `"enable_local_script_checks`" added to `"config`" successfuly!"
                }

                Start-Sleep 1
                Restart-Service consul-agent

                $i = 0
                while ((Get-Service -Name consul-agent).Status -ne "Running") {
                    $i++
                    Write-Host $i
                }
                Copy-Item -Path $scriptPathFrom -Destination $scriptPathTo -Force
            }
        }
    }
}

[string[]]$TargetServers = $null
$ADComputers = (Get-ADComputer -filter *).name

ForEach ($nodename in $nodenames) {
    switch -regex ($nodename) {
        "^renew$" { $TargetServers = Get-ChildItem -path $confpath\$confname -filter "*.mof" | % { $_.basename } }
        "^all$" { $TargetServers = $ADComputers }
        "\*" { $TargetServers += $ADComputers | ? { $_ -like $nodename } }
        DEFAULT { $TargetServers += $nodename }
    }
}

ForEach ($s in $TargetServers) {
    if ($ADComputers -notcontains $s) {
        if (Test-Path "$confpath\$confname\$s.mof") {
            remove-item -path "$confpath\$confname\$s.mof" -force
            write-verbose -message "Computer $s is not found in AD. MOF file was removed."
        }
        else {
            write-verbose -message "Computer $s is not found in AD. Nothing to do."
        }
    }
    else {
        $nodename = $s
        &$confname
    }
}
# SIG # Begin signature block
# MIIIhQYJKoZIhvcNAQcCoIIIdjCCCHICAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUl98WfzDIqWYhWOh0w3bB+hEZ
# IZigggXqMIIF5jCCBM6gAwIBAgITFgAAAIZ0TuEPmaJDNAAAAAAAhjANBgkqhkiG
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
# FTAjBgkqhkiG9w0BCQQxFgQUBAyFg/hMLm2goPzelNFH+sBFId8wDQYJKoZIhvcN
# AQEBBQAEggEAQBNgdihbREluV48k+2318EVPwUJHNwpRPY2ynWnZ4wU5YZNqhyLB
# gyMaUJIPQR3anILDXhsYfu+ri9HM9MZkclL6Aks4yDX65SV38EOZpRsIhI+1Tsw8
# B6+AC7MrtcyUzJmRxqOBDsfCIO6IsTKNxkdQ9bw9bp+r8PUOpQQ4t7aTM7xAhMj4
# dN6YU7tbyeGlaZziVQCouRw6JVVGSvODQV68rbdtjmn+eH03hBeC5j6C/GL8Cblh
# 7YX9jUw9Ey1OUmvPx8i1XkvToFnnCQf+pX4B4BzDzl7LPxtKiFkq31yB2JDVQeOj
# zvD85By3Wf7z3Zlr9D0BDY5JEAwik7fq5g==
# SIG # End signature block
