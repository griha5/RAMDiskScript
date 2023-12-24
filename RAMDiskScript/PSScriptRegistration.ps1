param (
    [Parameter(Mandatory=$true)]
    [string]$Action,
    [Parameter(Mandatory=$true)]
    [string]$State,
    [string]$CmdLine,
    [string]$Parameters,
    [string]$InputFile, 
    [string]$OutputFile
)


# Проверяем значение параметра $Action
if ($Action -eq "Registration" -or $Action -eq "Unregistration") 
{
    if(-not $CmdLine)
    {
        throw "Значение параметра 'CmdLine' должно быть задано для значений параметра 'Action' Registration' или 'Unregistration'"
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
elseif ( $Action -ne "GetAll")
{
    throw "Значение параметра 'Action' должно быть 'Registration', 'Unregistration' или 'GetAll'."
}

# Проверяем значение параметра $State
if ($State -ne "Startup" -and $State -ne "Shutdown") 
{
    throw "Значение параметра 'State' должно быть 'Startup' или 'Shutdown'."
}

if(-not $InputFile)
{
    $InputFile = Join-Path -Path $env:SystemRoot -ChildPath "System32\GroupPolicy\Machine\Scripts\psscripts.ini"
}

# Читаем содержимое файла psscripts.ini
$psscriptsContent = Get-Content -Path $InputFile -Raw

# Создаем Hashtable для хранения блоков
$blocks = @{}

# Инициализируем переменные для хранения текущего блока и его содержимого
$currentBlock = ""
$blockContent = @()
$blockNames = @()

# Разделяем содержимое файла на строки
$lines = $psscriptsContent -split "`r`n"

# Проверяем, является ли последняя строка пустой
if ($lines[-1] -eq "") 
{
    # Если последняя строка пустая, удаляем ее
    $lines = $lines[0..($lines.Length - 2)]
}

# Пройдем по каждой строке в файле
foreach ($line in $lines) 
{
    if ($line -match "^\[(.+)\]") 
    {
        # Начало нового блока
        $currentBlock = $Matches[1]
        $blockNames += $currentBlock
        $blocks[$currentBlock] = @()
    } 
    else 
    {
        $blocks[$currentBlock] += @("$line")
    }
}

# Имя блока полученное из $State
$stateBlockName = $State

# Определяем действие в зависимости от значения параметра -Action
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
elseif ($Action -eq "Registration") {
    # Выполняется действие для регистрации

    $blockNames = @($blockNames | Where-Object { $_ -ne $stateBlockName })
    $blockNames += @($stateBlockName)    

    $updatedBlock = @("0CmdLine=$CmdLine", "0Parameters=$Parameters")

    if (-not $blocks.ContainsKey($stateBlockName)) 
    {
        # Блок '$stateBlockName' отсутствует.
        # Создаем блок с именем, полученным из $State, и добавляем две строки
        $blocks[$stateBlockName] = $updatedBlock
    } 
    else
    {
        # Блок '$stateBlockName' уже существует.
        # Читаем строки из существующего блока и обновляем их
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
    # Выполняется действие для отмены регистрации.
    # Читаем строки из существующего блока и обновляем их
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
                } elseif ( !($line -match "^\s*$") ) 
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

        } else
        {
            # Совпадение в блоке $stateBlockName отсутствует, разрегестрация невозможна
        }        
    }
}

# Создаем новый файл "psscripts2.ini" с блоками, начиная с блока с пустым заглавием
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

# Очищаем атрибут Hidden для выходного ini-файла, если есть файл и он имеет этот атрибут
if (Test-Path $OutputFile -PathType Leaf) 
{
    $file = Get-Item -Path $OutputFile -Force
    $hiddenAttribute = $file.Attributes -band [System.IO.FileAttributes]::Hidden
    if ($hiddenAttribute -eq [System.IO.FileAttributes]::Hidden) 
    {    
        $file.Attributes = $file.Attributes -band (-bnot [System.IO.FileAttributes]::Hidden)
    }
}
# Сохраняем результат в выходной ini-файл
$psscripts2Content -join "`r`n" | Set-Content -Path $OutputFile -Encoding Unicode  

# Устанавливаем атрибут Hidden
(Get-Item -Path $OutputFile).Attributes = [System.IO.FileAttributes]::Hidden
