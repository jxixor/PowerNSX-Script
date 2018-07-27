
## Tech Summit Build - 3 Tier App ##
## Author: Anthony Burke t:@pandom_ b:networkinferno.net
## Revisions: Nick Bradford
## version 1.3
## February 2015
#-------------------------------------------------- 
# ____   __   _  _  ____  ____  __ _  ____  _  _ 
# (  _ \ /  \ / )( \(  __)(  _ \(  ( \/ ___)( \/ )
#  ) __/(  O )\ /\ / ) _)  )   //    /\___ \ )  ( 
# (__)   \__/ (_/\_)(____)(__\_)\_)__)(____/(_/\_)
#     PowerShell extensions for NSX for vSphere
#--------------------------------------------------

<#
Copyright Â© 2015 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.â€
#>

## Note: The OvfConfiguration portion of this example relies on this OVA. The securityGroup and Firewall configuration have a MANDATORY DEPENDANCY on this OVA being deployed at runtime. The script will fail if the conditions are not met. This OVA can be found here http://goo.gl/oBAFgq

# This paramter block defines global variables which a user can override with switches on execution.
    
#Make sure all the names are unique and the TransportZoneName is the TransportZone in the NSX Manager
#Names
$TsTransitLsName = "transit"
$TsWebLsName = "Web"
$TsAppLsName = "App"
$TsDbLsName = "DB"
$TsMgmtLsName = "Mgmt"
$TsEdgeName = "Edge"
$TsLdrName = "DLR"
$TransportZoneName = "TZ"

    # Edit EdgeUplinkPrimaryAddress and EdgeUplinkSecondaryAddress
    #Infrastructure
    $EdgeUplinkPrimaryAddress = "192.168.1.194"
    $EdgeUplinkSecondaryAddress = "192.168.1.195"
    $EdgeInternalPrimaryAddress = "172.16.1.1"
    $EdgeInternalSecondaryAddress = "172.16.1.6"
    $LdrUplinkPrimaryAddress = "172.16.1.2"
    $LdrUplinkProtocolAddress = "172.16.1.3"
    $LdrWebPrimaryAddress = "10.0.1.1"
    $WebNetwork = "10.0.1.0/24"
    $LdrAppPrimaryAddress = "10.0.2.1"
    $AppNetwork = "10.0.2.0/24"
    $LdrDbPrimaryAddress = "10.0.3.1"
    $DbNetwork = "10.0.3.0/24"
    $Global:TransitOspfAreaId = "10"
   
   #Edit each parameter in Compute to match your lab environment
    #Compute
   $ClusterName = "Compute"
   $DatastoreName = "ISCSI3"
   $EdgeUplinkNetworkName = "MGMTPG"
   $Password = "VMware1!VMware1!"

   #3Tier App
   $vAppName = "Books"
   #$BooksvAppLocation = ".\3.ova"

    #WebTier
    $Web01Name = "Web01"
    $Web01Ip = "10.0.1.11"
    $Web02Name = "Web02"
    $Web02Ip = "10.0.1.12"

    #AppTier
    $App01Name = "App01"
    $App01Ip = "10.0.2.11"
    $App02Name = "App02"
    $App02Ip = "10.0.2.12"
    $Db01Name = "Db01"
    $Db01Ip = "10.0.3.11"

    #DB Tier
    $Db02Name = "Db02"
    $Db02Ip = "10.0.3.12"

    #Subnet
    $DefaultSubnetMask = "255.255.255.0"
    $DefaultSubnetBits = "24"


    #Port
    $HttpPort = "80"

 
    ##LoadBalancer
    $LbAlgo = "round-robin"
    $WebpoolName = "WebPool"
    $ApppoolName = "AppPool"
    $WebVipName = "WebVIP"
    $AppVipName = "AppVIP"
    $WebAppProfileName = "WebAppProfile"
    $AppAppProfileName = "AppAppProfile"
    $VipProtocol = "http"
    ##Edge NAT
    $SourceTestNetwork = "192.168.1.0/24"
    
    ## Security Groups
    $WebSgName = "SG-Web"
    $WebSgDescription = "Web Security Group"
    $AppSgName = "SG-App"
    $AppSgDescription = "App Security Group"
    $DbSgName = "SG-Db"
    $DbSgDescription = "DB Security Group"
    $vAppSgName = "SG-Bookstore"
    $vAppSgDescription = "Books ALL Security Group"
    
    ## Security Tags
    $WebStName = "ST-Web"
    $AppStName = "ST-App"
    $DbStName = "ST-DB"
    
    ##IPset
    $AppVIP_IpSet_Name = "AppVIP_IpSet"
    $InternalESG_IpSet_Name = "InternalESG_IpSet"
    
    ##DFW
    $FirewallSectionName = "Bookstore Application"
    $DefaultHttpMonitorName = "default_http_monitor"

    #Script control
    $BuildTopology=$Global:True
    $DeployvApp=$Global:True
    [Parameter (Mandatory=$false)]
    [ValidateSet("static","ospf")]
    $Global:TopologyType="static"
