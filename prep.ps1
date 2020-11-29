$vcname = read-host "Please enter vCenter Server"
$esxCred = Get-Credential -Message "ESX Credentials" -UserName root
$vcenterPassword = Get-Credential -Message "vCenter Credentials"

$smtpServer = read-host "Please enter SMTP Server"
$fromAddr = read-host "Please enter from email address"
$toAddr = read-host "Please enter destination email address (comma separated)"
$toAddr = $toAddr.split(",")


$myObject = New-Object -TypeName psobject
$myObject | Add-Member -MemberType NoteProperty -Name EsxCredentials -Value $esxCred
$myObject | Add-Member -MemberType NoteProperty -Name VcCredentials -Value $vcenterPassword
$myObject | Add-Member -MemberType NoteProperty -Name VcName -Value $vcname
$myObject | Add-Member -MemberType NoteProperty -Name SmtpServer -Value $smtpServer
$myObject | Add-Member -MemberType NoteProperty -Name toAddr -Value $toAddr
$myObject | Add-Member -MemberType NoteProperty -Name fromAddr -Value $fromAddr

$myObject | Export-Clixml "esxReportDataCRD.xml"

'Cluster,Manufacturer,HardwareModel,CPUModel,Required BIOS Version,Power Management,IsDRSActive,DRSMode,isHAActive,HAFailoverLevel,ClusterEVCMode,ESXMaxEVCMode,ScratchConfig,SyslogConfig,isNTPConfigured,IsNTPRunning,vmk0Ip,vmk0Portgroup,vmk0Mtu,vmk0Netstack,vmk0EnabledServices,vmk1Ip,vmk1Portgroup,vmk1Mtu,vmk1Netstack,vmk1EnabledServices,vmk2Ip,vmk2Portgroup,vmk2Mtu,vmk2Netstack,vmk2EnabledServices,vmk3Ip,vmk3Portgroup,vmk3Mtu,vmk3Netstack,vmk3EnabledServices' > ClusterConfiguration.csv
'default,default,default,default,,High Performance,TRUE,FullyAutomated,TRUE,1,,intel-skylake,/vmfs/volumes/cd473ec9-c53b990b/esx_folder,"udp://siem02.dub:514,udp://10.200.29.62:514,udp://logstash-common.elk.dub:22059",10.200.8.16;10.200.8.17,TRUE,10.200.28.0/23,ESXi Management 180_Copied,1500,defaultTcpipStack,Management,"	10.237.240.0/23",vMotion 2001,9000,defaultTcpipStack,vMotion,"	10.103.8.0/22",NFS_Storage_1354,9000,Default,-,,,,,' >> ClusterConfiguration.csv
write-host "Please update Cluster Desired Configuration file"
pause
.\ClusterConfiguration.csv


