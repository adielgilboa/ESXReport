function _ConnectVC ($vcServer, $Username, $Password)
{    
    $vmwmodule = get-module -ListAvailable -name "VMware.VimAutomation.Core" 
    if ($vmwmodule -eq $null)
    {
        find-Module -Name "VMware.Vim*" | install-module
    }

    get-module -ListAvailable -name "VMware*"  | import-module

    if ($global:DefaultVIServers.length -gt 0)
    {
        write-host "Disconnecting from VC connections "
        Disconnect-VIServer * -Force -Confirm:$false 
    }
    if (($vcServer) -and ($Username) -and ($Password))
    {
        try
        {
            write-host "Connecting to VC"
            Connect-VIServer $vcServer -User $Username -Password $Password
        }
        catch
        {
            Write-Error "Error connecting to vCenter!"
        }
    }
    else
    {
        Write-Error "Please fill in all the details"
    }
}

function _GetVmnicPortgroupName ($vNic)
{
    if ($vNic.extensionData.Spec.DistributedVirtualPort -ne $null)
    {
        $dvsPortgroupId =  $vNic.extensionData.Spec | select -ExpandProperty DistributedVirtualPort |select -ExpandProperty PortgroupKey
        $dvsPortgroupName = Get-VDPortgroup -id DistributedVirtualPortgroup-$dvsPortgroupId |select -ExpandProperty name
        $PortgroupName = $dvsPortgroupName + " ("+ $dvsPortgroupId +")"
    }
    elseif ($vNic.extensionData.Spec.Portgroup -ne $null)
    {
        $vsPortgroupName = $vNic.extensionData.Spec | select -ExpandProperty Portgroup
        $vsName = $ESXHost |Get-VirtualPortGroup -name $vsPortgroupName |Get-VirtualSwitch | select -ExpandProperty name
        $PortgroupName = $vsPortgroupName + " ("+ $vsName +")"
    
    }
    elseif ($vNic.extensionData.Spec.OpaqueNetwork -ne $null)
    {
        $OpaqueNetwork = $vNic.extensionData.Spec  | select -ExpandProperty OpaqueNetwork
        $PortgroupName = $OpaqueNetwork.OpaqueNetworkId + " ("+ $OpaqueNetwork.OpaqueNetworkType +")"
    }
    else
    {
        $PortgroupName = $null
    }
    
    return $PortgroupName
}


