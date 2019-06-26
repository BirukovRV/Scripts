<#PSScriptInfo

.VERSION 0.0.0.9

.GUID a227f161-92aa-4444-b379-1656e0aa2b6f

.AUTHOR fr

.COMPANYNAME

.COPYRIGHT

.TAGS

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES


.PRIVATEDATA

#>

<#

.DESCRIPTION
 Auto Logon RDP User

#>
[CmdletBinding()]
Param(
    [ValidateNotNullOrEmpty()][string]$VaultHost='vault.service.consul',
    [Parameter(Mandatory=$True)][ValidatePattern('^[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12}$')][string]$Token,
    [Parameter(Mandatory=$True)][ValidateSet('Prod','ProdDedicated','Stage','Test')][string]$ServerType,
    [switch]$SecureServer
)

# Ожидание запуска прослушивателя RDP
[datetime]$lastBootTime = (Get-ComputerInfo).OsLastBootUpTime
[bool]$rdpListinerStarted = $False
do {
    [int64]$filterTime = $null
    $filterTime = [int64]((Get-Date)-$lastBootTime).TotalMilliseconds
    [string]$eventLogFilter = "<QueryList>`n`t<Query Id=`"0`" Path=`"Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational`">`n`t`t<Select Path=`"Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational`">*[System[(EventID=258) and TimeCreated[timediff(@SystemTime) &lt;= $filterTime]]]</Select>`n`t</Query>`n</QueryList>"
    [array]$rdpListinerEvents = $null
    $rdpListinerEvents = Get-WinEvent -LogName "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational" -FilterXPath $eventLogFilter -ErrorAction SilentlyContinue
    if($rdpListinerEvents.Count -gt 0) {
        $rdpListinerStarted = $True
    }
} while (!$rdpListinerStarted)

Start-Sleep 10

Import-Module 1xModule
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

[string]$SecureServerString = $null
[string]$partUrlServerSecurity = $null
if($SecureServer) {
    $SecureServerString = 'Protected'
    $partUrlServerSecurity = 'secureservers'
} else {
    if($ServerType -match '^(Prod|Test|Stage)$') {
        $SecureServerString = 'NotProtected'
        $partUrlServerSecurity = 'servers'
    } elseif($ServerType -eq 'ProdDedicated') {
        $SecureServerString = 'NotProtected Dedicated'
        $partUrlServerSecurity = 'dedicatedservers'
    }
}

[string]$metaInformation = "[b][size=16]Script autologon GUI users.[/size][/b]`nComputer name: $env:COMPUTERNAME`nServer type: $ServerType - $SecureServerString"

try {
    [string]$initUrl = 'https://' + $VaultHost + ':8200/v1/sys/init'
    [bool]$requestVaultInitStatus = $False
    $requestVaultInitStatus = ((Invoke-WebRequest -Uri $initUrl -Method Get -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json).initialized
} catch [System.Net.WebException] {
    Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]The request to the URL:$initUrl was completed with an error.`nCritical error.[/b]`n$_[/color]" -Quiet
    exit 1
}

if($requestVaultInitStatus) {
    try {
        [string]$sealedUrl = 'https://' + $VaultHost + ':8200/v1/sys/seal-status'
        [bool]$requesVaultSealedStatus = ((Invoke-WebRequest -Uri $sealedUrl -Method Get -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json).Sealed
    } catch [System.Net.WebException] {
        Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]The request to the URL:$sealedUrl was completed with an error.`nCritical error.[/b]`n$_[/color]" -Quiet
        exit 1
    }
    if($requesVaultSealedStatus) {
        Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]Vault at $VaultHost locked.`nCritical error.[/color][/b]" -Quiet
        exit 1
    }
} else {
    Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]Vault at $VaultHost not initialized.`nCritical error.[/color][/b]" -Quiet
    exit 1
}

[string[]]$listGuiAccounts = $null
[string]$ADSecurityGroup = $null

if(!$SecureServer) {
    if($ServerType -eq 'Prod') {
        $ADSecurityGroup = 'GuiAccounts'
        $listGuiAccounts = (Get-ADGroupMember -Identity $ADSecurityGroup -ErrorAction SilentlyContinue).Name | Sort-Object
    } elseif($ServerType -eq 'ProdDedicated') {
        $ADSecurityGroup = 'GuiDedicatedAccounts'
        $listGuiAccounts = (Get-ADGroupMember -Identity $ADSecurityGroup -ErrorAction SilentlyContinue).Name | Sort-Object
    } else {
        $ADSecurityGroup = 'GuiAccountsTest'
        $listGuiAccounts = (Get-ADGroupMember -Identity $ADSecurityGroup -ErrorAction SilentlyContinue).Name | Sort-Object
    }

} else {
    if($ServerType -eq 'Prod') {
        $ADSecurityGroup = 'GuiSecureAccounts'
        $listGuiAccounts = (Get-ADGroupMember -Identity $ADSecurityGroup -ErrorAction SilentlyContinue).Name | Sort-Object
    }
}

if(!$listGuiAccounts) {
    Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]The '$ADSecurityGroup' security group of the $env:USERDNSDOMAIN domain is empty.`nCritical error.[/color][/b]" -Quiet
    exit 1
}

