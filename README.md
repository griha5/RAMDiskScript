# RAMDiskScript for Windows Server

## Overview

The solution leverages iSCSI  technologies 
and provides PowerShell scripts for managing RAM virtual disks in the Windows Server environment.

## Usage

### 1) Create a virtual disk
```powershell
.\CreateRAMDisk.ps1 -diskLetter B: -diskSize 4Gb
```

### 2) Create virtual disk(s) with system registration

   Download the RAMDiskScript folder with all the scripts and run the script from this folder:
```powershell
.\InstallRAMDisk.ps1 -diskLetter B: -diskSize 4Gb
```

   If additional disks are needed, repeat the command for another disk, for example:
```powershell
.\InstallRAMDisk.ps1 -diskLetter A: -diskSize 8Gb
```

   All scripts from the RAMDiskScript folder will be copied to the "c:\Program Files\RAMDiskScript" folder
   and registered. Upon system startup, the disks will be restored, and upon system shutdown, 
   they will be automatically removed to expedite shutdown.

   To unregister disks from the system, execute the following command from the 'c:\Program Files\RAMDiskScript' folder:
```powershell
cd "c:\Program Files\RAMDiskScript"
.\UninstallRAMDisks.ps1
```

### Note

Make sure to run PowerShell with administrator privileges when executing these scripts. 
Additionally, ensure that the network card is configured for proper network functionality.