#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$DryRun,
    [ValidateSet('Safe', 'Gaming', 'FullClean')]
    [string]$Preset,
    [ValidateSet('WiFi', 'Ethernet', 'Both')]
    [string]$Target = 'Both'
)

$ErrorActionPreference = 'Stop'

$Script:Cfg = [pscustomobject]@{
    Title     = 'Network Cleaner and Optimiser'
    Version   = '1.0.0'
    Stamp     = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
    Home      = (Join-Path -Path $env:ProgramData -ChildPath 'NetworkOptimiser')
    Run       = $null
    LogFile   = $null
    StateFile = $null
    RegFolder = $null
    DryRun    = [bool]$DryRun
    Target    = $Target
    Preset    = $Preset
    Virtual   = $false
    Reboot    = $false
    Tested    = [ordered]@{ Before = $null; After = $null }
}

function Write-Ui {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'This is a console tool, the coloured output is the interface')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [ValidateSet('Plain', 'Head', 'Ok', 'Warn', 'Bad', 'Dim', 'Ask')][string]$Style = 'Plain'
    )
    $colour = switch ($Style) {
        'Head' { 'Cyan' }
        'Ok' { 'Green' }
        'Warn' { 'Yellow' }
        'Bad' { 'Red' }
        'Dim' { 'DarkGray' }
        'Ask' { 'White' }
        default { 'Gray' }
    }
    Write-Host $Text -ForegroundColor $colour
}

function Write-RunLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DRYRUN')][string]$Level = 'INFO'
    )
    if (-not $Script:Cfg.LogFile) { return }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    try {
        Add-Content -LiteralPath $Script:Cfg.LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Ui -Text "Could not write to the log file: $($_.Exception.Message)" -Style 'Bad'
    }
}

function Write-Head {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text ('=' * 66) -Style 'Head'
    Write-Ui -Text "  $Text" -Style 'Head'
    Write-Ui -Text ('=' * 66) -Style 'Head'
    Write-RunLog -Message "--- $Text ---"
}

function Test-Admin {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    Write-Ui -Text 'This needs admin rights. Asking Windows for them now...' -Style 'Warn'
    $psExe = (Get-Process -Id $PID).Path
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Script:Cfg.DryRun) { $argList += '-DryRun' }
    if ($Script:Cfg.Preset) { $argList += @('-Preset', $Script:Cfg.Preset) }
    $argList += @('-Target', $Script:Cfg.Target)
    try {
        Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Ui -Text 'You said no to the admin prompt, so nothing can be done. Closing.' -Style 'Bad'
        Start-Sleep -Seconds 3
    }
}

function Initialize-Workspace {
    $Script:Cfg.Run = Join-Path -Path $Script:Cfg.Home -ChildPath ('run_' + $Script:Cfg.Stamp)
    $Script:Cfg.RegFolder = Join-Path -Path $Script:Cfg.Run -ChildPath 'registry-backup'
    $Script:Cfg.LogFile = Join-Path -Path $Script:Cfg.Run -ChildPath 'log.txt'
    $Script:Cfg.StateFile = Join-Path -Path $Script:Cfg.Run -ChildPath 'original-settings.json'
    foreach ($dir in @($Script:Cfg.Home, $Script:Cfg.Run, $Script:Cfg.RegFolder)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    Write-RunLog -Message "$($Script:Cfg.Title) $($Script:Cfg.Version) started. Dry run: $($Script:Cfg.DryRun)"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @()
    )
    $text = ''
    $code = 0
    try {
        $raw = & $File @Arguments 2>&1
        $code = $LASTEXITCODE
        $text = ($raw | Out-String).Trim()
    } catch {
        $code = 1
        $text = $_.Exception.Message
    }
    Write-RunLog -Message "ran: $File $($Arguments -join ' ') -> exit $code"
    return [pscustomobject]@{ Code = $code; Text = $text }
}

function Invoke-Action {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Work,
        [switch]$NeedsReboot
    )
    if ($Script:Cfg.DryRun) {
        Write-Ui -Text "  [dry run] would do: $Label" -Style 'Dim'
        Write-RunLog -Level 'DRYRUN' -Message $Label
        return $true
    }
    try {
        $note = & $Work
        $tail = ''
        if ($note -is [string] -and $note.Length -gt 0) { $tail = " - $note" }
        Write-Ui -Text "  OK   $Label$tail" -Style 'Ok'
        Write-RunLog -Level 'OK' -Message "$Label$tail"
        if ($NeedsReboot) { $Script:Cfg.Reboot = $true }
        return $true
    } catch {
        Write-Ui -Text "  FAIL $Label" -Style 'Bad'
        Write-Ui -Text "       $($_.Exception.Message)" -Style 'Dim'
        Write-RunLog -Level 'ERROR' -Message "$Label :: $($_.Exception.Message)"
        return $false
    }
}

function Read-Choice {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Needs to print the prompt without a line break')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [string]$Default = ''
    )
    $suffix = if ($Default) { " [$Default]" } else { '' }
    Write-Ui -Text '' -Style 'Plain'
    Write-Host "$Question$suffix " -ForegroundColor White -NoNewline
    $answer = Read-Host
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Confirm-Go {
    param([string]$Question = 'Go ahead?')
    $answer = Read-Choice -Question "$Question (y/n)" -Default 'n'
    return ($answer -match '^(y|yes)$')
}

function Wait-Key {
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'Press Enter to go back to the menu.' -Style 'Dim'
    [void](Read-Host)
}

$Script:VirtualHint = @(
    'Hyper-V', 'vEthernet', 'VirtualBox', 'VMware', 'Virtual Adapter', 'Virtual Ethernet',
    'TAP-Windows', 'TAP Adapter', 'OpenVPN', 'WireGuard', 'NordLynx', 'Tailscale', 'ZeroTier',
    'Hamachi', 'Radmin', 'AnyConnect', 'Docker', 'WSL', 'Loopback', 'WAN Miniport',
    'Bluetooth', 'Npcap', 'Teredo', 'ISATAP', 'Kernel Debug', 'PANGP', 'Check Point', 'Sangfor'
)

function Test-VirtualAdapter {
    param([Parameter(Mandatory = $true)]$Adapter)
    $text = "$($Adapter.InterfaceDescription) $($Adapter.Name)"
    foreach ($hint in $Script:VirtualHint) {
        if ($text -like "*$hint*") { return $true }
    }
    if (($Adapter.PSObject.Properties.Name -contains 'Virtual') -and ($Adapter.Virtual -eq $true)) { return $true }
    return $false
}

function Get-AdapterKind {
    param([Parameter(Mandatory = $true)]$Adapter)
    $media = "$($Adapter.PhysicalMediaType) $($Adapter.MediaType)"
    if ($media -like '*802.11*' -or $media -like '*Wireless*') { return 'WiFi' }
    if ($media -like '*802.3*') { return 'Ethernet' }
    return 'Other'
}

function Get-TargetAdapter {
    param(
        [switch]$IncludeVirtual,
        [switch]$IncludeDown
    )
    $found = @()
    try {
        $raw = @(Get-NetAdapter -ErrorAction Stop)
    } catch {
        Write-Ui -Text "Could not read your network cards: $($_.Exception.Message)" -Style 'Bad'
        return @()
    }
    foreach ($a in $raw) {
        $virtual = Test-VirtualAdapter -Adapter $a
        if ($virtual -and -not ($IncludeVirtual -or $Script:Cfg.Virtual)) { continue }
        if ($a.Status -ne 'Up' -and -not $IncludeDown) { continue }
        $ip4 = $null
        $gw = $null
        $dns = @()
        try {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction Stop
            if ($cfg.IPv4Address) { $ip4 = ($cfg.IPv4Address | Select-Object -First 1).IPAddress }
            if ($cfg.IPv4DefaultGateway) { $gw = ($cfg.IPv4DefaultGateway | Select-Object -First 1).NextHop }
            if ($cfg.DNSServer) { $dns = @($cfg.DNSServer.ServerAddresses) }
        } catch {
            Write-RunLog -Level 'WARN' -Message "No IP config for $($a.Name): $($_.Exception.Message)"
        }
        $found += [pscustomobject]@{
            Name      = $a.Name
            Desc      = $a.InterfaceDescription
            Index     = $a.ifIndex
            Guid      = $a.InterfaceGuid
            Kind      = (Get-AdapterKind -Adapter $a)
            Status    = $a.Status
            Speed     = $a.LinkSpeed
            SpeedBps  = $a.TransmitLinkSpeed
            Duplex    = $a.FullDuplex
            Mac       = $a.MacAddress
            Driver    = $a.DriverVersionString
            DriverDay = $a.DriverDate
            Virtual   = $virtual
            IPv4      = $ip4
            Gateway   = $gw
            Dns       = $dns
        }
    }
    return @($found)
}

function Select-ScopedAdapter {
    param([object[]]$Adapter)
    switch ($Script:Cfg.Target) {
        'WiFi' { return @($Adapter | Where-Object { $_.Kind -eq 'WiFi' }) }
        'Ethernet' { return @($Adapter | Where-Object { $_.Kind -eq 'Ethernet' }) }
        default { return @($Adapter | Where-Object { $_.Kind -in @('WiFi', 'Ethernet') }) }
    }
}

$Script:PropMap = [ordered]@{
    'EEE'         = @{
        Title   = 'Energy Efficient Ethernet / Green Ethernet'
        Keyword = @('*EEE', 'EEELinkAdvertisement', 'AdvancedEEE', 'EnableGreenEthernet', 'GreenEthernet', 'EnableSavePowerNow', 'PowerSavingMode')
        Display = @('*Energy*Efficient*', '*Green Ethernet*', '*EEE*', '*Power Saving Mode*', '*Gigabit Lite*', '*Ultra Low Power*')
        Prefer  = @('Disabled', 'Off', 'Disable')
    }
    'PowerSave'   = @{
        Title   = 'Card power saving'
        Keyword = @('EnablePME', 'EnableDynamicPowerGating', 'ReduceSpeedOnPowerDown', 'AutoPowerSaveModeEnabled', 'SelectiveSuspend', '*SelectiveSuspend', 'EnableModernStandby')
        Display = @('*Selective Suspend*', '*Power Saving*', '*Reduce Speed On Power Down*', '*Auto Power Save*', '*System Idle Power Saver*')
        Prefer  = @('Disabled', 'Off', 'Disable')
    }
    'IntMod'      = @{
        Title   = 'Interrupt Moderation'
        Keyword = @('*InterruptModeration', 'InterruptModeration')
        Display = @('*Interrupt Moderation*')
        Prefer  = @('Disabled', 'Off')
    }
    'IntModRate'  = @{
        Title   = 'Interrupt Moderation Rate'
        Keyword = @('ITR', 'InterruptModerationRate', '*InterruptModerationRate')
        Display = @('*Interrupt Moderation Rate*')
        Prefer  = @('Off', 'Minimal', 'Low')
    }
    'FlowControl' = @{
        Title   = 'Flow Control'
        Keyword = @('*FlowControl', 'FlowControl')
        Display = @('*Flow Control*')
        Prefer  = @('Rx & Tx Enabled', 'Rx and Tx Enabled', 'Enabled')
    }
    'RxBuffers'   = @{
        Title   = 'Receive Buffers'
        Keyword = @('*ReceiveBuffers', 'ReceiveBuffers', 'RxDesc', 'NumRxDesc')
        Display = @('*Receive Buffers*', '*Receive Descriptors*')
        Prefer  = @()
    }
    'TxBuffers'   = @{
        Title   = 'Transmit Buffers'
        Keyword = @('*TransmitBuffers', 'TransmitBuffers', 'TxDesc', 'NumTxDesc')
        Display = @('*Transmit Buffers*', '*Transmit Descriptors*')
        Prefer  = @()
    }
    'Lso'         = @{
        Title   = 'Large Send Offload v2'
        Keyword = @('*LsoV2IPv4', '*LsoV2IPv6')
        Display = @('*Large Send Offload*')
        Prefer  = @('Enabled', 'On')
    }
    'Checksum'    = @{
        Title   = 'Checksum offloads'
        Keyword = @('*IPChecksumOffloadIPv4', '*TCPChecksumOffloadIPv4', '*TCPChecksumOffloadIPv6', '*UDPChecksumOffloadIPv4', '*UDPChecksumOffloadIPv6')
        Display = @('*Checksum Offload*')
        Prefer  = @('Rx & Tx Enabled', 'Rx and Tx Enabled', 'Enabled')
    }
    'Jumbo'       = @{
        Title   = 'Jumbo Frames'
        Keyword = @('*JumboPacket', 'JumboPacket', 'MTU')
        Display = @('*Jumbo*')
        Prefer  = @()
    }
    'Rss'         = @{
        Title   = 'Receive Side Scaling'
        Keyword = @('*RSS', 'RSS')
        Display = @('*Receive Side Scaling*', '*RSS*')
        Prefer  = @('Enabled', 'On')
    }
    'Rsc'         = @{
        Title   = 'Receive Segment Coalescing'
        Keyword = @('*RscIPv4', '*RscIPv6')
        Display = @('*Recv Segment Coalescing*', '*Receive Segment Coalescing*')
        Prefer  = @('Disabled', 'Off')
    }
    'SpeedDuplex' = @{
        Title   = 'Speed and Duplex'
        Keyword = @('*SpeedDuplex', 'SpeedDuplex', 'RequestedMediaType')
        Display = @('*Speed*Duplex*', '*Link Speed*')
        Prefer  = @('Auto Negotiation', 'Auto-Negotiation', 'Auto')
    }
    'Wol'         = @{
        Title   = 'Wake on LAN'
        Keyword = @('*WakeOnMagicPacket', '*WakeOnPattern', 'WakeOnLink', 'WakeOnSlot', 'EnableWakeOnLan')
        Display = @('*Wake on*', '*Wake Up*')
        Prefer  = @()
    }
    'Roam'        = @{
        Title   = 'Roaming aggressiveness'
        Keyword = @('RoamAggressiveness', 'RoamSensitivityLevel', 'RoamTendency', 'RoamingAggressiveness', 'ScanValidPeriod')
        Display = @('*Roaming*', '*Roam*')
        Prefer  = @()
    }
    'Band'        = @{
        Title   = 'Preferred band'
        Keyword = @('RoamingPreferredBandType', 'PreferredBand', 'BandPreference', 'VHTMode', 'Band')
        Display = @('*Preferred Band*', '*Band Preference*', '*Prefer*GHz*')
        Prefer  = @()
    }
    'TxPower'     = @{
        Title   = 'Transmit power'
        Keyword = @('TransmitPower', 'TxPowerLevel', 'TxPower', 'PowerLevel')
        Display = @('*Transmit Power*', '*Tx Power*')
        Prefer  = @('Highest', 'High', '100%')
    }
    'WifiMode'    = @{
        Title   = '802.11 wireless mode'
        Keyword = @('WirelessMode', '802.11a/b/g Wireless Mode', 'VHTMode', 'HTMode')
        Display = @('*Wireless Mode*', '*802.11*Mode*')
        Prefer  = @()
    }
    'MimoPower'   = @{
        Title   = 'MIMO power save'
        Keyword = @('MimoPowerSaveMode', 'MIMOPowerSaveMode', 'SmpsMode')
        Display = @('*MIMO Power Save*')
        Prefer  = @('No SMPS', 'Disabled', 'Off')
    }
    'ScanIdle'    = @{
        Title   = 'Background scanning while connected'
        Keyword = @('ScanWhenAssociated', 'BackgroundScan', 'ScanDisableMode')
        Display = @('*Scan*Associated*', '*Background Scan*')
        Prefer  = @('Disabled', 'Off')
    }
}