# Определение префикса серверов, по имени домена
[string]$serverNamePrefix = $null
switch -Regex ($env:USERDOMAIN) {
    "^wserv$" {$serverNamePrefix = "(wn|lux)"; break}
    "^.*serv$" {$serverNamePrefix = [Regex]::Match($env:USERDOMAIN, "^(\w+)(?=serv$)", 'IgnoreCase').Value; break}
    default {$serverNamePrefix = $env:USERDOMAIN}
}

[string]$userMask = ($env:computername -split "[-1-9]", 3)[1]
if($ServerType -eq 'Prod' -and !$SecureServer) {
    $listGuiAccounts = $l | where {$_ -match "^($usermask|GUI)\d{1,2}$"}
} elseif($ServerType -eq 'ProdDedicated' -and !$SecureServer) {
    $listGuiAccounts = $listGuiAccounts | where {$_ -match "^$usermask\d{1,2}$"}
}

if(!$listGuiAccounts) {
    Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]No account was found for the server in AD.`nCritical error.[/color][/b]" -Quiet
    exit 1
}

[string]$partUrlServerType = $null
switch -Regex ($ServerType) {
    '^Prod(Dedicated)?$' {$partUrlServerType = '~prod'; break}
    '^(test|stag(e|ing))$' {$partUrlServerType = '~test'; break}
}

[string]$urlVaultRequestSecret = 'https://' + $VaultHost + ':8200/v1/secret/' + $partUrlServerSecurity + '/guiaccounts/' + $partUrlServerType
[string]$urlVaultRequestSecret = $urlVaultRequestSecret.ToLower()
[PSObject]$vaultSecretData = $null

try {
    $requestVaultSecret = Invoke-WebRequest -UseBasicParsing -Uri $urlVaultRequestSecret -Method Get -Headers @{"X-Vault-Token"=$Token}
} catch [System.Net.WebException] {
    Push-1xMessage -Targets '54777' -Message "$metaInformation`n[b][color=Red]Error getting credentials from Vault[/b]`n$_[/color]`nCritical error." -Quiet
    exit 1
}

$vaultSecretData = ($requestVaultSecret.Content | ConvertFrom-Json).data

if($vaultSecretData) {
    [array]$accauntCredentials = $null
    foreach ($lGA in $listGuiAccounts) {
        if($vaultSecretData.PSObject.Properties.Name -contains $lGA) {
            $accauntCredentials += New-Object PSObject -Property @{UserName=$lGA; Password=[string]($vaultSecretData.PSObject.Properties | where {$_.Name -eq $lGA}).Value; Logon=[bool]$False}
        } else {
            $accauntCredentials += @{UserName=$lGA; Password='NotFound'; Logon=[bool]$False}
        }
    }
}

[string[]]$foundVaultAccounts = $null
$foundVaultAccounts = ($accauntCredentials | where {$_.Password -ne 'NotFound'}).UserName
[string[]]$notFoundVaultAccounts = $null
$notFoundVaultAccounts = ($accauntCredentials | where {$_.Password -eq 'NotFound'}).UserName

if($foundVaultAccounts) {
    $metaInformation += "`n[b][color=Green]Vault found credentials for users:[/b] " + [string]::Join(',', $foundVaultAccounts) + '[/color]'
}

if($notFoundVaultAccounts) {
    $metaInformation += "`n[b][color=Red]Vault not found credentials for users::[/b] " + [string]::Join(',', $notFoundVaultAccounts) + '[/color]'
}

if(!$foundVaultAccounts) {
    $metaInformation += "`n[b][color=Red]No credentials found for all users.`nCritical error.[/color][/b]"
    Push-1xMessage -Targets '54777' -Message $metaInformation -Quiet
    exit 1
}

$nugetPackageProviderConfig = @{
    Name='NuGet'
    MinimumVersion='2.8.5.201'
}

