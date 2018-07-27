. .\3TAVariables.ps1

###
# Do Not modify below this line! :)
###

Set-StrictMode -Version latest

## Validation of PowerCLI version. PowerCLI 6 is requried due to OvfConfiguration commands.

[int]$PowerCliMajorVersion = (Get-PowerCliVersion).major

if ( -not ($PowerCliMajorVersion -ge 6 ) ) { throw "OVF deployment tools requires PowerCLI version 6 or above" }

try {
    $Cluster = get-cluster $ClusterName -errorAction Stop
    $DataStore = get-datastore $DatastoreName -errorAction Stop
    $EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop
}
catch {
    throw "Failed getting vSphere Inventory Item: $_"
}

# Building out the required Logical Switches
function Build-LogicalSwitches {

    #Logical Switches
    write-host -foregroundcolor "Green" "Creating Logical Switches..."

## Creates four logical switches with each being assigned to a global varaible.
    $Global:TsTransitLs = Get-NsxTransportZone $TransportZoneName | New-NsxLogicalSwitch $TsTransitLsName
    $Global:TsWebLs = Get-NsxTransportZone $TransportZoneName | New-NsxLogicalSwitch $TsWebLsName
    $Global:TsAppLs = Get-NsxTransportZone $TransportZoneName | New-NsxLogicalSwitch $TsAppLsName
    $Global:TsDbLs = Get-NsxTransportZone $TransportZoneName | New-NsxLogicalSwitch $TsDbLsName
    $Global:TsMgmtLs = Get-NsxTransportZone $TransportZoneName | New-NsxLogicalSwitch $TsMgmtLsName


}

#Building out the DLR.
function Build-Dlr {

    ###
    # DLR

    # DLR Appliance has the uplink router interface created first.
    write-host -foregroundcolor "Green" "Creating DLR"
    $TsLdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TsTransitLsName -ConnectedTo $TsTransitLs -PrimaryAddress $LdrUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits
    # The DLR is created and assigned to a portgroup, and the datastore/cluster required
    $TsLdr = New-NsxLogicalRouter -name $TsLdrName -ManagementPortGroup $TsMgmtLs -interface $TsLdrvNic0 -cluster $cluster -datastore $DataStore


    ## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
    # Added to pipe to out-null to supporess output that we dont need.
    write-host -foregroundcolor Green "Adding Web LIF to DLR"
    $TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsWebLsName  -ConnectedTo $TsWebLs -PrimaryAddress $LdrWebPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
    write-host -foregroundcolor Green "Adding App LIF to DLR"
    $TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsAppLsName  -ConnectedTo $TsAppLs -PrimaryAddress $LdrAppPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
    write-host -foregroundcolor Green "Adding DB LIF to DLR"
    $TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsDbLsName  -ConnectedTo $TsDbLs -PrimaryAddress $LdrDbPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null


}

Function Configure-DlrDefaultRoute {

    ## DLR Routing - default route from DLR with a next-hop of the Edge.
    write-host -foregroundcolor Green "Setting default route on DLR to $EdgeInternalPrimaryAddress"
    ##The first line pulls the uplink name coz we cant assume we know the index ID
    $TsLdrTransitInt = get-nsxlogicalrouter $TsLdrName | get-nsxlogicalrouterinterface | ? { $_.name -eq $TsTransitLsName}
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $TsLdrTransitInt.index -DefaultGatewayAddress $EdgeInternalPrimaryAddress -confirm:$false | out-null

}

Function Build-Edge {

    # EDGE

    ## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
    $edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $EdgeUplinkPrimaryAddress -SecondaryAddress $EdgeUplinkSecondaryAddress -SubnetPrefixLength $DefaultSubnetBits
    $edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TsTransitLsName -type Internal -ConnectedTo $TsTransitLs -PrimaryAddress $EdgeInternalPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits -SecondaryAddress $EdgeInternalSecondaryAddress

    ## Deploy appliance with the defined uplinks
    write-host -foregroundcolor "Green" "Creating Edge"
    $Global:TSEdge1 = New-NsxEdge -name $TsEdgeName -cluster $Cluster -datastore $DataStore -Interface $edgevnic0,$edgevnic1 -Password $Password


}