function Get-AdapterProperty {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Key
    )
    if (-not $Script:PropMap.Contains($Key)) { return @() }
    $map = $Script:PropMap[$Key]
    try {
        $all = @(Get-NetAdapterAdvancedProperty -Name $Adapter.Name -AllProperties -ErrorAction Stop)
    } catch {
        Write-RunLog -Level 'WARN' -Message "No advanced properties on $($Adapter.Name): $($_.Exception.Message)"
        return @()
    }
    $hits = @()
    foreach ($p in $all) {
        $match = $false
        foreach ($k in $map.Keyword) { if ($p.RegistryKeyword -eq $k) { $match = $true } }
        if (-not $match) {
            foreach ($d in $map.Display) { if ($p.DisplayName -like $d) { $match = $true } }
        }
        if ($match) { $hits += $p }
    }
    return @($hits)
}

function Set-AdapterProperty {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Property,
        [string[]]$Prefer = @(),
        [string]$Value = ''
    )
    $pick = $Value
    if (-not $pick) {
        $valid = @()
        if ($Property.PSObject.Properties.Name -contains 'ValidDisplayValues' -and $Property.ValidDisplayValues) {
            $valid = @($Property.ValidDisplayValues)
        }
        foreach ($want in $Prefer) {
            $hit = $valid | Where-Object { $_ -eq $want } | Select-Object -First 1
            if ($hit) { $pick = $hit; break }
        }
        if (-not $pick) {
            foreach ($want in $Prefer) {
                $hit = $valid | Where-Object { $_ -like "*$want*" } | Select-Object -First 1
                if ($hit) { $pick = $hit; break }
            }
        }
    }
    if (-not $pick) { throw "This card has no value that matches [$($Prefer -join ', ')] for '$($Property.DisplayName)'." }
    if ($Property.DisplayValue -eq $pick) { return "already $pick" }
    if ($PSCmdlet.ShouldProcess($Property.DisplayName, "set to $pick")) {
        Set-NetAdapterAdvancedProperty -Name $Property.Name -DisplayName $Property.DisplayName -DisplayValue $pick -NoRestart -ErrorAction Stop
    }
    return "$($Property.DisplayName) -> $pick"
}

function Set-PropertyGroup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Key,
        [string[]]$Prefer = @()
    )
    $map = $Script:PropMap[$Key]
    $want = if ($Prefer.Count -gt 0) { $Prefer } else { $map.Prefer }
    $props = Get-AdapterProperty -Adapter $Adapter -Key $Key
    if ($props.Count -eq 0) { return "this card has no '$($map.Title)' setting, skipped" }
    $done = @()
    foreach ($p in $props) {
        try {
            if ($PSCmdlet.ShouldProcess($p.DisplayName, 'change')) {
                $done += (Set-AdapterProperty -Property $p -Prefer $want)
            }
        } catch {
            Write-RunLog -Level 'WARN' -Message "$($Adapter.Name) / $($p.DisplayName): $($_.Exception.Message)"
            $done += "$($p.DisplayName) could not be changed"
        }
    }
    return ($done -join '; ')
}

$Script:RegTouched = @(
    'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched',
    'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters',
    'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces',
    'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters',
    'HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters',
    'HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
)

function Backup-RegistryKey {
    $ok = 0
    foreach ($key in $Script:RegTouched) {
        $safe = ($key -replace '[\\ ]', '_')
        $file = Join-Path -Path $Script:Cfg.RegFolder -ChildPath "$safe.reg"
        $res = Invoke-Native -File 'reg.exe' -Arguments @('export', $key, $file, '/y')
        if ($res.Code -eq 0) { $ok++ } else { Write-RunLog -Level 'WARN' -Message "reg export skipped $key : $($res.Text)" }
    }
    return "$ok of $($Script:RegTouched.Count) keys saved to $($Script:Cfg.RegFolder)"
}

function Get-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

function Set-RegistryValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [ValidateSet('DWord', 'String', 'QWord')][string]$Type = 'DWord'
    )
    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", "set to $Value")) { return }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    if ($null -eq $Value) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
    }
}

function Get-DevicePowerState {
    param([Parameter(Mandatory = $true)]$Adapter)
    try {
        $nic = Get-NetAdapter -Name $Adapter.Name -ErrorAction Stop
        $pnp = $nic.PnPDeviceID
        if (-not $pnp) { return $null }
        $rows = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSPower_DeviceEnable' -ErrorAction Stop)
        foreach ($row in $rows) {
            if ($row.InstanceName -like "$pnp*") { return $row }
        }
        return $null
    } catch {
        Write-RunLog -Level 'WARN' -Message "Device power state not readable for $($Adapter.Name): $($_.Exception.Message)"
        return $null
    }
}

function Disable-DevicePowerOff {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory = $true)]$Adapter)
    $row = Get-DevicePowerState -Adapter $Adapter
    if ($null -eq $row) { return 'this card does not expose that setting, skipped' }
    if ($row.Enable -eq $false) { return 'already off' }
    if ($PSCmdlet.ShouldProcess($Adapter.Name, 'stop Windows turning this card off')) {
        Set-CimInstance -InputObject $row -Property @{ Enable = $false } -ErrorAction Stop
    }
    return 'Windows can no longer switch this card off to save power'
}

function Get-InterfaceRegistryPath {
    param([Parameter(Mandatory = $true)]$Adapter)
    return "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($Adapter.Guid)"
}

function Save-NetworkState {
    $state = [ordered]@{
        Stamp   = $Script:Cfg.Stamp
        Script  = $Script:Cfg.Version
        Windows = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        Tcp     = @()
        TcpText = ''
        Reg     = @()
        Cards   = @()
    }
    try {
        $state.Tcp = @(Get-NetTCPSetting -ErrorAction Stop | Select-Object -Property SettingName, AutoTuningLevelLocal,
            CongestionProvider, EcnCapability, Timestamps, InitialRtoMs, MinRtoMs, ScalingHeuristics, NonSackRttResiliency)
    } catch {
        Write-RunLog -Level 'WARN' -Message "TCP settings not readable: $($_.Exception.Message)"
    }
    $state.TcpText = (Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'show', 'global')).Text

    $regList = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Type = 'DWord' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Type = 'DWord' },
        @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'; Name = 'NonBestEffortLimit'; Type = 'DWord' }
    )
    foreach ($r in $regList) {
        $state.Reg += [ordered]@{ Path = $r.Path; Name = $r.Name; Type = $r.Type; Value = (Get-RegistryValue -Path $r.Path -Name $r.Name) }
    }

    foreach ($card in (Get-TargetAdapter -IncludeDown)) {
        $adv = @()
        try {
            foreach ($p in (Get-NetAdapterAdvancedProperty -Name $card.Name -AllProperties -ErrorAction Stop)) {
                $adv += [ordered]@{
                    DisplayName  = $p.DisplayName
                    Keyword      = $p.RegistryKeyword
                    DisplayValue = $p.DisplayValue
                    RegValue     = @($p.RegistryValue)
                }
            }
        } catch {
            Write-RunLog -Level 'WARN' -Message "Advanced properties not saved for $($card.Name): $($_.Exception.Message)"
        }
        $power = $null
        try {
            $pm = Get-NetAdapterPowerManagement -Name $card.Name -ErrorAction Stop
            $power = [ordered]@{
                ArpOffload             = "$($pm.ArpOffload)"
                NSOffload              = "$($pm.NSOffload)"
                D0PacketCoalescing     = "$($pm.D0PacketCoalescing)"
                DeviceSleepOnDisconnect = "$($pm.DeviceSleepOnDisconnect)"
                RsnRekeyOffload        = "$($pm.RsnRekeyOffload)"
                SelectiveSuspend       = "$($pm.SelectiveSuspend)"
                WakeOnMagicPacket      = "$($pm.WakeOnMagicPacket)"
                WakeOnPattern          = "$($pm.WakeOnPattern)"
            }
        } catch {
            Write-RunLog -Level 'WARN' -Message "Power settings not saved for $($card.Name): $($_.Exception.Message)"
        }
        $devRow = Get-DevicePowerState -Adapter $card
        $ifPath = Get-InterfaceRegistryPath -Adapter $card
        $state.Cards += [ordered]@{
            Name        = $card.Name
            Guid        = "$($card.Guid)"
            Kind        = $card.Kind
            Desc        = $card.Desc
            Advanced    = $adv
            Power       = $power
            DeviceEnable = if ($null -eq $devRow) { $null } else { [bool]$devRow.Enable }
            DnsV4       = @($card.Dns)
            AckFreq     = (Get-RegistryValue -Path $ifPath -Name 'TcpAckFrequency')
            NoDelay     = (Get-RegistryValue -Path $ifPath -Name 'TCPNoDelay')
        }
    }
    $json = $state | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $Script:Cfg.StateFile -Value $json -Encoding UTF8 -ErrorAction Stop
    Set-Content -LiteralPath (Join-Path -Path $Script:Cfg.Home -ChildPath 'last-run.txt') -Value $Script:Cfg.Run -Encoding UTF8 -ErrorAction Stop
    return "saved $($state.Cards.Count) cards to $($Script:Cfg.StateFile)"
}

function Checkpoint-System {
    $drive = $env:SystemDrive
    try {
        Enable-ComputerRestore -Drive $drive -ErrorAction Stop
    } catch {
        Write-RunLog -Level 'WARN' -Message "Could not turn on System Restore: $($_.Exception.Message)"
    }
    $freqPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    # windows refuses a second restore point within 24h unless this is 0
    $oldFreq = Get-RegistryValue -Path $freqPath -Name 'SystemRestorePointCreationFrequency'
    try {
        Set-RegistryValue -Path $freqPath -Name 'SystemRestorePointCreationFrequency' -Value 0 -Type 'DWord'
        Checkpoint-Computer -Description "Before Network Optimiser $($Script:Cfg.Stamp)" -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    } finally {
        if ($null -ne $oldFreq) {
            Set-RegistryValue -Path $freqPath -Name 'SystemRestorePointCreationFrequency' -Value $oldFreq -Type 'DWord'
        }
    }
    return 'restore point made'
}