[object[]]$currentNugetPackageProvider = $null
$currentNugetPackageProvider = Get-PackageProvider -Name $nugetPackageProviderConfig.Name -ListAvailable | Sort-Object Version -Descending
[bool]$installNugetPackageProvider = $False
if($currentNugetPackageProvider.Count -eq 0) {
    $installNugetPackageProvider = $True
} elseif ($currentNugetPackageProvider[0].Version -lt [Version]::Parse($nugetPackageProviderConfig.MinimumVersion)) {
    $installNugetPackageProvider = $True
}

if($installNugetPackageProvider) {
    Install-PackageProvider @nugetPackageProviderConfig -Force
}

$credentialManagerModuleConfig = @{
    NameModule='CredentialManager';
    VersionModule='2.0';
    RepositoryModule='PSGallery'
}

$credentialManagerModuleInformation = $null
$credentialManagerModuleInformation = Get-Module -Name $credentialManagerModuleConfig.NameModule -ListAvailable
if(!$credentialManagerModuleInformation) {
    Install-Module -Name $credentialManagerModuleConfig.NameModule -Repository $credentialManagerModuleConfig.RepositoryModule -MinimumVersion $credentialManagerModuleConfig.VersionModule -Force -Confirm:$false
} else {
    $credentialManagerModuleInformationRepository = $null
    $credentialManagerModuleInformationRepository = Find-Module -Name $credentialManagerModuleConfig.NameModule -MinimumVersion $credentialManagerModuleConfig.VersionModule -Repository $credentialManagerModuleConfig.RepositoryModule
    if(([Version]::Parse($credentialManagerModuleInformationRepository.Version)) -gt $credentialManagerModuleInformation.Version) {
        Install-Module -Name $credentialManagerModuleConfig.NameModule -Repository $credentialManagerModuleConfig.RepositoryModule -MinimumVersion $credentialManagerModuleConfig.VersionModule -Force -Confirm:$false
    }
}

