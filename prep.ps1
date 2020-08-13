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

