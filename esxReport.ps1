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


function _GetClustersStatus ($vcServer, $Username, $Password, $Location )
{
    $AllInfo = @()

   # _ConnectVC $vcServer $Username $Password

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
            #write-host "adding row " + $ESXhost.name 
            $ScratchLocation = ""
            $ScratchLocation = $advSettingsScratch | Where-Object {$_.entity.id -eq $ESXhost.id} |select -ExpandProperty value 
            $SyslogHost = ""
            $SyslogHost = $advSettingsSyslog | Where-Object {$_.entity.id -eq $ESXhost.id} |select -ExpandProperty value 

           # $ESXHostVmknics = _GetEsxVmnicSpecObj $ESXhost
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

function _GetHCL ($OfflineHCL)
{
    if (!$OfflineHCL)
    {
	    $hcl = Invoke-WebRequest -Uri http://www.virten.net/repo/vmware-iohcl.json -ErrorAction SilentlyContinue| ConvertFrom-Json
    }
    else
    {	
	    if (test-path -path $OfflineHCL)
	    {
		    $hcl = get-content $OfflineHCL | ConvertFrom-Json
	    }
	    else
	    {
		    throw "OfflineHCL was not found!"
	    }
    }
    return $hcl
}

Function _ConnectVIServer ($vCenterHost)
{
    if (!$vCenterCredentials)
    {
        $vCenterCredentials = get-credential -Message "vCenter Administrator Access Credentials"
    }
    $vCenterUsername = $vCenterCredentials.UserName
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($vCenterCredentials.Password)
    $vCenterPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    if (!$ESXCredentials)
    {
        $ESXCredentials = get-credential -Message "ESX root Username and Password" -UserName root
    }
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ESXCredentials.Password)
    $global:UnsecurePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)


    Import-Module "VMware.PowerCLI" -ErrorAction SilentlyContinue | out-null
    Get-Module -ListAvailable | where {$_.Name -like "VMware*"} | Import-Module -ErrorAction SilentlyContinue | out-null
    Connect-VIServer -Server $vCenterHost -User $vCenterUsername -Password $vCenterPassword -force -OutVariable $null | out-null

    if ($PSVersionTable.PSEdition -contains "Core")
    {
	    $global:isLinux = $true
    }
    else
    {
	    $global:isLinux = $false
    }

    #For Windows Version Only
    if ($isLinux -eq $false)
    {
        $host.ui.RawUI.WindowTitle = $global:defaultviserver.name
    }
}	