function _ExecuteConfigurationReport ($vcServer, $Location )
{
    $AllInfo = @()

    if ($global:DefaultVIServers.length -ne 1)
    {
        Write-Error "Could not connect to vCenter! invalid connections amount - " + $global:DefaultVIServers.length
    }
    else
    {
 
        write-host "getting host info"
        if ($Location)
        {
           $ESXhosts = Get-VMHost -name $vcServer -location $Location
        }
        else
        {
            $ESXhosts = Get-VMHost -name $vcServer
        }
        $advSettingsScratch = $ESXhosts | Get-AdvancedSetting -Name "ScratchConfig.CurrentScratchLocation"
        $advSettingsSyslog = $ESXhosts | Get-AdvancedSetting -Name "Syslog.global.LogHost"

        foreach ($ESXhost in $ESXhosts)
        {
            $Info = "" | Select Cluster,ESXi,isDRSActive,DRSMode,isHAActive,HAFailoverLevel,ClusterEVCMode,ESXMaximumCompatibleEVCMode,ScratchConfig,SyslogConfig,isNTPConfigured,isNTPRunning,vmk0_IP,vmk0_Portgroup,vmk0_MTU,vmk0_Netstack,vmk0_ServicesStatus,vmk1_IP,vmk1_Portgroup,vmk1_MTU,vmk1_Netstack,vmk1_ServicesStatus,vmk2_IP,vmk2_Portgroup,vmk2_MTU,vmk2_Netstack,vmk2_ServicesStatus,vmk3_IP,vmk3_Portgroup,vmk3_MTU,vmk3_Netstack,vmk3_ServicesStatus
            $ScratchLocation = ""
            $ScratchLocation = $advSettingsScratch | Where-Object {$_.entity.id -eq $ESXhost.id} |select -ExpandProperty value 
            $SyslogHost = ""
            $SyslogHost = $advSettingsSyslog | Where-Object {$_.entity.id -eq $ESXhost.id} |select -ExpandProperty value 

            $ESXHostAdapters = $ESXhost | Get-VMHostNetworkAdapter 
            $vmk0Services = $ESXHostAdapters |where {$_.DeviceName -eq "vmk0"} | select VMotionEnabled,FaultToleranceLoggingEnabled,ManagementTrafficEnabled,VsanTrafficEnabled,DhcpEnabled
            $vmk1Services = $ESXHostAdapters |where {$_.DeviceName -eq "vmk1"} | select VMotionEnabled,FaultToleranceLoggingEnabled,ManagementTrafficEnabled,VsanTrafficEnabled,DhcpEnabled
            $vmk2Services = $ESXHostAdapters |where {$_.DeviceName -eq "vmk2"} | select VMotionEnabled,FaultToleranceLoggingEnabled,ManagementTrafficEnabled,VsanTrafficEnabled,DhcpEnabled
            $vmk3Services = $ESXHostAdapters |where {$_.DeviceName -eq "vmk3"} | select VMotionEnabled,FaultToleranceLoggingEnabled,ManagementTrafficEnabled,VsanTrafficEnabled,DhcpEnabled

            $info.Cluster                              = $ESXhost.parent.name
            $info.ESXi                                 = $ESXhost.name
            $info.isDRSActive                          = $ESXhost.parent.drsenabled
            $info.DRSMode                              = $ESXhost.parent.drsautomationlevel
            $info.isHAActive                           = $ESXhost.parent.haenabled
            $info.HAFailoverLevel                      = $ESXhost.parent.HAFailoverLevel
            $info.ClusterEVCMode                       = $ESXhost.parent.EVCMode
            $info.ESXMaximumCompatibleEVCMode          = $ESXhost.MaxEVCMode
            $info.ScratchConfig                        = $ScratchLocation
            $info.SyslogConfig                         = $SyslogHost
            $info.isNTPConfigured                      = ($ESXHost.ExtensionData.Config.DateTimeInfo.NtpConfig.Server -join ";")
            $info.isNTPRunning                         = ($ESXHost.ExtensionData.Config.Service.Service | where {$_.key -eq "ntpd"} | select -ExpandProperty Running)
            $info.vmk0_IP                              = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk0"} | select -ExpandProperty IP)
            $info.vmk0_Portgroup                       = (_GetVmnicPortgroupName ($ESXHostAdapters |where {$_.DeviceName -eq "vmk0"}))
            $info.vmk0_MTU                             = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk0"} | select -ExpandProperty MTU)
            $info.vmk0_Netstack                        = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk0"} | select -ExpandProperty ExtensionData |select -ExpandProperty spec |select -ExpandProperty netstackInstanceKey)
            $info.vmk0_ServicesStatus                  = $vmk0Services
            $info.vmk1_IP                              = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk1"} | select -ExpandProperty IP)
            $info.vmk1_Portgroup                       = (_GetVmnicPortgroupName ($ESXHostAdapters |where {$_.DeviceName -eq "vmk1"}))
            $info.vmk1_MTU                             = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk1"} | select -ExpandProperty MTU)
            $info.vmk1_Netstack                        = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk1"} | select -ExpandProperty ExtensionData |select -ExpandProperty spec |select -ExpandProperty netstackInstanceKey)
            $info.vmk1_ServicesStatus                  = $vmk1Services
            $info.vmk2_IP                              = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk2"} | select -ExpandProperty IP)
            $info.vmk2_Portgroup                       = (_GetVmnicPortgroupName ($ESXHostAdapters |where {$_.DeviceName -eq "vmk2"}))
            $info.vmk2_MTU                             = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk2"} | select -ExpandProperty MTU)
            $info.vmk2_Netstack                        = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk2"} | select -ExpandProperty ExtensionData |select -ExpandProperty spec |select -ExpandProperty netstackInstanceKey)
            $info.vmk2_ServicesStatus                  = $vmk2Services
            $info.vmk3_IP                              = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk3"} | select -ExpandProperty IP)
            $info.vmk3_Portgroup                       = (_GetVmnicPortgroupName ($ESXHostAdapters |where {$_.DeviceName -eq "vmk3"}))
            $info.vmk3_MTU                             = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk3"} | select -ExpandProperty MTU)
            $info.vmk3_Netstack                        = ($ESXHostAdapters |where {$_.DeviceName -eq "vmk3"} | select -ExpandProperty ExtensionData |select -ExpandProperty spec |select -ExpandProperty netstackInstanceKey)
            $info.vmk3_ServicesStatus                  = $vmk3Services 


            $AllInfo += $info
        }
        return $AllInfo
    }

}
	

