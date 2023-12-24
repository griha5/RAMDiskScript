param (
    [Parameter(Mandatory=$true)]
    [string]$Action,       # Action: "Registration", "Unregistration", or "GetAll"
    [Parameter(Mandatory=$true)]
    [string]$State,        # State: "Startup" or "Shutdown"
    [string]$CmdLine,      # Command line
    [string]$Parameters,   # Parameters
    [string]$InputFile,    # Input file
    [string]$OutputFile    # Output file
)

# Check the value of the $Action parameter
if ($Action -eq "Registration" -or $Action -eq "Unregistration") 
{
    if(-not $CmdLine)
    {
        throw "The 'CmdLine' parameter must be specified for 'Registration' or 'Unregistration' actions."
    }

    if($Parameters -eq $null)
    {
        $Parameters = ""
    }

    if(-not $OutputFile)
    {
        $OutputFile = Join-Path -Path $env:SystemRoot -ChildPath "System32\GroupPolicy\Machine\Scripts\psscripts.ini"
    }

}
elseif ($Action -ne "GetAll")
{
    throw "The 'Action' parameter must be 'Registration', 'Unregistration', or 'GetAll'."
}

# Check the value of the $State parameter
if ($State -ne "Startup" -and $State -ne "Shutdown") 
{
    throw "The 'State' parameter must be 'Startup' or 'Shutdown'."
}

if(-not $InputFile)
{
    $InputFile = Join-Path -Path $env:SystemRoot -ChildPath "System32\GroupPolicy\Machine\Scripts\psscripts.ini"
}

# Read the contents of the psscripts.ini file
$psscriptsContent = Get-Content -Path $InputFile -Raw

# Create a Hashtable to store blocks
$blocks = @{}

# Initialize variables to store the current block and its content
$currentBlock = ""
$blockContent = @()
$blockNames = @()

# Split the content of the file into lines
$lines = $psscriptsContent -split "`r`n"

# Check if the last line is empty
if ($lines[-1] -eq "") 
{
    # If the last line is empty, remove it
    $lines = $lines[0..($lines.Length - 2)]
}

# Iterate through each line in the file
foreach ($line in $lines) 
{
    if ($line -match "^\[(.+)\]") 
    {
        # Start of a new block
        $currentBlock = $Matches[1]
        $blockNames += $currentBlock
        $blocks[$currentBlock] = @()
    } 
    else 
    {
        $blocks[$currentBlock] += @("$line")
    }
}

# Name of the block obtained from $State
$stateBlockName = $State