function Set-EdgeFwDefaultAccept {

     #Change the default FW policy of the edge.  At the time of writing there is not  an explicit cmdlet to do this, so we update the XML manually and push it back using Set-NsxEdge
    write-host -foregroundcolor "Green" "Setting $TsEdgeName firewall default rule to permit"
    $TsEdge1 = get-nsxedge $TsEdge1.name
    $TsEdge1.features.firewall.defaultPolicy.action = "accept"
    $TsEdge1 | Set-NsxEdge -confirm:$false | out-null

}

function Set-Edge-Db-Nat {
    write-host -foregroundcolor "Green" "Using the devils technology - NAT - to expose access to the Database VM"
    $SrcNatPort = 3306
    $TranNatPort = 3306
    Get-NsxEdge $TsEdgeName | Get-NsxEdgeNat | Set-NsxEdgeNat -enabled -confirm:$false | out-null
    $DbNat = get-NsxEdge $TsEdgeName | Get-NsxEdgeNat | New-NsxEdgeNatRule -vNic 0 -OriginalAddress $SourceTestNetwork -TranslatedAddress $Db01Ip -action dnat -Protocol tcp -OriginalPort $SrcNatPort -TranslatedPort $TranNatPort -LoggingEnabled -Enabled -Description "Open SSH on port $SrcNatPort to $TranNatPort"

}

function Set-EdgeStaticRoute {

    write-host -foregroundcolor "Green" "Adding static route to Web, App and DB networks to $TsEdgeName"
    ##Static route from Edge to Web and App via DLR Uplink if -topologytype is not defined or static selected
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgestaticroute -Network $WebNetwork -NextHop $LdrUplinkPrimaryAddress -confirm:$false | out-null
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgestaticroute -Network $AppNetwork -NextHop $LdrUplinkPrimaryAddress -confirm:$false | out-null
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgestaticroute -Network $DbNetwork -NextHop $LdrUplinkPrimaryAddress -confirm:$false | out-null

}

function Configure-EdgeOSPF {
    #If -TopoologyType ospf is selected then this function is run.
    write-host -foregroundcolor Green "Configuring Edge OSPF"
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $EdgeUplinkPrimaryAddress -confirm:$false | out-null

    #Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

    #Create new Area 0 for OSPF
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

    #Area to interface mapping
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $TransitOspfAreaId -vNic 1 -confirm:$false | out-null

}

function Configure-LogicalRouterOspf {

    write-host -foregroundcolor Green "Configuring Logicalrouter OSPF"
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $LdrUplinkPrimaryAddress -ProtocolAddress $LdrUplinkProtocolAddress -ForwardingAddress $LdrUplinkPrimaryAddress  -confirm:$false | out-null

    #Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

    #Create new Area
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

    #Area to interface mapping
    $TsLdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TsTransitLsName}

    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $TransitOspfAreaId -vNic $TsLdrTransitInt.index -confirm:$false | out-null

    #Enable Redistribution into OSPF of connected routes.
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner ospf -FromConnected -Action permit -confirm:$false | out-null

}