Function _GetDeviceList ($esxhost)
{
	if ($Location)
	{
		$devices = get-vmhost -name $esxhost -Location $Location | Get-VMHostPciDevice | where { $_.DeviceClass -eq "MassStorageController" -or $_.DeviceClass -eq "NetworkController" -or $_.DeviceClass -eq "SerialBusController"} 
	}
	else
	{
		$devices = get-vmhost -name $esxhost | Get-VMHostPciDevice | where { $_.DeviceClass -eq "MassStorageController" -or $_.DeviceClass -eq "NetworkController" -or $_.DeviceClass -eq "SerialBusController"} 
	}
    $AllInfo = @()
    $counter = 0
    $Length = $devices.length
    write-host "found $Length devices"
    Foreach ($device in $devices) 
    {
	    $counter++
	    $Percent = $Counter / $Length * 100
	    $Percent = [math]::truncate($Percent) 
	    $VMHostName = $device.vmhost.name 
	    Write-Progress -Activity "Device Compatibility Search in Progress (Current Host - $VMHostName)" -Status "$Counter / $Length Complete:" -PercentComplete $Percent;
	    # Ignore USB Controller
	    if ($device.DeviceName -like "*USB*" -or $device.DeviceName -like "*iLO*" -or $device.DeviceName -like "*iDRAC*") 
	    {
		    continue
	    }

	    $Info = "" | Select Parent, VMHost, VMHostVersion,VMHostBuild, Device, DeviceName, VendorName, DeviceClass, vid, did, svid, ssid, Driver, DriverVersion, FirmwareVersion, VibVersion, Supported,DeviceWarnings, Reference
	    $Info.VMHost = $device.VMHost
	    $Info.DeviceName = $device.DeviceName
	    $Info.VendorName = $device.VendorName
	    $Info.DeviceClass = $device.DeviceClass
	    $Info.VMHostBuild = $device.VMHost.build
	    $Info.Parent = $device.VMHost.Parent.name
	    $Info.vid = [String]::Format("{0:x4}", $device.VendorId)
	    $Info.did = [String]::Format("{0:x4}", $device.DeviceId)
	    $Info.svid = [String]::Format("{0:x4}", $device.SubVendorId)
	    $Info.ssid = [String]::Format("{0:x4}", $device.SubDeviceId)

        #Get ESXi Host Version
		$esxcliv1 = $device.vmhost | get-esxcli
		$ESXVersionArr =$esxcliv1.system.version.get().version.split(".")
		$ESXVersion =  $ESXVersionArr[0] + "." + $ESXVersionArr[1]
		$ESXUpdate = $esxcliv1.system.version.get().update
		if (($ESXUpdate -ne "0") -or ($ESXUpdate -eq $null))
		{
			$ESXRelease = $ESXVersion +  " U" + $ESXUpdate
		}
		else
		{
			$ESXRelease = $ESXVersion
		}
		
		if (($SimulateESXiVersion -eq $null) -or ($SimulateESXiVersion -eq "") -or ($SimulateESXiVersion -eq " "))
		{
			$Info.VMHostVersion = $ESXRelease
		}
		else
		{
			$Info.VMHostVersion = $SimulateESXiVersion
		}
	
	    if(($device.DeviceClass -eq "SerialBusController") -or ($device.DeviceClass -eq "NetworkController"))
	    {
		    #Handle Network Adapters - Get Installed Drivers and Firmware information using Get-EsxCli Version 2
		    if ($device.DeviceClass -eq "NetworkController")
		    {
			    # Get NIC list to identify vmnicX from PCI slot Id
			    $esxcli = $device.VMHost | Get-EsxCli -V2
			    $niclist = $esxcli.network.nic.list.Invoke();
			    $vmnicId = $niclist | where { $_.PCIDevice -like '*'+$device.Id}
			    $Info.Device = $vmnicId.Name
			
			    # Get NIC driver and firmware information
			    Write-Debug "Processing $($Info.VMHost.Name) $($Info.Device) $($Info.DeviceName)"
			    if ($vmnicId.Name)
			    {      
				    $vmnicDetail = $esxcli.network.nic.get.Invoke(@{nicname = $vmnicId.Name})
				    $Info.Driver = $vmnicDetail.DriverInfo.Driver
				    $Info.DriverVersion = $vmnicDetail.DriverInfo.Version
				    $Info.FirmwareVersion = $vmnicDetail.DriverInfo.FirmwareVersion
				
				    # Get driver vib package version
				    Try
				    {
					    $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = "net-"+$vmnicDetail.DriverInfo.Driver})
				    }
				    Catch
				    {
					    $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = $vmnicDetail.DriverInfo.Driver})
				    }
				    $Info.VibVersion = $driverVib.Version
			    }
		
		    } 
		    #Handle FC Adapters - Get Installed Drivers and Firmware information using Get-EsxCli Version 2 and Plink to ESXi Host
		    elseif ( $device.DeviceClass -eq "SerialBusController")
		    {
			    # Identify HBA (FC) with PCI slot Id
			    # Todo: Sometimes this call fails with: Get-VMHostHba  Object reference not set to an instance of an object.
			    $esxcli = $device.VMHost | Get-EsxCli -V2
			    $vmhbaId = $device.VMHost |Get-VMHostHba -ErrorAction SilentlyContinue | where { $_.PCI -like '*'+$device.Id}
			    $Info.Device = $vmhbaId.Device
			    $Info.Driver = $vmhbaId.Driver
							
				
			    # Get driver vib package version
			    Try
			    {
				    $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = "scsi-"+$vmhbaId.Driver})
			    }
			    Catch
			    {
				    Try
				    {
					    $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = $vmhbaId.Driver})
				    }
				    Catch
				    {
						if ($vmhbaId.Driver.Contains("_") )
						{
							$vibname = $vmhbaId.Driver.replace("_","-")
						}
					    $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = $vibname})
				    }
			    }
			    $Info.VibVersion = $driverVib.Version
			    $Info.DriverVersion = $vmhbaId.DriverInfo.Version
			    
						
				# Get HBA Device Firmware and Driver using ESXCLI
				$DeviceName = $vmhbaId.Device
				$ESXHBAs = $esxcli.storage.san.fc.list.Invoke() |Select  @{N="Adapter";E={$_.Adapter}},@{N="DriverVersion";E={$_.DriverVersion}},@{N="FirmwareVersion";E={$_.FirmwareVersion}}
				
				$info.FirmwareVersion = $ESXHBAs | where {$_.Adapter -eq $DeviceName} | select -ExpandProperty "FirmwareVersion"
				$info.DriverVersion =  $ESXHBAs | where {$_.Adapter -eq $DeviceName} | select -ExpandProperty "DriverVersion"

				if ($Info.FirmwareVersion -eq $null)
				{
				    $Info.FirmwareVersion = "N/A"
				}
				if ($Info.DriverVersion -eq $null)
				{
					$Info.DriverVersion = "N/A"
				}

			    Write-Host "Got HBA $DeviceName Firmware $($Info.FirmwareVersion) and Driver: $($Info.DriverVersion)"
			}
		  
            
            if ($info.device -ne $null)
            {
		        $AllInfo += $Info
            }
	    }
    }
    return $AllInfo
}