function _EnableSSH
{
    ##Check TSM-SSH Service status on hosts and enable if needed
    $HostsSSHServices = Get-VMHost | Get-VMHostService | Where { $_.Key -eq "TSM-SSH" } 

    foreach ($HostSSHService in $HostsSSHServices)
    {
	    if ($HostSSHService.Running -eq $false)
	    {
		    $HostSSHService | Start-VMHostService
	    }
    }
    return $HostsSSHServices
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

	    $DeviceFound = $false
	    $Info = "" | Select Parent, VMHost, VMHostVersion,VMHostBuild, Device, DeviceName, VendorName, DeviceClass, vid, did, svid, ssid, Driver, DriverVersion, FirmwareVersion, VibVersion, Supported,RecommendedDriverVersion, RecommendedFirmwareVersion, RecommendedESXRelease, Reference
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
		#write-host "Comparing if current release $ESXRelease is at the compatibility table.. "
		
		if (($SimulateESXiVersion -eq $null) -or ($SimulateESXiVersion -eq "") -or ($SimulateESXiVersion -eq " "))
		{
			$Info.VMHostVersion = $ESXRelease
		}
		else
		{
			$Info.VMHostVersion = $SimulateESXiVersion
		}

	    # Search HCL entry with PCI IDs VID, DID, SVID and SSID
	    $EntriesArray = @()
	    Foreach ($entry in $hcl.data.ioDevices) 
	    {
		    If (($Info.vid -eq $entry.vid) -and ($Info.did -eq $entry.did) -and ($Info.svid -eq $entry.svid) -and ($Info.ssid -eq $entry.ssid)) 
		    {
			    $EntriesArray += $entry.url
			    #$Info.Reference = $entry.url
			    $DeviceFound = $true
		    } 
	    }
	
	    $Info.Reference = $EntriesArray  -join ";"
	
	    if($DeviceFound)
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
					    $vibname = $vmhbaId.Driver.replace("_","-")
					    $driverVib = $esxcli.software.vib.get.Invoke(@{vibname = $vibname})
				    }
			    }
			    $Info.VibVersion = $driverVib.Version
			    $Info.DriverVersion = $vmhbaId.DriverInfo.Version
			    $DeviceName = $vmhbaId.Device
			
			    #write-host "Got Device Name : $DeviceName"
			    $ESXHostName=$device.VMHost.name
                
			
			    $keyval = $null
			    $InstanceName = $null
			    if ($isLinux)
			    {
				    $keyval = echo y | sshpass -p $UnsecurePassword ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$ESXHostIP '/usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -l -a '
			    }
			    else
			    {
                    $ErrorActionPreference = 'SilentlyContinue'
				    $keyval = echo y | .\plink -pw $UnsecurePassword root@$ESXHostName '/usr/lib/vmware/vmkmgmt_keyval/vmkmgmt_keyval -l -a '
                    $ErrorActionPreference = 'Continue'
			    } 
			
			    try
			    {
				    $InstanceName = $keyval | findstr "Instance:" | findstr $DeviceName # 2>&1
	
				    if ($InstanceName -eq $null)
				    {
					    Throw "could not get instance name!"
				    }
			    }
			    catch
			    {
				    try
				    {
					    $DeviceName = $DeviceName.replace("_","-")
					    $InstanceName = $keyval | findstr "Instance:" | findstr $DeviceName # 2>&1
					    if ($InstanceName -eq $null)
					    {
						    Throw "could not get instance name!"
					    }
				    }
				    catch
				    {
					    write-host "COULD NOT FIND INSTANCE NAME FOR DEVICE $DeviceName ON HOST " + $device.VMHost.Name
				    }
			    }
				
				if ($InstanceName)
				{
					#write-host = $InstanceName
					$InstanceName = $InstanceName.split(":")[1].split(" ")[2]
					#Write-Host "Got instance name $InstanceName"
					# $keyval =  $keyval -replace '\n',"####"
					$keyval = $keyval | out-string
					$keyvalarr = $keyval -split "Key Value Instance:"
					foreach ($keyvalinstance in $keyvalarr)
					{
						$dev = $keyvalinstance -split "\n" | select -First 1
						$dev = $dev -replace '\n','' 
						$dev = $dev -replace '\s','' 
						$InstanceName = $InstanceName -replace '\n',''
						$InstanceName = $InstanceName -replace '\s',''
						if ($dev -contains $InstanceName)
						{
							$FirmwareString = ""
							$DriverString = ""
							if ($dev -match "Emulex")
							{
								$FirmwareString = $keyvalinstance -split "\n" | findstr "FW Version:"
								$FirmwareString = $FirmwareString |findstr "FW"
								$FirmwareString = $FirmwareString.Split(":")[1]

								$DriverString =  $keyvalinstance -split "\n" | findstr "ROM Version:"
								$DriverString = $DriverString | findstr "ROM"  
								$DriverString = $DriverString.Split(":")[1]
							}
							else
							{
								#Write-Host "found keyval for instance $InstanceName"
								$FirmwareDriverString = $keyvalinstance -split "\n" | findstr "Firmware"
								$devicenamefromkeyval = $keyvalinstance -split "\n" | Select-String "Firmware" -Context 1
								$Info.DeviceName = $devicenamefromkeyval -split "\n" | select -first 1

								$FirmwareString = $FirmwareDriverString.split(",")[0]  -split "FC " | select -Last 1
								$FirmwareString = $FirmwareString.split(" ")[2]
								$DriverString = $FirmwareDriverString.split(",")[1].split(" ")[3] 
							}
							break
						}

					}
					$Info.FirmwareVersion = $FirmwareString	  
					$Info.DriverVersion = $DriverString
				}
				else
				{
				    $Info.FirmwareVersion = "N/A"
					$Info.DriverVersion = "N/A"
				}
			    #Write-Host "Got Firmware $FirmwareString and Driver: $DriverString"
			}
		
		    #Handle Local Storage Controllers - Get Installed Drivers and Firmware information -T.B.D
		    elseif ($device.DeviceClass -eq "MassStorageController")
		    {
			    #write-host "MassStorageController" #T.B.D
		    }  
		    $AllInfo += $Info
	    }
    }
    return $AllInfo
}

