param(
    [string]$ConfigPath,
    [switch]$Force
)

function SetConfig() {
    param (
        $config
    )

    $global:buildPath = $config.build.img_path
    $global:buildVMPath = Join-Path $buildPath "Virtual Machines"
    $global:buildVM = Join-Path $buildVMPath (Get-ChildItem $buildVMPath -Filter *.vmcx | Select-Object -ExpandProperty Name)
    $global:vmName = $config.vm.name ?? "Virtual-Machine"
    $global:vmDestination = Join-Path $config.build.vm_dest $vmName
    $global:vmVHDDest = Join-Path $vmDestination "Virtual Hard Disks"
    $global:vhdxName = "$vmName.vhdx"
    $global:vmNetAdapter = $config.vm.net_adapter ?? "Default Switch"
    $global:vmProcessorCount = $config.vm.processor_count ?? 1
    $global:vmMemorySize = ($config.vm.memory_size * 1MB) ?? 1024MB
    $global:vmMemorySizeMin = $config.vm.memory_size.min * 1MB
    $global:vmMemorySizeMax = $config.vm.memory_size.max * 1MB
    $global:vmStaticMac = $config.vm.static_mac ?? $false
    $global:vmStopAction = $config.vm.stop_action ?? "Shutdown"
    $global:vmStartAction = $config.vm.start_action ?? "StartIfRunning"   
}

# Define variables
$vmconfig = Get-Content $ConfigPath -raw | ConvertFrom-Json
$vmcount = $vmconfig.count
$todo = @()
for ($i = 0; $i -lt $vmcount; $i++) {
    SetConfig $vmconfig[$i]
    $vm = Get-VM $vmName -ErrorAction SilentlyContinue

    if (-not $vm) {
        Write-Host "`n$vmName"
        Write-Host "-----------"
        Write-Host "`tDoesn't exist. Will be created" -ForegroundColor Yellow
        $changes = $true
    } else {
        $changes = $false
        Write-Host "`n$vmName"
        Write-Host "-----------"
        $currProcCount = (Get-VMProcessor -VMName $vmName).Count
        if ($currProcCount -ne $vmProcessorCount) {
            Write-Host "`tProcessor count: $currProcCount -> $vmProcessorCount"
            $changes = $true
        }

        $currMemory = (Get-VMMemory $vmName).Startup / (1024 * 1024)
        $currMaxMem = (Get-VMMemory $vmName).Maximum / (1024 * 1024)
        $currMinMem = (Get-VMMemory $vmName).Minimum / (1024 * 1024)
        $currMemoryDynamic = (Get-VMMemory $vmName).DynamicMemoryEnabled
        
        if (([string]::IsNullOrEmpty($vmMemorySizeMin)) -and ([string]::IsNullOrEmpty($vmMemorySizeMax))) {
            if (($currMemory) -ne ($vmMemorySize / (1024 * 1024))) {
                Write-Host "`tMemory size: $currMemory -> " ($vmMemorySize / (1024 * 1024))
                $changes = $true
            }
        } else {
            if (($currMaxMem) -ne ($vmMemorySizeMax / (1024 * 1024))) {
                Write-Host "`tMax memory size: $currMaxMem -> " ($vmMemorySizeMax / (1024 * 1024))
                $changes = $true
            }
            if (($currMinMem) -ne ($vmMemorySizeMin / (1024 * 1024))) {
                Write-Host "`tMin memory size: $currMinMem -> " ($vmMemorySizeMin / (1024 * 1024)) 
                $changes = $true
            }
            if ($currMemoryDynamic -ne $True) {
                Write-Host "`tDynamic memory: $currMemoryDynamic -> $True"
                $changes = $true 
            }
        }

        $currNetAdapter = (Get-VMNetworkAdapter $vmName).SwitchName
        if ($currNetAdapter -ne $vmNetAdapter) {
            Write-Host "`tNetwork adapter: $currNetAdapter -> $vmNetAdapter"
            $changes = $true
        }

        $currMacType = (Get-VMNetworkAdapter -VMName $vmName).DynamicMacAddressEnabled
        if ($currMacType -eq $vmStaticMac) {
            switch ($currMacType){
                $true {$currMacType = "Dynamic"}
                $false {$currMacType = "Static"}
            }
            switch ($vmStaticMac){
                $true {$confMacType = "Static"}
                $false {$confMacType = "Dynamic"}
            }
            Write-Host "`tMac type: $currMacType -> $confMacType"
            $changes = $true
        }

    }
    if (-not ($changes)) {
        Write-Host "`tNo changes." -ForegroundColor Magenta
    } else {
        $todo += $vmconfig[$i]
    }    
}

