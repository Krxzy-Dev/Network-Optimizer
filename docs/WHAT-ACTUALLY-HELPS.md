# What actually helps and what barely does anything

No hype. Here is what each tweak is really worth, split by Wi-Fi and Ethernet.

Scale used below:

- **Big** you will notice it without measuring
- **Medium** you will see it in the before and after test
- **Small** real but under a millisecond, or only in odd cases
- **Nothing** it does not change anything useful

---

## Wi-Fi

### Worth doing

| Tweak | Effect | Why |
|---|---|---|
| Wi-Fi power saving off | **Big** | This is the number one cause of Wi-Fi lag spikes on laptops. The card dozes between packets and the first packet after a quiet moment arrives 50 to 200 ms late. Turning it off makes ping steady instead of spiky. Costs battery. |
| Stop Windows turning the card off | **Big** | Same problem from the other direction. If you get disconnects that fix themselves, this is usually why. |
| MIMO power save off | **Medium** | The card drops to one aerial to save power. Set to No SMPS it keeps them all running, which helps signal and speed. |
| Prefer 5 GHz | **Medium** | 2.4 GHz is packed with neighbours, microwaves and Bluetooth. 5 GHz is quieter and faster. Only if you are near the router, since 5 GHz does not go through walls well. |
| Transmit power on full | **Small to medium** | Only matters if you are far from the router. Near it, no difference. |
| Faster DNS server | **Medium** | Pages start loading sooner because names resolve quicker. It does not raise your download speed by a single Mbps. |

### Only sometimes

| Tweak | Effect | Why |
|---|---|---|
| Background scanning down | **Small, sometimes medium** | Fixes a blip every few seconds on some Intel cards. On a laptop you carry around the house it makes roaming between access points slower and worse. |
| Nagle off | **Small** | Shaves a few ms off games. On Wi-Fi the jitter from the air is far bigger than anything Nagle does, so it gets lost in the noise. |
| Bounce the card | **Big when stuck, nothing otherwise** | It is a fix, not a speed up. |

### Not worth it on Wi-Fi

| Tweak | Effect | Why |
|---|---|---|
| Interrupt Moderation off | **Nothing** | Most Wi-Fi drivers do not even have the setting, and Wi-Fi latency is dominated by the radio anyway. |
| Jumbo Frames | **Nothing** | Wi-Fi does not use them. |
| Receive buffers up | **Small at best** | Wi-Fi rarely pushes enough packets to fill the buffers. |

### The honest truth about Wi-Fi

If your Wi-Fi is bad, the settings on this page are the small stuff. In order of what actually
fixes Wi-Fi:

1. Move closer to the router, or move the router
2. Get off 2.4 GHz
3. Change the router's channel to one your neighbours are not on
4. Update the Wi-Fi driver from Intel or your laptop maker
5. Then, and only then, these tweaks

---

## Ethernet

### Worth doing

| Tweak | Effect | Why |
|---|---|---|
| EEE / Green Ethernet off | **Big on affected cards** | Plenty of Realtek onboard NICs drop the link for a second every few minutes with this on. If you get random one second freezes in games, try this first. On a card that does not have the bug, it changes nothing. |
| Stop Windows turning the card off | **Big if you get disconnects** | Same as Wi-Fi. |
| Receive buffers up | **Medium** | Real on gigabit and faster lines, or when you are downloading and gaming at the same time. Microsoft recommends maxing the receive buffer for receive heavy work. Costs a bit of RAM. |
| Checksum and LSO offloads on | **Medium, but only if they were off** | They are on by default. If a driver update or an old tweak guide turned them off, turning them back on takes real load off your CPU. If they were already on, no change. |
| Auto Negotiation for speed and duplex | **Big if it was forced wrong** | Somebody forcing 100 Mbps Full is how a gigabit card ends up at a tenth of its speed. |

### Only sometimes

| Tweak | Effect | Why |
|---|---|---|
| Interrupt Moderation off | **Small** | Real, measurable, and usually under a millisecond. Worth it on a gaming PC with CPU headroom. On a weak CPU under load it can make things worse. |
| Nagle off | **Small** | A few ms in games that send lots of tiny packets. It makes your PC send more, smaller packets, which is worse on a slow upload. |
| Flow Control on | **Small** | Stops dropped packets on a busy switch. On cheap unmanaged switches it can cause head of line blocking instead. Leave it on unless you have a reason. |
| RSC off | **Small** | Trades a bit of throughput for a bit of latency. Only worth it if you game on a fast PC. |
| Jumbo Frames | **Medium for NAS transfers, nothing for internet** | Only if every device in the path supports it. Get one wrong and things half work in confusing ways. |

### Not worth it

| Tweak | Effect | Why |
|---|---|---|
| QoS reservable bandwidth to 0 | **Nothing** | The famous "Windows steals 20 percent" thing is wrong. That bandwidth is only reserved while an app is actively asking for it, and it is given straight back when nobody is. Changing it to 0 gains you nothing and can make a video call worse. |
| Auto tuning set to normal | **Nothing, unless it was changed** | Normal is already the default. This is here to undo somebody else's bad advice. If it was set to `disabled` you were capped at a 64 KB window, and fixing that is **big**. |
| RSS on | **Nothing, unless it was off** | On by default on every modern card. Worth checking, not worth bragging about. |
| ECN on | **Nothing to small** | Needs your ISP and the far end to support it. A few old routers break with it on. Off by default here for a reason. |
| Network throttling off | **Nothing to small** | The throttle only kicks in while a multimedia app has registered with the scheduler. On a gaming PC that can mean a small gain. On a weaker PC it can make audio crackle. |
| Initial RTO to 2000 ms | **Small** | Only affects how quickly a connection that has already failed gets retried. You will not feel it. |
| TCP timestamps off | **Nothing** | 12 bytes on a 1500 byte packet, and it is already off by default. |
| Congestion control change | **Nothing on modern Windows** | CUBIC is already the default on Windows 10 2004 and newer. On older builds CTCP can help on a long, high latency line. |

---

## Cache cleaning: read this bit

None of the cleaning in Section 1 makes anything faster when your network is working fine. Flushing
DNS on a healthy PC gains you nothing, and for the next few minutes it is actually slightly slower
because the cache has to fill again.

What cache cleaning is for is **fixing things**:

| Problem | What fixes it |
|---|---|
| A site loads on your phone but not your PC | Flush DNS |
| You changed router and things are weird | Clear ARP, renew IP |
| No internet after removing a VPN or an anti-virus | Winsock reset |
| Nothing works and you have tried everything | TCP/IP stack reset |
| Everything is slow and pages redirect oddly | Clear the proxy |
| Windows is eating your upload | Empty the Delivery Optimisation cache |

---

## If you only do five things

1. Turn off Wi-Fi power saving, and stop Windows turning the card off
2. Turn off Energy Efficient Ethernet on Realtek cards
3. Use a decent DNS server
4. Update the network driver from the maker's site, not Windows Update
5. On Ethernet, check you are actually linked at the speed your card supports

Everything else on this page is fine tuning. Do those five first.

---

## What will never help

- No registry tweak makes your internet package faster
- No setting on your PC fixes a bad line, a bad cable or a contended street cabinet
- If your ping to the game server is 80 ms because the server is 3000 km away, nothing here
  changes that. Physics wins
