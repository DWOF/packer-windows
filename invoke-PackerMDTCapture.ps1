function Invoke-PackerMDTCapture {
    [CmdletBinding()]
    param (
        [ValidateScript({Test-Path $_ })]
        [string]$ISOPath = 'C:\git\packer-windows\iso\SW_DVD9_WIN_PRO_ENT_EDU_N_10_1809_64-BIT_ENGLISH_MLF_X21-96501.ISO',
        [ValidateScript({Test-Path $_ })]
        [string]$PackerTemplateRoot = 'C:\git\packer-windows\',
        [pscredential]$Credential,
        [ValidateScript({Test-Path $_ })]
        [string]$JSONpath = 'C:\git\packer-windows\phtwin10.json',
        [string]$MDTServer = 'QAHMDT01',
        [string]$MDTPSDDriveName = 'DS002',
        [string]$MDTDriveRoot = 'E:\MDT',
        [string]$MDTCapturePath = 'E:\MDT-Win10-Capture\',
        [string[]]$TSNames = ('WIN10-DESKTOP','WIN10-LAPTOP')
    )
 
    #Get hash of ISO
    $Hash = Get-FileHash -Path $ISOPath | Select-Object -ExpandProperty Hash
    $StartTime = Get-Date
    Set-Location $PackerTemplateRoot
    #Start Packer build
    packer build  -var iso_url=$ISOPath -var iso_checksum=$Hash -var iso_checksum_type=SHA256 -force $JSONpath
    Start-Sleep -Seconds 30
    #Check MDT Status of capture
    $DeploymentStatus = Invoke-Command -ComputerName $MDTServer -ArgumentList $StartTime,$MDTServer,$MDTPSDDriveName,$MDTDriveRoot,$MDTCapturePath,$TSNames -Credential $Credential -ScriptBlock {
        Add-PSSnapin Microsoft.BDD.PSSnapIn -ErrorAction Stop | Out-Null
        New-PSDrive -Name $Using:MDTPSDDriveName -PSProvider MDTProvider -Root $Using:MDTDriveRoot -ErrorAction Stop  | Out-Null
        $Status = Get-MDTMonitorData -Path DS002: | Where-Object {$_.Name -eq 'WIN-10' -and $_.StartTime.ToLocalTime() -gt $Using.StartTime} | Select-Object -ExpandProperty DeploymentStatus
        if ($Status -ne '3')
        {
            'False'
        }
        else 
        {
            'True'    
        }
        Remove-PSDrive -Name $Using:MDTPSDDriveName -PSProvider MDTProvider -Force | Out-Null
    }
    if ($DeploymentStatus -eq 'False')
    {
        Write-Warning -Message 'Packer build failed. Exiting'
        Break
    }
    #Import WIM into MDT Production share and change task sequences to use new OS
    Invoke-Command -ComputerName $MDTServer -ArgumentList $MDTServer,$MDTPSDDriveName,$MDTDriveRoot,$MDTCapturePath,$TSNames -Credential $Credential -ScriptBlock {
        try 
        {
            Add-PSSnapin Microsoft.BDD.PSSnapIn -ErrorAction Stop
            New-PSDrive -Name $Using:MDTPSDDriveName -PSProvider MDTProvider -Root $Using:MDTDriveRoot -ErrorAction Stop
            $File = Get-ChildItem -Path "$($Using:MDTCapturePath)Captures\" -ErrorAction Stop | Where-Object {$_.Extension -eq '.wim'} | Sort-Object -Property LastWriteTime -Descending  | Select-Object -First 1 
            $FileDate = Get-Date -UFormat %m-%d-%Y-%H-%M
            Import-MDTOperatingSystem -Path "$($Using:MDTPSDDriveName):\Operating Systems" -SourceFile $File.FullName -Destination (($File.Name).Replace('.wim','') + '-' + $FileDate) -ErrorAction Stop -Verbose
            $LastCapture = Get-ChildItem "$($Using:MDTPSDDriveName):\Operating Systems" -ErrorAction Stop -Verbose | Where-Object {[datetime]($_.createdtime) -gt (Get-Date).AddMinutes(-20)}  | Sort-Object -Property CreatedTime -Descending | Select-Object -First 1 
            $GUID = (Get-ItemProperty "$($Using:MDTPSDDriveName):\Operating Systems\$($LastCapture.PSChildName)" -ErrorAction Stop -Verbose).guid
        }
        catch
        {
            Write-Error $_
            Write-Warning -Message 'Stopped execution'
            Remove-PSDrive -Name $Using:MDTPSDDriveName -PSProvider MDTProvider -Force
            Break
        }
        foreach ($TSName in $Using:TSNames)
        {
            $TSXML = [xml](Get-Content "$($Using:MDTDriveRoot)\Control\$($TSName)\ts.xml" -Verbose)
            $OldGUID = $TSXML.sequence.globalVarList.variable | Where-Object {$_.name -eq "OSGUID"} | Select-Object -ExpandProperty '#text' -First 1
            (Get-Content "$($Using:MDTDriveRoot)\Control\$($TSName)\ts.xml" ).replace($OldGUID, $GUID) | Set-Content "$($Using:MDTDriveRoot)\Control\$($TSName)\ts.xml" -Verbose
        }
        Update-MDTDeploymentShare -Path "$($Using:MDTPSDDriveName):" -Verbose -whatif
        Remove-PSDrive -Name $Using:MDTPSDDriveName  -PSProvider MDTProvider -Force -Verbose
    }
}