Function _CheckDeviceOnline ($DeviceList, $OfflineHCL)
{
	$AllDevicesWithSupport = @()	
	foreach ($device in $DeviceList)	
    {
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Accept", "*/*")
        $headers.Add("Accept-Encoding", "application/gzip, deflate, br")
        $headers.Add("x-api-key", "SJyb8QjK2L")
        $headers.Add("x-api-toolid", "180209100001")
        $headers.Add("x-request-id", "8f90e8af-4821-4159-aad2-f360533ab2e2")
        $headers.Add("Cookie", "vdc-cookie=!RugicSNTG0EN4P36Re7Y1j0kh+zwSVQ64eyLh0Z4957C/vk8HLqvMEUNxqMAk/gjZVYHVqHvlZMWyA==")
		$url = "https://apigw.vmware.com/m4/compatibility/v1/compatible/iodevices/search?vid=0x$($device.vid)&did=0x$($device.did)&svid=0x$($device.svid)&ssid=0x$($device.ssid)&releaseversion=$($device.VMHostVersion)&driver=$($device.driver)&driverversion=$($device.driverversion)" # &firmware=$($device.firmwareversion)
		write-host "Host $($device.vmhost.name) device $($device.DeviceName) Checking device with URL: "
		write-host "$url"
        $response = Invoke-RestMethod $url -Method 'GET' -Headers $headers -Body $body
		$potentialMatches = @()

        $matches = new-object system.collections.arraylist
		
        if ($response.potentialMatches.length -gt 0)
        {
            $potentialMatches = $response.potentialMatches
        }
        else
        {
            $potentialMatches = $response.matches
        }

		$device.Supported = "Not Compatible"
        foreach ($match in $PotentialMatches)
        {
			
            $matches.add($match.vcgLink) > $null
			if ($match.features -is [array])
			{
				$matchFeatures = $match.features
			}
			else
			{
				$members =  $match.features | Get-Member |where {$_.MemberType -eq "NoteProperty"}
				$matchFeatures = @()
				write-host "DEBUG - got members: $($members.name)"
				foreach ($member in $members)
				{
					$matchFeatures += $match.features.($member.name)
				}
			}
            foreach ($AdapterFeatures in $matchFeatures)
            {
				
				$driverVersion = $device.driverversion
				# Getting the firmware version as major and minor only. (example:  "mfw 8.50.9.0 storm 8.38.2.0" is compared as 8.50 and 8.38)
				$firmwareVersions = $device.firmwareversion.split(" ") | Select-String -Pattern [0-9]*\.[0-9]* -List
				
				foreach ($firmwareVersion in $firmwareVersions)
				{
					[string]$firmwareVersionString = $firmwareVersion
					$firmwareVersionArr = $firmwareVersionString.split(".") | select -first 2
					$firmwareVersionResult = $firmwareVersionArr -join "."
					
					if (($AdapterFeatures.driverVersion -like "*$driverVersion*") -and (($AdapterFeatures.firmwareVersion -like "*$firmwareVersionResult*") -or ($AdapterFeatures.firmwareVersion -like $null) -or ($AdapterFeatures.firmwareVersion -eq "N/A") ))
					{
						$device.Supported = "Compatible"
					}
				}
            }			
        }

        $device.reference = $matches -join (";")

        $device.DeviceWarnings = $response.searchResult.warnings -join ";"

        $AllDevicesWithSupport += $device
    }
    return $AllDevicesWithSupport

}

Function _ExportToFiles ($ExportInfo)
{

    $ExportInfoTmp = @()
    foreach ($ExportInfoObj in $ExportInfo)
    {
   	    $keys = get-member -InputObject $ExportInfoObj | Where-Object {$_.MemberType -eq "NoteProperty"}
        foreach ($key in $keys.name)
	    {	
		    if ($csvLine.$key -match ",")
		    {
			    $ExportInfoObj.$key = $ExportInfoObj.$key.Replace(",","_")
		    }
        }
        $ExportInfoTmp += $ExportInfoObj
    }

    $DateString =get-date -Format yyyy-mm-dd_HH-mm-ss
    if ($outfile)
    {
	    if (-not (Test-Path $outfile)) 
	    { 
		    mkdir -p $outfile
		    rmdir $outfile
	    }
	    $ReportName = $outfile
    }
    else
    {
	    if (-not (Test-Path ".\Reports")) 
	    { 
		    mkdir "Reports"
	    }
	    $ReportName = "Reports\IO-Device-Report-" + $DateString
    }
    write-host "%%%%%%%%% EXPORTING %%%%%%%%%"
    write-host $ExportInfoTmp |ft -AutoSize

    # Export to CSV
    $ExportInfoTmp |Export-Csv -NoTypeInformation "$ReportName.csv"

    # Export to HTML
    $css  = "table{ Margin: 0px 0px 0px 4px; Border: 1px solid rgb(200, 200, 200); Font-Family: Tahoma; Font-Size: 8pt; Background-Color: rgb(252, 252, 252); }"
    $css += "tr:hover td { Background-Color: #6495ED; Color: rgb(255, 255, 255);}"
    $css += "tr:nth-child(even) { Background-Color: rgb(242, 242, 242); }"

    Set-Content -Value $css -Path "$ReportName.css"

    $CSSURI = $ReportName.split("\")[1]

    $ExportInfoTmp | ConvertTo-Html -CSSUri "$CSSURI.css" | Set-Content "$ReportName.html"

}

Function _GetServerList ($esxhost)
{
	# Gets the host object
	if ($Location)
	{
		$vmHosts = get-vmhost -name $esxhost -Location $Location
	}
	else
	{
	    $vmHosts = Get-VMHost -name $esxhost
	}
    $AllServerInfo = @()

	# Go over each host and extract needed information
    Foreach ($vmHost in $vmHosts) 
    {
        $HostManuf = $($vmHost.Manufacturer)
        $HostModel = $($vmHost.model)
        $HostCpu = $($vmHost.ProcessorType)
        $Info = "" | Select VMHost, Build, ReleaseLevel, Manufacturer, Model, BiosVersion, BiosReleaseDate, Cpu, Supported, SupportedReleases, Reference, Note
        $Info.VMHost = $vmHost.Name
        $Info.Build = $vmHost.Build
        $Info.Manufacturer = $HostManuf
        $Info.Model = $HostModel
        $Info.Cpu = $HostCpu

        $View = Get-View $vmHost | Select @{N="BIOSVersion";E={$_.Hardware.BiosInfo.BiosVersion}},@{N="BIOSDate";E={$_.Hardware.BiosInfo.releaseDate}}
        $Info.BiosReleaseDate = $view.BIOSDate
    
        #Get ESXi Host Version
		$esxcliv1 = $vmhost | get-esxcli
		$ESXVersionArr =$esxcliv1.system.version.get().version.split(".")
		$ESXVersion =  $ESXVersionArr[0] + "." + $ESXVersionArr[1]
		$ESXUpdate = $esxcliv1.system.version.get().update
		if (($ESXUpdate -ne "0") -or ($ESXUpdate -eq $null))
		{
			$Info.ReleaseLevel = $ESXVersion +  " U" + $ESXUpdate
		}
		else
		{
			$Info.ReleaseLevel = $ESXVersion
		
        }

        $Data = @()

		# Connects to VMware API Gateway to extract the compatibility
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
		$headers.Add("Accept", "*/*")
		$headers.Add("Accept-Encoding", "application/gzip, deflate, br")
		$headers.Add("x-api-key", "SJyb8QjK2L")
		$headers.Add("x-api-toolid", "180209100001")
		$headers.Add("x-request-id", "64c7522b-be59-445e-b45c-504dda7a6107")

		$model=$Info.Model 
        $releaseversion=$Info.ReleaseLevel 
        if ($releaseversion -match "ESXi ")
        {
            $releaseversion.trim("ESXi ")
        }
		$vendor=$Info.Manufacturer 
        $cpuFeatureId= $vmhost.ExtensionData.Hardware.CpuFeature[1].Eax
        if ($vendor -like "*HPE*") # ($vmhost.ExtensionData.Hardware.BiosInfo.MajorRelease) -and ($vmhost.ExtensionData.Hardware.BiosInfo.MinorRelease)
        {
			$biosVersion = $vmhost.ExtensionData.Hardware.BiosInfo.BiosVersion
			
			$biosDateString = $vmhost.ExtensionData.Hardware.BiosInfo.ReleaseDate.ToString("MM-dd-yyy")
			$biosModel = $vmhost.ExtensionData.Hardware.BiosInfo.BiosVersion
			$biosMajorMinor = $HpBiosHcl.server_bios_mapping |where {$_.bios_model -eq $biosModel} | select -ExpandProperty "bios_version" | where {$_ -like "*$biosDateString*"}
			$biosMajorMinor = $biosMajorMinor.split("_")[0]
            $bios = "$($vmhost.ExtensionData.Hardware.BiosInfo.BiosVersion)_$($biosMajorMinor)"
        }
        else
        {
            $bios = "$($vmhost.ExtensionData.Hardware.BiosInfo.BiosVersion)"
        }
		$Info.BiosVersion = $bios
		$response = Invoke-RestMethod "https://apigw.vmware.com/m4/compatibility/v1/compatible/servers/search?model=$model&releaseversion=$releaseversion&vendor=$vendor&bios=$bios&cpuFeatureId=$cpuFeatureId" -Method 'GET' -Headers $headers
		$response | ConvertTo-Json		

        $Info.Note = $response.searchResult.warnings -join ";" 
		$Info.SupportedReleases = ""
        if ($response.potentialMatches.length -gt 0)
        {
            $potentialMatches = $response.potentialMatches
        }
        else
        {
            $potentialMatches = $response.matches
        }

        $Info.Supported = "Not Compatible"
        $references = new-object system.collections.arraylist
        foreach ($potentialMatch in $potentialMatches)
        {
            $references.Add($potentialMatch.vcgLink)
            foreach ($BiosFeatures in $potentialMatch.features)
            {
                if ($BiosFeatures.bios -like "*$bios*")
                {
                    $Info.Supported = "Compatible"
                }
            }
        }
        $info.reference = $references -join ";"
        

        $AllServerInfo += $Info
    }
    write-host $AllServerInfo

    return $AllServerInfo
}

