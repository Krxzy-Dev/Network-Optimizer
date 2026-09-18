# Network Optimizer

A menu driven network cleaner and tuner for Windows 10 and 11. It finds your Wi-Fi and Ethernet
cards, shows you which one your internet is actually going through, and lets you clean the caches
and change the settings that make a real difference. Every change is backed up first and there is
a one click undo.

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)
![PSScriptAnalyzer](https://img.shields.io/badge/PSScriptAnalyzer-0%20warnings-brightgreen)
![Admin](https://img.shields.io/badge/needs-admin-orange)

---

## Contents

- [What it does](#what-it-does)
- [Quick start](#quick-start)
- [The menu](#the-menu)
- [Presets](#presets)
- [What each section does](#what-each-section-does)
- [What needs a reboot](#what-needs-a-reboot)
- [Safety, backup and undo](#safety-backup-and-undo)
- [Testing before and after](#testing-before-and-after)
- [Which tweaks actually help](#which-tweaks-actually-help)
- [Where it saves things](#where-it-saves-things)
- [Command line options](#command-line-options)
- [FAQ](#faq)
- [What it will not do](#what-it-will-not-do)
- [Sources](#sources)

---

## What it does

- Finds every Wi-Fi and Ethernet card, skips virtual ones like Hyper-V, VPNs and WSL unless you
  ask for them (menu 2, then 4)
- Tells you which card your internet is going out through
- Lets you work on Wi-Fi only, Ethernet only, or both
- Clears every network cache Windows keeps and can reset the whole TCP/IP stack
- Turns off the power saving that causes Wi-Fi lag spikes and Ethernet dropouts
- Reads your card's real driver settings instead of guessing, so it works on Intel, Realtek,
  Killer, Marvell and Aquantia without hard coding any brand
- Runs a ping, jitter, packet loss, DNS and download test on each card so you can compare
  Wi-Fi against Ethernet side by side
- Backs up everything to a JSON file and .reg files before it touches anything
- Has a dry run mode that shows you what would change without changing it

## Quick start

1. Download `NetworkOptimizer.ps1` and `Run.bat` into the same folder
2. Double click `Run.bat`
3. Say yes to the admin prompt
4. Start with option 1 to see what you have got, then option 7 and pick the Safe preset

`Run.bat` asks for admin and starts PowerShell with the execution policy bypassed, so you do not
have to mess about with any of that yourself. The script also checks for admin on its own if you
prefer to run the .ps1 directly.

## The menu

```
  1. Show me what I have got (all cards, speeds, IPs, DNS, TCP settings)
  2. Pick which cards to work on            [now: Both]
  3. Clean and reset caches
  4. TCP/IP tweaks and DNS
  5. Wi-Fi tweaks
  6. Ethernet tweaks
  7. Presets (Safe, Gaming, Full Clean, Custom)
  8. Speed and ping test, before and after
  9. Undo

  D. Dry run mode                          [now: OFF]
  L. Open the log and backup folder
  0. Quit
```

Items are colour coded. Grey and white are low risk, yellow means think about it first, red means
it can break something.

Nothing is applied until you have seen a full list of what will change and typed `y`.

## Presets

| Preset | What it does | Reboot | Who it is for |
|---|---|---|---|
| **Safe** | Cache cleaning plus the tweaks that help almost everyone. Power saving off, offloads on, jumbo frames off, auto tuning normal. | No | Everyone. Start here. |
| **Gaming** | Everything in Safe plus the latency tweaks: Nagle off, network throttling off, RSC off, interrupt moderation off, bigger buffers. | Yes | Gamers on a decent CPU. |
| **Full Clean and Reset** | Every cache cleared, Winsock reset, TCP/IP stack reset, proxy cleared, fresh IP. | Yes | When the network is broken and you want a clean slate. |
| **Custom** | A numbered list of all 35 tweaks. Pick the ones you want. | Depends | People who know what they are after. |

Each preset targets whatever you picked in menu option 2, so you can run Safe on Ethernet only and
leave your Wi-Fi alone.

## What each section does

### 3. Clean and reset caches

| Option | What it does | Risk |
|---|---|---|
| Flush DNS cache | Dumps saved name lookups, re-registers this PC in DNS | Low |
| Clear ARP cache | Wipes the list of which device has which address | Low |
| Clear route and destination cache | Throws away remembered paths, IPv4 and IPv6 | Low |
| Drop and grab a fresh IP | Release and renew, IPv4 and IPv6. You drop offline for a few seconds | Medium |
| Clear NetBIOS cache | Old style Windows name lookups for file shares | Low |
| Reset Winsock | Clears junk left by old VPNs and dodgy anti-virus. **Reboot** | Medium |
| Reset the TCP/IP stack | Back to factory. Static IPs and DNS you set by hand will go. **Reboot** | High |
| Clear the proxy | System proxy and the one in Internet Options. Adware loves leaving one behind | Medium |
| Empty Delivery Optimisation cache | Bins the update chunks Windows shares with other PCs | Low |
| Restart network services | DNS Client, DHCP Client, WLAN AutoConfig, Wired AutoConfig, NLA | Medium |
| Reset the firewall | **Wipes every firewall rule.** The firewall itself stays on | High |
| Bounce the card | Off and on again. Clears a stuck link | Medium |

### 4. TCP/IP tweaks and DNS

| Option | What it does | Risk |
|---|---|---|
| Auto tuning to normal | The Windows default. Right for nearly everyone | Low |
| Receive Side Scaling on | Spreads incoming traffic over several CPU cores | Low |
| RSC off | Stops small packets being glued together. Tiny latency win, costs CPU | Medium |
| ECN on | Lets routers say they are getting full. Off by default, some old routers hate it | Medium |
| TCP timestamps off | Saves 12 bytes a packet. Windows ships with it off anyway | Low |
| Initial RTO to 2000 ms | Retries a dead connection quicker. Barely noticeable | Medium |
| Congestion control to CUBIC | Falls back to CTCP on older builds | Medium |
| Network throttling off | Can help a gaming PC, can make audio crackle on a weak one. **Reboot** | Medium |
| Nagle off | Stops tiny packets being held back. A few ms off games. **Reboot** | Medium |
| QoS reservable bandwidth to 0 | Honestly: this does next to nothing. It is here because people ask | Low |
| **D.** DNS switcher | Cloudflare 1.1.1.1, Google 8.8.8.8, Quad9 9.9.9.9, or back to automatic | Low |
| **E.** Encrypted DNS | DNS over HTTPS. Windows 11 only | Low |
| **S.** Show TCP settings | Prints the current settings with the auto tuning levels explained | None |

### 5. Wi-Fi tweaks

| Option | What it does | Risk |
|---|---|---|
| Wi-Fi power saving off | The biggest fix for random Wi-Fi lag spikes on laptops. Eats battery | Low |
| Prefer 5 GHz | Picks 5 GHz over 2.4 GHz when both are there | Low |
| Transmit power on full | Helps if you are far from the router | Low |
| Background scanning down | Stops the blip every few seconds. Makes roaming slower | Medium |
| **S.** Show Wi-Fi info | Signal, band, channel, radio type, link speed | None |
| **P.** Browse driver settings | Every setting your card actually has, change them one by one | Varies |
| **R.** Wi-Fi drop report | Builds the HTML report of the last three days of connects and drops | None |
| **C.** Bounce the card | Off and on again | Medium |

### 6. Ethernet tweaks

| Option | What it does | Risk |
|---|---|---|
| EEE and Green Ethernet off | Stops the dropouts a lot of Realtek cards get every few minutes | Low |
| Stop Windows switching the card off | Unticks the Device Manager power box | Low |
| Driver power saving off | Selective suspend, sleep on unplug and the rest | Low |
| Checksum and LSO on | Hands the boring maths to the card instead of your CPU | Low |
| Receive and transmit buffers up | Fewer dropped packets when things get busy | Low |
| Flow Control on | Card asks the switch to slow down instead of dropping packets | Low |
| Interrupt Moderation off | Lowest possible ping, more CPU use | Medium |
| Jumbo Frames off | The safe setting. Off unless every device on your network does them | Low |
| Speed and duplex to Auto | Auto is nearly always right | Low |
| **J.** Jumbo Frames ON | With a warning you have to read first | Medium |
| **F.** Force speed and duplex | Only if you know the other end is broken | Medium |
| **W.** Wake on LAN | Turn it on or off | Low |
| **D.** Driver version | Shows your driver, warns if it is over two years old, links to the makers | None |
| **C.** Bounce the card | Off and on again | Medium |

If your gigabit card is sitting at 100 Mbps, option 1 will warn you. Nine times out of ten that is
a bad cable or a bad port, not a setting.

## What needs a reboot

Only these five:

- Reset Winsock
- Reset the TCP/IP stack
- Network throttling off
- Nagle off
- QoS reservable bandwidth to 0

The script keeps track and tells you at the end if a reboot is waiting. Everything else takes
effect straight away, though a few driver settings only settle properly after you bounce the card.

## Safety, backup and undo

Before it changes anything it will:

1. Export every registry key it touches to timestamped `.reg` files
2. Save the current value of every TCP setting, every Wi-Fi and Ethernet driver setting, every
   power setting and your DNS servers to `original-settings.json`
3. Offer to make a System Restore point

To undo, pick **9** from the main menu:

- **Option 1** puts everything back from the newest backup, setting by setting
- **Option 2** forces everything back to Windows and driver defaults, for when the backup is gone
- **Option 3** lets you pick an older backup folder

**Dry run mode** (`D` on the main menu) does a full run and prints every single thing it would do,
without doing any of it. Good for a first look.

Every action, result and error goes in a timestamped log. Every step is wrapped in its own
try/catch, so one thing failing does not stop the rest.

## Testing before and after

Menu option 8 runs, per card:

- Ping to 1.1.1.1, 8.8.8.8 and 9.9.9.9, twenty pings each
- Jitter, worked out from the gap between one ping and the next
- Packet loss
- DNS lookup time against three real sites
- A 25 MB download from Cloudflare's speed test

The ping, jitter, loss and DNS tests are pinned to each card's own IP address, so you get a real
Wi-Fi against Ethernet comparison. The download test tries to pin itself too and falls back to the
default route if Windows will not let it, which it will tell you in the log.

Run the before test, apply your tweaks, then run the after test. You get a table like this:

```
Card                   Type         Ping ms  Jitter ms   Loss %     DNS ms   Down Mbps
--------------------------------------------------------------------------------------
Wi-Fi                  WiFi            24.5        6.2        1         41       118.4
  after                                18.1        2.1        0         12       131.9
  verdict: ping 6.4 ms better, jitter 4.1 ms better, download 13.5 Mbps different
```

Internet speeds bounce around on their own, so run it a few times before you decide anything.

## Which tweaks actually help

Short version:

| Tweak | Real world effect |
|---|---|
| Wi-Fi power saving off | **Big.** Fixes lag spikes and dropouts on laptops |
| EEE / Green Ethernet off | **Big** on Realtek cards that drop the link every few minutes |
| Stop Windows turning the card off | **Big** if you get random disconnects |
| Faster DNS server | **Noticeable.** Pages start loading sooner. Does not change your speed |
| Flush DNS / ARP / Winsock reset | **Big when broken, nothing when fine.** Fixes, not speed ups |
| Receive buffers up | **Small to medium** on a busy or gigabit plus connection |
| Nagle off | **Small.** A few ms in games, and it costs you on slow lines |
| Interrupt Moderation off | **Small.** Under a millisecond, and more CPU use |
| Auto tuning, RSS, offloads | **Nothing if already default.** They are on by default. Worth checking, not worth bragging about |
| Network throttling off | **Nothing to small.** Only matters if a media app is hogging the scheduler |
| QoS reservable bandwidth | **Nothing.** The 20 percent was never being wasted |

The full honest breakdown, per tweak, for Wi-Fi and Ethernet separately, is in
[docs/WHAT-ACTUALLY-HELPS.md](docs/WHAT-ACTUALLY-HELPS.md).

## Where it saves things

```
C:\ProgramData\NetworkOptimiser\
    last-run.txt                  points at the newest run
    run_2026-09-18_14-22-01\
        log.txt                   everything it did, with times and errors
        original-settings.json    your settings before the changes
        registry-backup\          .reg files you can double click to restore
```

Menu option `L` opens that folder.

## Command line options

```powershell
.\NetworkOptimizer.ps1                              # normal menu
.\NetworkOptimizer.ps1 -DryRun                      # menu, but nothing gets changed
.\NetworkOptimizer.ps1 -Preset Safe                 # run a preset and quit
.\NetworkOptimizer.ps1 -Preset Gaming -Target WiFi  # gaming preset, Wi-Fi only
```

`-Preset` takes `Safe`, `Gaming` or `FullClean`. `-Target` takes `WiFi`, `Ethernet` or `Both`.
You still get asked to confirm before anything changes.

## FAQ

**Will this make my internet package faster?**
No. Nothing on your PC can make a 50 Mbps line into a 500 Mbps line. What it can fix is your PC
wasting some of what you already pay for, and the lag spikes that come from power saving.

**Is it safe?**
The Safe preset is. Everything is backed up first and there is an undo. The two high risk items
(reset the TCP/IP stack, reset the firewall) are marked in red and are not in any preset except
Full Clean.

**Does it turn off Windows Defender, the firewall or Windows Update?**
No, and it never will. The firewall reset puts the rules back to default and leaves the firewall
switched ON. Emptying the Delivery Optimisation cache does not stop updates.

**Will it work on my Realtek / Intel / Killer card?**
Yes. It reads the settings your driver actually exposes and matches on both the display name and
the registry keyword, so it does not care which brand you have. If your card does not have a
setting, it says so and skips it instead of failing.

**Why does it say a setting was skipped?**
Because your card does not have it. Different drivers expose different things. That is normal.

**Something broke, what now?**
Menu option 9, then option 1. If that is not enough, option 2 forces everything back to defaults.
If that is still not enough, use the System Restore point.

## What it will not do

- It will not touch Defender, the firewall state, or Windows Update
- It will not enable TCP Chimney Offload or IPsec Task Offload. Microsoft deprecated both and says
  they can hurt performance
- It will not use made up registry keys or Windows XP era tweaks
- It will not promise you numbers it cannot deliver

## Sources

Every tweak in this tool comes from Microsoft documentation or a well known optimiser. The list of
which tweak came from where is in [docs/SOURCES.md](docs/SOURCES.md).

---

Use this at your own risk. It backs your settings up and it can put them back, but it is still
changing system settings on your PC.