Function _CheckDeviceOnline ($DeviceList, $OfflineHCL)
{
	$AllInfoWithSupport = @()	
	foreach ($Info in $DeviceList)	
    {
		# Check if Firmware and Drivers are supported according to VMWare Official I/O Devices Compatibility Matrix : https://www.vmware.com/resources/compatibility/search.php?deviceCategory=io
		$Info.Supported = $false
		foreach ($EntryReference in $EntriesArray)
		{
			$ProductCompatCsvArr = @()
			if (!$OfflineHCL)
			{
				$ProductIdWebUrl = $EntryReference
				$ProductIdWebContent = Invoke-WebRequest "$ProductIdWebUrl"
				$ProductCompatCsv = $ProductIdWebContent.content -split "Release,Device Driver\(s\),Firmware Version,Additional Firmware Version,Driver Type,Driver Model,Footnotes,Feature Category,Features" | select -last 1
				$ProductCompatCsv = $ProductCompatCsv  -split('" /></form') | select -first 1
				$ProductCompatCsvArr = $ProductCompatCsv.split("`n")
			}

			#$device.VMhost.ExtensionData.Config.Product.version #6.5.0 (even if its update 1)
			#$device.VMhost.ExtensionData.Config.Product.apiVersion # 6.5
			
		
			$InfoSupportedDriverVersion = ""
			$InfoSupportedFirmwareVersion = ""
			$InfoSupportedESXRelease= ""
			$InfoSuggestedDriver = ""
			$InfoSuggestedFirmware = ""
			Foreach($Line in $ProductCompatCsvArr )
			{
				$SupportedESXRelease = $line.split(",")[0]
				#write-host "Supported Release : $SupportedESXRelease "
				if ($InfoSupportedESXRelease -NotLike "*$SupportedESXRelease;*")
				{
					$InfoSupportedESXRelease += $SupportedESXRelease + ";"
				}
				if ($SupportedESXRelease -like "*$ESXRelease*")
				{
					#write-host "found ESX release! checking drivers and firmware.."
					$SupportedDriverVersion = $line.split(",")[1]
					$SupportedFirmwareVersion = $line.split(",")[2].replace("x","")
					$InfoSupportedDriverVersion += $SupportedDriverVersion + ";"
					$InfoSupportedFirmwareVersion += $SupportedFirmwareVersion + ";"
					#write-host "Checking if firmware supported : $SupportedFirmwareVersion 		to current : " $Info.FirmwareVersion
					#write-host "Checking if driver   supported : $SupportedDriverVersion 		to current : " $Info.DriverVersion
					
					$InfoDriverVerion = $Info.DriverVersion
					$infoFirmwareVersion = $info.FirmwareVersion
					if ($SupportedFirmwareVersion -ne "N/A")
					{
						$SupportedFirmwareVersionArr=$SupportedFirmwareVersion.split("/") 
					}
					$InfoDriverVerion = $InfoDriverVerion  -replace '(^\s+)','' -replace '(\s+$)','' -replace '\s+','' -replace '\s',''  #Removes spaces for comparison 
					
					if ($InfoSuggestedFirmware -eq "")
					{
						foreach ($obj in $SupportedFirmwareVersionArr)
						{
							if ($obj -ne "N/A")
							{
								$InfoSuggestedFirmware = $obj
								break;
							}
						}
					}
					foreach ($tempSupportedFirmwareVersion in $SupportedFirmwareVersionArr)
					{
						$isGreaterVer = $False 
						for ($i=0; $i -lt $InfoSuggestedFirmware.split(".").length ; $i++ )
						{
							try 
							{
								if (([int]$tempSupportedFirmwareVersion.split(".")[$i] -gt [int]$InfoSuggestedFirmware.split(".")[$i]) -or ([int]$tempSupportedFirmwareVersion.split(".")[$i] -eq [int]$InfoSuggestedFirmware.split(".")[$i]))
								{
									$isGreaterVer = $True
								}
								else
								{
									$isGreaterVer = $False
									break
								}
							}
							Catch
							{
								$isGreaterVer = $False
								break
							}
						}
						
						if ($isGreaterVer -eq $True)
						{
							$InfoSuggestedFirmware = $tempSupportedFirmwareVersion
							$InfoSuggestedDriver = $SupportedDriverVersion
						}
						#write-host "Comparing firmware version " + $infoFirmwareVersion + " to supported firmware version " + $tempSupportedFirmwareVersion
						if (($infoFirmwareVersion -like "*$tempSupportedFirmwareVersion*") -or ($tempSupportedFirmwareVersion -like "*$infoFirmwareVersion*"))
						{	
							#write-host "Firmware is compatible, checking driver.."
							#write-host "Comparing driver version $InfoDriverVerion to supported driver version =="$SupportedDriverVersion"=="
							if (($InfoDriverVerion -like "*$SupportedDriverVersion*") -or ($SupportedDriverVersion -like "*$InfoDriverVerion*")) 
							{
								#write-host "FOUND SUPPORTED VERSION! DRIVER $SupportedDriverVersion $tempSupportedFirmwareVersion"
								$Info.Supported = $true
								break
							}
						}
					}
					if ($Info.Supported -eq $true)
					{
						break
					}
				}
			}
			if ($Info.Supported -eq $true)
			{
				break
			}
		}
		if ($info.Supported -eq $false)
		{
			$Info.RecommendedDriverVersion = $InfoSuggestedDriver 
			$Info.RecommendedFirmwareVersion = $InfoSuggestedFirmware
			$Info.RecommendedESXRelease = $ESXRelease
		}
        $AllInfoWithSupport += $Info
    }
    return $AllInfoWithSupport
}

