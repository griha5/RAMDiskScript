param (
    [string]$uninstallFolder = [System.IO.Path]::GetDirectoryName($PSCommandPath)
)
$createRAMDiskPath = Join-Path $uninstallFolder -ChildPath СreateRAMDisk.ps1 
$stopRAMDisksPath = Join-Path $uninstallFolder -ChildPath StopRAMDisks.ps1 

.\StopRAMDisks.ps1

$skripts =  .\PSScriptRegistration.ps1 -Action GetAll -State Startup
$createRAMDiskItem = Get-Item -LiteralPath $createRAMDiskPath
foreach ($skript in $skripts) 
{
    if((Test-Path $skript["cmdLine"]) -and    
        (Get-Item -LiteralPath $skript["cmdLine"]).FullName -ieq $createRAMDiskItem.FullName)
    {
         .\PSScriptRegistration.ps1 -Action Unregistration -State Startup -CmdLine $skript["cmdLine"] -Parameters $skript["parameters"]    
    }
}

$skripts =  .\PSScriptRegistration.ps1 -Action GetAll -State Shutdown
$stopRAMDisksPathItem = Get-Item -LiteralPath $stopRAMDisksPath
$unregScript = $null
foreach ($skript in $skripts) 
{
    if((Test-Path $skript["cmdLine"]) -and    
        (Get-Item -LiteralPath $skript["cmdLine"]).FullName -ieq $stopRAMDisksPathItem.FullName)
    {
        .\PSScriptRegistration.ps1 -Action Unregistration -State Shutdown -CmdLine $skript["cmdLine"] -Parameters $skript["parameters"]   
    }
}

.\StopRAMDisks.ps1

gpupdate /force

Get-Disk
