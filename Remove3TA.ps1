. .\3TAVariables.ps1

#Stop and Delete 3 Tier VApp

Write-Host -ForegroundColor Green "Moving the NICs off of Logical Switches"
$web01NA = Get-VM -Name web01 | Get-NetworkAdapter
$web02NA = Get-VM -Name web02 | Get-NetworkAdapter
$app01NA = Get-VM -Name app01 | Get-NetworkAdapter
$app02NA = Get-VM -Name app02 | Get-NetworkAdapter
$db01NA = Get-VM -Name db01 | Get-NetworkAdapter
$webNA = Get-VDPortgroup -Name PGWeb
$appNA = Get-VDPortgroup -Name PGApp
$dbNA = Get-VDPortgroup -Name PGDB
Get-VM Web01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM Web02 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM App01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM App02 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM DB01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false

Set-NetworkAdapter -NetworkAdapter $web01NA -Portgroup $webNA -Confirm:$false
Set-NetworkAdapter -NetworkAdapter $web02NA -Portgroup $webNA -Confirm:$false
Set-NetworkAdapter -NetworkAdapter $app01NA -Portgroup $appNA -Confirm:$false
Set-NetworkAdapter -NetworkAdapter $app02NA -Portgroup $appNA -Confirm:$false
Set-NetworkAdapter -NetworkAdapter $db01NA -Portgroup $dbNA -Confirm:$false

Get-VM Web01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM Web02 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM App01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM App02 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
Get-VM DB01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false

#Deleting Firewall Section
write-host -foregroundcolor "Green" "Removing Firewall Section..."
Get-NsxFirewallSection $FirewallSectionName | Remove-NsxFirewallSection -force -Confirm:$false

#Remove Security Groups
write-host -foregroundcolor "Green" "Removing Security Groups..."
Get-NsxSecurityGroup $WebSgName |Remove-NsxSecurityGroup -Confirm:$false
Get-NsxSecurityGroup $AppSgName |Remove-NsxSecurityGroup -Confirm:$false
Get-NsxSecurityGroup $DbSgName |Remove-NsxSecurityGroup -Confirm:$false
Get-NsxSecurityGroup $vAppSgName |Remove-NsxSecurityGroup -Confirm:$false


#Remove service
Get-NsxService -name "tcp-80" | Remove-NsxService -Confirm:$false
Get-NsxService -Name "tcp-3306" | Remove-NsxService -Confirm:$false

#Remove IPSets
write-host -foregroundcolor "Green" "Removing IPsets..."
Get-NsxIpSet AppVIP_ipSet | Remove-NsxIpSet -Confirm:$false
Get-NsxIpSet InternalESG_IpSet| Remove-NsxIpSet -Confirm:$false
Get-NsxIpSet "Source_Network" | Remove-NsxIpSet -Confirm:$false

#Remove Security Tags
Get-NsxSecurityTag -Name ST-App | Remove-NsxSecurityTag -Confirm:$false
Get-NsxSecurityTag -Name ST-Web | Remove-NsxSecurityTag -Confirm:$false
Get-NsxSecurityTag -Name ST-DB | Remove-NsxSecurityTag -Confirm:$false

#Remove Edges
write-host -foregroundcolor "Green" "Removing Edge..."
Get-NsxEdge $TsEdgeName | Remove-NsxEdge -Confirm:$false
write-host -foregroundcolor "Green" "Removing DLR..."
Get-NsxLogicalRouter $TsLdrName | Remove-NsxLogicalRouter -Confirm:$false

#Remove Logical Switches
Start-Sleep -Seconds 5
write-host -foregroundcolor "Green" "Removing Logical Switches..."
Get-NsxTransportZone |Get-NsxLogicalSwitch $TsMgmtLsName | Remove-NsxLogicalSwitch -Confirm:$false
Get-NsxTransportZone |Get-NsxLogicalSwitch $TsDbLsName | Remove-NsxLogicalSwitch -Confirm:$false
Get-NsxTransportZone |Get-NsxLogicalSwitch $TsAppLsName | Remove-NsxLogicalSwitch -Confirm:$false
Get-NsxTransportZone |Get-NsxLogicalSwitch $TsWebLsName | Remove-NsxLogicalSwitch -Confirm:$false
Get-NsxTransportZone |Get-NsxLogicalSwitch $TsTransitLsName | Remove-NsxLogicalSwitch -Confirm:$false
