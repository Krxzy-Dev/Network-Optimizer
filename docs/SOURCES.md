# Where each tweak came from

Every setting this tool changes is backed by one of the sources below. Nothing here was made up,
and nothing is a Windows XP or Windows 7 leftover.

## The sources

| Tag | Source |
|---|---|
| `MS-NIC` | [Network Adapter Performance Tuning in Windows Server](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics) |
| `MS-NETSH` | [netsh](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh) |
| `MS-IPCONFIG` | [ipconfig](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/ipconfig) |
| `MS-ARP` | [arp](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/arp) |
| `MS-NBTSTAT` | [nbtstat](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/nbtstat) |
| `MS-TCP` | [Set-NetTCPSetting](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-nettcpsetting) |
| `MS-ADAPTER` | [Get-NetAdapter](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter) |
| `MS-ADVPROP` | [Set-NetAdapterAdvancedProperty](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapteradvancedproperty) |
| `MS-POWER` | [Set-NetAdapterPowerManagement](https://learn.microsoft.com/en-us/powershell/module/netadapter/set-netadapterpowermanagement) |
| `MS-ACK` | [New registry entry for controlling TCP ACK (KB328890)](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/registry-entry-control-tcp-acknowledgment-behavior) |
| `MS-DOH` | [Secure DNS Client over HTTPS (DoH)](https://learn.microsoft.com/en-us/windows-server/networking/dns/doh-client-support) |
| `MS-DO` | [Delete-DeliveryOptimizationCache](https://learn.microsoft.com/en-us/powershell/module/deliveryoptimization/delete-deliveryoptimizationcache) |
| `WINUTIL` | [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) |
| `SOPHIA` | [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows) |
| `DEBLOAT` | [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) |

## Section 1: cleaning and resetting

| Tweak | Source | Note |
|---|---|---|
| Flush DNS cache | `MS-IPCONFIG` | `ipconfig /flushdns` |
| Re-register in DNS | `MS-IPCONFIG` | `ipconfig /registerdns` |
| Release and renew IPv4 and IPv6 | `MS-IPCONFIG` | `/release`, `/renew`, `/release6`, `/renew6` |
| Clear ARP cache | `MS-ARP`, `MS-NETSH` | `arp -d *` plus `netsh interface ip delete arpcache` |
| Clear destination and neighbour cache | `MS-NETSH` | `netsh interface ipv4 delete destinationcache` and the ipv6 version |
| Clear NetBIOS cache | `MS-NBTSTAT` | `-R` purges the cache, `-RR` re-registers with WINS |
| Winsock reset | `MS-NETSH` | `netsh winsock reset` |
| TCP/IP stack reset | `MS-NETSH` | `netsh int ip reset` and `netsh int ipv6 reset` |
| Clear system proxy | `MS-NETSH` | `netsh winhttp reset proxy` |
| Clear Internet Options proxy | `WINUTIL` | `ProxyEnable` and `ProxyServer` under Internet Settings |
| Empty Delivery Optimisation cache | `MS-DO`, `DEBLOAT` | Uses the built in cmdlet, falls back to clearing the folder |
| Restart network services | `WINUTIL` | Same service list WinUtil uses for network work |
| Reset the firewall | `MS-NETSH` | `netsh advfirewall reset`, then makes sure it is switched back on |
| Bounce the adapter | `MS-ADAPTER` | `Restart-NetAdapter` |

## Section 2: TCP/IP

| Tweak | Source | Note |
|---|---|---|
| Auto tuning level | `MS-NIC`, `MS-TCP` | Microsoft lists all five levels and says Normal is the default |
| Receive Side Scaling | `MS-NIC` | Microsoft recommends RSS when there are fewer cards than cores |
| Receive Segment Coalescing | `MS-NIC` | Microsoft lists RSC state in `netsh int tcp show global` |
| ECN | `MS-TCP` | `-EcnCapability`. Off by default here because it is debated |
| TCP timestamps | `MS-TCP` | `-Timestamps`. RFC 1323, 12 bytes a packet |
| Initial RTO | `MS-TCP` | `-InitialRtoMs`, valid range 300 to 3000 in steps of 10 |
| Congestion provider | `MS-TCP` | CUBIC on modern builds, CTCP on older ones. Read only on some Windows 10 builds, the script handles that |
| NetworkThrottlingIndex, SystemResponsiveness | `WINUTIL` | Multimedia Class Scheduler keys under `Multimedia\SystemProfile`. Optional, off by default |
| TcpAckFrequency and TCPNoDelay | `MS-ACK` | KB328890 gives the exact path and range. Microsoft says do not change it without knowing your network, so it is optional and off by default |
| QoS NonBestEffortLimit | `WINUTIL` | Included with an honest explanation. It does not do what people think |
| DNS switcher | `WINUTIL`, `SOPHIA` | Same provider list both use: Cloudflare, Google, Quad9 |
| DNS over HTTPS | `MS-DOH`, `SOPHIA` | Uses `Add-DnsClientDohServerAddress`, falls back to `netsh dns add encryption`. Windows 11 only |

## Section 3: Wi-Fi

| Tweak | Source | Note |
|---|---|---|
| Stop Windows powering the card down | `MS-POWER` | Device Manager power box, set through `MSPower_DeviceEnable` |
| Driver power saving off | `MS-ADVPROP`, `MS-NIC` | Microsoft's low latency advice says set the power profile to High Performance |
| Power plan Wi-Fi setting | `MS-NIC` | Same section. Uses the documented `powercfg` subgroup and setting GUIDs |
| MIMO power save | `MS-ADVPROP` | Read from the card, only changed if the card has it |
| Roaming, preferred band, transmit power, 802.11 mode | `MS-ADVPROP` | All found by looking up the real `DisplayName` and `RegistryKeyword` on your card |
| Background scanning | `MS-ADVPROP`, `MS-NETSH` | Driver keyword plus `netsh wlan set profileparameter autoSwitch=no` |
| Signal, band, channel, link speed | `MS-NETSH` | `netsh wlan show interfaces` |
| Wi-Fi drop report | `MS-NETSH` | `netsh wlan show wlanreport` |

## Section 4: Ethernet

| Tweak | Source | Note |
|---|---|---|
| Skipping virtual adapters | `MS-ADAPTER` | `Get-NetAdapter` plus a name match for Hyper-V, VPNs, WSL and the rest |
| Link speed and duplex warning | `MS-ADAPTER` | Compares the live link speed against the card's own list of supported speeds |
| Speed and duplex on Auto | `MS-ADVPROP` | `*SpeedDuplex` |
| Energy Efficient Ethernet, Green Ethernet | `MS-ADVPROP` | Matched on `*EEE`, `EnableGreenEthernet`, `AdvancedEEE` and the display names, so Intel, Realtek, Killer and Marvell all work |
| Interrupt Moderation | `MS-NIC` | Microsoft: turn it off for the lowest possible latency, and it costs CPU |
| Flow Control | `MS-ADVPROP` | `*FlowControl` |
| Receive and transmit buffers | `MS-NIC` | Microsoft: raise the receive buffer to the maximum for receive heavy work |
| Large Send Offload v2 and checksum offloads | `MS-NIC` | Microsoft: enabling offloads is usually a good thing, and enable static offloads for low latency |
| Jumbo Frames | `MS-ADVPROP` | Off by default. Every device in the path has to agree |
| Wake on LAN | `MS-POWER` | `WakeOnMagicPacket` and `WakeOnPattern` |
| Driver version and date | `MS-ADAPTER` | `DriverVersionString` and `DriverDate` |

## Section 5 and 6: presets, backup and undo

| Feature | Source | Note |
|---|---|---|
| Preset and tweak layout | `WINUTIL` | Each tweak carries its own title, description, risk, apply block and undo. Presets are named lists of tweak ids, same as `preset.json` |
| Undo for every tweak | `SOPHIA` | Sophia's rule that every tweak has a matching restore |
| Restore point | `WINUTIL` | Including the `SystemRestorePointCreationFrequency = 0` trick, or Windows refuses a second point within 24 hours |
| Registry export before changes | `WINUTIL` | `reg.exe export` for each key the tool touches |

## Deliberately left out

| Thing | Why |
|---|---|
| TCP Chimney Offload | Microsoft deprecated it in Windows Server 2016 and says it can hurt performance (`MS-NIC`) |
| IPsec Task Offload | Same. Deprecated and can hurt performance (`MS-NIC`) |
| `TcpWindowSize`, `NumTcbTablePartitions`, `MaxHashTableSize` | Microsoft says these are ignored on anything newer than Server 2003 (`MS-NIC`) |
| `DefaultTTL`, `Tcp1323Opts`, `GlobalMaxTcpWindowSize` | Windows XP era registry tweaks. They do nothing now |
| MTU forcing | The card negotiates it. Forcing it usually makes things worse, not better |
| Turning off Defender, the firewall or Windows Update | Never worth it |
