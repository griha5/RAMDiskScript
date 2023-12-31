param (
    [string]$diskLetter,
    [long]$diskSize,
    [string]$installFolder = $(Join-Path -Path $env:ProgramFiles -ChildPath "RAMDiskScript")
)

if($diskLetter -match "^(?<letter>[a-zA-Z]):?$")
{
    $diskLetter = $Matches["letter"].ToUpper()
}
else
{
    throw "Disk letter must be a capital or small letter of the Latin alphabet!"
}

$logPath= Join-Path $installFolder -ChildPath log.txt 

$createRAMDiskPath = Join-Path $installFolder -ChildPath CreateRAMDisk.ps1 
$stopRAMDisksPath = Join-Path $installFolder -ChildPath StopRAMDisks.ps1 
$uninstallRAMDisksPath = Join-Path $installFolder -ChildPath UninstallRAMDisks.ps1
$installRAMDiskPath = Join-Path $installFolder -ChildPath InstallRAMDisk.ps1
$pSScriptRegistration = Join-Path $installFolder -ChildPath PSScriptRegistration.ps1
$gpoIniUpdate = Join-Path $installFolder -ChildPath GpoIniUpdate.ps1

if(-not (Test-Path $installFolder))
{
    New-Item -ItemType Directory -Path $installFolder -Force
}

if((Get-Item -LiteralPath $installFolder).FullName -ine (Get-Item -LiteralPath $PSScriptRoot).FullName)
{

    Copy-Item -Path (Split-Path $createRAMDiskPath -Leaf) -Destination $createRAMDiskPath -Force
    Copy-Item -Path (Split-Path $stopRAMDisksPath -Leaf) -Destination $stopRAMDisksPath -Force
    Copy-Item -Path (Split-Path $uninstallRAMDisksPath -Leaf) -Destination $uninstallRAMDisksPath -Force
    Copy-Item -Path (Split-Path $installRAMDiskPath -Leaf) -Destination $installRAMDiskPath -Force
    Copy-Item -Path (Split-Path $pSScriptRegistration -Leaf) -Destination $pSScriptRegistration -Force
    Copy-Item -Path (Split-Path $gpoIniUpdate -Leaf) -Destination $gpoIniUpdate -Force
}

.\CreateRAMDisk.ps1 -diskLetter $diskLetter -diskSize $diskSize -logPath $logPath

$scripts =  .\PSScriptRegistration.ps1 -Action GetAll -State Startup
$createRAMDiskItem = Get-Item -LiteralPath $createRAMDiskPath
$unregScript = $null
foreach ($script in $scripts) 
{
    if((Test-Path $script["cmdLine"]) -and    
        (Get-Item -LiteralPath $script["cmdLine"]).FullName -ieq $createRAMDiskItem.FullName -and 
        $script["parameters"] -match "\s*-diskLetter\s+(?<letter>[a-zA-Z]):?\s+" -and
        $Matches["letter"] -ieq $diskLetter)
    {
        $unregScript = $script      
    }
}

if(-not -not $unregScript)
{
    .\PSScriptRegistration.ps1 -Action Unregistration -State Startup -CmdLine $unregScript["cmdLine"] -Parameters $unregScript["parameters"]
}

.\PSScriptRegistration.ps1 -Action Registration -State Startup -CmdLine $createRAMDiskPath -Parameters "-diskLetter ${diskLetter}: -diskSize ${diskSize} -logPath `"${logPath}`""

$scripts =  .\PSScriptRegistration.ps1 -Action GetAll -State Shutdown
$createRAMDiskItem = Get-Item -LiteralPath $createRAMDiskPath
$unregScript = $null
foreach ($script in $scripts) 
{
    if((Test-Path $script["cmdLine"]) -and    
        (Get-Item -LiteralPath $script["cmdLine"]).FullName -ieq $stopRAMDisksPath.FullName)
    {
        $unregScript = $script      
    }
}
if(-not $unregScript)
{
    .\PSScriptRegistration.ps1 -Action Registration -State Shutdown -CmdLine $stopRAMDisksPath -Parameters "-logPath `"${logPath}`""
}

.\GpoIniUpdate.ps1
gpupdate /force