function Get-LastRunFolder {
    $pointer = Join-Path -Path $Script:Cfg.Home -ChildPath 'last-run.txt'
    if (Test-Path -LiteralPath $pointer) {
        $path = (Get-Content -LiteralPath $pointer -Raw -ErrorAction SilentlyContinue).Trim()
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    $runs = @(Get-ChildItem -LiteralPath $Script:Cfg.Home -Directory -Filter 'run_*' -ErrorAction SilentlyContinue |
        Sort-Object -Property Name -Descending)
    if ($runs.Count -gt 0) { return $runs[0].FullName }
    return $null
}

function Restore-NetworkState {
    param([Parameter(Mandatory = $true)][string]$Folder)
    $file = Join-Path -Path $Folder -ChildPath 'original-settings.json'
    if (-not (Test-Path -LiteralPath $file)) { throw "No saved settings in $Folder" }
    $state = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json

    foreach ($r in $state.Reg) {
        $label = "put back $($r.Name)"
        [void](Invoke-Action -Label $label -Work {
            if ($null -eq $r.Value) {
                if (Test-Path -LiteralPath $r.Path) {
                    Remove-ItemProperty -LiteralPath $r.Path -Name $r.Name -Force -ErrorAction SilentlyContinue
                }
                return 'removed (it was not there before)'
            }
            Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.Value -Type $r.Type
            return "back to $($r.Value)"
        }.GetNewClosure())
    }

    foreach ($card in $state.Cards) {
        $live = Get-NetAdapter -Name $card.Name -ErrorAction SilentlyContinue
        if ($null -eq $live) {
            Write-Ui -Text "  SKIP $($card.Name) is not plugged in any more" -Style 'Warn'
            continue
        }
        Write-Ui -Text "  Card: $($card.Name)" -Style 'Plain'
        foreach ($p in $card.Advanced) {
            $now = Get-NetAdapterAdvancedProperty -Name $card.Name -RegistryKeyword $p.Keyword -ErrorAction SilentlyContinue
            if ($null -eq $now) { continue }
            if ("$($now.DisplayValue)" -eq "$($p.DisplayValue)") { continue }
            [void](Invoke-Action -Label "$($p.DisplayName) back to $($p.DisplayValue)" -Work {
                Set-NetAdapterAdvancedProperty -Name $card.Name -RegistryKeyword $p.Keyword -RegistryValue $p.RegValue -NoRestart -ErrorAction Stop
                return $null
            }.GetNewClosure())
        }
        if ($null -ne $card.Power) {
            [void](Invoke-Action -Label "power settings back on $($card.Name)" -Work {
                $splat = @{ Name = $card.Name; NoRestart = $true; ErrorAction = 'Stop' }
                foreach ($k in @('ArpOffload', 'NSOffload', 'D0PacketCoalescing', 'DeviceSleepOnDisconnect', 'RsnRekeyOffload', 'SelectiveSuspend', 'WakeOnMagicPacket', 'WakeOnPattern')) {
                    $v = $card.Power.$k
                    if ($v -in @('Enabled', 'Disabled')) { $splat[$k] = $v }
                }
                Set-NetAdapterPowerManagement @splat
                return $null
            }.GetNewClosure())
        }
        if ($null -ne $card.DeviceEnable) {
            [void](Invoke-Action -Label "'let Windows turn this card off' back on $($card.Name)" -Work {
                $fake = [pscustomobject]@{ Name = $card.Name; Guid = $card.Guid }
                $row = Get-DevicePowerState -Adapter $fake
                if ($null -eq $row) { return 'not available' }
                Set-CimInstance -InputObject $row -Property @{ Enable = [bool]$card.DeviceEnable } -ErrorAction Stop
                return $null
            }.GetNewClosure())
        }
        $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($card.Guid)"
        [void](Invoke-Action -Label "Nagle keys back on $($card.Name)" -Work {
            foreach ($pair in @(@('TcpAckFrequency', $card.AckFreq), @('TCPNoDelay', $card.NoDelay))) {
                if ($null -eq $pair[1]) {
                    if (Test-Path -LiteralPath $ifPath) {
                        Remove-ItemProperty -LiteralPath $ifPath -Name $pair[0] -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    Set-RegistryValue -Path $ifPath -Name $pair[0] -Value $pair[1] -Type 'DWord'
                }
            }
            return $null
        }.GetNewClosure())
        if ($card.DnsV4 -and @($card.DnsV4).Count -gt 0) {
            [void](Invoke-Action -Label "DNS servers back on $($card.Name)" -Work {
                Set-DnsClientServerAddress -InterfaceAlias $card.Name -ServerAddresses @($card.DnsV4) -ErrorAction Stop
                return ($card.DnsV4 -join ', ')
            }.GetNewClosure())
        } else {
            [void](Invoke-Action -Label "DNS back to automatic on $($card.Name)" -Work {
                Set-DnsClientServerAddress -InterfaceAlias $card.Name -ResetServerAddresses -ErrorAction Stop
                return $null
            }.GetNewClosure())
        }
    }

    foreach ($t in $state.Tcp) {
        if ($t.SettingName -notin @('Internet', 'Datacenter', 'InternetCustom', 'DatacenterCustom', 'Compat')) { continue }
        [void](Invoke-Action -Label "TCP profile $($t.SettingName) back to how it was" -Work {
            $splat = @{ SettingName = $t.SettingName; ErrorAction = 'Stop' }
            if ($t.AutoTuningLevelLocal) { $splat['AutoTuningLevelLocal'] = "$($t.AutoTuningLevelLocal)" }
            if ($t.EcnCapability) { $splat['EcnCapability'] = "$($t.EcnCapability)" }
            if ($t.Timestamps) { $splat['Timestamps'] = "$($t.Timestamps)" }
            if ($t.ScalingHeuristics) { $splat['ScalingHeuristics'] = "$($t.ScalingHeuristics)" }
            Set-NetTCPSetting @splat
            return $null
        }.GetNewClosure())
    }
    return 'done'
}

function Restore-WindowsDefault {
    Write-Ui -Text 'Putting the main settings back to what Windows ships with.' -Style 'Warn'
    [void](Invoke-Action -Label 'auto-tuning back to normal' -Work {
        Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'set', 'global', 'autotuninglevel=normal') | Out-Null
        return $null
    })
    [void](Invoke-Action -Label 'RSS on, RSC on, ECN off, timestamps off' -Work {
        foreach ($set in @('rss=enabled', 'rsc=enabled', 'ecncapability=disabled', 'timestamps=disabled', 'initialRto=3000')) {
            Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'set', 'global', $set) | Out-Null
        }
        return $null
    })
    [void](Invoke-Action -Label 'throttling and QoS keys removed' -Work {
        $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Set-RegistryValue -Path $mm -Name 'NetworkThrottlingIndex' -Value 10 -Type 'DWord'
        Set-RegistryValue -Path $mm -Name 'SystemResponsiveness' -Value 20 -Type 'DWord'
        $ps = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched'
        if (Test-Path -LiteralPath $ps) {
            Remove-ItemProperty -LiteralPath $ps -Name 'NonBestEffortLimit' -Force -ErrorAction SilentlyContinue
        }
        return $null
    })
    foreach ($card in (Get-TargetAdapter -IncludeDown)) {
        [void](Invoke-Action -Label "every advanced setting on $($card.Name) back to the driver default" -Work {
            Reset-NetAdapterAdvancedProperty -Name $card.Name -DisplayName '*' -NoRestart -ErrorAction Stop
            return $null
        }.GetNewClosure())
        $ifPath = Get-InterfaceRegistryPath -Adapter $card
        [void](Invoke-Action -Label "Nagle keys cleared on $($card.Name)" -Work {
            if (Test-Path -LiteralPath $ifPath) {
                Remove-ItemProperty -LiteralPath $ifPath -Name 'TcpAckFrequency' -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -LiteralPath $ifPath -Name 'TCPNoDelay' -Force -ErrorAction SilentlyContinue
            }
            return $null
        }.GetNewClosure())
    }
    $Script:Cfg.Reboot = $true
}

function Invoke-NetshTcp {
    param([Parameter(Mandatory = $true)][string]$Setting)
    $r = Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'set', 'global', $Setting)
    if ($r.Code -ne 0 -or $r.Text -match 'not supported|parameter is incorrect|Element not found|syntax supplied') {
        throw "netsh would not take $Setting on this PC. $($r.Text)"
    }
    return $Setting
}

