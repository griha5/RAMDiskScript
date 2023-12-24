param (
    [string]$logPath
)

$diskPath="ramdisk:RAM-disk-$diskLetter.vhdx"
$targetName="target-RAM-disks"

# Инициализация массива с идентификаторами инициаторов

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

"" | Write-OutputToFile
"StopRAM" | Write-OutputToFile

$target2 = Get-IscsiServerTarget -ComputerName localhost | Where TargetName -EQ $targetName

if($target2 -ne $null){
    "Удаление таргета ${target2.TargetName}" | Write-OutputToFile
    Remove-IscsiServerTarget -TargetName $target2.TargetName -ComputerName localhost
}

""| Write-OutputToFile 