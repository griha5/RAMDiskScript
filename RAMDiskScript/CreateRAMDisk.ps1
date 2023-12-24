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
        throw "The disk letter (parameter -diskLetter) must be specified and be a capital or small letter of the Latin alphabet!"
    }

    $initiatorIds=@("DnsName:$([System.Net.Dns]::GetHostName())")

    $diskPath="ramdisk:RAM-disk-$diskLetter.vhdx"
    $targetName="target-RAM-disks"

    if (!(Get-WindowsFeature -Name FS-iSCSITarget-Server).Installed) {
        Write-Output "The 'iSCSI Target Server' role (FS-iSCSITarget-Server) is not installed" | Write-OutputToFile 
        Write-Output "Installing the iSCSI Target Server role (FS-iSCSITarget-Server)" | Write-OutputToFile 
        Install-WindowsFeature -Name FS-iSCSITarget-Server
    }

    if ((Get-Service -Name WinTarget).Status -eq 'Stopped') {
        Write-Output "The 'Microsoft iSCSI Target Server' service (WinTarget) is not running"  | Write-OutputToFile 
        Write-Output "Starting the 'Microsoft iSCSI Target Server' service (WinTarget)" | Write-OutputToFile 
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
            throw "The disk letter ${diskLetter}: is already in use!"
        }

        Write-Output "Creating a new iSCSI virtual disk $diskPath with a size of $diskSize" | Write-OutputToFile 
        $ramDisk = New-IscsiVirtualDisk -Path $diskPath -Size $diskSize -ComputerName localhost
    } 
    else 
    {
        if($ramDisk.Size -ne $diskSize)
        {
            Write-Output "Resizing the iSCSI virtual disk $diskPath is required" | Write-OutputToFile 

            $target = Get-IscsiServerTarget -ComputerName localhost | Where TargetName -EQ $targetName
            if($target -ne $null)
            {
                if(-not -not ($target.LunMappings | Where-Object { $_.Path -eq $diskPath}))
                {   
                    Write-Output "Removing the disk from the iSCSI target $diskPath" | Write-OutputToFile                     
                    Remove-IscsiVirtualDiskTargetMapping -TargetName $targetName -DevicePath $diskPath -ComputerName localhost
                }
            }
            
            Write-Output "Removing the old iSCSI virtual disk $diskPath with a size of ${ramDisk.Size}" | Write-OutputToFile 
            Remove-IscsiVirtualDisk -Path $diskPath -ComputerName localhost
            Write-Output "Creating a new iSCSI virtual disk $diskPath with a size of $diskSize" | Write-OutputToFile 
            $ramDisk = New-IscsiVirtualDisk -Path $diskPath -Size $diskSize -ComputerName localhost
        }
    }

    $target = Get-IscsiServerTarget -ComputerName localhost | Where TargetName -EQ $targetName
    if($target -eq $null) {
        Write-Output "Creating an iSCSI target" | Write-OutputToFile 
        $target = New-IscsiServerTarget -TargetName $targetName -InitiatorIds $initiatorIds -ComputerName localhost 
    } else {
        if($target.InitiatorIds -eq $null -or (Compare-Object $target.InitiatorIds $initiatorIds) -ne $null){
            Write-Output "Configuring the iSCSI target parameters" | Write-OutputToFile 
            Set-IscsiServerTarget -TargetName $target.TargetName -InitiatorIds $initiatorIds -ComputerName localhost
        }    
    }

    if(-not ($target.LunMappings | Where-Object { $_.Path -eq $diskPath}))
    {                
        Write-Output "Adding a mapping for the iSCSI virtual disk" | Write-OutputToFile 
        Add-IscsiVirtualDiskTargetMapping -TargetName $targetName -DevicePath $diskPath -ComputerName localhost
    }

    if ((Get-Service -Name MSiSCSI).Status -eq 'Stopped') 
    {
        Write-Output "The 'Microsoft iSCSI Initiator Service' service (MSiSCSI) is not running"  | Write-OutputToFile 
        Write-Output "Starting the 'Microsoft iSCSI Initiator Service' service (MSiSCSI)" | Write-OutputToFile 
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
        Write-Output "Creating a new iSCSI portal for $([System.Net.Dns]::GetHostName()):3260" | Write-OutputToFile
        $portal = New-IscsiTargetPortal -TargetPortalAddress ([System.Net.Dns]::GetHostName()) -TargetPortalPortNumber 3260
    }

    if(-not (Get-IscsiTarget | Where-Object { $_.NodeAddress -eq $target.TargetIqn}).IsConnected)
    {
        Write-Output "Connecting to the iSCSI target ${target.TargetIqn}" | Write-OutputToFile 
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
            Write-Output "Waiting for the virtual disk to be detected. Attempt ${attempts} ..." | Write-OutputToFile
            Start-Sleep -Seconds 1
        }
    }

    if ($disk -eq $null) {
        throw "Failed to detect the virtual disk ${ramDisk.SerialNumber}"
    }

    if($disk.PartitionStyle -ne "MBR")
    {
        Write-Output "Initializing the disk ${ramDisk.SerialNumber}" | Write-OutputToFile 
        $disk = Initialize-Disk -InputObject $disk -PartitionStyle MBR -PassThru
    }

    $partition = Get-Partition -Disk $disk
    if(-not $partition)
    {
        Write-Output "Creating a new partition with the letter ${diskLetter}:" | Write-OutputToFile 
        $partition = New-Partition -InputObject $disk -DriveLetter $diskLetter -UseMaximumSize
    }

    if(-not $partition.DriveLetter)
    {
        Write-Output "Assigning the disk letter ${diskLetter}:" | Write-OutputToFile 
        $partition | Add-PartitionAccessPath -AccessPath "${diskLetter}:"
    }

    $volume = Get-Volume -Partition $partition
    if(-not $volume.FileSystem)
    {
        Write-Output "Formatting the disk ${diskLetter}:" | Write-OutputToFile 
        $volume = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel "RAMDRIVE_${diskLetter}" -Confirm:$false
    }

    ""| Write-OutputToFile 
}
catch {
    Write-Output "Error creating the virtual disk" | Write-OutputToFile
    Write-Output "ERROR: $($_.Exception.Message)" | Write-OutputToFile 
}
