param (
    [string]$diskLetter,
    [long]$diskSize,
    [string]$installFolder = $(Join-Path -Path $env:ProgramFiles -ChildPath "RAM")
)

if($diskLetter -match "^(?<letter>[a-zA-Z]):?$")
{
    $diskLetter = $Matches["letter"].ToUpper()
}
else
{
    throw "Буква диска должна быть большой или маленькой буквой латинского алфавита!"
}

$logPath= Join-Path $installFolder -ChildPath log.txt 

$createRAMDiskPath = Join-Path $installFolder -ChildPath СreateRAMDisk.ps1 
$stopRAMDisksPath = Join-Path $installFolder -ChildPath StopRAMDisks.ps1 
$uninstallRAMDisksPath = Join-Path $installFolder -ChildPath UninstallRAMDisks.ps1
$installRAMDiskPath = Join-Path $installFolder -ChildPath InstallRAMDisk.ps1
$pSScriptRegistration = Join-Path $installFolder -ChildPath PSScriptRegistration.ps1

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
}

.\СreateRAMDisk.ps1 -diskLetter $diskLetter -diskSize $diskSize -logPath $logPath

$skripts =  .\PSScriptRegistration.ps1 -Action GetAll -State Startup
$createRAMDiskItem = Get-Item -LiteralPath $createRAMDiskPath
$unregScript = $null
foreach ($skript in $skripts) 
{
    if((Test-Path $skript["cmdLine"]) -and    
        (Get-Item -LiteralPath $skript["cmdLine"]).FullName -ieq $createRAMDiskItem.FullName -and 
        $skript["parameters"] -match "\s*-diskLetter\s+(?<letter>[a-zA-Z]):?\s+" -and
        $Matches["letter"] -ieq $diskLetter)
    {
        $unregScript = $skript      
    }
}

if(-not -not $unregScript)
{
    .\PSScriptRegistration.ps1 -Action Unregistration -State Startup -CmdLine $unregScript["cmdLine"] -Parameters $unregScript["parameters"]
}

.\PSScriptRegistration.ps1 -Action Registration -State Startup -CmdLine $createRAMDiskPath -Parameters "-diskLetter ${diskLetter}: -diskSize ${diskSize} -logPath `"${logPath}`""

$skripts =  .\PSScriptRegistration.ps1 -Action GetAll -State Shutdown
$createRAMDiskItem = Get-Item -LiteralPath $createRAMDiskPath
$unregScript = $null
foreach ($skript in $skripts) 
{
    if((Test-Path $skript["cmdLine"]) -and    
        (Get-Item -LiteralPath $skript["cmdLine"]).FullName -ieq $stopRAMDisksPath.FullName)
    {
        $unregScript = $skript      
    }
}
if(-not $unregScript)
{
    .\PSScriptRegistration.ps1 -Action Registration -State Shutdown -CmdLine $stopRAMDisksPath -Parameters "-logPath `"${logPath}`""
}