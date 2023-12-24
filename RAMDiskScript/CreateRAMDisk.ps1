param (
    [string]$diskLetter,
    [long]$diskSize,
    [string]$logPath
)

function Write-OutputToFile {
    param (
        [Parameter(ValueFromPipeline=$true)]
        [string]$InputString
    )

    process {
        $output = "$([System.DateTime]::Now.ToString("yyy-MM-mm HH:mm:ss.fff"))   $_"
        if (-not $script:logPath ) 
        {
            Write-Output $output
        } 
        else 
        {
            $output | Out-File -FilePath $script:logPath -Append
            Write-Output $output
        }
    }
}

try 
{
    ""| Write-OutputToFile 

    if($diskLetter -match "^(?<letter>[a-zA-Z]):?$")
    {
        $diskLetter = $Matches["letter"].ToUpper()
    }
    else
    {
        throw "Буква диска (параметр -diskLetter) должна быть задана и быть большой или маленькой буквой латинского алфавита!"
    }

    $initiatorIds=@("DnsName:$([System.Net.Dns]::GetHostName())")

    $diskPath="ramdisk:RAM-disk-$diskLetter.vhdx"
    $targetName="target-RAM-disks"

    if (!(Get-WindowsFeature -Name FS-iSCSITarget-Server).Installed) {
        Write-Output "Роль 'iSCSI Target Server' (FS-iSCSITarget-Server) не установлена" | Write-OutputToFile 
        Write-Output "Установка роли iSCSI Target Server (FS-iSCSITarget-Server)" | Write-OutputToFile 
        Install-WindowsFeature -Name FS-iSCSITarget-Server
    }

    if ((Get-Service -Name WinTarget).Status -eq 'Stopped') {
        Write-Output "Служба 'Microsoft iSCSI Target Server' (WinTarget) не запущена"  | Write-OutputToFile 
        Write-Output "Запуск службы 'Microsoft iSCSI Target Server' (WinTarget)" | Write-OutputToFile 
        Start-Service -Name WinTarget
    }

    $ramDisk = Get-IscsiVirtualDisk -ComputerName localhost | Where Path -EQ $diskPath
    if($ramDisk -eq $null) 
    {
        $localDriveLetters = (Get-Volume).DriveLetter | Where-Object { $_ -ne $null } | Sort-Object -Unique
        $removableDriveLetters = (Get-WmiObject Win32_DiskDrive | Where-Object { $_.MediaType -eq "RemovableMedia" }).Partitions | ForEach-Object {
            $_.Associators | Where-Object { $_.ClassName -eq "Win32_LogicalDisk" } | ForEach-Object { $_.DeviceID }
        } | Sort-Object -Unique
        $networkDriveLetters = (Get-SmbMapping).LocalPath -replace ':'
        $allDriveLetters = ($localDriveLetters + $removableDriveLetters + $networkDriveLetters) | ForEach-Object { $_.ToString().ToUpper() }

        if($allDriveLetters.Contains($diskLetter.ToUpper()))
        {
            throw "Буква диска ${diskLetter}: уже занята!"
        }

        Write-Output "Создание нового iSCSI виртуального диска $diskPath размером $diskSize" | Write-OutputToFile 
        $ramDisk = New-IscsiVirtualDisk -Path $diskPath -Size $diskSize -ComputerName localhost
    } 
    else 
    {
        if($ramDisk.Size -ne $diskSize)
        {
            Write-Output "Требуется изменение размера iSCSI виртуального диска $diskPath" | Write-OutputToFile 

            $target = Get-IscsiServerTarget -ComputerName localhost | Where TargetName -EQ $targetName
            if($target -ne $null)
            {
                if(-not -not ($target.LunMappings | Where-Object { $_.Path -eq $diskPath}))
                {   
                    Write-Output "Удаление диска из iSCSI цели $diskPath" | Write-OutputToFile                     
                    Remove-IscsiVirtualDiskTargetMapping -TargetName $targetName -DevicePath $diskPath -ComputerName localhost
                }
            }
            
            Write-Output "Удаление старого iSCSI виртуального диска $diskPath размером ${ramDisk.Size}" | Write-OutputToFile 
            Remove-IscsiVirtualDisk -Path $diskPath -ComputerName localhost
            Write-Output "Создание нового iSCSI виртуального диска $diskPath размером $diskSize" | Write-OutputToFile 
            $ramDisk = New-IscsiVirtualDisk -Path $diskPath -Size $diskSize -ComputerName localhost
        }
    }

    $target = Get-IscsiServerTarget -ComputerName localhost | Where TargetName -EQ $targetName
    if($target -eq $null) {
        Write-Output "Создание iSCSI цели" | Write-OutputToFile 
        $target = New-IscsiServerTarget -TargetName $targetName -InitiatorIds $initiatorIds -ComputerName localhost 
    } else {
        if($target.InitiatorIds -eq $null -or (Compare-Object $target.InitiatorIds $initiatorIds) -ne $null){
            Write-Output "Настройка параметров iSCSI цели" | Write-OutputToFile 
            Set-IscsiServerTarget -TargetName $target.TargetName -InitiatorIds $initiatorIds -ComputerName localhost
        }    
    }

    if(-not ($target.LunMappings | Where-Object { $_.Path -eq $diskPath}))
    {                
        Write-Output "Добавление маппинга для iSCSI виртуального диска" | Write-OutputToFile 
        Add-IscsiVirtualDiskTargetMapping -TargetName $targetName -DevicePath $diskPath -ComputerName localhost
    }

    if ((Get-Service -Name MSiSCSI).Status -eq 'Stopped') 
    {
        Write-Output "Служба 'Microsoft iSCSI Initiator Service' (MSiSCSI) не запущена"  | Write-OutputToFile 
        Write-Output "Запуск службы 'Microsoft iSCSI Initiator Service' (MSiSCSI)" | Write-OutputToFile 
        Start-Service -Name MSiSCSI
    }

    if(-not (Get-IscsiTargetPortal | Where-Object {
          $_.TargetPortalAddress.ToUpper() -eq [System.Net.Dns]::GetHostName().ToUpper() -and
          $_.TargetPortalPortNumber -eq 3260 -and
          $_.InitiatorPortalAddress -eq $null -and
          -not $_.InitiatorInstanceName -and
          $_.PSComputerName -eq $null -and
          $_.IsDataDigest -eq $False -and
          $_.IsHeaderDigest -eq $False }))
    {
        Write-Output "Создание нового портала iSCSI для $([System.Net.Dns]::GetHostName()):3260" | Write-OutputToFile
        $portal = New-IscsiTargetPortal -TargetPortalAddress ([System.Net.Dns]::GetHostName()) -TargetPortalPortNumber 3260
    }

    if(-not (Get-IscsiTarget | Where-Object { $_.NodeAddress -eq $target.TargetIqn}).IsConnected)
    {
        Write-Output "Подключение к iSCSI-цели ${target.TargetIqn}" | Write-OutputToFile 
        $connect = Connect-IscsiTarget -NodeAddress $target.TargetIqn
    }
    
    $attempts = 0
    $disk = $null
    while ($disk -eq $null -and $attempts -lt 3) 
    {
        $attempts++
        $disk = Get-Disk | Where SerialNumber -EQ $ramDisk.SerialNumber
        if ($disk -eq $null) 
        {
            Write-Output "Ожидание обнаружения виртуального диска. Попытка ${attempts} ..." | Write-OutputToFile
            Start-Sleep -Seconds 1
        }
    }

    if ($disk -eq $null) {
        throw "Не удалось обнаружить виртуальный диск ${ramDisk.SerialNumber}"
    }

    if($disk.PartitionStyle -ne "MBR")
    {
        Write-Output "Инициализация диска ${ramDisk.SerialNumber}" | Write-OutputToFile 
        $disk = Initialize-Disk -InputObject $disk -PartitionStyle MBR -PassThru
    }

    $partition = Get-Partition -Disk $disk
    if(-not $partition)
    {
        Write-Output "Создание нового раздела с буквой ${diskLetter}:" | Write-OutputToFile 
        $partition = New-Partition -InputObject $disk -DriveLetter $diskLetter -UseMaximumSize
    }

    if(-not $partition.DriveLetter)
    {
        Write-Output "Назначение буквы диска ${diskLetter}:" | Write-OutputToFile 
        $partition | Add-PartitionAccessPath -AccessPath "${diskLetter}:"
    }

    $volume = Get-Volume -Partition $partition
    if(-not $volume.FileSystem)
    {
        Write-Output "Форматирование диска ${diskLetter}:" | Write-OutputToFile 
        $volume = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel "RAMDRIVE_${diskLetter}" -Confirm:$false
    }

    ""| Write-OutputToFile 
}
catch {
    Write-Output "Ошибка при создании виртуального диска" | Write-OutputToFile
    Write-Output "ERROR: $($_.Exception.Message)" | Write-OutputToFile 
}
