#Скрипт останавливает проект на сервере. Запрашивает имя проекта и сервер, после чего производит определяет тип проекта (консоль или windows-служба) и производит остановку соответствующим ему образом.
param(
$projectname,
$servername
)
#повторяем запрос имени проекта и сервера до получения корректного ввода
if (!$projectname){while(!$projectname){$projectname = Read-host "ProjectName"; $pauseflag = $true}}

if (!$servername){while(!$servername){$servername = Read-host "Servername"; $pauseflag = $true}}

[string[]]$folders = (dir \\$($env:USERDOMAIN).lan\dfs\BinStorage\$projectname).fullname | sort -Descending
$lastcommitfolder = ((dir ($folders | sort -Descending | select -first 1)) | sort LastWriteTime)[0].fullName
$Runnedprojectinfo = Get-Content $lastcommitfolder\_BuildProperty.txt
#в зависимости от типа проекта удаляем его соответствующим способом
if($Runnedprojectinfo[0].split("=")[1] -eq "console"){
	Invoke-Command -ComputerName $servername -ArgumentList $lastcommitfolder -ScriptBlock {& $($args[0])\StopAndUninstall.ps1}
}
if($Runnedprojectinfo[0].split("=")[1] -eq "webdeploy" -or $Runnedprojectinfo[0].split("=")[1] -eq "deploysite"){
    $files = Get-childitem -path ($lastcommitfolder + "\DeployPackage") -Recurse
    $configpath = ($files | ? {$_.name -like "*.SetParameters.xml"}).fullname
    $string = (Get-Content $configpath | Select-String '<setParameter name="IIS Web Application Name" value=').line.split(" ") | ? {if ($_ -like "value=*"){$_}}
    $sitename =  $string.split('"')[1]
    Invoke-Command -ComputerName $servername -ArgumentList $sitename -ScriptBlock {Stop-Website $using:sitename; Stop-WebAppPool $using:sitename}
}
if($Runnedprojectinfo[0].split("=")[1] -eq "WINservice"){
	invoke-command -ComputerName $servername -scriptblock{	Stop-service 1xProject-$($using:projectname) -force -confirm:$false}
}

# SIG # Begin signature block
# MIIITQYJKoZIhvcNAQcCoIIIPjCCCDoCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUQtUntl4bBX/oRFkNbz8qgE5i
# I1+gggW3MIIFszCCBJugAwIBAgITPQAAAEctAH7QrwYrgAAAAAAARzANBgkqhkiG
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
# hvcNAQkEMRYEFPGAseM0HeCe/SWTGSZcKrs0YeetMA0GCSqGSIb3DQEBAQUABIIB
# ABoHCDxhPA2bFIi7DOedfcvZnXMHFKeCEvVWIG3Uk5H2H5syhpYazES0MB7R7fxO
# bK/w4KV27eKrg4qJIW5ccYxONdVDd2oRoKT5x+ER1wJQTPx2eRS4lYH1NIQ/xP0x
# W5mxsLnhb2AkHiLZRvcTXVlsfg7xwUAGFuvw5LCZEarVSfTMZX7sDWrKeVsxYmIr
# B5Tkp0j6771CAgZbAZ7YyJkoAu6i0+sanPLWjmt2MwxMLVydZcB81NSq+q4qdb+b
# 1RystlmWh75cBkM4IDMk5P1BEsJ4MIqyPy0mIFhVSTd9y5/Y+Y+NVXxbFuGdWTq/
# weo7xJ+jtqwuRGznEcqQsoM=
# SIG # End signature block