$Script:Tweaks = [ordered]@{

    'clean-dns'       = [pscustomobject]@{
        Title = 'Flush the DNS cache and sign back in to DNS'
        Detail = 'Dumps the saved name lookups. Fixes sites that load on your phone but not your PC.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'DNS cache flushed' -Work {
                $r = Invoke-Native -File 'ipconfig.exe' -Arguments @('/flushdns')
                if ($r.Code -ne 0) { throw $r.Text }
                return $null
            })
            [void](Invoke-Action -Label 'this PC re-registered in DNS' -Work {
                Invoke-Native -File 'ipconfig.exe' -Arguments @('/registerdns') | Out-Null
                return $null
            })
        }
    }

    'clean-arp'       = [pscustomobject]@{
        Title = 'Clear the ARP cache'
        Detail = 'Wipes the list of which device on your network has which address. Handy after swapping a router.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'ARP table cleared' -Work {
                $a = Invoke-Native -File 'arp.exe' -Arguments @('-d', '*')
                $b = Invoke-Native -File 'netsh.exe' -Arguments @('interface', 'ip', 'delete', 'arpcache')
                if ($a.Code -ne 0 -and $b.Code -ne 0) { throw "$($a.Text) $($b.Text)" }
                return $null
            })
        }
    }

    'clean-route'     = [pscustomobject]@{
        Title = 'Clear the route and destination cache'
        Detail = 'Throws away remembered paths to other machines, for IPv4 and IPv6.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            foreach ($fam in @('ipv4', 'ipv6')) {
                [void](Invoke-Action -Label "$fam destination cache cleared" -Work {
                    $r = Invoke-Native -File 'netsh.exe' -Arguments @('interface', $fam, 'delete', 'destinationcache')
                    if ($r.Code -ne 0) { throw $r.Text }
                    return $null
                }.GetNewClosure())
            }
            [void](Invoke-Action -Label 'IPv6 neighbour cache cleared' -Work {
                Invoke-Native -File 'netsh.exe' -Arguments @('interface', 'ipv6', 'delete', 'neighbors') | Out-Null
                return $null
            })
        }
    }

    'clean-ip'        = [pscustomobject]@{
        Title = 'Drop and grab a fresh IP address'
        Detail = 'Gives back your current address and asks the router for a new one. IPv4 and IPv6. You will lose the connection for a few seconds.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            foreach ($step in @(@('/release', 'IPv4 dropped'), @('/release6', 'IPv6 dropped'), @('/renew', 'IPv4 renewed'), @('/renew6', 'IPv6 renewed'))) {
                [void](Invoke-Action -Label $step[1] -Work {
                    Invoke-Native -File 'ipconfig.exe' -Arguments @($step[0]) | Out-Null
                    return $null
                }.GetNewClosure())
            }
        }
    }

    'clean-netbios'   = [pscustomobject]@{
        Title = 'Clear the NetBIOS name cache'
        Detail = 'Old style Windows name lookups used for local file shares.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'NetBIOS cache purged' -Work {
                Invoke-Native -File 'nbtstat.exe' -Arguments @('-R') | Out-Null
                return $null
            })
            [void](Invoke-Action -Label 'NetBIOS names registered again' -Work {
                Invoke-Native -File 'nbtstat.exe' -Arguments @('-RR') | Out-Null
                return $null
            })
        }
    }

    'clean-winsock'   = [pscustomobject]@{
        Title = 'Reset Winsock'
        Detail = 'Puts the bit of Windows that apps talk to the network through back to stock. Clears out junk left by old VPNs and dodgy anti-virus. Needs a reboot.'
        Group = 'Clean'; Scope = 'System'; Reboot = $true; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'Winsock reset' -NeedsReboot -Work {
                $r = Invoke-Native -File 'netsh.exe' -Arguments @('winsock', 'reset')
                if ($r.Code -ne 0) { throw $r.Text }
                return 'reboot needed'
            })
        }
    }

    'clean-stack'     = [pscustomobject]@{
        Title = 'Reset the whole TCP/IP stack'
        Detail = 'The big one. Puts IPv4 and IPv6 back to factory. Any static IP or DNS you set by hand goes as well. Needs a reboot.'
        Group = 'Clean'; Scope = 'System'; Reboot = $true; Risk = 'High'
        Apply = {
            foreach ($fam in @('ip', 'ipv6')) {
                [void](Invoke-Action -Label "$fam stack reset" -NeedsReboot -Work {
                    $r = Invoke-Native -File 'netsh.exe' -Arguments @('int', $fam, 'reset')
                    if ($r.Code -ne 0 -and $r.Text -notmatch 'Resetting') { throw $r.Text }
                    return 'reboot needed'
                }.GetNewClosure())
            }
        }
    }

    'clean-proxy'     = [pscustomobject]@{
        Title = 'Clear the proxy settings'
        Detail = 'Clears the system proxy and the one in Internet Options. Loads of adware leaves a proxy behind that slows everything down.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'system proxy cleared' -Work {
                $r = Invoke-Native -File 'netsh.exe' -Arguments @('winhttp', 'reset', 'proxy')
                if ($r.Code -ne 0) { throw $r.Text }
                return $null
            })
            [void](Invoke-Action -Label 'Internet Options proxy switched off' -Work {
                $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
                Set-RegistryValue -Path $path -Name 'ProxyEnable' -Value 0 -Type 'DWord'
                Remove-ItemProperty -LiteralPath $path -Name 'ProxyServer' -Force -ErrorAction SilentlyContinue
                return $null
            })
        }
    }

    'clean-do'        = [pscustomobject]@{
        Title = 'Empty the Delivery Optimisation cache'
        Detail = 'Windows keeps chunks of updates on disk to share with other PCs. This bins the cache. It does not turn off Windows Update.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'Delivery Optimisation cache emptied' -Work {
                if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
                    & 'Delete-DeliveryOptimizationCache' -Force
                    return 'used the built in command'
                }
                $folder = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\DeliveryOptimization'
                if (Test-Path -LiteralPath $folder) {
                    Get-ChildItem -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    return 'cleared the folder by hand'
                }
                return 'nothing to clear'
            })
        }
    }

    'clean-services'  = [pscustomobject]@{
        Title = 'Restart the network services'
        Detail = 'Bounces DNS Client, DHCP Client, WLAN AutoConfig, Wired AutoConfig and Network Location Awareness.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            $list = @(
                @{ Name = 'Dnscache'; Nice = 'DNS Client' },
                @{ Name = 'Dhcp'; Nice = 'DHCP Client' },
                @{ Name = 'WlanSvc'; Nice = 'WLAN AutoConfig' },
                @{ Name = 'dot3svc'; Nice = 'Wired AutoConfig' },
                @{ Name = 'NlaSvc'; Nice = 'Network Location Awareness' }
            )
            foreach ($svc in $list) {
                [void](Invoke-Action -Label "$($svc.Nice) restarted" -Work {
                    $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
                    if ($null -eq $s) { return 'not on this PC' }
                    if ($s.StartType -eq 'Disabled') { return 'switched off, left alone' }
                    Restart-Service -Name $svc.Name -Force -ErrorAction Stop
                    return $null
                }.GetNewClosure())
            }
        }
    }

    'clean-firewall'  = [pscustomobject]@{
        Title = 'Reset Windows Firewall to its defaults'
        Detail = 'WARNING: every firewall rule you or your apps added gets wiped. Games and file sharing may ask permission again. The firewall stays ON.'
        Group = 'Clean'; Scope = 'System'; Reboot = $false; Risk = 'High'
        Apply = {
            [void](Invoke-Action -Label 'firewall rules back to default' -Work {
                $r = Invoke-Native -File 'netsh.exe' -Arguments @('advfirewall', 'reset')
                if ($r.Code -ne 0) { throw $r.Text }
                Invoke-Native -File 'netsh.exe' -Arguments @('advfirewall', 'set', 'allprofiles', 'state', 'on') | Out-Null
                return 'firewall left switched on'
            })
        }
    }

    'clean-cycle'     = [pscustomobject]@{
        Title = 'Switch the card off and back on'
        Detail = 'Same as unplugging it. Clears a stuck link. You will drop offline for about ten seconds.'
        Group = 'Clean'; Scope = 'Both'; Reboot = $false; Risk = 'Medium'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "$($c.Name) bounced" -Work {
                    Restart-NetAdapter -Name $c.Name -ErrorAction Stop
                    Start-Sleep -Seconds 4
                    return $null
                }.GetNewClosure())
            }
        }
    }

    'tcp-autotune'    = [pscustomobject]@{
        Title = 'TCP auto-tuning set to normal'
        Detail = 'Lets Windows size the receive window to suit the line. Normal is the Windows default and it is right for nearly everyone.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'auto-tuning set to normal' -Work { return (Invoke-NetshTcp -Setting 'autotuninglevel=normal') })
        }
    }

    'tcp-rss'         = [pscustomobject]@{
        Title = 'Receive Side Scaling on'
        Detail = 'Spreads incoming traffic over several CPU cores instead of hammering core 0.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'RSS on globally' -Work { return (Invoke-NetshTcp -Setting 'rss=enabled') })
            foreach ($c in (Select-ScopedAdapter -Adapter (Get-TargetAdapter))) {
                [void](Invoke-Action -Label "RSS on for $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'Rss' -Prefer @('Enabled'))
                }.GetNewClosure())
            }
        }
    }

    'tcp-rsc-off'     = [pscustomobject]@{
        Title = 'Receive Segment Coalescing off'
        Detail = 'RSC glues small packets together to save CPU. Good for big downloads, adds a tiny bit of delay. Only worth turning off if you game on a fast PC.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'RSC off globally' -Work { return (Invoke-NetshTcp -Setting 'rsc=disabled') })
            foreach ($c in (Select-ScopedAdapter -Adapter (Get-TargetAdapter))) {
                [void](Invoke-Action -Label "RSC off for $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'Rsc' -Prefer @('Disabled'))
                }.GetNewClosure())
            }
        }
    }

    'tcp-ecn'         = [pscustomobject]@{
        Title = 'ECN on'
        Detail = 'Lets routers say "I am getting full" instead of binning packets. Helps on some lines, does nothing on most, and a few old routers hate it. Off by default.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'ECN switched on' -Work { return (Invoke-NetshTcp -Setting 'ecncapability=enabled') })
        }
    }

    'tcp-timestamps'  = [pscustomobject]@{
        Title = 'TCP timestamps off'
        Detail = 'Timestamps add 12 bytes to every packet. Windows ships with them off already, this just makes sure.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'timestamps off' -Work { return (Invoke-NetshTcp -Setting 'timestamps=disabled') })
        }
    }

    'tcp-rto'         = [pscustomobject]@{
        Title = 'Initial RTO dropped to 2000 ms'
        Detail = 'How long Windows waits before trying a connection again. Default is 3000 ms. Lower means a dead connection retries quicker. Tiny effect.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'initial RTO set to 2000 ms' -Work { return (Invoke-NetshTcp -Setting 'initialRto=2000') })
        }
    }

    'tcp-congestion'  = [pscustomobject]@{
        Title = 'Congestion control set to CUBIC'
        Detail = 'How Windows works out how hard to push. CUBIC is the default on Windows 10 2004 and later and it is fine. Older builds may only offer CTCP.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $false; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'congestion provider set' -Work {
                $r = Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'set', 'supplemental', 'Template=Internet', 'CongestionProvider=cubic')
                if ($r.Code -eq 0 -and $r.Text -notmatch 'not supported|incorrect') { return 'CUBIC' }
                $r2 = Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'set', 'supplemental', 'Template=Internet', 'CongestionProvider=ctcp')
                if ($r2.Code -eq 0 -and $r2.Text -notmatch 'not supported|incorrect') { return 'CTCP, this build has no CUBIC' }
                throw 'this build of Windows will not let the congestion provider be changed'
            })
        }
    }

    'tcp-throttle'    = [pscustomobject]@{
        Title = 'Network throttling off'
        Detail = 'Windows caps background network work so audio and video stay smooth. Turning the cap off can help a gaming PC and can make audio crackle on a weak one.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $true; Risk = 'Medium'
        Apply = {
            [void](Invoke-Action -Label 'throttling cap removed' -NeedsReboot -Work {
                $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
                Set-RegistryValue -Path $mm -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type 'DWord'
                Set-RegistryValue -Path $mm -Name 'SystemResponsiveness' -Value 10 -Type 'DWord'
                return 'reboot needed'
            })
        }
    }

    'tcp-nagle'       = [pscustomobject]@{
        Title = 'Nagle off on the picked cards'
        Detail = 'Stops Windows holding tiny packets back to bundle them up. Shaves a few ms off games. It costs you bandwidth on slow lines. Gaming only.'
        Group = 'Tcp'; Scope = 'Both'; Reboot = $true; Risk = 'Medium'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "Nagle off on $($c.Name)" -NeedsReboot -Work {
                    $path = Get-InterfaceRegistryPath -Adapter $c
                    if (-not (Test-Path -LiteralPath $path)) { throw 'no registry key for this card' }
                    Set-RegistryValue -Path $path -Name 'TcpAckFrequency' -Value 1 -Type 'DWord'
                    Set-RegistryValue -Path $path -Name 'TCPNoDelay' -Value 1 -Type 'DWord'
                    return 'reboot needed'
                }.GetNewClosure())
            }
        }
    }

    'tcp-qos'         = [pscustomobject]@{
        Title = 'QoS reservable bandwidth set to 0 percent'
        Detail = 'Straight talk: that 20 percent is not being wasted, apps get it back when nobody is using it. This changes almost nothing. It is here because people ask for it.'
        Group = 'Tcp'; Scope = 'System'; Reboot = $true; Risk = 'Low'
        Apply = {
            [void](Invoke-Action -Label 'reservable bandwidth set to 0' -NeedsReboot -Work {
                Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched' -Name 'NonBestEffortLimit' -Value 0 -Type 'DWord'
                return 'reboot needed, and do not expect much'
            })
        }
    }

    'wifi-power'      = [pscustomobject]@{
        Title = 'Wi-Fi power saving off'
        Detail = 'Stops the card dozing between packets. This is the single biggest fix for random Wi-Fi lag spikes on laptops. It does eat battery.'
        Group = 'WiFi'; Scope = 'WiFi'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "Windows can no longer power down $($c.Name)" -Work {
                    return (Disable-DevicePowerOff -Adapter $c)
                }.GetNewClosure())
                [void](Invoke-Action -Label "driver power saving off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'PowerSave' -Prefer @('Disabled', 'Off'))
                }.GetNewClosure())
                [void](Invoke-Action -Label "MIMO power save off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'MimoPower' -Prefer @('No SMPS', 'Disabled'))
                }.GetNewClosure())
            }
            [void](Invoke-Action -Label 'power plan set to max Wi-Fi performance' -Work {
                $sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
                $set = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
                foreach ($mode in @('setacvalueindex', 'setdcvalueindex')) {
                    $r = Invoke-Native -File 'powercfg.exe' -Arguments @("/$mode", 'SCHEME_CURRENT', $sub, $set, '0')
                    if ($r.Code -ne 0) { throw $r.Text }
                }
                Invoke-Native -File 'powercfg.exe' -Arguments @('/setactive', 'SCHEME_CURRENT') | Out-Null
                return 'on battery too'
            })
        }
    }

    'wifi-band'       = [pscustomobject]@{
        Title = 'Prefer the 5 GHz band'
        Detail = 'Tells the card to pick 5 GHz over 2.4 GHz when both are there. 5 GHz is faster and less crowded but does not go through walls as well. Got a 6E card and a 6 GHz router? Set that with option P instead.'
        Group = 'WiFi'; Scope = 'WiFi'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "5 GHz preferred on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'Band' -Prefer @('Prefer 5GHz band', 'Prefer 5.2GHz band', '5GHz', 'Prefer 5 GHz'))
                }.GetNewClosure())
            }
        }
    }

    'wifi-txpower'    = [pscustomobject]@{
        Title = 'Wi-Fi transmit power on full'
        Detail = 'Some drivers ship at a lower power to save battery. Full power helps if you are far from the router.'
        Group = 'WiFi'; Scope = 'WiFi'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "transmit power on full for $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'TxPower' -Prefer @('Highest', 'High', '100%', '5. Highest'))
                }.GetNewClosure())
            }
        }
    }

    'wifi-scan'       = [pscustomobject]@{
        Title = 'Background Wi-Fi scanning turned down'
        Detail = 'Your card sniffs for other networks while you are connected, which can cause a blip every few seconds. Turning it down can make roaming between access points slower.'
        Group = 'WiFi'; Scope = 'WiFi'; Reboot = $false; Risk = 'Medium'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "scan while connected off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'ScanIdle' -Prefer @('Disabled', 'Off'))
                }.GetNewClosure())
            }
            [void](Invoke-Action -Label 'auto switch off on saved networks' -Work {
                $out = (Invoke-Native -File 'netsh.exe' -Arguments @('wlan', 'show', 'profiles')).Text
                $names = @([regex]::Matches($out, '(?m)^\s*All User Profile\s*:\s*(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() })
                if ($names.Count -eq 0) { return 'no saved networks' }
                foreach ($n in $names) {
                    Invoke-Native -File 'netsh.exe' -Arguments @('wlan', 'set', 'profileparameter', "name=$n", 'autoSwitch=no') | Out-Null
                }
                return "$($names.Count) networks done"
            })
        }
    }

    'eth-eee'         = [pscustomobject]@{
        Title = 'Energy Efficient Ethernet and Green Ethernet off'
        Detail = 'These drop the link speed or park the port when things go quiet. On a lot of Realtek cards that means a dropout every few minutes. Turn them off.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "EEE and Green Ethernet off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'EEE' -Prefer @('Disabled', 'Off'))
                }.GetNewClosure())
            }
        }
    }

    'eth-devicepower' = [pscustomobject]@{
        Title = 'Stop Windows switching the network card off'
        Detail = 'Unticks "allow the computer to turn off this device to save power" in Device Manager.'
        Group = 'Ethernet'; Scope = 'Both'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "power down blocked on $($c.Name)" -Work {
                    return (Disable-DevicePowerOff -Adapter $c)
                }.GetNewClosure())
            }
        }
    }

    'eth-cardpower'   = [pscustomobject]@{
        Title = 'Driver level power saving off'
        Detail = 'Selective suspend, idle power saver and the rest. Same idea as above but set in the driver.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "driver power saving off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'PowerSave' -Prefer @('Disabled', 'Off'))
                }.GetNewClosure())
                [void](Invoke-Action -Label "sleep on unplug off on $($c.Name)" -Work {
                    Set-NetAdapterPowerManagement -Name $c.Name -DeviceSleepOnDisconnect 'Disabled' -NoRestart -ErrorAction Stop
                    return $null
                }.GetNewClosure())
            }
        }
    }

    # chimney offload and ipsec task offload are dead, never add them here
    'eth-offload'     = [pscustomobject]@{
        Title = 'Checksum and Large Send Offload on'
        Detail = 'Hands the boring maths to the card instead of your CPU. Microsoft says leave these on.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "checksum offloads on for $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'Checksum' -Prefer @('Rx & Tx Enabled', 'Rx and Tx Enabled', 'Enabled'))
                }.GetNewClosure())
                [void](Invoke-Action -Label "Large Send Offload v2 on for $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'Lso' -Prefer @('Enabled'))
                }.GetNewClosure())
            }
        }
    }

    'eth-buffers'     = [pscustomobject]@{
        Title = 'Receive and transmit buffers turned up'
        Detail = 'More buffers means fewer dropped packets when things get busy. Costs a bit of RAM. Microsoft recommends maxing the receive buffers on busy machines.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                foreach ($key in @('RxBuffers', 'TxBuffers')) {
                    [void](Invoke-Action -Label "$key raised on $($c.Name)" -Work {
                        $props = Get-AdapterProperty -Adapter $c -Key $key
                        if ($props.Count -eq 0) { return 'this card sizes its own buffers, skipped' }
                        $notes = @()
                        foreach ($p in $props) {
                            $top = $null
                            if ($p.ValidDisplayValues) {
                                $nums = @($p.ValidDisplayValues | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
                                if ($nums.Count -gt 0) { $top = ($nums | Sort-Object)[-1] }
                            }
                            if ($null -eq $top -and $p.NumericParameterMaxValue) { $top = [int]$p.NumericParameterMaxValue }
                            if ($null -eq $top) { $notes += "$($p.DisplayName) has no max to read"; continue }
                            Set-NetAdapterAdvancedProperty -Name $c.Name -DisplayName $p.DisplayName -DisplayValue "$top" -NoRestart -ErrorAction Stop
                            $notes += "$($p.DisplayName) -> $top"
                        }
                        return ($notes -join '; ')
                    }.GetNewClosure())
                }
            }
        }
    }

    'eth-flow'        = [pscustomobject]@{
        Title = 'Flow Control on'
        Detail = 'Lets the card ask the switch to slow down instead of dropping packets. Leave it on unless your switch is rubbish.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "flow control on for $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'FlowControl' -Prefer @('Rx & Tx Enabled', 'Rx and Tx Enabled', 'Enabled'))
                }.GetNewClosure())
            }
        }
    }

    'eth-intmod'      = [pscustomobject]@{
        Title = 'Interrupt Moderation off'
        Detail = 'Moderation batches up interrupts to save CPU, at the cost of a little delay. Off means lowest possible ping and more CPU use. Only worth it on a decent CPU.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Medium'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "interrupt moderation off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'IntMod' -Prefer @('Disabled', 'Off'))
                }.GetNewClosure())
            }
        }
    }

    'eth-jumbo-off'   = [pscustomobject]@{
        Title = 'Make sure Jumbo Frames are off'
        Detail = 'Jumbo frames only work if your router, your switch and the other PC all do them too. If one does not, things break in weird ways. Off is the safe setting.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "jumbo frames off on $($c.Name)" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'Jumbo' -Prefer @('Disabled', 'Off', '1514'))
                }.GetNewClosure())
            }
        }
    }

    'eth-speedauto'   = [pscustomobject]@{
        Title = 'Speed and duplex back on Auto Negotiation'
        Detail = 'Auto is nearly always right. Forcing a speed is how people end up stuck at 100 Mbps.'
        Group = 'Ethernet'; Scope = 'Ethernet'; Reboot = $false; Risk = 'Low'
        Apply = {
            param($cards)
            foreach ($c in $cards) {
                [void](Invoke-Action -Label "$($c.Name) set to auto negotiate" -Work {
                    return (Set-PropertyGroup -Adapter $c -Key 'SpeedDuplex' -Prefer @('Auto Negotiation', 'Auto-Negotiation', 'Auto'))
                }.GetNewClosure())
            }
        }
    }
}