if ($todo) {
    $answer = Read-Host "Apply these changes? (Only 'yes' will allow you to proceed.)"
    If ($answer -eq 'yes') {
        try {
            foreach ($config in $todo) {
                SetConfig $config

                Write-Host "`n$vmName"
                Write-Host "-----------"
                $vm = Get-VM $vmName -ErrorAction SilentlyContinue

                if (-not $vm) {
                    # Delete VM folder if it exists and -Force flag is set
                    if ($Force) {
                        if (Test-Path $vmDestination) {
                            Remove-Item $vmDestination -Force -Recurse
                        }           
                    }

                    # Create VM folders
                    Write-Host "`tCreating..."
                    if (-not(Test-Path $vmDestination)) {
                        New-Item $vmDestination -ItemType dir | Out-Null
                    }
                    if (-not(Test-Path $vmVHDDest)) {
                        New-Item $vmVHDDest -ItemType dir | Out-Null
                    }

                    # Import packer-built VM
                    $packerVM = Import-VM -Path $buildVM -Copy -GenerateNewId -VhdDestinationPath $vmVHDDest -VirtualMachinePath $vmDestination

                    # Rename the imported VM
                    Rename-VM -VM $packerVM -NewName $vmName

                    # Rename VHDX
                    $disk = Get-VMHardDiskDrive -VMName $vmName  | Select-Object -First 1
                    $vhdxPath = Join-Path (Split-Path $disk.path) $vhdxName
                    Rename-Item -Path $disk.path -NewName $vhdxPath

                    # Remove the old VHDX from the VM and add renamed VHDX
                    Remove-VMHardDiskDrive -VMName $vmName -ControllerLocation $disk.ControllerLocation -ControllerNumber $disk.ControllerNumber -ControllerType SCSI
                    Add-VMHardDiskDrive -VMName $vmName -Path $vhdxPath
                } else {
                    Write-Host "`tStopping..."
                    Stop-VM $vmName
                    do {
                        $vmState = Get-VM $vmName | Select-Object -ExpandProperty State
                        Start-Sleep -Seconds 5
                    } until ($vmState -eq "Off")
                    Write-Host "`t$vmName stopped successfully!"
                    Write-Host "`tReconfiguring..."
                }

                # Set VM processor count
                Set-VMProcessor -VMName $vmName -Count $vmProcessorCount

                # Set VM memory size
                if (([string]::IsNullOrEmpty($vmMemorySizeMin)) -and ([string]::IsNullOrEmpty($vmMemorySizeMax))) {
                    Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false -StartupBytes $vmMemorySize 
                } else {
                    if ([string]::IsNullOrEmpty($vmMemorySizeMin)) {
                        Write-Host "`tMin value is empty or missing. Using default memory size for build." -ForegroundColor Yellow
                    } elseif ([string]::IsNullOrEmpty($vmMemorySizeMax)) {
                        Write-Host "`tMax value is empty or missing. Using default memory size for build." -ForegroundColor Yellow
                    } else {
                        Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $true -MinimumBytes $vmMemorySizeMin -MaximumBytes $vmMemorySizeMax
                    }
                }

                # Set network adapter
                Connect-VMNetworkAdapter -VMName $vmName -SwitchName $vmNetAdapter

                #Set MAC type if set to static
                $nic = Get-VMNetworkAdapter -VMName $vmName
                if ($vmStaticMac) {                    
                    Set-VMNetworkAdapter -VMName $vmName -StaticMacAddress $nic.macaddress
                } else {
                    Set-VMNetworkAdapter -VMName $vmName -DynamicMacAddress $true
                }

                # Set auto start/stop actionss
                Set-VM -Name $vmName -AutomaticStartAction $vmStartAction -AutomaticStopAction $vmStopAction

                # Start the VM
                Start-VM -Name $vmName

                if (-not($vm)) {
                    Write-Host "`t$VMName imported successfully from $buildPath" -ForegroundColor Green
                    Write-Host "`tGetting IP for $VMName..."
                    $timeout = 120 # Timeout in seconds
                    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    $timedout = $false
                    $vmIP = $null
                    do {
                        if ($stopwatch.Elapsed.TotalSeconds -gt $timeout) {
                            $timedout = $true
                            break
                        }
                
                        $vmIP = (Get-VM -Name $VMName).NetworkAdapters | ForEach-Object { $_.IPAddresses }
                        if ($vmIP) {
                            break
                        }
                
                        Start-Sleep -Seconds 2
                    } until ($vmIP)
                    
                    if ($timedout) {
                        Write-Host "`tTimed out after $timeout seconds. Could not retrive IP." -ForegroundColor Red
                    } else {
                        Write-Host "`tAccess VM at: $vmIP" -ForegroundColor Cyan
                    }
                } else {
                    Write-Host "`t$VMName reconfigured successfully!" -ForegroundColor Green
                }
            }
        } catch {
            Write-Error $_
        }
    } else {
        write-Host "No changes applied."
    }
}
