#Setup variables
$testVM1 = get-vm w2012-1
$testVM2 = get-vm w2012-2
$testPort = "80"
$testProto = "tcp"
$testSection = "PowerNSXSection"
$testRule = "Test Rule"
$testServiceName = "service1"
 
#Create NSX Service
$testService1 = New-NsxService -Name $testServiceName -Protocol $testProto -Port $testPort
 
#Create Firewall Section
$newSection = New-NsxFirewallSection $testSection
 
#Create Basic VM to VM any service rule *Block Traffic*
 
Get-NsxFirewallSection $newSection | New-NsxFirewallRule -Name $testRule -Source $testVM1 -Destination $testVM2 -action deny
 