Function _CheckServerOnline ($ServerList)
{
    ## Reads each line and verify if BIOS version + ESXi Version is supported according to the server reference URL
    #T.B.D
    return $ServerList
}

Function _MergeLists ($ServerListWithSupport, $DeviceListWithSupport)
{
    $FinalList = @()
    foreach ($device in $DeviceListWithSupport) 
    {
        $Line = "" | Select Parent, VMHost, ServerBuild, ServerReleaseLevel, ServerManufacturer, ServerModel, BiosVersion, BiosReleaseDate, ServerCpu, ServerSupported, ServerSupportedReleases, ServerReference, ServerNote, VMHostVersion,VMHostBuild, Device, DeviceName, VendorName, DeviceClass, vid, did, svid, ssid, Driver, DriverVersion, FirmwareVersion, VibVersion, Supported,DeviceWarnings, Reference
        foreach ($server in $ServerListWithSupport)
        {
            if ($Device.VMHost -match '^'+$server.VMHost+'$')
            {
                $Line.Parent = $device.parent
                $Line.VMHost = $device.VMHost
                $Line.ServerBuild = $server.Build
                $Line.ServerReleaseLevel = $server.ReleaseLevel
                $Line.ServerManufacturer = $server.Manufacturer
                $Line.ServerModel = $server.Model
				$Line.BiosVersion = $server.BiosVersion
				$Line.BiosReleaseDate = $server.BiosReleaseDate
                $Line.ServerCpu = $server.Cpu
                $Line.ServerSupported = $server.Supported
                $Line.ServerSupportedReleases = $server.SupportedReleases
                $Line.ServerReference = $server.Reference
                $Line.ServerNote = $server.Note
                $Line.VMHostVersion = $Device.VMHostVersion
                $Line.VMHostBuild = $Device.VMHostBuild
                $Line.Device = $Device.Device
                $Line.DeviceName = $Device.DeviceName
                $Line.VendorName = $Device.VendorName
                $Line.DeviceClass = $Device.DeviceClass
                $Line.vid = $Device.vid
                $Line.did = $Device.did
				$Line.svid = $Device.svid
                $Line.ssid = $Device.ssid
                $Line.Driver = $Device.Driver
                $Line.DriverVersion = $Device.DriverVersion
                $Line.FirmwareVersion = $Device.FirmwareVersion
                $Line.VibVersion = $Device.VibVersion
                $Line.Supported = $Device.Supported
                $Line.DeviceWarnings = $Device.DeviceWarnings
                $Line.Reference = $Device.Reference
                $lineFound = $true
                break
            }
        }
        $FinalList += $Line
    }
    return $FinalList
}


