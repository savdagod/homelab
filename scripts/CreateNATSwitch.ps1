$SwitchName = "Default Switch"
New-VMSwitch -Name $SwitchName -SwitchType Internal

$if = Get-NetAdapter | Where-Object {$_.Name -eq $SwitchName} | Select-Object -ExpandProperty ifIndex
New-NetNat -name InternalNATNetwork -InternalIPInterfaceAddressPrefix 172.16.0.0/24
New-NetIPAddress -IPAddress 172.16.0.1 -PrefixLength 24 -InterfaceIndex $if
New-NetFirewallRule -DisplayName "Allow NAT" -Direction Inbound -Protocol Any -LocalAddress Any -RemoteAddress 172.16.0.0/24 -Action Allow