function Build-LoadBalancer {

    # Switch that enables Loadbanacing on $TSedgeName
    write-host -foregroundcolor "Green" "Enabling LoadBalancing on $TsEdgeName"
    Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled | out-null

    # Edge LB config - define pool members.  By way of example, we will use two different methods for defining pool membership.  Webpool via predefine memberspec first...
    write-host -foregroundcolor "Green" "Creating Web Pool"

    $webpoolmember1 = New-NsxLoadBalancerMemberSpec -name $Web01Name -IpAddress $Web01Ip -Port $HttpPort
    $webpoolmember2 = New-NsxLoadBalancerMemberSpec -name $Web02Name -IpAddress $Web02Ip -Port $HttpPort

    # ... And create the web pool
    $WebPool =  Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $WebPoolName -Description "Web Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Memberspec $webpoolmember1,$webpoolmember2

    # Now, method two for the App Pool  Create the pool with empty membership.
    write-host -foregroundcolor "Green" "Creating App Pool"
    $AppPool = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $AppPoolName -Description "App Tier Pool" -Transparent:$false -Algorithm $LbAlgo

    # ... And now add the pool members
    $AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App01Name -IpAddress $App01Ip -Port $HttpPort
    $AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App02Name -IpAddress $App02Ip -Port $HttpPort

    # Create App Profiles. It is possible to use the same but for ease of operations this will be two.
    write-host -foregroundcolor "Green" "Creating Application Profiles for Web and App"
    $WebAppProfile = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name $WebAppProfileName  -Type $VipProtocol
    $AppAppProfile = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | new-NsxLoadBalancerApplicationProfile -Name $AppAppProfileName  -Type $VipProtocol

    # Create the VIPs for the relevent WebPools. Applied to the Secondary interface variables declared.
    write-host -foregroundcolor "Green" "Creating VIPs"
    Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $WebVipName -Description $WebVipName -ipaddress $EdgeUplinkSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $WebAppProfile -DefaultPool $WebPool -AccelerationEnabled | out-null
    Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $AppVipName -Description $AppVipName -ipaddress $EdgeInternalSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $AppAppProfile -DefaultPool $AppPool -AccelerationEnabled | out-null

}
## NOTE: From here below this requires the OVF that VMware uses internally. Please customise for your three tier application.
function deploy-3TiervApp {
  write-host -foregroundcolor "Green" "Deploying 'The Bookstore' application "
  # vCenter and the VDS has no understanding of a "Logical Switch". It only sees it as a VDS portgroup. This looks up the Logical Switch defined by the variable $TsWebLsName and runs iterates the result across Get-NsxBackingPortGroup. The results are used below in the networkdetails section.
  $WebNetwork = get-nsxtransportzone $TransportZoneName | get-nsxlogicalswitch $TsWebLsName | Get-NsxBackingPortGroup
  $AppNetwork = get-nsxtransportzone $TransportZoneName | get-nsxlogicalswitch $TsAppLsName | Get-NsxBackingPortGroup
  $DbNetwork = get-nsxtransportzone $TransportZoneName | get-nsxlogicalswitch $TsDbLsName | Get-NsxBackingPortGroup


  ## Compute details - finds the host with the least used memory for deployment.
    #$VMHost = $cluster | Get-VMHost | Sort MemoryUsageGB | Select -first 1
    $web01NA = Get-VM -Name web01 | Get-NetworkAdapter
    $web02NA = Get-VM -Name web02 | Get-NetworkAdapterft
    $app01NA = Get-VM -Name app01 | Get-NetworkAdapter
    $app02NA = Get-VM -Name app02 | Get-NetworkAdapter
    $db01NA = Get-VM -Name db01 | Get-NetworkAdapter
    Set-NetworkAdapter -NetworkAdapter $web01NA -Portgroup $WebNetwork -Confirm:$false
    Set-NetworkAdapter -NetworkAdapter $web02NA -Portgroup $WebNetwork -Confirm:$false
    Set-NetworkAdapter -NetworkAdapter $app01NA -Portgroup $AppNetwork -Confirm:$false
    Set-NetworkAdapter -NetworkAdapter $app02NA -Portgroup $AppNetwork -Confirm:$false
    Set-NetworkAdapter -NetworkAdapter $db01NA -Portgroup $DbNetwork -Confirm:$false

    Get-VM Web01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false
    Get-VM Web02 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false
    Get-VM App01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false
    Get-VM App02 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false
    Get-VM DB01 | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$true -Confirm:$false



#With all the desired OVF configuration done it is time to run the deployment.
#  Import-vApp -Source $BooksvAppLocation -OvfConfiguration $OvfConfiguration -Name Books -Location $Cluster -VMHost $Vmhost -Datastore $Datastore | out-null
#  write-host -foregroundcolor "Green" "Starting $vAppName vApp components"
#  Start-vApp $vAppName | out-null
}