$Script:Presets = [ordered]@{
    'Safe'      = @{
        Title = 'Safe'
        Detail = 'Low risk cleaning and the tweaks that help nearly everyone. Nothing here needs a reboot.'
        Ids = @('clean-dns', 'clean-arp', 'clean-route', 'clean-netbios', 'clean-do', 'clean-services',
            'tcp-autotune', 'tcp-rss', 'tcp-timestamps',
            'wifi-power', 'wifi-band', 'wifi-txpower',
            'eth-eee', 'eth-devicepower', 'eth-cardpower', 'eth-offload', 'eth-flow', 'eth-jumbo-off')
    }
    'Gaming'    = @{
        Title = 'Gaming'
        Detail = 'Everything in Safe plus the latency tweaks. A couple of these need a reboot and a couple use more CPU.'
        Ids = @('clean-dns', 'clean-arp', 'clean-route', 'clean-netbios', 'clean-do', 'clean-services',
            'tcp-autotune', 'tcp-rss', 'tcp-timestamps', 'tcp-congestion', 'tcp-nagle', 'tcp-throttle', 'tcp-rsc-off',
            'wifi-power', 'wifi-band', 'wifi-txpower',
            'eth-eee', 'eth-devicepower', 'eth-cardpower', 'eth-offload', 'eth-flow', 'eth-jumbo-off', 'eth-intmod', 'eth-buffers')
    }
    'FullClean' = @{
        Title = 'Full Clean and Reset'
        Detail = 'Every cache cleared and the whole stack reset. This is the "it is broken, fix it" option. You will need to reboot.'
        Ids = @('clean-dns', 'clean-arp', 'clean-route', 'clean-netbios', 'clean-proxy', 'clean-do',
            'clean-services', 'clean-winsock', 'clean-stack', 'clean-ip')
    }
}

function Get-ScopedCard {
    param(
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][object[]]$Cards
    )
    if ($Scope -eq 'System') { return @() }
    if ($Scope -eq 'Both') { return @($Cards) }
    return @($Cards | Where-Object { $_.Kind -eq $Scope })
}

function Show-Plan {
    param(
        [Parameter(Mandatory = $true)][string[]]$Ids,
        [Parameter(Mandatory = $true)][object[]]$Cards
    )
    Write-Head -Text 'Here is exactly what will change'
    Write-Ui -Text "Cards picked: $($Script:Cfg.Target)" -Style 'Plain'
    foreach ($c in $Cards) {
        Write-Ui -Text "  $("$($c.Kind)".PadRight(8)) $($c.Name)  ($($c.Desc))" -Style 'Dim'
    }
    Write-Ui -Text '' -Style 'Plain'
    $n = 0
    foreach ($id in $Ids) {
        if (-not $Script:Tweaks.Contains($id)) { continue }
        $t = $Script:Tweaks[$id]
        $n++
        $flags = @()
        if ($t.Reboot) { $flags += 'reboot' }
        if ($t.Risk -ne 'Low') { $flags += "$($t.Risk.ToLower()) risk" }
        $tail = if ($flags.Count -gt 0) { '  [' + ($flags -join ', ') + ']' } else { '' }
        $style = if ($t.Risk -eq 'High') { 'Bad' } elseif ($t.Risk -eq 'Medium') { 'Warn' } else { 'Plain' }
        Write-Ui -Text ("{0,2}. {1}{2}" -f $n, $t.Title, $tail) -Style $style
        Write-Ui -Text "    $($t.Detail)" -Style 'Dim'
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text "$n things will be changed." -Style 'Head'
    if ($Script:Cfg.DryRun) { Write-Ui -Text 'Dry run is ON, so nothing is actually going to change.' -Style 'Warn' }
}

# every scriptblock built in a loop needs GetNewClosure or the loop variable is gone by the time it runs
function Invoke-Tweak {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Cards
    )
    if (-not $Script:Tweaks.Contains($Id)) { return }
    $t = $Script:Tweaks[$Id]
    $scoped = Get-ScopedCard -Scope $t.Scope -Cards $Cards
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text "> $($t.Title)" -Style 'Head'
    if ($t.Scope -ne 'System' -and $scoped.Count -eq 0) {
        Write-Ui -Text "  SKIP no $($t.Scope) card is picked or plugged in" -Style 'Warn'
        Write-RunLog -Level 'WARN' -Message "skipped $Id, no matching card"
        return
    }
    try {
        & $t.Apply $scoped
    } catch {
        Write-Ui -Text "  FAIL the whole step fell over: $($_.Exception.Message)" -Style 'Bad'
        Write-RunLog -Level 'ERROR' -Message "$Id blew up: $($_.Exception.Message)"
    }
    if ($t.Reboot -and -not $Script:Cfg.DryRun) { $Script:Cfg.Reboot = $true }
}

function Invoke-TweakList {
    param(
        [Parameter(Mandatory = $true)][string[]]$Ids,
        [switch]$SkipSafety
    )
    $cards = Select-ScopedAdapter -Adapter (Get-TargetAdapter)
    if ($cards.Count -eq 0) {
        Write-Ui -Text 'No live Wi-Fi or Ethernet card matches what you picked. Nothing to do.' -Style 'Bad'
        Wait-Key
        return
    }
    Show-Plan -Ids $Ids -Cards $cards
    if (-not (Confirm-Go -Question 'Apply all of that?')) {
        Write-Ui -Text 'Left everything alone.' -Style 'Warn'
        Wait-Key
        return
    }
    if (-not $SkipSafety -and -not $Script:Cfg.DryRun) {
        Write-Head -Text 'Backing your settings up first'
        [void](Invoke-Action -Label 'registry keys exported' -Work { return (Backup-RegistryKey) })
        [void](Invoke-Action -Label 'current settings saved to JSON' -Work { return (Save-NetworkState) })
        if (Confirm-Go -Question 'Make a System Restore point as well? It takes a minute') {
            [void](Invoke-Action -Label 'system restore point' -Work { return (Checkpoint-System) })
        }
    }
    Write-Head -Text 'Doing the work'
    foreach ($id in $Ids) { Invoke-Tweak -Id $id -Cards $cards }
    Show-Finish
    Wait-Key
}

function Show-Finish {
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text ('-' * 66) -Style 'Head'
    if ($Script:Cfg.DryRun) {
        Write-Ui -Text 'Dry run finished. Nothing was changed.' -Style 'Warn'
    } else {
        Write-Ui -Text 'All done.' -Style 'Ok'
        Write-Ui -Text "Log and backups: $($Script:Cfg.Run)" -Style 'Dim'
    }
    if ($Script:Cfg.Reboot) {
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text 'REBOOT NEEDED. Some of that will not take effect until you restart.' -Style 'Warn'
    }
}

