#скрипт принимает данные о проекте из скрипта deployonServer.ps1, удаляет прежние файлы проекта, записывает новые, предварительно размещенные в windows\temp
#Все действия осуществляются путем использования задач планировщика задач windows.
Param (
[Parameter(Mandatory=$true)]
[string]$target,
[Parameter(Mandatory=$true)]
[string]$username,
[Parameter(Mandatory=$false)]
[string]$app,
[Parameter(Mandatory=$true)]
[string]$project,
[Parameter(Mandatory=$true)]
[string]$tempname
)

#getting sessions info
$FlagProcesses = (Get-WMIObject -ComputerName $target -Class Win32_Process -filter 'name="taskhostex.exe"')
$sessions = @{}
#Если владелец процесса не Администратор, добавляем в $sessions его текущего владельца
foreach ($c in $FlagProcesses){if ($c.getowner().user -ne "Administrator"){$sessions.add($c.getowner().user, $c.SessionId.ToString())}}

#генерируем конфиг для создания необходимых задач планировщика
if($app -ne $null){
    [array]$app = $app.split(" ", 2)
    $exe = "C:\1xprojects\Consoles\$project\$($app[0])"
    $content = Get-Content \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\TemplateRunAPP.xml
    for ($i=0; $i -ne $content.Count; $i++){
        if ($content[$i] -eq "      <Command></Command>"){$content[$i] = "      <Command>" + $exe + "</Command>"}
        if ($content[$i] -eq "	  <Arguments></Arguments>" -and $app.count -gt 1) {$content[$i] = "	  <Arguments>$($app[1].Trim())</Arguments>"}
        if ($content[$i] -eq "      <UserId></UserId>"){$content[$i] = "      <UserId>" + "$($env:USERDOMAIN)\" + $username + "</UserId>"}
        if ($content[$i] -eq "	  <WorkingDirectory></WorkingDirectory>"){$content[$i] = "	  <WorkingDirectory>" + $exe.Substring(0, $exe.LastIndexOf("\")) + "</WorkingDirectory>"}
    }
    $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
    $outpath = "\\" + $target + "\C$\Windows\Temp\" + $tempname + "\" + $project + ".xml"
    try {[System.IO.File]::WriteAllLines($outpath, $content, $Utf8NoBomEncoding)} catch {$Errorcollector += $Error[0]}
}
   
    $content = Get-Content \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\TemplateRunScripts.xml
for ($i=0; $i -ne $content.Count; $i++){
    if ($content[$i] -eq "      <Command></Command>"){$content[$i] = "      <Command>powershell.exe</Command>"}
    if ($content[$i] -eq "	  <Arguments></Arguments>"){$content[$i] = "	  <Arguments>-file C:\windows\temp\$tempname\StopAndUninstall.ps1 $project</Arguments>"}
    if ($content[$i] -eq "      <UserId></UserId>"){$content[$i] = "      <UserId>" + "$($env:USERDOMAIN)\" + $username + "</UserId>"}
}
$outpath = "\\" + $target + "\C$\Windows\Temp\$tempname\PreUninst-$project.xml"
try {[System.IO.File]::WriteAllLines($outpath, $content, $Utf8NoBomEncoding)} catch {$Errorcollector += $Error[0]}

$content = Get-Content \\$($env:USERDOMAIN).lan\dfs\Scripts\Deploy\TemplateRunScripts.xml
for ($i=0; $i -ne $content.Count; $i++){
    if ($content[$i] -eq "      <Command></Command>"){$content[$i] = "      <Command>powershell.exe</Command>"}
    if ($content[$i] -eq "	  <Arguments></Arguments>"){$content[$i] = "	  <Arguments>-file C:\windows\temp\$tempname\Install.ps1 $project</Arguments>"}
    if ($content[$i] -eq "      <UserId></UserId>"){$content[$i] = "      <UserId>" + "$($env:USERDOMAIN)\" + $username + "</UserId>"}
}
$outpath = "\\" + $target + "\C$\Windows\Temp\$tempname\Install-$project.xml"
try {[System.IO.File]::WriteAllLines($outpath, $content, $Utf8NoBomEncoding)} catch {$Errorcollector += $Error[0]}

# !!!Регистрозависимость!!!
$XmlQuery="<QueryList>
  <Query Id='0' Path='Microsoft-Windows-TaskScheduler/Operational'>
    <Select Path='Microsoft-Windows-TaskScheduler/Operational'>*[System[TimeCreated[timediff(@SystemTime) &lt;=7000]]]</Select>
  </Query>
</QueryList>"

#start application
$id = $sessions["$username"]
#в скриптблоке удаляются прежние задачи  планировщика, разворачивающие сервисы и создаются новы, устанавливающие новую версию сервиса из "C:\Windows\temp\имя проекта"
Invoke-Command -ComputerName $target -ArgumentList $project, $id, $tempname, $XmlQuery, $app -ScriptBlock {
    $project = $args[0]; $id = $args[1]; $tempname = $args[2]; $XmlQuery = $args[3]; $app = $args[4]
    if ($app -ne $null){
        SchTasks.exe /delete /tn $project /F 2>&1 | Out-Null
        SchTasks.exe /create /XML "C:\Windows\temp\$tempname\$project.xml" /tn $project | Out-Null
    }
    SchTasks.exe /delete /tn PreUninst-$project /F 2>&1 | Out-Null
    SchTasks.exe /create /XML "C:\Windows\temp\$tempname\PreUninst-$project.xml" /tn PreUninst-$project | Out-Null
    SchTasks.exe /delete /tn Install-$project /F 2>&1 | Out-Null
    SchTasks.exe /create /XML "C:\Windows\temp\$tempname\Install-$project.xml" /tn Install-$project | Out-Null
    
    Start-ScheduledTask -TaskName PreUninst-$project
    While ((Get-ScheduledTask -TaskName PreUninst-$project).State -eq "Running"){Start-Sleep -Milliseconds 200}
    #удаляем файлы проекта  
    if(Test-Path "C:\1xprojects\Consoles\$project" 2>$null){(Get-ChildItem -Path "C:\1xprojects\Consoles\$project").fullname | Remove-Item -force -Recurse 2>&1 | Out-null}
    New-Item -ItemType directory -Path "C:\1xprojects\Consoles\$project"  -Force | Out-Null
    Get-ChildItem -Path C:\Windows\temp\$tempname\ObjectsToDeploy | % {Move-Item -Path $_.FullName -Destination "C:\1xprojects\Consoles\$project" -force}
    #устанавливаем приложение вызовомм задачи планировщика 
    Start-ScheduledTask -TaskName Install-$project
    While ((Get-ScheduledTask -TaskName Install-$project).State -eq "Running"){Start-Sleep -Milliseconds 200}
    
    if ($app -ne $null){
        SchTasks.exe /run /tn $project | out-null

        #parsing log
        Start-sleep -Seconds 4
        $Events = Get-WinEvent -FilterXml $XmlQuery 2> $null
        $Events = $Events | ? {$_.Properties[0].value -eq ("\"+ $project)}
        $excludedEvents = @(100, 106, 110, 200) #не учитываем HTTP коды информационных сообщений
        if ($events.id -notcontains 129){Write-Error "Application process was not started!"}
        for ($a=0; $a -ne $Events.count; $a++){
            if ($Events[$a].id -eq 129){
                For($b=0;$b -ne $Events.count; $b++){
                    if ($Events[$b].id -eq 200 -and $Events[$b].Properties[3].value -eq $Events[$a].Properties[2].value){
                        For($c=0;$c -ne $Events.count; $c++){
                            if ($Events[$c].id -eq 201 -and $Events[$c].Properties[1].value -eq $Events[$b].Properties[2].value){
                                $ec = $Events[$c].Properties[3].value; Write-Error "!!! Application ended quickly with exitcode $ec"
                            }
                        }
                    }
                }
            }
        }
    }

    SchTasks.exe /delete /tn $project /F 2>&1 | Out-Null
    SchTasks.exe /delete /tn PreUninst-$project /F 2>&1 | Out-Null
    SchTasks.exe /delete /tn Install-$project /F 2>&1 | Out-Null
}

# SIG # Begin signature block
# MIIITQYJKoZIhvcNAQcCoIIIPjCCCDoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUozWfBUNEaUPeOdFbJFJDAE32
# eDigggW3MIIFszCCBJugAwIBAgITPQAAAEctAH7QrwYrgAAAAAAARzANBgkqhkiG
# 9w0BAQUFADBIMRMwEQYKCZImiZPyLGQBGRYDbGFuMRUwEwYKCZImiZPyLGQBGRYF
# d3NlcnYxGjAYBgNVBAMTEXdzZXJ2LUFERFMyLVdOLUNBMB4XDTE3MDIxMDE0MDcx
# NFoXDTE5MDIxMDE0MTcxNFowVjETMBEGCgmSJomT8ixkARkWA2xhbjEVMBMGCgmS
# JomT8ixkARkWBXdzZXJ2MRgwFgYDVQQLDA9DdXN0b21fQWNjb3VudHMxDjAMBgNV
# BAMTBUxleHVzMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAldmdrO9w
# Pqfxrno5opGZgHc+K+swOM4GXFzHReRZ8UKe6PfKIq1ZLIKJkRdzf68W0M/S7wCv
# Zwn4Z8wqKH0rAP6mle/RVVUXVhiMbTFjQrUMdJu0TZO/gfkwz5uMIVs/RkRkdjKr
# Mq9J0TFzMptFfL3tezEaPViNPVd1t8tG77jwxMgs15perAbs/sLdcly2BRQCkN9h
# XnBDG+bopuyZdl3NgyGnT88kZozOdUc7ga1wGRtcrqu8SYThdRaDgTNpbNPb0wLA
# d2A37fJUrPUpuUaO3hgOV1SadQyWPZgrrtT18LYzrwKI4xDzc+SvOL2h5jj6Xz5E
# 9bORsXjOZPnVuQIDAQABo4IChjCCAoIwPQYJKwYBBAGCNxUHBDAwLgYmKwYBBAGC
# NxUIgqrNTIG4kT+BxYc/h426EsTaZoFFgqGuWIOOqgECAWQCAQUwEwYDVR0lBAww
# CgYIKwYBBQUHAwMwDgYDVR0PAQH/BAQDAgeAMBsGCSsGAQQBgjcVCgQOMAwwCgYI
# KwYBBQUHAwMwHQYDVR0OBBYEFEeMskv4fbtPnUWsX1H3x3aNSLyvMB8GA1UdIwQY
# MBaAFORHEsxvI9aBIYvkrkzmwixOGD9LMIHOBgNVHR8EgcYwgcMwgcCggb2ggbqG
# gbdsZGFwOi8vL0NOPXdzZXJ2LUFERFMyLVdOLUNBLENOPWFkZHMyLXduLENOPUNE
# UCxDTj1QdWJsaWMlMjBLZXklMjBTZXJ2aWNlcyxDTj1TZXJ2aWNlcyxDTj1Db25m
# aWd1cmF0aW9uLERDPXdzZXJ2LERDPWxhbj9jZXJ0aWZpY2F0ZVJldm9jYXRpb25M
# aXN0P2Jhc2U/b2JqZWN0Q2xhc3M9Y1JMRGlzdHJpYnV0aW9uUG9pbnQwgcEGCCsG
# AQUFBwEBBIG0MIGxMIGuBggrBgEFBQcwAoaBoWxkYXA6Ly8vQ049d3NlcnYtQURE
# UzItV04tQ0EsQ049QUlBLENOPVB1YmxpYyUyMEtleSUyMFNlcnZpY2VzLENOPVNl
# cnZpY2VzLENOPUNvbmZpZ3VyYXRpb24sREM9d3NlcnYsREM9bGFuP2NBQ2VydGlm
# aWNhdGU/YmFzZT9vYmplY3RDbGFzcz1jZXJ0aWZpY2F0aW9uQXV0aG9yaXR5MCoG
# A1UdEQQjMCGgHwYKKwYBBAGCNxQCA6ARDA9sZXh1c0B3c2Vydi5sYW4wDQYJKoZI
# hvcNAQEFBQADggEBAAdA02TK2RRLT2KCeVlSIwvq0mV6qaE0D7F0jPQv3kxey+9F
# 1ja2lNTRfJvE0n7rhxoL+YHLTmz23ajdAGdYvs/fBJBqDOhAzjnpdqat3nqdCByM
# QJCWjTYtBbal1O5qO3sz469wVQtH7YvedKJiwE3NG9CTQyjuLvTunYifdtWeqtj+
# s/WUtACSUDMSHfNrFU0Jq3ERNikWQJTNex06Sre6sQodqaBQ8++JJYY1bMjI28sV
# HqNYrti1FMb8sSlkI3HPgXvZNzV9D5/XCLpIx6VP75wAFMUPhtDZgmE2tbHtPqEE
# bNuxuRjN9M+CQH1d3PPyW+F8AN/oJDZlH4kAHM8xggIAMIIB/AIBATBfMEgxEzAR
# BgoJkiaJk/IsZAEZFgNsYW4xFTATBgoJkiaJk/IsZAEZFgV3c2VydjEaMBgGA1UE
# AxMRd3NlcnYtQUREUzItV04tQ0ECEz0AAABHLQB+0K8GK4AAAAAAAEcwCQYFKw4D
# AhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZI
# hvcNAQkEMRYEFObncJcjQzKAvcCOacwi2nci0qSiMA0GCSqGSIb3DQEBAQUABIIB
# ADjBCFTX88uYGe5/5sm79Xvtnjjrn4K+jF3mo3bB8D1EZn44AK0z30VBmm7noefq
# O97c2nLKXUgqqt+39i2uZ7E2KHWsTHYTBADe3TskOS4OuyIryJ2k99kTWzEKUJeV
# GKRDNSVFIXdFom4X0ZCplQoPxQPBhU3nqnxiavZPGX0op3oay8zAY2hnVjxIj/tX
# f1+Z/C4oBUZJGEJiHkpc/mJUFHKEoP5PpAEqTu/oHs9LbdrRjxbGZWVJnsek0+O3
# 25goV6FqCb/M7CdxpuI4BiKwIl1NvG3tVtrot7ujf0jjRC2U8zJUhU49IfCvTj1J
# iUfT5AdVL5nvfLX5spsqhuw=
# SIG # End signature block