function _ExecuteHardwareReport ($esxHostName)
{
    ## Run all functions
	write-host "##### GETTING SERVER LIST #####"
    $ServerList = _GetServerList $esxHostName
	write-host "##### GETTING SERVER ONLINE SUPPORT #####"
    $ServerListWithSupport = _CheckServerOnline $ServerList

	write-host "##### GETTING DEVICE LIST #####"
    $DeviceList = _GetDeviceList $esxHostName
	write-host "##### GETTING DEVICE ONLINE SUPPORT #####"
    $DeviceListWithSupport = _CheckDeviceOnline $DeviceList $OfflineHCL

    $FinalList = _MergeLists $ServerListWithSupport $DeviceListWithSupport
    return $FinalList
}

function _SendMail($smtpServer, $smtpPort, $smtpCredentials, $smtpSSL, $emailTo, $emailSubject, $emailBody)
{
	write-host "Sending to address $emailTo with body:  `r`n <br /> $emailBody"
	Send-MailMessage -SmtpServer $smtpServer -BodyAsHtml -Port $smtpPort -UseSsl:$smtpSSL -credential $smtpCredentials -from $fromAddr -to $emailTo -Subject $emailSubject -Body  $emailBody -Attachments .\logs\esxHardwareReport_$logdate.csv, .\logs\esxConfigurationReport_$logdate.csv
}