Function _RevertSSH ($HostsSSHServices)
{
    ##Stopping SSH Services
    foreach ($HostSSHService in $HostsSSHServices)
    {
	    if ($HostSSHService.Running -eq $false)
	    {
		    $HostSSHService | Stop-VMHostService
	    }
    }
}

Function _ExportToFiles ($ExportInfo)
{
    # Display all Infos
    #$AllInfo

    # Display ESXi, DeviceName and supported state
    #$AllInfo |select VMHost,Device,DeviceName,Supported,Referece |ft -AutoSize

    # Display device, driver and firmware information
    $ExportInfoTmp = @()
    foreach ($ExportInfoObj in $ExportInfo)
    {
   	    $keys = get-member -InputObject $ExportInfoObj | Where-Object {$_.MemberType -eq "NoteProperty"}
        foreach ($key in $keys.name)
	    {	
		    if ($csvLine.$key -match ",")
		    {
			    #write-host "Replacing Info.$key , to _"
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

    if (!$isLinux)
    {
	    invoke-item "$ReportName.html" -confirm:$False
    }
}

Function _GetServerList ($esxhost)
{
    <#
      .NOTES
      Author: Florian Grehl - www.virten.net
      Reference: http://www.virten.net/2016/05/vmware-hcl-in-json-format/
  
      .DESCRIPTION
      Verifies server hardware against VMware HCL.
      This script uses a JSON based VMware HCL maintained by www.virten.net.
      Works well with HP and Dell. Works acceptable with IBM and Cisco.
  
      Many vendors do not use the same model string in VMware HCL and Server BIOS Information.
      Server may then falsely be reported as unsupported.

      .EXAMPLE
      Check-HCL 
    #>
	if (!$ServerEsxiReleases)
	{	
		if (!$OfflineServerEsxiReleases)
		{
			$global:ServerEsxiReleases = Invoke-WebRequest -Uri http://www.virten.net/repo/esxiReleases.json | ConvertFrom-Json
		}
		else
		{
			$global:ServerEsxiReleases = Get-Content $OfflineServerEsxiReleases | convertfrom-json
		}
	}
    if (!$OfflineServerHclJson)
    {
        $ServerHclJson = Invoke-WebRequest -Uri http://www.virten.net/repo/vmware-hcl.json
        [void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")        
        $jsonserializer= New-Object -TypeName System.Web.Script.Serialization.JavaScriptSerializer 
        $jsonserializer.MaxJsonLength = [int]::MaxValue
        $hcl = $jsonserializer.DeserializeObject($ServerHclJson)
    }
    else
    {
        $ServerHclJson = Get-Content $OfflineServerHclJson | convertfrom-json
        $hcl = $ServerHclJson 
    }

	if ($Location)
	{
		$vmHosts = get-vmhost -name $esxhost -Location $Location
	}
	else
	{
	    $vmHosts = Get-VMHost -name $esxhost
	}
    $AllServerInfo = @()

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
        $Info.BiosVersion = $view.BIOSVersion
        $Info.BiosReleaseDate = $view.BIOSDate
    
        $release = $ServerEsxiReleases.data.esxiReleases |? build -eq $vmHost.Build
        if($release) 
        {
            $updateRelease = $($release.updateRelease)
            $Info.ReleaseLevel = $updateRelease
        } 
        else
        {
            $updateRelease = $false
            $Info.Note = "ESXi Build $($vmHost.Build) not found in database." 
        } 
        $Data = @()
        Foreach ($server in $hcl.data.server) 
        {
            $ModelFound = $false
            if ($HostModel.StartsWith("UCS") -and $ModelMatch.Contains("UCS"))
            {
                $HostLen=$HostModel.Length
                $UCS_MODEL=$HostModel.Substring(5,4)
                if ($HostLen -eq 12) 
                {
                    $UCS_GEN=$HostModel.Substring(10,2)
                }
                if ($HostLen -eq 14) 
                {
                    $UCS_GEN=$HostModel.Substring(10,3)
                }
                $isUCSMODEL=$ModelMatch.Contains($UCS_MODEL)
                if ($isUCSMODEL -eq "True") 
                {
                    $isUCSGEN=$ModelMatch.Contains($UCS_GEN)
                    if ($isUCSGEN -eq "True") 
                    {
                        $ModelFound = $true
                    }
                }
            }
            $ModelMatch = $server.model 
            $ModelMatch = $ModelMatch -replace "IBM ",""
            $ModelMatch = ("*"+$ModelMatch+"*")
            if ($HostManuf -eq "HP")
            {
                If ($HostModel -like $ModelMatch -and $server.manufacturer -eq $HostManuf) 
                { 
                    $ModelFound = $true
                }
            } 
            else 
            {
                If ($HostModel -like $ModelMatch) 
                { 
                    $ModelFound = $true
                }
            }
            If ($ModelFound) 
            { 
                If($server.cpuSeries -like "Intel Xeon*")
                {
                    $cpuSeriesMatch = $server.cpuSeries -replace "Intel Xeon ","" -replace " Series","" -replace "00","??" -replace "xx","??" -replace "-v"," v"
                    $HostCpuMatch = $HostCpu -replace " 0 @"," @" -replace "- ","-" -replace "  "," "
                    $cpuSeriesMatch = ("*"+$cpuSeriesMatch+" @*")
                    if ($HostCpuMatch -notlike $cpuSeriesMatch)
                    {
                        continue
                    }
                }
                $helper = New-Object PSObject
                Add-Member -InputObject $helper -MemberType NoteProperty -Name Model $server.model
                Add-Member -InputObject $helper -MemberType NoteProperty -Name CPU $server.cpuSeries
                Add-Member -InputObject $helper -MemberType NoteProperty -Name Releases $server.releases
                Add-Member -InputObject $helper -MemberType NoteProperty -Name URL $server.url
                $Data += $helper
            }
        }
    
        If ($Data.Count -eq 1)
        {
            Foreach ($obj in $Data) 
            {
                $release = $ServerEsxiReleases.data.esxiReleases |? build -eq $vmHost.Build
                if ($updateRelease -and ($obj.Releases -contains $updateRelease))
                {
                    $Info.Supported = $true
                } 
                else 
                {
                    $Info.Supported = $false
                }
                $Info.SupportedReleases = $obj.Releases
                $Info.Reference = $($obj.url)
            }
        } 
        elseif ($Data.Count -gt 1)
        {
			$references = ""
			Foreach ($obj in $Data) 
            {
				$references = $references + $($obj.url)
				$Info.Note = "More than 2 HCL Entries found." 
			}
			$Info.Reference = $($obj.url)
        } 
        else 
        {
            $Info.supported = $false
            $Info.Note = "No HCL Entries found." 
        }
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
        $Line = "" | Select Parent, VMHost, ServerBuild, ServerReleaseLevel, ServerManufacturer, ServerModel, BiosVersion, BiosReleaseDate, ServerCpu, ServerSupported, ServerSupportedReleases, ServerReference, ServerNote, VMHostVersion,VMHostBuild, Device, DeviceName, VendorName, DeviceClass, vid, did, svid, ssid, Driver, DriverVersion, FirmwareVersion, VibVersion, Supported,RecommendedDriverVersion, RecommendedFirmwareVersion, RecommendedESXRelease, Reference
        #$Info = "" | Select Parent, VMHost, VMHostVersion,VMHostBuild, Device, DeviceName, VendorName, DeviceClass, vid, did, svid, ssid, Driver, DriverVersion, 
        #FirmwareVersion, VibVersion, Supported,RecommendedDriverVersion, RecommendedFirmwareVersion, RecommendedESXRelease, Reference
        #$Info = "" | Select VMHost, ServerBuild, ServerReleaseLevel, ServerManufacturer, ServerModel, ServerCpu, ServerSupported, ServerSupportedReleases, ServerReference, ServerNote
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
                $Line.ssid = $Device.ssid
                $Line.Driver = $Device.Driver
                $Line.DriverVersion = $Device.DriverVersion
                $Line.FirmwareVersion = $Device.FirmwareVersion
                $Line.VibVersion = $Device.VibVersion
                $Line.Supported = $Device.Supported
                $Line.RecommendedDriverVersion = $Device.RecommendedDriverVersion
                $Line.RecommendedFirmwareVersion = $Device.RecommendedFirmwareVersion
                $Line.RecommendedESXRelease = $Device.RecommendedESXRelease
                $Line.Reference = $Device.Reference
                $lineFound = $true
                break
            }
        }
        $FinalList += $Line
    }
    return $FinalList
}

function _ExecuteConfigurationReport ($esxHostName)
{
   # _ConnectVC $esxHostName $esxUsername $esxPassword
    $Report = _GetClustersStatus $esxHostName $esxUsername $esxPassword 
   # Disconnect-VIServer * -Force -Confirm:$false 
    return $Report
}
function _ExecuteHardwareReport ($esxHostName)
{
    ## Run all functions
    #_ConnectVC $esxHostName $esxUsername $esxPassword
    $hcl = _GetHCL 
    #$HostsSSHServices = _EnableSSH

    $ServerList = _GetServerList $esxHostName
    $ServerListWithSupport = _CheckServerOnline $ServerList

    $DeviceList = _GetDeviceList $esxHostName
    $DeviceListWithSupport = _CheckDeviceOnline $DeviceList $OfflineHCL


    $FinalList = _MergeLists $ServerListWithSupport $DeviceListWithSupport
    #_RevertSSH $HostsSSHServices
    #Disconnect-VIServer * -Force -Confirm:$false 
    return $FinalList
}

function _SendMail($emailTo)
{
	
	Send-MailMessage -SmtpServer $smtpServer -from $fromAddr -to $emailTo -Subject "New ESX(s) joined the vCenter" -Body  "New ESX joined the vCenter" -Attachments .\logs\esxHardwareReport_$logdate.csv, .\logs\esxConfigurationReport_$logdate.csv

}

function _Main
{
	########### MAIN ############

	#cd "C:\ESXReportScript"

	# Get VC and ESX credentials from file
	$credentials = Import-Clixml .\esxReportDataCRD.xml
	
	$vCenterServer = $credentials.VcName
	$smtpServer = $credentials.SmtpServer
	$fromAddr = $credentials.fromAddr
	$toAddress = $credentials.toAddr 
	
	$esxUsername = $credentials.EsxCredentials.UserName 
	$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credentials.EsxCredentials.Password)
	$global:esxPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

	$vcUsername =  $credentials.VcCredentials.UserName  
	$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credentials.VcCredentials.Password)
	$global:vcPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)


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
			$xml.Add($xmltmparr[$i])
		}
	}
	catch
	{
		$xml = New-Object System.Collections.ArrayList
	}

	# Get hosts from vCenter and checks if the host is new according to the local XML file
	$esxhosts = get-vmhost  | where {$_.Manufacturer -NE "VMware"} | where {$_.state -eq "Connected" -or $_.state -eq "Maintenance"}

	$runtime = get-date
	$runtime = $runtime.ToUniversalTime()
	$hostsToExecute = @()
	foreach ($esxhost in $esxhosts)
	{
		$ServerIdXml = $null
		$ServerIdXml = $xml | where {$_.ServerId -eq $esxhost.id}

		if ((!$ServerIdXml) ) # -or ($InstalledDate -lt $LastRunTime)
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
			$xmlConf.Add($xmlConftmparr[$i])
		}
	}
	catch
	{
		$xmlConf = New-Object System.Collections.ArrayList
	}


	for ($i=0 ; $i -lt $esxConfigurationReport.Length ; $i++)
	{
		$xmlConf.Add($esxConfigurationReport[$i])
	}
	$xmlConf | Export-Clixml "esxConfReportData.xml"


	Write-Host "############# Saving Hardware Report #############"
	try
	{
		$xmlHardware = New-Object System.Collections.ArrayList
		$xmlHardwaretmparr = Import-Clixml -Path "esxHardwareReportData.xml"
		for($i = 0 ; $i -lt $xmlHardwaretmparr.length; $i++)
		{
			$xmlHardware.Add($xmlHardwaretmparr[$i])
		}
	}
	catch
	{
		$xmlHardware = New-Object System.Collections.ArrayList
	}


	for ($i=0 ; $i -lt $esxHardwareReport.Length ; $i++)
	{
		$xmlHardware.Add($esxHardwareReport[$i])
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
		_SendMail $toAddress
	}


	
}


$logdate = get-date -Format 'hh-mm_dd-MM-yyyy'
Start-Transcript -Path .\logs\esx_report_$logdate.log
	
_Main
Stop-Transcript