[array]$mstscProcess = $null
[string]$serverFullName = $env:COMPUTERNAME + '.' + $env:USERDOMAIN + '.lan'
"ID:0`tStartOperations" | Out-File -FilePath "C:\dbugrdp.txt" #debug
foreach ($aC in ($accauntCredentials | where {$_.Password -ne 'NotFound'})) {
    [string]$UserName = $null
    $UserName = $env:USERDOMAIN + "\" + $aC.UserName
    [int64]$filterTime = $null
    $filterTime = [int64]((Get-Date)-$lastBootTime).TotalMilliseconds
    [string]$eventLogFilter = "<QueryList>`n`t<Query Id=`"0`" Path=`"Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`">`n`t`t<Select Path=`"Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`">*[System[(EventID=21 or EventID=22) and TimeCreated[timediff(@SystemTime) &lt;= $filterTime]]] and *[UserData[EventXML[(User=`"$UserName`")]]]</Select>`n`t</Query>`n</QueryList>"
    [void](New-StoredCredential -Target $serverFullName -UserName $UserName -Password $aC.Password -Comment 'AutologonScript')
    $mstscProcess += New-Object PSObject -Property @{
        UserName=$aC.UserName;
        ProcessInfo=(Start-Process -FilePath mstsc.exe -ArgumentList "/v:$serverFullName" -PassThru)
    }
    "ID:1`t$(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.Id)`t$(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime)" | Out-File -FilePath "C:\dbugrdp.txt" -Append

    #$ttlLogon = Get-Date
    [bool]$isLogon = $False
    do {
        "ID:2`t$((Get-Process -ID $(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.Id) -ErrorAction SilentlyContinue).ID)`tProcessRDP-$($aC.UserName)" | Out-File -FilePath "C:\dbugrdp.txt" -Append
        [array]$logEvents = $null
        $logEvents = Get-WinEvent -LogName "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" -FilterXPath $eventLogFilter -ErrorAction SilentlyContinue
        if($logEvents.Count -eq 2) {
            if(($logEvents.ID -contains 21) -and ($logEvents.ID -contains 22)) {
                $aC.Logon = $isLogon = $True
                "ID:3`tEvents 21 and 22 found" | Out-File -FilePath "C:\dbugrdp.txt" -Append
            }
        } else {
            "ID:4`tEvents 21 and 22 NOT found" | Out-File -FilePath "C:\dbugrdp.txt" -Append
        }
        if(((Get-Date)-($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime).TotalSeconds -ge 60) {
            "ID:5`t$((Get-Process -ID $(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.Id) -ErrorAction SilentlyContinue).ID)`t$(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime)" | Out-File -FilePath "C:\dbugrdp.txt" -Append
            "ID:6`t$(((Get-Date)-($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime).TotalSeconds)`t timeOutLogon" | Out-File -FilePath "C:\dbugrdp.txt" -Append
            $isLogon = $True
        }
        if(!$isLogon) {
            "ID:7`t$((Get-Process -ID $(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.Id) -ErrorAction SilentlyContinue).ID)`t$(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime)`tExecutingTime-$(((Get-Date)-($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime).TotalSeconds)" | Out-File -FilePath "C:\dbugrdp.txt" -Append
            Start-Sleep 5
        }
    } while(!$isLogon)
    if(Get-Process -Id ($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.ID -ErrorAction SilentlyContinue) {
        Start-Sleep 1
        "ID:8`t$((Get-Process -ID $(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.Id) -ErrorAction SilentlyContinue).ID)`t$(($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime)`tExecutingTime-$(((Get-Date)-($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.StartTime).TotalSeconds)`tStopProcess" | Out-File -FilePath "C:\dbugrdp.txt" -Append
        Stop-Process -ID ($mstscProcess | where {$_.UserName -eq $aC.UserName}).ProcessInfo.ID -Force
    }
}

[void](Remove-StoredCredential -Target $serverFullName -ErrorAction SilentlyContinue)

if($accauntCredentials.Logon -notcontains $True) {
    $metaInformation += "`n[b][color=Red]All accounts for which it was possible to get passwords from Vault could not log in.`nCritical error.[/color][/b]"
    Push-1xMessage -Targets '54777' -Message $metaInformation -Quiet
    exit 1
} else {
    [string[]]$notLogonUsers = $null
    $notLogonUsers = ($accauntCredentials | where {($_.Password -ne 'NotFound') -and !$_.Logon}).UserName
    [string[]]$logonUsers = $null
    $logonUsers = ($accauntCredentials | where {($_.Password -ne 'NotFound') -and $_.Logon}).UserName

    if($notLogonUsers) {
        $metaInformation += "`n[b][color=Red]Unable to log in to accounts:[/b] " + [string]::Join(',', $notLogonUsers) + '[/color]'
    }

    if(!$notLogonUsers -and $logonUsers) {
        $metaInformation += "`n[b][color=Green]All accounts for which it was possible to obtain passwords from Vault successfully logged on to the system[/b][/color]"
        Push-1xMessage -Targets '54777' -Message $metaInformation -Quiet
        exit 0
    }

    if($logonUsers) {
        $metaInformation += "`n[b][color=Green]Accounts successfully logged on to the system:[/b] " + [string]::Join(',', $logonUsers) + '[/color]'
        Push-1xMessage -Targets '54777' -Message $metaInformation -Quiet
        exit 0
    }
}
# SIG # Begin signature block
# MIIIkgYJKoZIhvcNAQcCoIIIgzCCCH8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU0RkV3PKPWgVhacRaNb82CsuL
# yKKgggX3MIIF8zCCBNugAwIBAgITFgAAAIXTMiU6mvbfMQAAAAAAhTANBgkqhkiG
# 9w0BAQ0FADBNMRMwEQYKCZImiZPyLGQBGRYDbGFuMRcwFQYKCZImiZPyLGQBGRYH
# YW1zc2VydjEdMBsGA1UEAxMUYW1zc2Vydi1BTVMtQUREUzEtQ0EwHhcNMTgwOTI3
# MTUyMTU1WhcNMjAwOTI3MTUzMTU1WjCBgTETMBEGCgmSJomT8ixkARkWA2xhbjEX
# MBUGCgmSJomT8ixkARkWB2Ftc3NlcnYxHjAcBgNVBAsTFVN5c3RlbSBBZG1pbmlz
# dHJhdG9yczENMAsGA1UECxMEUm9vdDEPMA0GA1UECxMGRG9tYWluMREwDwYDVQQD
# EwhmaXJlcmFpbjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKr7liOc
# Xbwbeh3+y+jf62zlKlaW+UkfWpUq7vWFJtXd9XHQu9lQal4cnRyQZ6TNWi5HsCVd
# g7xa3vKj8LFOYR/o0rpUSJC5Ywq7jG85onLEsDX//8q1FEmi/RBWjTvz8uo7Yav9
# P29eatj1yJVCaWqEWLTUTyKcgicty2zjjjx3H0+EjJkVkHVG36EuX1hxynWkWvpP
# uiX7Y4tJoFxi9thWuKjx1uieOqvuRUY9rM8n+TWgz8gPkDMCb+a1B678PRO+butj
# VLsOS7d++8HFIstvweFZDguaqqaIFX5PtWYKndzd454tSy/+iRVVyY9siM1JgSY4
# xRHo9p+KpFibSxcCAwEAAaOCApUwggKRMDwGCSsGAQQBgjcVBwQvMC0GJSsGAQQB
# gjcVCIOumnuCg4Ee/Ykdh8S4eYW4wAqBToeWnVXpyBYCAWQCAQMwEwYDVR0lBAww
# CgYIKwYBBQUHAwMwDgYDVR0PAQH/BAQDAgeAMBsGCSsGAQQBgjcVCgQOMAwwCgYI
# KwYBBQUHAwMwHQYDVR0OBBYEFLKx/j584PdFam2uzzJ2bMqXc+ujMB8GA1UdIwQY
# MBaAFGA+ftAsX/zJPVeQypIvTiVokTA1MIHUBgNVHR8EgcwwgckwgcaggcOggcCG
# gb1sZGFwOi8vL0NOPWFtc3NlcnYtQU1TLUFERFMxLUNBLENOPWFtcy1hZGRzMSxD
# Tj1DRFAsQ049UHVibGljJTIwS2V5JTIwU2VydmljZXMsQ049U2VydmljZXMsQ049
# Q29uZmlndXJhdGlvbixEQz1hbXNzZXJ2LERDPWxhbj9jZXJ0aWZpY2F0ZVJldm9j
# YXRpb25MaXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQw
# gcYGCCsGAQUFBwEBBIG5MIG2MIGzBggrBgEFBQcwAoaBpmxkYXA6Ly8vQ049YW1z
# c2Vydi1BTVMtQUREUzEtQ0EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZp
# Y2VzLENOPVNlcnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9YW1zc2VydixEQz1s
# YW4/Y0FDZXJ0aWZpY2F0ZT9iYXNlP29iamVjdENsYXNzPWNlcnRpZmljYXRpb25B
# dXRob3JpdHkwLwYDVR0RBCgwJqAkBgorBgEEAYI3FAIDoBYMFGZpcmVyYWluQGFt
# c3NlcnYubGFuMA0GCSqGSIb3DQEBDQUAA4IBAQAY0DDytGfbAhI1Q0YcAwI7gOU0
# tUd0XtFoOzgldsQJqZt+3u9vxTnE/OHffGgOCZHpU+55Gys+6pgvO4nQAxlsgRP4
# xdGQ18PLCNRgCrjgk95FbFZ+tP9cpGCxZ9KLBoBtJGsOPRuiBbjadGcGQgnTa0y7
# +PPNEIyhJuNjV5jpVjGkHGxNfGTMtf7csZOpLg74Q16l93tmS+KEpC1Tay9uUOIc
# W8zyjgQ09LIHpajl+5ayd47jgn52YG40Yy+wnde8ewfbJxvGfpr3C0KtpIzT5GX7
# zUXSqZ0794S+snKcTO6AM59SeRtZim+wk3waqgR6/cLqRKoeOt3wOOUaers2MYIC
# BTCCAgECAQEwZDBNMRMwEQYKCZImiZPyLGQBGRYDbGFuMRcwFQYKCZImiZPyLGQB
# GRYHYW1zc2VydjEdMBsGA1UEAxMUYW1zc2Vydi1BTVMtQUREUzEtQ0ECExYAAACF
# 0zIlOpr23zEAAAAAAIUwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKA
# AKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFrw8w5RG0lTxjl9+TE0LwtH
# 1enGMA0GCSqGSIb3DQEBAQUABIIBAFmA1IuH8eW7d4f/JA2iZ6sv8/bkV3K0uUp5
# ugg8/BCI2a7SRWuRPaPIDinA9AXZrceASzfVYaIIz6k3gYJ/SJWOhX+d5CkJFhj0
# tooRGT8aM22OthF7MXT4AZMXHn+nZraIaQU96p4/gf+tXSI656WV1v467Sx9H1Mw
# HyS+Hggo7ROQFB/pN0O+2azi43WdT0RY4fGbDq1pzY67+9C43cBJI7WbHsR6hH4b
# qQjKndJLCmHuRFiSAYPG84J5ZfU2Xv0C4iEG3oV9wHVCfd4vbDwaWNcuVqCKbOvj
# zXuSq3w1hWCihg7DnJc0n4oGNbcvJkfkSj+ZIl6GuR8Z2ZK7uig=
# SIG # End signature block