function Invoke-CustomPick {
    $ids = @($Script:Tweaks.Keys)
    Write-Head -Text 'Pick your own tweaks'
    $i = 0
    foreach ($id in $ids) {
        $i++
        $t = $Script:Tweaks[$id]
        $style = if ($t.Risk -eq 'High') { 'Bad' } elseif ($t.Risk -eq 'Medium') { 'Warn' } else { 'Plain' }
        Write-Ui -Text ("{0,2}. [{1,-8}] {2}" -f $i, $t.Group, $t.Title) -Style $style
        Write-Ui -Text "    $($t.Detail)" -Style 'Dim'
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'Type the numbers you want, split by commas. Like: 1,2,5,14' -Style 'Plain'
    $pick = Read-Choice -Question 'Numbers (or blank to go back)'
    if (-not $pick) { return }
    $chosen = @()
    foreach ($bit in ($pick -split ',')) {
        $n = 0
        if ([int]::TryParse($bit.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $ids.Count) {
            $chosen += $ids[$n - 1]
        } else {
            Write-Ui -Text "Ignored '$($bit.Trim())', that is not on the list." -Style 'Warn'
        }
    }
    if ($chosen.Count -eq 0) {
        Write-Ui -Text 'Nothing picked.' -Style 'Warn'
        Wait-Key
        return
    }
    Invoke-TweakList -Ids $chosen
}

function Show-NetworkSummary {
    Write-Head -Text 'What you have got right now'
    $cards = Get-TargetAdapter -IncludeVirtual -IncludeDown
    foreach ($c in $cards) {
        $style = if ($c.Status -eq 'Up') { 'Ok' } else { 'Dim' }
        $tag = if ($c.Virtual) { ' (virtual)' } else { '' }
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text "$($c.Name)$tag" -Style $style
        Write-Ui -Text "  card      $($c.Desc)" -Style 'Dim'
        Write-Ui -Text "  type      $($c.Kind)      status: $($c.Status)" -Style 'Dim'
        Write-Ui -Text "  speed     $($c.Speed)     full duplex: $($c.Duplex)" -Style 'Dim'
        Write-Ui -Text "  address   $($c.IPv4)     gateway: $($c.Gateway)" -Style 'Dim'
        Write-Ui -Text "  dns       $(($c.Dns) -join ', ')" -Style 'Dim'
        Write-Ui -Text "  driver    $($c.Driver)   dated: $($c.DriverDay)" -Style 'Dim'
        if ($c.Kind -eq 'Ethernet' -and $c.Status -eq 'Up') {
            Test-LinkSpeed -Card $c
        }
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'TCP settings Windows is using' -Style 'Head'
    $txt = (Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'show', 'global')).Text
    foreach ($line in ($txt -split "`r?`n")) {
        if ($line.Trim()) { Write-Ui -Text "  $($line.Trim())" -Style 'Dim' }
    }
    Wait-Key
}

function Test-LinkSpeed {
    param([Parameter(Mandatory = $true)]$Card)
    $bps = 0
    if ($Card.SpeedBps) { $bps = [double]$Card.SpeedBps }
    if ($bps -le 0) { return }
    $mbps = [math]::Round($bps / 1000000)
    $max = 0
    try {
        $prop = Get-NetAdapterAdvancedProperty -Name $Card.Name -RegistryKeyword '*SpeedDuplex' -ErrorAction Stop
        foreach ($v in @($prop.ValidDisplayValues)) {
            if ($v -match '([\d.]+)\s*Gbps') { $max = [math]::Max($max, [double]$Matches[1] * 1000) }
            elseif ($v -match '([\d.]+)\s*Mbps') { $max = [math]::Max($max, [double]$Matches[1]) }
        }
    } catch {
        Write-RunLog -Level 'WARN' -Message "Could not read the speed list for $($Card.Name)"
    }
    if ($max -gt 0 -and $mbps -lt $max) {
        Write-Ui -Text "  WARNING this card can do $max Mbps but the link is only $mbps Mbps." -Style 'Warn'
        Write-Ui -Text "          Nine times out of ten that is a bad cable or a bad port. Try another cable first." -Style 'Warn'
    }
}

function Show-WiFiInfo {
    Write-Head -Text 'Wi-Fi right now'
    $txt = (Invoke-Native -File 'netsh.exe' -Arguments @('wlan', 'show', 'interfaces')).Text
    if (-not $txt -or $txt -match 'not running|no wireless') {
        Write-Ui -Text 'No Wi-Fi on this PC, or the WLAN service is off.' -Style 'Warn'
        Wait-Key
        return
    }
    foreach ($line in ($txt -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        $style = 'Dim'
        if ($t -match '^(Signal|Receive rate|Transmit rate|Band|Channel|Radio type|SSID)') { $style = 'Plain' }
        if ($t -match '^Signal\s*:\s*(\d+)%') {
            $pct = [int]$Matches[1]
            $style = if ($pct -ge 70) { 'Ok' } elseif ($pct -ge 45) { 'Warn' } else { 'Bad' }
        }
        Write-Ui -Text "  $t" -Style $style
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'Rough guide: over 70% signal is good, 45 to 70 is usable, under 45 will drop out.' -Style 'Dim'
    Wait-Key
}

function Save-WlanReport {
    Write-Head -Text 'Wi-Fi report'
    Write-Ui -Text 'This builds an HTML report of the last three days of Wi-Fi connects and drops.' -Style 'Plain'
    if (-not (Confirm-Go -Question 'Build it?')) { return }
    [void](Invoke-Action -Label 'WLAN report built' -Work {
        $r = Invoke-Native -File 'netsh.exe' -Arguments @('wlan', 'show', 'wlanreport')
        if ($r.Code -ne 0) { throw $r.Text }
        return "look in $env:ProgramData\Microsoft\Windows\WlanReport\wlan-report-latest.html"
    })
    Wait-Key
}

function Show-AdvancedEditor {
    param([ValidateSet('WiFi', 'Ethernet')][string]$Kind)
    $cards = @((Get-TargetAdapter) | Where-Object { $_.Kind -eq $Kind })
    if ($cards.Count -eq 0) {
        Write-Ui -Text "No live $Kind card found." -Style 'Warn'
        Wait-Key
        return
    }
    $card = $cards[0]
    if ($cards.Count -gt 1) {
        Write-Head -Text "Which $Kind card?"
        for ($i = 0; $i -lt $cards.Count; $i++) {
            Write-Ui -Text ("{0}. {1}  ({2})" -f ($i + 1), $cards[$i].Name, $cards[$i].Desc) -Style 'Plain'
        }
        $pick = Read-Choice -Question 'Number' -Default '1'
        $n = 0
        if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $cards.Count) { $card = $cards[$n - 1] }
    }
    while ($true) {
        Write-Head -Text "Settings on $($card.Name)"
        try {
            $props = @(Get-NetAdapterAdvancedProperty -Name $card.Name -AllProperties -ErrorAction Stop |
                Sort-Object -Property DisplayName)
        } catch {
            Write-Ui -Text "Could not read the settings: $($_.Exception.Message)" -Style 'Bad'
            Wait-Key
            return
        }
        for ($i = 0; $i -lt $props.Count; $i++) {
            $p = $props[$i]
            Write-Ui -Text ("{0,2}. {1,-40} {2}" -f ($i + 1), $p.DisplayName, $p.DisplayValue) -Style 'Plain'
        }
        Write-Ui -Text '' -Style 'Plain'
        $pick = Read-Choice -Question 'Number to change (blank to go back)'
        if (-not $pick) { return }
        $n = 0
        if (-not ([int]::TryParse($pick, [ref]$n)) -or $n -lt 1 -or $n -gt $props.Count) {
            Write-Ui -Text 'Not on the list.' -Style 'Warn'
            continue
        }
        $p = $props[$n - 1]
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text "$($p.DisplayName)" -Style 'Head'
        Write-Ui -Text "  registry keyword : $($p.RegistryKeyword)" -Style 'Dim'
        Write-Ui -Text "  set to now       : $($p.DisplayValue)" -Style 'Dim'
        $valid = @($p.ValidDisplayValues)
        if ($valid.Count -gt 0) {
            Write-Ui -Text "  you can pick     :" -Style 'Dim'
            for ($j = 0; $j -lt $valid.Count; $j++) {
                Write-Ui -Text ("    {0}. {1}" -f ($j + 1), $valid[$j]) -Style 'Plain'
            }
            $vp = Read-Choice -Question 'New value number (blank to cancel)'
            if (-not $vp) { continue }
            $vn = 0
            if (-not ([int]::TryParse($vp, [ref]$vn)) -or $vn -lt 1 -or $vn -gt $valid.Count) { continue }
            $newVal = $valid[$vn - 1]
        } else {
            $newVal = Read-Choice -Question 'Type the new value (blank to cancel)'
            if (-not $newVal) { continue }
        }
        [void](Invoke-Action -Label "$($p.DisplayName) set to $newVal" -Work {
            Set-NetAdapterAdvancedProperty -Name $card.Name -DisplayName $p.DisplayName -DisplayValue $newVal -NoRestart -ErrorAction Stop
            return $null
        }.GetNewClosure())
    }
}

$Script:DnsChoice = [ordered]@{
    '1' = @{ Name = 'Cloudflare'; V4 = @('1.1.1.1', '1.0.0.1'); V6 = @('2606:4700:4700::1111', '2606:4700:4700::1001'); Doh = 'https://cloudflare-dns.com/dns-query' }
    '2' = @{ Name = 'Google'; V4 = @('8.8.8.8', '8.8.4.4'); V6 = @('2001:4860:4860::8888', '2001:4860:4860::8844'); Doh = 'https://dns.google/dns-query' }
    '3' = @{ Name = 'Quad9'; V4 = @('9.9.9.9', '149.112.112.112'); V6 = @('2620:fe::fe', '2620:fe::9'); Doh = 'https://dns.quad9.net/dns-query' }
    '4' = @{ Name = 'Back to automatic'; V4 = @(); V6 = @(); Doh = '' }
}

function Select-DnsServer {
    Write-Head -Text 'DNS servers'
    Write-Ui -Text 'DNS turns names like youtube.com into addresses. A quicker one makes pages start loading sooner.' -Style 'Plain'
    Write-Ui -Text 'It does not make your download speed any faster.' -Style 'Dim'
    Write-Ui -Text '' -Style 'Plain'
    foreach ($k in $Script:DnsChoice.Keys) {
        $d = $Script:DnsChoice[$k]
        $addr = if ($d.V4.Count -gt 0) { ($d.V4 -join ', ') } else { 'whatever your router says' }
        Write-Ui -Text "$k. $($d.Name)  -  $addr" -Style 'Plain'
    }
    $pick = Read-Choice -Question 'Which one (blank to go back)'
    if (-not $pick -or -not $Script:DnsChoice.Contains($pick)) { return }
    $choice = $Script:DnsChoice[$pick]
    $cards = Select-ScopedAdapter -Adapter (Get-TargetAdapter)
    if ($cards.Count -eq 0) {
        Write-Ui -Text 'No live card to set it on.' -Style 'Bad'
        Wait-Key
        return
    }
    foreach ($c in $cards) {
        [void](Invoke-Action -Label "DNS on $($c.Name)" -Work {
            if ($choice.V4.Count -eq 0) {
                Set-DnsClientServerAddress -InterfaceIndex $c.Index -ResetServerAddresses -ErrorAction Stop
                return 'back to automatic'
            }
            Set-DnsClientServerAddress -InterfaceIndex $c.Index -ServerAddresses ($choice.V4 + $choice.V6) -ErrorAction Stop
            return "$($choice.Name) - $($choice.V4 -join ', ')"
        }.GetNewClosure())
    }
    [void](Invoke-Action -Label 'DNS cache flushed so the change takes hold' -Work {
        Invoke-Native -File 'ipconfig.exe' -Arguments @('/flushdns') | Out-Null
        return $null
    })
    Wait-Key
}

function Enable-DohChoice {
    Write-Head -Text 'Encrypted DNS (DNS over HTTPS)'
    $build = [int](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
    if ($build -lt 22000) {
        Write-Ui -Text "This is Windows 10 (build $build). Built in DoH is a Windows 11 thing, so this is skipped." -Style 'Warn'
        Wait-Key
        return
    }
    Write-Ui -Text 'This wraps your DNS lookups in HTTPS so your internet provider cannot read them.' -Style 'Plain'
    Write-Ui -Text 'It will fall back to normal DNS if the encrypted one does not answer.' -Style 'Dim'
    Write-Ui -Text 'Do not use this on a work laptop joined to a company domain, it breaks internal names.' -Style 'Warn'
    Write-Ui -Text '' -Style 'Plain'
    foreach ($k in @('1', '2', '3')) {
        Write-Ui -Text "$k. $($Script:DnsChoice[$k].Name)" -Style 'Plain'
    }
    $pick = Read-Choice -Question 'Which one (blank to go back)'
    if (-not $pick -or $pick -notin @('1', '2', '3')) { return }
    $choice = $Script:DnsChoice[$pick]
    $cards = Select-ScopedAdapter -Adapter (Get-TargetAdapter)
    foreach ($ip in $choice.V4) {
        [void](Invoke-Action -Label "DoH template added for $ip" -Work {
            if (Get-Command -Name 'Add-DnsClientDohServerAddress' -ErrorAction SilentlyContinue) {
                $have = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
                if ($null -eq $have) {
                    Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $choice.Doh -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop
                    return 'added'
                }
                return 'already known to Windows'
            }
            $r = Invoke-Native -File 'netsh.exe' -Arguments @('dns', 'add', 'encryption', "server=$ip", "dohtemplate=$($choice.Doh)", 'autoupgrade=yes', 'udpfallback=yes')
            if ($r.Code -ne 0) { throw $r.Text }
            return 'added with netsh'
        }.GetNewClosure())
    }
    foreach ($c in $cards) {
        [void](Invoke-Action -Label "DNS set to $($choice.Name) on $($c.Name)" -Work {
            Set-DnsClientServerAddress -InterfaceIndex $c.Index -ServerAddresses ($choice.V4 + $choice.V6) -ErrorAction Stop
            return $null
        }.GetNewClosure())
        [void](Invoke-Action -Label "encryption switched on for $($c.Name)" -Work {
            $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($c.Guid)\DohInterfaceSettings\Doh"
            foreach ($ip in $choice.V4) {
                Set-RegistryValue -Path (Join-Path -Path $base -ChildPath $ip) -Name 'DohFlags' -Value 2 -Type 'QWord'
            }
            return 'encrypted first, plain DNS as backup'
        }.GetNewClosure())
    }
    [void](Invoke-Action -Label 'DNS cache flushed' -Work {
        Invoke-Native -File 'ipconfig.exe' -Arguments @('/flushdns') | Out-Null
        return $null
    })
    Write-Ui -Text 'Check it worked in Settings, Network, your adapter, DNS settings. It should say Encrypted.' -Style 'Dim'
    Wait-Key
}

function Show-DriverNote {
    Write-Head -Text 'Driver versions'
    foreach ($c in (Get-TargetAdapter)) {
        Write-Ui -Text "$($c.Name)  ($($c.Kind))" -Style 'Plain'
        Write-Ui -Text "  $($c.Desc)" -Style 'Dim'
        Write-Ui -Text "  driver $($c.Driver), dated $($c.DriverDay)" -Style 'Dim'
        $age = $null
        if ($c.DriverDay) {
            try { $age = ((Get-Date) - [datetime]$c.DriverDay).Days } catch { $age = $null }
        }
        if ($null -ne $age -and $age -gt 730) {
            Write-Ui -Text "  That driver is over two years old. Worth checking the maker's website." -Style 'Warn'
        }
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'Get drivers from the card maker, not Windows Update:' -Style 'Plain'
    Write-Ui -Text '  Intel Wi-Fi and LAN  : intel.com/content/www/us/en/download-center/home.html' -Style 'Dim'
    Write-Ui -Text '  Realtek LAN          : realtek.com/en/downloads' -Style 'Dim'
    Write-Ui -Text '  Killer / Rivet       : killernetworking.com/support' -Style 'Dim'
    Write-Ui -Text '  Marvell / Aquantia   : marvell.com/support' -Style 'Dim'
    Write-Ui -Text 'On a laptop, try the laptop maker first. Their drivers are tested with your hardware.' -Style 'Dim'
    Wait-Key
}

$Script:PingHost = @('1.1.1.1', '8.8.8.8', '9.9.9.9')
$Script:LookupName = @('www.microsoft.com', 'www.google.com', 'www.cloudflare.com')
$Script:SpeedUrl = 'https://speed.cloudflare.com/__down?bytes=25000000'

function Measure-PingResult {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Source = '',
        [int]$Count = 20
    )
    $argv = @('-n', "$Count", '-w', '1500')
    if ($Source) { $argv += @('-S', $Source) }
    $argv += $Target
    $out = (Invoke-Native -File 'ping.exe' -Arguments $argv).Text
    $times = @([regex]::Matches($out, 'time[=<]\s*(\d+)\s*ms') | ForEach-Object { [double]$_.Groups[1].Value })
    if ($times.Count -eq 0) {
        try {
            $fallback = @(Test-Connection -ComputerName $Target -Count $Count -ErrorAction Stop)
            $times = @($fallback | ForEach-Object { [double]$_.ResponseTime })
        } catch {
            Write-RunLog -Level 'WARN' -Message "ping to $Target got nothing back: $($_.Exception.Message)"
        }
    }
    if ($times.Count -eq 0) {
        return [pscustomobject]@{ Target = $Target; Avg = $null; Min = $null; Max = $null; Jitter = $null; Loss = 100 }
    }
    $jitter = 0
    if ($times.Count -gt 1) {
        $gaps = @()
        for ($i = 1; $i -lt $times.Count; $i++) { $gaps += [math]::Abs($times[$i] - $times[$i - 1]) }
        $jitter = [math]::Round(($gaps | Measure-Object -Average).Average, 1)
    }
    $stat = $times | Measure-Object -Average -Minimum -Maximum
    $loss = [math]::Round((($Count - $times.Count) / [double]$Count) * 100, 1)
    return [pscustomobject]@{
        Target = $Target
        Avg    = [math]::Round($stat.Average, 1)
        Min    = [math]::Round($stat.Minimum, 1)
        Max    = [math]::Round($stat.Maximum, 1)
        Jitter = $jitter
        Loss   = $loss
    }
}

function Measure-LookupTime {
    param([string[]]$Server = @())
    $ms = @()
    foreach ($name in $Script:LookupName) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            if ($Server.Count -gt 0) {
                Resolve-DnsName -Name $name -Server $Server[0] -Type A -DnsOnly -ErrorAction Stop | Out-Null
            } else {
                Resolve-DnsName -Name $name -Type A -DnsOnly -ErrorAction Stop | Out-Null
            }
            $watch.Stop()
            $ms += $watch.Elapsed.TotalMilliseconds
        } catch {
            $watch.Stop()
            Write-RunLog -Level 'WARN' -Message "lookup of $name failed: $($_.Exception.Message)"
        }
    }
    if ($ms.Count -eq 0) { return $null }
    return [math]::Round(($ms | Measure-Object -Average).Average, 1)
}

function Measure-DownloadSpeed {
    param([string]$SourceIp = '')
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $req = [System.Net.HttpWebRequest]::Create($Script:SpeedUrl)
        $req.Method = 'GET'
        $req.Timeout = 30000
        $req.ReadWriteTimeout = 30000
        $req.UserAgent = 'NetworkOptimiser'
        # only way to pin a download to one card on PS 5.1
        if ($SourceIp) {
            try {
                $req.ServicePoint.BindIPEndPointDelegate = [System.Net.BindIPEndPoint] {
                    return (New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse($SourceIp)), 0)
                }.GetNewClosure()
            } catch {
                Write-RunLog -Level 'WARN' -Message "Could not pin the download to $SourceIp, using the default route instead."
            }
        }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $buffer = New-Object byte[] 65536
        $total = 0L
        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $total += $read
            if ($watch.Elapsed.TotalSeconds -gt 25) { break }
        }
        $watch.Stop()
        $stream.Dispose()
        $resp.Dispose()
        if ($watch.Elapsed.TotalSeconds -le 0 -or $total -le 0) { return $null }
        return [math]::Round((($total * 8) / $watch.Elapsed.TotalSeconds) / 1000000, 1)
    } catch {
        Write-RunLog -Level 'WARN' -Message "speed test failed: $($_.Exception.Message)"
        return $null
    }
}