function _ConfCompareToCsv ($esxConfigurationReport, $esxHardwareReport)
{
	foreach ($esxConfiguration in $esxConfigurationReport)
	{
        Write-Host "Comparing $esxConfiguration to local CSV"
        $isRecordFound = $false

        # Searching for cluster
        $ESXConfigurationCsv = $ClusterConfigurationCsv | Where-Object {$_.Cluster -eq $esxConfiguration.cluster}
        if ($ESXConfigurationCsv -eq $null)
        {
            $ESXConfigurationCsv = $ClusterConfigurationCsv | Where-Object {$_.Cluster -eq "default"}
        }

        # Check conf             
        if (($esxConfiguration.isHAActive -ne $ESXConfigurationCsv.isHAActive) -or ($esxConfiguration.HAFailoverLevel -ne $ESXConfigurationCsv.HAFailoverLevel))
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi + " HA mismatch"
        }
        
        if (($esxConfiguration.DRSMode -ne $ESXConfigurationCsv.DRSMode) -or ($esxConfiguration.isDRSActive -ne $ESXConfigurationCsv.isDRSActive))
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi  + " DRS mismatch"
        }
        
        if ($esxConfiguration.ClusterEVCMode -ne $esxConfiguration.ClusterEVCMode)
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi + " EVC mismatch"
        }
        
        if ($esxConfiguration.ScratchConfig -notlike   "/vmfs/volumes/*")
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi + " Scratch Partition mismatch"
        }
        
        if ($esxConfiguration.SyslogConfig -ne $ESXConfigurationCsv.SyslogConfig )
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi +  " Syslog mismatch"
        }
        
        if (($esxConfiguration.isNTPConfigured  -ne $ESXConfigurationCsv.isNTPConfigured ) -or ($esxConfiguration.isNTPRunning  -ne $ESXConfigurationCsv.isNTPRunning) )
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi + " NTP mismatch"
        }
		if ($esxConfiguration.vmk0_Portgroup.toLower().indexOf("esxi management 180") -eq -1 ) 
        {
            $Gaps =  $Gaps + " `r`n <br /> Host " + $esxConfiguration.ESXi + " Portgroup mismatch"
        }
        
	}

	foreach ($esxHardware in $esxHardwareReport)
	{
		if ($esxHardware.Supported -ne "Compatible")
		{
			$Gaps =  $Gaps + "`r`n <br /> Host " +$esxHardware.VMHost + " device " + $esxHardware.Device + " driver-firmware mismatch"
		}
		if ($esxHardware.ServerSupported -ne "Compatible")
		{
            if ($gaps -notmatch "Host " +$esxHardware.VMHost + " Host version mismatch")
            {
			    $Gaps =  $Gaps + "`r`n <br /> Host " +$esxHardware.VMHost + " Host version mismatch"
            }
		}
	}	
    if ($Gaps)
    {
        $Gaps = "ESXi hosts differences found:" + $Gaps
    }

    return $Gaps
}
function _Main
{
	########### MAIN ############

	# Get VC and ESX credentials from file
	$credentials = Import-Clixml .\esxReportDataCRD.xml
	$ClusterConfigurationCsv = Import-Csv .\ClusterConfiguration.csv 
	
	$vCenterServer = $credentials.VcName
	$smtpServer = $credentials.SmtpServer
	$fromAddr = $credentials.fromAddr
	$toAddress = $credentials.toAddr 
	$smtpPort = $credentials.smtpPort 
	$smtpCredentials = $credentials.smtpCredentials 
	$smtpSSL = $credentials.smtpSSL 


	$vcUsername =  $credentials.VcCredentials.UserName  
	$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credentials.VcCredentials.Password)
	$global:vcPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

	$HpBiosHcl = Get-Content -Raw -Path ".\resources_hpe-server-bios-mapping.json" |  ConvertFrom-Json
	
	
	
	$esxConfigurationReport = New-Object System.Collections.ArrayList
	$esxHardwareReport = New-Object System.Collections.ArrayList

	_ConnectVC $vCenterServer $vcUsername $vcPassword

	# Get all ESX that already executed the report on and build new array (only importing from XML causes array to be fixed size..)
	try
	{
		$xml = New-Object System.Collections.ArrayList
		$xmltmparr = Import-Clixml -Path "esxReportData.xml"
		for($i = 0 ; $i -lt $xmltmparr.length; $i++)
		{
			$xml.Add($xmltmparr[$i]) > $null
		}
	}
	catch
	{
		$xml = New-Object System.Collections.ArrayList
	}

	# Get hosts from vCenter and checks if the host is new according to the local XML file
	$esxhosts = get-vmhost | where {$_.Manufacturer -NE "VMware"} | where {$_.state -eq "Connected" -or $_.state -eq "Maintenance"}

	$runtime = get-date
	$runtime = $runtime.ToUniversalTime()
	$hostsToExecute = @()
	foreach ($esxhost in $esxhosts)
	{
		$ServerIdXml = $null
		$ServerIdXml = $xml | where {$_.ServerId -eq $esxhost.id}

		## Get ESXi install date and current date for comparison 
		$Date = get-date 
		$esxcli = $esxhost | Get-EsxCli -v2
		$epoch = $esxcli.system.uuid.get.Invoke().Split('-')[0]
		$EsxInstalledDate = [timezone]::CurrentTimeZone.ToUniversalTime(([datetime]'1/1/1970').AddSeconds([int]"0x$($epoch)"))

		$timespan = $Date - $EsxInstalledDate
		
		if ((!$ServerIdXml) -and ($timespan.totalminutes -gt 60))
		{
			$hostsToExecute += $esxhost
		}
	}
	
	
	# Execute report on new ESXi hosts
	$arrLength = $hostsToExecute.length
	write-host "############ Generating report on $arrLength hosts ############"
	$ConfigurationReport = @()
	$HardwareReport = @()
	$i=1
	foreach ($hostToExecute in $hostsToExecute)
	{
		write-host "Getting esxcli v2 on host $esxhost"	
		$esxcli = $hostToExecute | Get-EsxCli -v2
		$epoch = $esxcli.system.uuid.get.Invoke().Split('-')[0]
		$InstalledDate = [timezone]::CurrentTimeZone.ToUniversalTime(([datetime]'1/1/1970').AddSeconds([int]"0x$($epoch)"))
		$Date = get-date 

		$ESXCSV = New-Object PSObject
		$ESXCSV | add-member Noteproperty InstallationDate $InstallationDate
		$ESXCSV | add-member Noteproperty LastRuntime      $LastRuntime
		$ESXCSV | add-member Noteproperty ServerName       $ServerName
		$ESXCSV | add-member Noteproperty ServerId       $ServerId

		$esxhostname = $hostToExecute.name
		write-host "############ GETTING CONFIGURATION REPORT FROM HOST $esxhostname  ($i/$arrLength)############"
		$esxConfigurationReport +=  _ExecuteConfigurationReport ($hostToExecute.name)
		write-host "############ GETTING HARDWARE REPORT FROM HOST $esxhostname  ($i/$arrLength)############"		
		$esxHardwareReport += _ExecuteHardwareReport ($hostToExecute.name)
		$ConfigurationReport += $esxConfigurationReport
		$HardwareReport += $esxHardwareReport

		$ESXCSV.InstallationDate = $InstalledDate
		$ESXCSV.LastRuntime = $Date
		$ESXCSV.ServerName = $hostToExecute.name
		$ESXCSV.ServerId = $hostToExecute.Id
		$xml.Add($ESXCSV)
		$i++
	}

	Disconnect-VIServer * -Force -Confirm:$false 

	Write-Host "############# Script Output Configuration Report #############"

	$esxConfigurationReport | fl


	Write-Host "############# Script Output Hardware Report #############"

	$esxHardwareReport | fl


	Write-Host "############# Saving Configuration Report #############"
	try
	{
		$xmlConf = New-Object System.Collections.ArrayList
		$xmlConftmparr = Import-Clixml -Path "esxConfReportData.xml"
		for($i = 0 ; $i -lt $xmlConftmparr.length; $i++)
		{
			$xmlConf.Add($xmlConftmparr[$i]) > $null
		}
	}
	catch
	{
		$xmlConf = New-Object System.Collections.ArrayList
	}


	for ($i=0 ; $i -lt $esxConfigurationReport.Length ; $i++)
	{
		$xmlConf.Add($esxConfigurationReport[$i]) > $null
	}
	$xmlConf | Export-Clixml "esxConfReportData.xml"


	Write-Host "############# Saving Hardware Report #############"
	try
	{
		$xmlHardware = New-Object System.Collections.ArrayList
		$xmlHardwaretmparr = Import-Clixml -Path "esxHardwareReportData.xml"
		for($i = 0 ; $i -lt $xmlHardwaretmparr.length; $i++)
		{
			$xmlHardware.Add($xmlHardwaretmparr[$i]) > $null
		}
	}
	catch
	{
		$xmlHardware = New-Object System.Collections.ArrayList
	}


	for ($i=0 ; $i -lt $esxHardwareReport.Length ; $i++)
	{
		$xmlHardware.Add($esxHardwareReport[$i]) > $null
	}
	$xmlHardware | Export-Clixml "esxHardwareReportData.xml"

	Write-Host "############# Saving Metadata for next runs #############"
	$xml | Export-Clixml "esxReportData.xml"

	Write-Host "############# Preparing email with the new ESXi host details #############"

	## Generating CSV with new ESXi Objs
	$esxHardwareReport	  | Export-Csv -NoTypeInformation ".\logs\esxHardwareReport_$logdate.csv"
	$esxConfigurationReport | Export-Csv  -NoTypeInformation ".\logs\esxConfigurationReport_$logdate.csv"

	if ($esxHardwareReport.Length -gt 0)
	{
    
	    Write-Host "Comparing list to its defaults"
	    $esxConfigurationReportDifferences = _ConfCompareToCsv $esxConfigurationReport $esxHardwareReport
        if ($esxConfigurationReportDifferences)
        {
			$emailSubject = "ESXi hosts configuration differences"
		    $emailBody = $esxConfigurationReportDifferences
        }
		else
		{
			$emailSubject = "New ESXi hosts joined the vCenter"
			$emailBody = "New ESXi hosts joined the vCenter"
		}
		_SendMail $smtpServer $smtpPort $smtpCredentials $smtpSSL $toAddress $emailSubject $emailBody
	}
}


$logdate = get-date -Format 'hh-mm_dd-MM-yyyy'
Start-Transcript -Path .\logs\esx_report_$logdate.log
	
_Main
Stop-Transcript