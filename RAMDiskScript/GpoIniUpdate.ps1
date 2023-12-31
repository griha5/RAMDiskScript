param (
    [string]$scriptsFolder = $(Join-Path -Path $env:SystemRoot -ChildPath "System32\GroupPolicy\Machine\Scripts")
)

if (-not (Test-Path -Path $scriptsFolder)) 
{
    New-Item -ItemType Directory -Path $scriptsFolder -Force
}

$scriptsFolderStartup = Join-Path -Path $scriptsFolder -ChildPath "Startup"
if (-not (Test-Path -Path $scriptsFolderStartup)) 
{
    New-Item -ItemType Directory -Path $scriptsFolderStartup -Force
}

$scriptsFolderShutdown = Join-Path -Path $scriptsFolder -ChildPath "Shutdown"
if (-not (Test-Path -Path $scriptsFolderShutdown)) 
{
    New-Item -ItemType Directory -Path $scriptsFolderShutdown -Force
}

$pathToFile =Join-Path -Path (Get-Item (Get-Item $scriptsFolder).Parent.FullName).Parent.FullName -ChildPath "gpt.ini"

if (Test-Path $pathToFile -PathType Leaf) 
{
    $iniContent = Get-Content -Path $pathToFile -Raw
}
else
{
    $iniContent = ""
}

$iniObject = @{}
$section = $null
$iniContent -split '\r?\n' | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^\[(.+)\]$') 
    {
        $section = $Matches[1]
        $iniObject[$section] = @{}
    } 
    elseif ($line -match '^(.+)=(.+)$' -and $section) 
    {
        $key = $Matches[1].Trim()
        $value = $Matches[2].Trim()
        $iniObject[$section][$key] = $value
    }
}

if (-not $iniObject.ContainsKey('General')) {
    $iniObject['General'] = @{}}

if (-not $iniObject['General'].ContainsKey('gPCMachineExtensionNames')) {
    $iniObject['General']['gPCMachineExtensionNames'] = '[]'
}
$gPCMachineExtensionNames = @([regex]::Matches($iniObject['General']['gPCMachineExtensionNames'], '\{(.*?)\}')  | ForEach-Object { $_.Groups[1].Value.ToString() })

$addScripts=@()

if(-not $gPCMachineExtensionNames.Contains('42B5FAAE-6536-11D2-AE5A-0000F87571E3'))
{
    $addScripts += '42B5FAAE-6536-11D2-AE5A-0000F87571E3'
}

if(-not $gPCMachineExtensionNames.Contains('40B6664F-4972-11D1-A7CA-0000F87571E3'))
{
    $addScripts += '40B6664F-4972-11D1-A7CA-0000F87571E3'
}

if(-not -not $addScripts)
{
    $gPCMachineExtensionNames+=$addScripts
    $iniObject['General']['gPCMachineExtensionNames']="[{" + ($gPCMachineExtensionNames -join '}{') + "}]"

    if (-not $iniObject['General'].ContainsKey('Version')) 
    {
        $iniObject['General']['Version'] = '0'
    }

    $iniObject['General']['Version'] = ([System.Int32]::Parse($iniObject['General']['Version'])+1).ToString()

    $newIniContent = $iniObject.Keys | ForEach-Object {
        "[$_]"
        $iniObject[$_].GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    }

    $newIniContent -join "`r`n" | Set-Content -Path $pathToFile -Encoding Unicode
}