function Measure-NetworkTest {
    param([switch]$Quick)
    $cards = Select-ScopedAdapter -Adapter (Get-TargetAdapter)
    if ($cards.Count -eq 0) {
        Write-Ui -Text 'No live card to test.' -Style 'Bad'
        return $null
    }
    $rows = @()
    foreach ($c in $cards) {
        Write-Ui -Text "Testing $($c.Name) ($($c.Kind))..." -Style 'Plain'
        $pings = @()
        foreach ($h in $Script:PingHost) {
            Write-Ui -Text "  pinging $h" -Style 'Dim'
            $pings += Measure-PingResult -Target $h -Source $c.IPv4 -Count $(if ($Quick) { 10 } else { 20 })
        }
        $good = @($pings | Where-Object { $null -ne $_.Avg })
        $avg = if ($good.Count -gt 0) { [math]::Round((($good | Measure-Object -Property Avg -Average).Average), 1) } else { $null }
        $jit = if ($good.Count -gt 0) { [math]::Round((($good | Measure-Object -Property Jitter -Average).Average), 1) } else { $null }
        $loss = [math]::Round((($pings | Measure-Object -Property Loss -Average).Average), 1)
        Write-Ui -Text '  timing DNS lookups' -Style 'Dim'
        $dns = Measure-LookupTime -Server @($c.Dns | Where-Object { $_ -notmatch ':' })
        $speed = $null
        if (-not $Quick) {
            Write-Ui -Text '  downloading 25 MB to check the speed' -Style 'Dim'
            $speed = Measure-DownloadSpeed -SourceIp $c.IPv4
        }
        $rows += [pscustomobject]@{
            Card   = $c.Name
            Kind   = $c.Kind
            Ping   = $avg
            Jitter = $jit
            Loss   = $loss
            Dns    = $dns
            Speed  = $speed
        }
    }
    return @($rows)
}

function Format-TestValue {
    param($Value, [string]$Unit = '')
    if ($null -eq $Value) { return 'n/a' }
    return "$Value$Unit"
}

function Show-TestTable {
    param(
        [object[]]$Before,
        [object[]]$After
    )
    Write-Head -Text 'Results'
    $header = "{0,-22} {1,-9} {2,10} {3,10} {4,8} {5,10} {6,11}" -f 'Card', 'Type', 'Ping ms', 'Jitter ms', 'Loss %', 'DNS ms', 'Down Mbps'
    Write-Ui -Text $header -Style 'Head'
    Write-Ui -Text ('-' * $header.Length) -Style 'Dim'
    foreach ($row in $Before) {
        $line = "{0,-22} {1,-9} {2,10} {3,10} {4,8} {5,10} {6,11}" -f `
            $row.Card, $row.Kind, (Format-TestValue -Value $row.Ping), (Format-TestValue -Value $row.Jitter),
            (Format-TestValue -Value $row.Loss), (Format-TestValue -Value $row.Dns), (Format-TestValue -Value $row.Speed)
        Write-Ui -Text $line -Style 'Plain'
        if ($After) {
            $match = @($After | Where-Object { $_.Card -eq $row.Card }) | Select-Object -First 1
            if ($match) {
                $line2 = "{0,-22} {1,-9} {2,10} {3,10} {4,8} {5,10} {6,11}" -f `
                    '  after', '', (Format-TestValue -Value $match.Ping), (Format-TestValue -Value $match.Jitter),
                    (Format-TestValue -Value $match.Loss), (Format-TestValue -Value $match.Dns), (Format-TestValue -Value $match.Speed)
                Write-Ui -Text $line2 -Style 'Ok'
                Show-TestVerdict -Before $row -After $match
            }
        }
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'Ping and jitter are the numbers that matter for games and calls.' -Style 'Dim'
    Write-Ui -Text 'Run the test a few times. Internet speeds bounce around on their own.' -Style 'Dim'
}

function Show-TestVerdict {
    param($Before, $After)
    $notes = @()
    if ($null -ne $Before.Ping -and $null -ne $After.Ping) {
        $diff = [math]::Round($Before.Ping - $After.Ping, 1)
        if ([math]::Abs($diff) -lt 1) { $notes += 'ping about the same' }
        elseif ($diff -gt 0) { $notes += "ping $diff ms better" }
        else { $notes += "ping $([math]::Abs($diff)) ms worse" }
    }
    if ($null -ne $Before.Jitter -and $null -ne $After.Jitter) {
        $diff = [math]::Round($Before.Jitter - $After.Jitter, 1)
        if ($diff -gt 0.5) { $notes += "jitter $diff ms better" }
        elseif ($diff -lt -0.5) { $notes += "jitter $([math]::Abs($diff)) ms worse" }
    }
    if ($null -ne $Before.Speed -and $null -ne $After.Speed) {
        $diff = [math]::Round($After.Speed - $Before.Speed, 1)
        if ([math]::Abs($diff) -gt 2) { $notes += "download $diff Mbps different" }
    }
    if ($notes.Count -gt 0) {
        Write-Ui -Text ("  verdict: " + ($notes -join ', ')) -Style 'Dim'
    }
}

function Invoke-TestMenu {
    while ($true) {
        Write-Head -Text 'Speed and ping test'
        $haveBefore = $null -ne $Script:Cfg.Tested.Before
        Write-Ui -Text '1. Run the BEFORE test' -Style 'Plain'
        Write-Ui -Text '2. Run the AFTER test and compare' -Style 'Plain'
        Write-Ui -Text '3. Quick ping only, no download' -Style 'Plain'
        Write-Ui -Text '4. Show the last results again' -Style 'Plain'
        Write-Ui -Text '0. Back' -Style 'Plain'
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text "Before test done: $(if ($haveBefore) { 'yes' } else { 'no' })" -Style 'Dim'
        if (Get-Command -Name 'speedtest' -ErrorAction SilentlyContinue) {
            Write-Ui -Text 'Ookla speedtest CLI spotted on this PC. Option 5 will use it.' -Style 'Dim'
            Write-Ui -Text '5. Run Ookla speedtest CLI' -Style 'Plain'
        }
        $pick = Read-Choice -Question 'Pick one'
        switch ($pick) {
            '1' {
                $Script:Cfg.Tested.Before = Measure-NetworkTest
                $Script:Cfg.Tested.After = $null
                if ($Script:Cfg.Tested.Before) { Show-TestTable -Before $Script:Cfg.Tested.Before }
                Wait-Key
            }
            '2' {
                if (-not $haveBefore) {
                    Write-Ui -Text 'Run the before test first or there is nothing to compare with.' -Style 'Warn'
                    Wait-Key
                    continue
                }
                $Script:Cfg.Tested.After = Measure-NetworkTest
                Show-TestTable -Before $Script:Cfg.Tested.Before -After $Script:Cfg.Tested.After
                Wait-Key
            }
            '3' {
                $rows = Measure-NetworkTest -Quick
                if ($rows) { Show-TestTable -Before $rows }
                Wait-Key
            }
            '4' {
                if (-not $haveBefore) {
                    Write-Ui -Text 'Nothing saved yet.' -Style 'Warn'
                } else {
                    Show-TestTable -Before $Script:Cfg.Tested.Before -After $Script:Cfg.Tested.After
                }
                Wait-Key
            }
            '5' {
                [void](Invoke-Action -Label 'Ookla speedtest' -Work {
                    $r = Invoke-Native -File 'speedtest' -Arguments @('--accept-license', '--accept-gdpr')
                    Write-Ui -Text $r.Text -Style 'Plain'
                    return $null
                })
                Wait-Key
            }
            '0' { return }
            default { return }
        }
    }
}

function Show-Banner {
    Clear-Host
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text '  ==============================================================' -Style 'Head'
    Write-Ui -Text "   $($Script:Cfg.Title)  v$($Script:Cfg.Version)" -Style 'Head'
    Write-Ui -Text '   Cleans and tunes Wi-Fi and Ethernet on Windows 10 and 11' -Style 'Head'
    Write-Ui -Text '  ==============================================================' -Style 'Head'
    Write-Ui -Text '' -Style 'Plain'
}

function Select-TargetKind {
    $cards = Get-TargetAdapter
    Write-Head -Text 'Which cards do you want to work on?'
    if ($cards.Count -eq 0) {
        Write-Ui -Text 'Nothing is connected right now.' -Style 'Warn'
    }
    foreach ($c in $cards) {
        Write-Ui -Text "  $("$($c.Kind)".PadRight(8)) $("$($c.Name)".PadRight(24)) $("$($c.Speed)".PadRight(12)) $($c.IPv4)" -Style 'Ok'
        Write-Ui -Text "           $($c.Desc)" -Style 'Dim'
    }
    $gwCard = @($cards | Where-Object { $_.Gateway }) | Select-Object -First 1
    if ($gwCard) {
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text "Your internet is going out through: $($gwCard.Name) ($($gwCard.Kind))" -Style 'Head'
    }
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text '1. Wi-Fi only' -Style 'Plain'
    Write-Ui -Text '2. Ethernet only' -Style 'Plain'
    Write-Ui -Text '3. Both' -Style 'Plain'
    Write-Ui -Text "4. Turn virtual cards on or off  [now: $(if ($Script:Cfg.Virtual) { 'included' } else { 'skipped' })]" -Style 'Plain'
    $pick = Read-Choice -Question 'Pick one' -Default '3'
    switch ($pick) {
        '1' { $Script:Cfg.Target = 'WiFi' }
        '2' { $Script:Cfg.Target = 'Ethernet' }
        '4' {
            $Script:Cfg.Virtual = -not $Script:Cfg.Virtual
            if ($Script:Cfg.Virtual) {
                Write-Ui -Text 'Virtual cards are now included. Hyper-V switches, VPN adapters and WSL' -Style 'Warn'
                Write-Ui -Text 'will get changed too. Bouncing one of those can drop a VM or a VPN.' -Style 'Warn'
            } else {
                Write-Ui -Text 'Virtual cards are back to being skipped.' -Style 'Ok'
            }
            Write-RunLog -Message "virtual cards included: $($Script:Cfg.Virtual)"
            Wait-Key
            return
        }
        default { $Script:Cfg.Target = 'Both' }
    }
    Write-Ui -Text "Working on: $($Script:Cfg.Target)" -Style 'Ok'
    Write-RunLog -Message "target set to $($Script:Cfg.Target)"
    Wait-Key
}

function Invoke-GroupMenu {
    param(
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string]$Heading,
        $Extra = $null
    )
    while ($true) {
        Write-Head -Text $Heading
        $ids = @($Script:Tweaks.Keys | Where-Object { $Script:Tweaks[$_].Group -eq $Group })
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $t = $Script:Tweaks[$ids[$i]]
            $style = if ($t.Risk -eq 'High') { 'Bad' } elseif ($t.Risk -eq 'Medium') { 'Warn' } else { 'Plain' }
            $flag = ''
            if ($t.Reboot) { $flag = '  (needs a reboot)' }
            Write-Ui -Text ("{0,2}. {1}{2}" -f ($i + 1), $t.Title, $flag) -Style $style
            Write-Ui -Text "    $($t.Detail)" -Style 'Dim'
        }
        if ($null -ne $Extra) {
            Write-Ui -Text '' -Style 'Plain'
            foreach ($key in $Extra.Keys) {
                Write-Ui -Text " $key. $($Extra[$key].Label)" -Style 'Plain'
            }
        }
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text ' A. Do every one of the numbered items above' -Style 'Plain'
        Write-Ui -Text ' 0. Back to the main menu' -Style 'Plain'
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text 'Red means it can break things. Yellow means think first.' -Style 'Dim'
        $pick = Read-Choice -Question 'Pick one, or several split by commas'
        if (-not $pick -or $pick -eq '0') { return }
        if ($pick.ToUpper() -eq 'A') {
            Invoke-TweakList -Ids $ids
            continue
        }
        if ($null -ne $Extra -and $Extra.Contains($pick.ToUpper())) {
            & $Extra[$pick.ToUpper()].Run
            continue
        }
        $chosen = @()
        foreach ($bit in ($pick -split ',')) {
            $n = 0
            if ([int]::TryParse($bit.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $ids.Count) {
                $chosen += $ids[$n - 1]
            }
        }
        if ($chosen.Count -eq 0) {
            Write-Ui -Text 'That was not on the list.' -Style 'Warn'
            continue
        }
        Invoke-TweakList -Ids $chosen
    }
}

function Invoke-CleanMenu {
    Invoke-GroupMenu -Group 'Clean' -Heading 'Clean and reset the network caches'
}

function Invoke-TcpMenu {
    $extra = [ordered]@{
        'D' = @{ Label = 'Change DNS servers (Cloudflare, Google, Quad9 or back to automatic)'; Run = { Select-DnsServer } }
        'E' = @{ Label = 'Turn on encrypted DNS (Windows 11 only)'; Run = { Enable-DohChoice } }
        'S' = @{ Label = 'Show the TCP settings Windows is using now'; Run = {
                Write-Head -Text 'TCP settings'
                $txt = (Invoke-Native -File 'netsh.exe' -Arguments @('int', 'tcp', 'show', 'global')).Text
                foreach ($line in ($txt -split "`r?`n")) { if ($line.Trim()) { Write-Ui -Text "  $($line.Trim())" -Style 'Dim' } }
                Write-Ui -Text '' -Style 'Plain'
                Write-Ui -Text 'Auto-tuning levels, plain English:' -Style 'Plain'
                Write-Ui -Text '  normal            the default, right for nearly everyone' -Style 'Dim'
                Write-Ui -Text '  restricted        holds the window back a bit, only for dodgy routers' -Style 'Dim'
                Write-Ui -Text '  highlyrestricted  holds it back a lot, last resort' -Style 'Dim'
                Write-Ui -Text '  disabled          old fixed 64 KB window, will cap you on fast lines' -Style 'Dim'
                Write-Ui -Text '  experimental      huge window, can upset older kit' -Style 'Dim'
                Wait-Key
            }
        }
    }
    Invoke-GroupMenu -Group 'Tcp' -Heading 'TCP/IP tweaks' -Extra $extra
}