# Determine the action based on the value of the -Action parameter
if ($Action -eq "GetAll") 
{
    $result=@()

    if($blocks.ContainsKey($stateBlockName))
    {
        $existingBlock = $blocks[$stateBlockName]

        $number=$null        

        foreach ($line1 in $existingBlock) 
        {
            if ($line1 -match "^(?<number>\d+)CmdLine=(?<cmdLineBody>.*)") 
            {
                $tempNumber = [int]$Matches["number"]
                $cmdLineBody = $Matches["cmdLineBody"]

                $parametersBody = ""
                foreach ($line2 in $existingBlock) 
                {
                    if ($line2 -match "^${tempNumber}Parameters=(?<parametersBody>.*)") 
                    {
                        $parametersBody = $Matches["parametersBody"]
                        break
                    }                             
                }

                $cmdAndParam =@{}
                $cmdAndParam["cmdLine"]=$cmdLineBody
                $cmdAndParam["parameters"]=$parametersBody

                $result +=  @{"cmdLine"=$cmdLineBody; "parameters"=$parametersBody}
            }        
        }        
    }

    return $result
}
elseif ($Action -eq "Registration") 
{
    # Performing the action for registration

    $blockNames = @($blockNames | Where-Object { $_ -ne $stateBlockName })
    $blockNames += @($stateBlockName)    

    $updatedBlock = @("0CmdLine=$CmdLine", "0Parameters=$Parameters")

    if (-not $blocks.ContainsKey($stateBlockName)) 
    {
        # Block '$stateBlockName' is absent.
        # Create a block with the name obtained from $State and add two lines
        $blocks[$stateBlockName] = $updatedBlock
    } 
    else
    {
        # Block '$stateBlockName' already exists.
        # Read lines from the existing block and update them
        $existingBlock = $blocks[$stateBlockName]

        foreach ($line in $existingBlock) 
        {
            if ($line -match "^(?<number>\d+)(?<str>(CmdLine)|(Parameters))=(?<body>.*)") 
            {
                $number = [int]$Matches["number"]
                $str = $Matches["str"]
                $body = $Matches["body"]
                $number++
                $updatedBlock += "$number$str=$(([string]$body).Trim())"
            } 
            elseif ( !($line -match "^\s*$") ) 
            {
                $updatedBlock += $line
            }
        }
        $blocks[$stateBlockName] = $updatedBlock
    }
} 
elseif ($Action -eq "Unregistration") 
{
    # Performing the action for unregistration.
    # Read lines from the existing block and update them
    if($blocks.ContainsKey($stateBlockName))
    {
        $existingBlock = $blocks[$stateBlockName]

        $number=$null

        foreach ($line1 in $existingBlock) 
        {
            if ($line1 -match "^(?<number>\d+)CmdLine=(?<cmdLineBody>.*)") 
            {
                $tempNumber = [int]$Matches["number"]
                $cmdLineBody = $Matches["cmdLineBody"]
                if($cmdLineBody.Trim() -eq $CmdLine.Trim())
                {
                    $parametersBody = ""
                    foreach ($line2 in $existingBlock) 
                    {
                        if ($line2 -match "^${tempNumber}Parameters=(?<parametersBody>.*)") 
                        {
                            $parametersBody = $Matches["parametersBody"]
                            break
                        }                             
                    }

                    if($parametersBody.Trim() -eq $Parameters.Trim())
                    {
                        $number=$tempNumber
                        break
                    }
                }
            }        
        }

        if($number -ne $null) 
        {
            $updatedBlock = @()
            foreach ($line in $existingBlock) 
            {
                if ($line -match "^(?<number>\d+)(?<str>(CmdLine)|(Parameters))=(?<body>.*)") 
                {
                    $tempNumber = [int]$Matches["number"]
                    $str = $Matches["str"]
                    $body = $Matches["body"]
                    if($tempNumber -ne $number) {
                        if($tempNumber -gt $number) 
                        {
                            $tempNumber--
                        }                            
                        $updatedBlock += "$tempNumber$str=$(([string]$body).Trim())"
                    }
                } 
                elseif ( !($line -match "^\s*$") ) 
                {
                    $updatedBlock += $line
                }
            }
            $blockNames = @($blockNames | Where-Object { $_ -ne $stateBlockName })                       
            if(-not -not $updatedBlock)
            {            
                $blockNames += @($stateBlockName)
                $blocks[$stateBlockName] = $updatedBlock
            }
            else
            {
                $blocks.Remove($stateBlockName);
            }
        } 
        else
        {
            # Matching in the $stateBlockName block is absent, unregistration is not possible
        }        
    }
}

# Create a new file "psscripts2.ini" with blocks, starting from the block with an empty heading
$psscripts2File = Join-Path -Path $env:SystemRoot -ChildPath "System32\GroupPolicy\Machine\Scripts\psscripts2.ini"
$psscripts2Content = @()

if($blocks.ContainsKey("")) 
{
    $psscripts2Content += $blocks[""]
}

foreach ($blockName in $blockNames) 
{
    if ($blockName -ne "") 
    {
        $psscripts2Content += "[$blockName]"
        $psscripts2Content += $blocks[$blockName]
    }
}

# Clear the Hidden attribute for the output ini file if there is a file and it has this attribute
if (Test-Path $OutputFile -PathType Leaf) 
{
    $file = Get-Item -Path $OutputFile -Force
    $hiddenAttribute = $file.Attributes -band [System.IO.FileAttributes]::Hidden
    if ($hiddenAttribute -eq [System.IO.FileAttributes]::Hidden) 
    {    
        $file.Attributes = $file.Attributes -band (-bnot [System.IO.FileAttributes]::Hidden)
    }
}
# Save the result to the output ini file
$psscripts2Content -join "`r`n" | Set-Content -Path $OutputFile -Encoding Unicode  

# Set the Hidden attribute
(Get-Item -Path $OutputFile).Attributes = [System.IO.FileAttributes]::Hidden