function Apply-Microsegmentation {

 #####################################
    # Microseg config

    write-host -foregroundcolor Green "Getting Services"

    # Assume these services exist which they do in a default NSX deployment.
    $httpservice = New-NsxService -name "tcp-80" -protocol tcp -port "80"
    $mysqlservice = New-NsxService -name "tcp-3306" -protocol tcp -port "3306"

    #Create Security Tags

    $WebSt = New-NsxSecurityTag -name $WebStName
    $AppSt = New-NsxSecurityTag -name $AppStName
    $DbSt = New-NsxSecurityTag -name $DbStName


    # Create IP Sets

    write-host -foregroundcolor "Green" "Creating Source IP Groups"
    $AppVIP_IpSet = New-NsxIPSet -Name $AppVIP_IpSet_Name -IPAddresses $EdgeInternalSecondaryAddress
    $InternalESG_IpSet = New-NsxIPSet -name $InternalESG_IpSet_Name -IPAddresses $EdgeInternalPrimaryAddress

    write-host -foregroundcolor "Green" "Creating Security Groups"

    #Create SecurityGroups and with static includes
    $WebSg = New-NsxSecurityGroup -name $WebSgName -description $WebSgDescription -includemember $WebSt
    $AppSg = New-NsxSecurityGroup -name $AppSgName -description $AppSgDescription -includemember $AppSt
    $DbSg = New-NsxSecurityGroup -name $DbSgName -description $DbSgDescription -includemember $DbSt
    $BooksSg = New-NsxSecurityGroup -name $vAppSgName -description $vAppSgName -includemember $WebSg, $AppSg, $DbSg

    # Apply Security Tag to VM's for Security Group membership

    $WebVMs = Get-Vm | ? {$_.name -match ("Web0")}
    $AppVMs = Get-Vm | ? {$_.name -match ("App0")}
    $DbVMs = Get-Vm | ? {$_.name -match ("Db0")}


    $WebSt | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $WebVMs | Out-Null
    $AppSt | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $AppVMs | Out-Null
    $DbSt | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $DbVMs | Out-Null

    #Building firewall section with value defined in $FirewallSectionName
    write-host -foregroundcolor "Green" "Creating Firewall Section"

    $FirewallSection = new-NsxFirewallSection $FirewallSectionName

    #Actions
    $AllowTraffic = "allow"
    $DenyTraffic = "deny"

    #Allows Web VIP to reach WebTier
    write-host -foregroundcolor "Green" "Creating Web Tier rule"
    $SourcesRule = get-nsxfirewallsection $FirewallSectionName | New-NSXFirewallRule -Name "VIP to Web" -Source $InternalESG_IpSet -Destination $WebSg -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg -position bottom

    #Allows Web tier to reach App Tier via the APP VIP and then the NAT'd vNIC address of the Edge
    write-host -foregroundcolor "Green" "Creating Web to App Tier rules"
    $WebToAppVIP = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$WebSgName to App VIP" -Source $WebSg -Destination $AppVIP_IpSet -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg, $AppSg -position bottom
    $ESGToApp = get-NsxFirewallSection $FirewallSectionName | New-NsxFirewallRule -Name "App ESG interface to $AppSgName" -Source $InternalEsg_IpSet -Destination $appSg -service $HttpService -Action $Allowtraffic -AppliedTo $AppSg -position bottom

    #Allows App tier to reach DB Tier directly
    write-host -foregroundcolor "Green" "Creating Db Tier rules"
    $AppToDb = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$AppSgName to $DbSgName" -Source $AppSg -Destination $DbSg -Service $MySqlService -Action $AllowTraffic -AppliedTo $AppSg, $DbSG -position bottom

    write-host -foregroundcolor "Green" "Creating deny all applied to $vAppSgName"
    #Default rule that wraps around all VMs within the topolgoy - application specific DENY ALL
    $BooksDenyAll = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "Deny All Books" -Action $DenyTraffic -AppliedTo $BooksSg -position bottom -EnableLogging -tag "$BooksSG"
    write-host -foregroundcolor "Green" "Books application deployment complete."

}
if ( $BuildTopology ) {

    Build-LogicalSwitches
    Build-Dlr
    Configure-DlrDefaultRoute
    Build-Edge
    Set-EdgeFwDefaultAccept
    Set-Edge-Db-Nat
    Build-LoadBalancer
    switch ( $TopologyType ) {
        "static"  {
            Set-EdgeStaticRoute
        }

        "ospf" {
            Configure-EdgeOSPF
            Configure-LogicalRouterOSPF
        }
    }


 }
if ( $DeployvApp ) {
  deploy-3TiervApp
  Apply-Microsegmentation
}