function Invoke-WiFiMenu {
    $extra = [ordered]@{
        'S' = @{ Label = 'Show signal, band, channel and link speed'; Run = { Show-WiFiInfo } }
        'P' = @{ Label = 'Browse and change this card driver settings one by one'; Run = { Show-AdvancedEditor -Kind 'WiFi' } }
        'R' = @{ Label = 'Build the Wi-Fi drop report'; Run = { Save-WlanReport } }
        'C' = @{ Label = 'Switch the Wi-Fi card off and back on'; Run = {
                Invoke-TweakList -Ids @('clean-cycle')
            }
        }
    }
    Invoke-GroupMenu -Group 'WiFi' -Heading 'Wi-Fi tweaks' -Extra $extra
}

function Invoke-EthernetMenu {
    $extra = [ordered]@{
        'P' = @{ Label = 'Browse and change this card driver settings one by one'; Run = { Show-AdvancedEditor -Kind 'Ethernet' } }
        'J' = @{ Label = 'Turn Jumbo Frames ON (read the warning first)'; Run = { Enable-JumboFrame } }
        'F' = @{ Label = 'Force a speed and duplex instead of Auto'; Run = { Set-SpeedDuplex } }
        'W' = @{ Label = 'Wake on LAN settings'; Run = { Set-WakeOnLan } }
        'D' = @{ Label = 'Driver version and where to get updates'; Run = { Show-DriverNote } }
        'C' = @{ Label = 'Switch the Ethernet card off and back on'; Run = {
                Invoke-TweakList -Ids @('clean-cycle')
            }
        }
    }
    Invoke-GroupMenu -Group 'Ethernet' -Heading 'Ethernet tweaks' -Extra $extra
}

function Enable-JumboFrame {
    Write-Head -Text 'Jumbo Frames'
    Write-Ui -Text 'Jumbo frames send bigger chunks of data at once. On a home network that only helps' -Style 'Plain'
    Write-Ui -Text 'if you move huge files to a NAS or another PC.' -Style 'Plain'
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'READ THIS: every switch, router and PC in the path has to support it and be set the same.' -Style 'Warn'
    Write-Ui -Text 'If one of them does not, you get slow transfers and things that half work. Your internet' -Style 'Warn'
    Write-Ui -Text 'connection will not get any faster either way.' -Style 'Warn'
    if (-not (Confirm-Go -Question 'Still want it on?')) { return }
    $cards = @((Get-TargetAdapter) | Where-Object { $_.Kind -eq 'Ethernet' })
    foreach ($c in $cards) {
        [void](Invoke-Action -Label "jumbo frames on for $($c.Name)" -Work {
            return (Set-PropertyGroup -Adapter $c -Key 'Jumbo' -Prefer @('9014', '9014 Bytes', '9000', '9k', 'Jumbo 9000'))
        }.GetNewClosure())
    }
    Wait-Key
}

function Set-SpeedDuplex {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Head -Text 'Speed and duplex'
    Write-Ui -Text 'Auto Negotiation is right almost every time. Only force a speed if you know the other' -Style 'Plain'
    Write-Ui -Text 'end is broken. Forcing the wrong thing gets you a dead link or awful speeds.' -Style 'Warn'
    $cards = @((Get-TargetAdapter) | Where-Object { $_.Kind -eq 'Ethernet' })
    if ($cards.Count -eq 0) {
        Write-Ui -Text 'No live Ethernet card.' -Style 'Warn'
        Wait-Key
        return
    }
    foreach ($c in $cards) {
        $props = Get-AdapterProperty -Adapter $c -Key 'SpeedDuplex'
        if ($props.Count -eq 0) {
            Write-Ui -Text "$($c.Name) does not let you set this." -Style 'Warn'
            continue
        }
        $p = $props[0]
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text "$($c.Name) is on: $($p.DisplayValue)" -Style 'Plain'
        $valid = @($p.ValidDisplayValues)
        for ($i = 0; $i -lt $valid.Count; $i++) {
            Write-Ui -Text ("  {0}. {1}" -f ($i + 1), $valid[$i]) -Style 'Plain'
        }
        $pick = Read-Choice -Question 'Number (blank to leave it alone)'
        if (-not $pick) { continue }
        $n = 0
        if (-not ([int]::TryParse($pick, [ref]$n)) -or $n -lt 1 -or $n -gt $valid.Count) { continue }
        $val = $valid[$n - 1]
        if ($PSCmdlet.ShouldProcess($c.Name, "set speed and duplex to $val")) {
            [void](Invoke-Action -Label "$($c.Name) set to $val" -Work {
                Set-NetAdapterAdvancedProperty -Name $c.Name -DisplayName $p.DisplayName -DisplayValue $val -NoRestart -ErrorAction Stop
                return $null
            }.GetNewClosure())
        }
    }
    Wait-Key
}

function Set-WakeOnLan {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Head -Text 'Wake on LAN'
    Write-Ui -Text 'Wake on LAN lets another device switch this PC on over the network.' -Style 'Plain'
    Write-Ui -Text 'Turning it off can stop random wake ups. Turning it on lets you wake the PC remotely.' -Style 'Dim'
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text '1. Turn Wake on LAN OFF (stops random wake ups)' -Style 'Plain'
    Write-Ui -Text '2. Turn Wake on LAN ON (magic packet only)' -Style 'Plain'
    $pick = Read-Choice -Question 'Pick one (blank to go back)'
    if ($pick -notin @('1', '2')) { return }
    $on = ($pick -eq '2')
    $cards = Select-ScopedAdapter -Adapter (Get-TargetAdapter)
    foreach ($c in $cards) {
        if (-not $PSCmdlet.ShouldProcess($c.Name, "wake on lan $(if ($on) { 'on' } else { 'off' })")) { continue }
        [void](Invoke-Action -Label "wake on LAN on $($c.Name)" -Work {
            $state = if ($on) { 'Enabled' } else { 'Disabled' }
            Set-NetAdapterPowerManagement -Name $c.Name -WakeOnMagicPacket $state -WakeOnPattern 'Disabled' -NoRestart -ErrorAction Stop
            return "magic packet $state, pattern wake off"
        }.GetNewClosure())
    }
    Wait-Key
}

function Invoke-PresetMenu {
    while ($true) {
        Write-Head -Text 'Presets'
        $keys = @($Script:Presets.Keys)
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $p = $Script:Presets[$keys[$i]]
            Write-Ui -Text ("{0}. {1}" -f ($i + 1), $p.Title) -Style 'Plain'
            Write-Ui -Text "   $($p.Detail)" -Style 'Dim'
        }
        Write-Ui -Text ("{0}. Custom - pick tweaks one by one" -f ($keys.Count + 1)) -Style 'Plain'
        Write-Ui -Text '0. Back' -Style 'Plain'
        $pick = Read-Choice -Question 'Pick one'
        $n = 0
        if (-not ([int]::TryParse($pick, [ref]$n))) { return }
        if ($n -eq 0) { return }
        if ($n -eq ($keys.Count + 1)) { Invoke-CustomPick; continue }
        if ($n -ge 1 -and $n -le $keys.Count) {
            Invoke-TweakList -Ids $Script:Presets[$keys[$n - 1]].Ids
        }
    }
}

function Invoke-UndoMenu {
    Write-Head -Text 'Undo'
    $folder = Get-LastRunFolder
    Write-Ui -Text '1. Put everything back from the saved settings file' -Style 'Plain'
    if ($folder) {
        Write-Ui -Text "   Newest backup: $folder" -Style 'Dim'
    } else {
        Write-Ui -Text '   No backup found. Option 1 will not work.' -Style 'Warn'
    }
    Write-Ui -Text '2. Force everything back to Windows defaults (use this if the backup is gone)' -Style 'Plain'
    Write-Ui -Text '3. Pick an older backup folder' -Style 'Plain'
    Write-Ui -Text '0. Back' -Style 'Plain'
    $pick = Read-Choice -Question 'Pick one'
    switch ($pick) {
        '1' {
            if (-not $folder) { Wait-Key; return }
            if (-not (Confirm-Go -Question 'Put every setting back to how it was before?')) { return }
            [void](Invoke-Action -Label 'restore from backup' -Work { return (Restore-NetworkState -Folder $folder) })
            Show-Finish
            Wait-Key
        }
        '2' {
            Write-Ui -Text 'This resets every advanced setting on every card to the driver default.' -Style 'Warn'
            if (-not (Confirm-Go -Question 'Sure?')) { return }
            Restore-WindowsDefault
            Show-Finish
            Wait-Key
        }
        '3' {
            $runs = @(Get-ChildItem -LiteralPath $Script:Cfg.Home -Directory -Filter 'run_*' -ErrorAction SilentlyContinue |
                Sort-Object -Property Name -Descending)
            if ($runs.Count -eq 0) {
                Write-Ui -Text 'No backups saved yet.' -Style 'Warn'
                Wait-Key
                return
            }
            for ($i = 0; $i -lt $runs.Count; $i++) {
                Write-Ui -Text ("{0,2}. {1}" -f ($i + 1), $runs[$i].Name) -Style 'Plain'
            }
            $p = Read-Choice -Question 'Number'
            $n = 0
            if ([int]::TryParse($p, [ref]$n) -and $n -ge 1 -and $n -le $runs.Count) {
                if (Confirm-Go -Question "Restore from $($runs[$n - 1].Name)?") {
                    [void](Invoke-Action -Label 'restore from backup' -Work { return (Restore-NetworkState -Folder $runs[$n - 1].FullName) })
                    Show-Finish
                }
            }
            Wait-Key
        }
        default { return }
    }
}

function Invoke-MainMenu {
    while ($true) {
        Show-Banner
        $dry = if ($Script:Cfg.DryRun) { 'ON' } else { 'OFF' }
        $dryStyle = if ($Script:Cfg.DryRun) { 'Warn' } else { 'Dim' }
        Write-Ui -Text '  1. Show me what I have got (all cards, speeds, IPs, DNS, TCP settings)' -Style 'Plain'
        $virt = if ($Script:Cfg.Virtual) { ', virtual included' } else { '' }
        Write-Ui -Text "  2. Pick which cards to work on            [now: $($Script:Cfg.Target)$virt]" -Style 'Plain'
        Write-Ui -Text '  3. Clean and reset caches' -Style 'Plain'
        Write-Ui -Text '  4. TCP/IP tweaks and DNS' -Style 'Plain'
        Write-Ui -Text '  5. Wi-Fi tweaks' -Style 'Plain'
        Write-Ui -Text '  6. Ethernet tweaks' -Style 'Plain'
        Write-Ui -Text '  7. Presets (Safe, Gaming, Full Clean, Custom)' -Style 'Plain'
        Write-Ui -Text '  8. Speed and ping test, before and after' -Style 'Plain'
        Write-Ui -Text '  9. Undo' -Style 'Plain'
        Write-Ui -Text '' -Style 'Plain'
        Write-Ui -Text "  D. Dry run mode                          [now: $dry]" -Style $dryStyle
        Write-Ui -Text '  L. Open the log and backup folder' -Style 'Plain'
        Write-Ui -Text '  0. Quit' -Style 'Plain'
        Write-Ui -Text '' -Style 'Plain'
        if ($Script:Cfg.Reboot) {
            Write-Ui -Text '  You have changes waiting on a reboot.' -Style 'Warn'
        }
        $pick = (Read-Choice -Question 'Pick one').ToUpper()
        switch ($pick) {
            '1' { Show-NetworkSummary }
            '2' { Select-TargetKind }
            '3' { Invoke-CleanMenu }
            '4' { Invoke-TcpMenu }
            '5' { Invoke-WiFiMenu }
            '6' { Invoke-EthernetMenu }
            '7' { Invoke-PresetMenu }
            '8' { Invoke-TestMenu }
            '9' { Invoke-UndoMenu }
            'D' {
                $Script:Cfg.DryRun = -not $Script:Cfg.DryRun
                Write-Ui -Text "Dry run is now $(if ($Script:Cfg.DryRun) { 'ON, nothing will be changed' } else { 'OFF, changes are real' })" -Style 'Warn'
                Start-Sleep -Seconds 2
            }
            'L' {
                Start-Process -FilePath 'explorer.exe' -ArgumentList $Script:Cfg.Run
            }
            '0' {
                if ($Script:Cfg.Reboot) {
                    Write-Ui -Text 'Remember to reboot for the rest of the changes to kick in.' -Style 'Warn'
                    Start-Sleep -Seconds 2
                }
                return
            }
            default { }
        }
    }
}

function Invoke-Main {
    if (-not (Test-Admin)) {
        Invoke-SelfElevate
        return
    }
    Initialize-Workspace
    Show-Banner
    Write-Ui -Text "Logging to: $($Script:Cfg.LogFile)" -Style 'Dim'
    if ($Script:Cfg.DryRun) {
        Write-Ui -Text 'Dry run mode is ON. Nothing will actually change.' -Style 'Warn'
    }
    if ($Script:Cfg.Preset) {
        Write-Ui -Text "Running the $($Script:Cfg.Preset) preset straight off." -Style 'Plain'
        Invoke-TweakList -Ids $Script:Presets[$Script:Cfg.Preset].Ids
        return
    }
    Start-Sleep -Milliseconds 700
    Invoke-MainMenu
    Write-Ui -Text '' -Style 'Plain'
    Write-Ui -Text 'Sorted. Catch you later.' -Style 'Ok'
    Write-RunLog -Message 'finished'
}

Invoke-Main
