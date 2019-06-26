[CmdletBinding()]
param
(
    # Тип операции
    [parameter(Mandatory = $true)]
    [ValidateSet("Add", "Remove")]
    [string]$Access,
    # Кто может читать и писать
    [parameter(Mandatory = $true)]
    [string[]]$Principal,
    # На каком объекте можно читать и писать, указывать DN объекта
    [parameter(Mandatory = $true)]
    [string]$TargetDN,
    # Название атрибута
    [parameter(Mandatory = $true)]
    [ValidateSet("AA-UserPassword")]
    [string]$Attribute,
    # Типы разрешений
    [parameter(Mandatory = $true)]
    [ValidateSet("ExtendedRight", "WriteProperty", "ReadProperty")]
    [string[]]$Rights
)

Import-Module ActiveDirectory
$rootdse = Get-ADRootDSE
# Наследование ACE
$SecurityInheritance = "SelfAndChildren"
# Объект которому присваивается разрешение
[System.Object]$AdPrincipal = $null;
# Заглушка для наследования
[guid]$InheritedObjectType = "00000000-0000-0000-0000-000000000000"
# Путь к объекту на который установим ACL
$targetPath = "AD:$TargetDN"
# Хэш таблица GUID аттрибутов из схемы
$guidmap = @{}
# Получаем все guid схемы
Get-ADObject -SearchBase ($rootdse.SchemaNamingContext) -LDAPFilter `
    "(schemaidguid=*)" -Properties lDAPDisplayName, schemaIDGUID |
    ForEach-Object { $guidmap[$_.lDAPDisplayName] = [System.GUID]$_.schemaIDGUID }

foreach ($name in $Principal) {
    # Нужно для определения класса объекта
    $getPrincipalObj = Get-ADObject -Filter { Name -eq $name }
    # Нужно для получения DN
    $getTargetObj = Get-ADObject -Filter { DistinguishedName -eq $TargetDN }

    if ( ($getPrincipalObj -eq $null) -or ($getTargetObj -eq $null) ) {
        Write-Warning "Cannot find '$name' or '$TargetDN'" -ErrorAction Stop
    }

    switch ($getPrincipalObj.ObjectClass) {
        "group" {
            $AdPrincipal = Get-ADGroup $name;
            $SecurityInheritance = "Children"
        }
        "user" {
            $AdPrincipal = Get-ADUser $name;
        }
        "computer" {
            $AdPrincipal = Get-ADComputer $name;
        }
        Default { Write-Warning "Param 'Principal' must be ObjectClass of 'group', 'computer' or 'user'" }
    }
    # Получаем SID объекта для которого присваиваем разрешение
    $PrincipalSID = New-Object System.Security.Principal.SecurityIdentifier $AdPrincipal.SID
    $accessRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule $PrincipalSID, $Rights, "Allow", $guidmap[$Attribute], $SecurityInheritance, $InheritedObjectType
    $acl = Get-ACL -Path $targetPath

    switch ($Access) {
        'Add' {
            # Добавление правила объекту читать свои и чужие отрибуты, применим к группе
            $acl.AddAccessRule($accessRule)
            Write-Host "Added access rule to '$name' and '$OU' with the following parameters: " -ForegroundColor Yellow
            Write-Host "`t$Attribute `n`t$Rights `n`t$SecurityInheritance `n" -ForegroundColor Cyan
        }
        'Remove' {
            # Убрать правило у объекта
            $acl.RemoveAccessRule($accessRule)
            Write-Host "Removed access rule from '$name' and '$OU' with the following parameters: " -ForegroundColor Yellow
            Write-Host "`t$Attribute `n`t$Rights `n`t$SecurityInheritance `n" -ForegroundColor Cyan
        }
        Default { Write-Warning "Use command: 'add' or 'remove'" }
    }
    Set-ACL -ACLObject $acl -Path $targetPath
}