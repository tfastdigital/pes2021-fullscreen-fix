#Requires -Version 5.1
<#
.NOTES
    Version: 1.1.0
    Project: https://github.com/tfastdigital6/pes2021-fullscreen-fix
    Licence: MIT

.SYNOPSIS
    Permanent fullscreen fix for eFootball PES 2021 SEASON UPDATE (any PC, any install folder).

.DESCRIPTION
    PES 2021 is an exclusive-fullscreen game. On modern Windows it drops to the taskbar when
    something steals focus (screen recorders, notifications, Windows Update), and it fails to
    enter fullscreen at all when the desktop uses DPI scaling > 100% or when
    "fullscreen optimizations" are enabled.

    This script makes the game start (and stay) in true fullscreen:

      1. settings.dat  : Screen Mode = Full Screen + the monitor's native resolution.
      2. PES2021.exe   : "Disable fullscreen optimizations" + "Override high DPI scaling:
                         Application" compatibility flags (per-user, works on any PC).
      3. PES2021.exe   : Windows graphics preference = High performance (fixes hybrid-GPU
                         laptops that flip between Intel and NVIDIA/AMD).
      4. Keeper        : while the game runs it restores + refocuses the window within ~0.5 s
                         whenever it gets minimized involuntarily. Deliberate Alt+Tab / Win
                         key is respected and never fought.
      5. Overlays      : known focus-stealing overlays (screen recorders, Xbox Game Bar,
                         NVIDIA/AMD/Overwolf/RivaTuner overlays) are closed automatically
                         while the game runs, and Game Bar / Game DVR is switched off.
    6. Focus lock    : Windows' own foreground lock is raised (ForegroundLockTimeout via
                 SPI_SETFOREGROUNDLOCKTIMEOUT) so background apps cannot pull the
                 game out of fullscreen. This is the documented fix for the
                 Windows 11 24H2/25H2 "game jumps to the desktop" bug.
    7. Diagnose      : -Action Diagnose logs which process grabs the foreground, so an
                 unknown focus thief can be identified on any PC.

    Everything is auto-detected: game folder, Documents\KONAMI settings folder, monitor
    resolution. Nothing is hard-coded, no admin rights needed, so the whole game folder can
    be copied to another PC and the fix keeps working.

.PARAMETER Action
    Play    (default) Repair everything, launch the game, keep it fullscreen until it exits.
    Fix              Repair settings/registry only (no launch).
    Keep             Watchdog only - attach to a running game (or wait for one to start).
    Overlays         Close known overlay processes now and exit.
    Diagnose         Log foreground-window changes for -DiagnoseSeconds and report the
                     processes that keep grabbing focus. Changes nothing.
    Restore          Undo every change (settings backup, registry values, startup entry).

.PARAMETER ForegroundLockMs
    Foreground lock timeout in milliseconds (default 3600000 = 1 hour). The timer restarts on
    every key press / mouse move, so while you play no background app can grab focus.
    Windows' own default is 200000 (200 s). Use -NoForegroundLock to leave it untouched.

.PARAMETER NoForegroundLock
    Do not change the Windows foreground lock timeout.

.PARAMETER SilenceNotifications
    Turn off Windows notification banners while the game runs (restored by -Action Restore).
    Notification toasts are a documented cause of fullscreen games dropping to the taskbar.

.PARAMETER DefenderExclusion
    Add the game folder to Microsoft Defender exclusions. Reported on the PES forums to fix
    fullscreen and "save data" failures caused by the antivirus blocking the game. Needs an
    elevated PowerShell window; skipped with a message otherwise.

.PARAMETER DiagnoseSeconds
    How long -Action Diagnose watches the foreground window (default 120).

.PARAMETER GpuPreference
    Which graphics processor the game must use when the PC has more than one GPU
    (integrated + discrete). Everything is detected automatically - no vendor names are
    hard-coded, so the same script works on other PCs.

    Auto        (default) Highest-performance GPU whenever 2+ GPUs are found.
    High        Always the high-performance / discrete GPU.
    PowerSaving Always the integrated GPU.
    Default     Let Windows decide (removes the override).
    Skip        Do not touch the GPU setting at all.

.PARAMETER NoGpuFix
    Shorthand for -GpuPreference Skip.

.PARAMETER OverlayAction
    Close  (default) Terminate known overlay processes while the game is running.
    Report           Only list the overlays that are running - close nothing.
    Off              Do not touch overlays at all.

.PARAMETER PreserveOverlay
    Names from the built-in overlay list to leave alone, e.g. -PreserveOverlay 'OBS Studio'.

.PARAMETER ExtraOverlay
    Additional process names to treat as overlays and close, e.g. -ExtraOverlay 'MyOverlayApp'.

.PARAMETER OverlayScanSeconds
    How often overlays are re-checked while playing (default 15 s), so a recorder that
    restarts itself is closed again.

.PARAMETER NoGameBarFix
    Do not switch off Xbox Game Bar / Game DVR in the registry.

.PARAMETER Mode
    Fullscreen (default) True exclusive fullscreen - recommended, taskbar is hidden by Windows.
    Borderless           Fallback for PCs where exclusive fullscreen cannot work (broken driver,
                         capture cards, some multi-monitor setups). Runs the game in a borderless
                         window that covers the monitor.

.PARAMETER GameDir
    Folder containing PES2021.exe. Auto-detected when omitted.

.PARAMETER MonitorIndex
    Which monitor to play on (0 = first). Default: the primary monitor.

.PARAMETER InstallStartup
    Also start the watchdog at Windows logon, so the fix works even when you launch the game
    from its own shortcut, Steam or the exe directly.

.PARAMETER RemoveStartup
    Remove the logon watchdog.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\PES2021-Fullscreen.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\PES2021-Fullscreen.ps1 -Action Fix -InstallStartup

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\PES2021-Fullscreen.ps1 -Mode Borderless
#>
[CmdletBinding()]
param(
    [ValidateSet('Play', 'Fix', 'Keep', 'Overlays', 'Diagnose', 'Gpu', 'Restore')]
    [string]$Action = 'Play',

    [ValidateSet('Fullscreen', 'Borderless')]
    [string]$Mode = 'Fullscreen',

    [string]$GameDir,

    [int]$MonitorIndex = -1,

    [switch]$InstallStartup,
    [switch]$RemoveStartup,
    [int]$StartupGraceSeconds = 150,
    [switch]$AlwaysRestore,

    [ValidateSet('Close', 'Report', 'Off')]
    [string]$OverlayAction = 'Close',

    [string[]]$PreserveOverlay = @(),
    [string[]]$ExtraOverlay = @(),
    [int]$OverlayScanSeconds = 15,
    [switch]$NoGameBarFix,

    [uint32]$ForegroundLockMs = 3600000,
    [switch]$NoForegroundLock,
    [switch]$SilenceNotifications,
    [switch]$DefenderExclusion,
    [int]$DiagnoseSeconds = 120,

    [ValidateSet('Auto', 'High', 'PowerSaving', 'Default', 'Skip')]
    [string]$GpuPreference = 'Auto',
    [switch]$NoGpuFix,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$script:LogFile = Join-Path $env:TEMP 'PES2021Fullscreen.log'
$script:SettingsBackupSuffix = '.pesfix.bak'
$script:StateDir = Join-Path $env:LOCALAPPDATA 'PES2021FullscreenFix'
$script:PreservedOverlays = @($PreserveOverlay)
$script:ExtraOverlays = @($ExtraOverlay)
$script:OverlayNoted = @{}
$script:OverlayCloseCount = @{}

# --------------------------------------------------------------------------- interop
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class PesFix
{
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct MONITORINFO {
        public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
    }

    public const int SW_RESTORE = 9;
    public const int GWL_STYLE   = -16;
    public const int GWL_EXSTYLE = -20;

    public static readonly int WS_CAPTION    = 0x00C00000;
    public static readonly int WS_THICKFRAME = 0x00040000;
    public static readonly int WS_SYSMENU    = 0x00080000;
    public static readonly int WS_MINIMIZEBOX= 0x00020000;
    public static readonly int WS_MAXIMIZEBOX= 0x00010000;
    public static readonly int WS_BORDER     = 0x00800000;
    public static readonly int WS_POPUP_VIS  = unchecked((int)0x94000000); // POPUP|VISIBLE|CLIPSIBLINGS

    public static readonly IntPtr HWND_TOPMOST    = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST  = new IntPtr(-2);
    public const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010;

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int idx, int value);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="GetWindowTextW")]
    public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

    const uint SPI_GETFOREGROUNDLOCKTIMEOUT = 0x2000;
    const uint SPI_SETFOREGROUNDLOCKTIMEOUT = 0x2001;
    const uint SPIF_UPDATEINIFILE = 0x01;
    const uint SPIF_SENDCHANGE    = 0x02;

    // Windows' foreground lock: for this many ms after user input, background apps are
    // refused when they try to push themselves into the foreground.
    //
    // NOTE (verified on Windows 11 26200): SPI_SETFOREGROUNDLOCKTIMEOUT takes the value
    // directly in pvParam - passing a pointer corrupts the stored setting. SPI_GET...
    // returns a cached value, so the authoritative read is the registry value.
    public static bool SetForegroundLockTimeout(uint milliseconds)
    {
        return SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0,
                                    (IntPtr)unchecked((int)milliseconds),
                                    SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }

    // ---- helpers ----------------------------------------------------------------

    const uint GW_OWNER = 4;
    const int WS_EX_TOOLWINDOW = 0x00000080;

    // Windows the user reaches on purpose: taskbar, desktop, task view, start menu.
    static readonly string[] DeliberateClasses = new string[] {
        "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
        "Progman", "WorkerW", "ForegroundStaging", "MultitaskingViewFrame",
        "InputApp", "Shell_InputSwitchTopLevelWindow", "Windows.UI.Core.CoreWindow"
    };

    // A window that looks like an app the user actually switched to (has a taskbar button,
    // a title, no owner). Notifications, tooltips and game overlays do not match this.
    public static bool IsRealAppWindow(IntPtr h)
    {
        if (h == IntPtr.Zero) return false;
        if (!IsWindowVisible(h)) return false;
        if ((GetWindowLong(h, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return false;
        if (GetWindow(h, GW_OWNER) != IntPtr.Zero) return false;
        if (GetWindowTextLength(h) == 0) return false;

        var sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        string cls = sb.ToString();
        foreach (string bad in DeliberateClasses) if (cls == bad) return false;
        if (cls.StartsWith("Windows.UI.") || cls.StartsWith("Qt")) return false;
        return true;
    }

    // True when the player clearly chose to leave the game (Alt/Win held, taskbar, desktop
    // or a normal app in the foreground). False for notifications / overlay junk.
    public static bool ForegroundShowsUserLeft()
    {
        if (UserWantsOut()) return true;
        IntPtr fg = GetForegroundWindow();
        if (IsRealAppWindow(fg)) return true;

        var sb = new StringBuilder(256);
        GetClassName(fg, sb, 256);
        string cls = sb.ToString();
        foreach (string deliberate in DeliberateClasses) if (cls == deliberate) return true;
        return false;
    }

    public static bool UserWantsOut()
    {
        // Any of these being held means the player is deliberately leaving the game.
        short alt   = GetAsyncKeyState(0x12); // VK_MENU
        short lwin  = GetAsyncKeyState(0x5B); // VK_LWIN
        short rwin  = GetAsyncKeyState(0x5C); // VK_RWIN
        return (alt & 0x8000) != 0 || (lwin & 0x8000) != 0 || (rwin & 0x8000) != 0;
    }

    // Bring the game window back and give it the foreground. When a raised
    // ForegroundLockTimeout is in force our own process is a "background" caller too, so the
    // restore is done with the lock temporarily released and then put straight back.
    public static bool Focus(IntPtr h, uint lockToRestore)
    {
        if (AttemptFocus(h)) return true;
        if (lockToRestore == 0) return false;

        SetForegroundLockTimeout(0);
        try { return AttemptFocus(h); }
        finally { SetForegroundLockTimeout(lockToRestore); }
    }

    public static bool Focus(IntPtr h) { return Focus(h, 0); }

    static bool AttemptFocus(IntPtr h)
    {
        if (IsIconic(h)) { ShowWindow(h, SW_RESTORE); System.Threading.Thread.Sleep(120); }
        BringWindowToTop(h);
        if (GetForegroundWindow() == h) return true;

        uint pid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out pid);
        uint me = GetCurrentThreadId();
        if (fgThread != 0 && fgThread != me) AttachThreadInput(me, fgThread, true);
        bool ok = SetForegroundWindow(h);
        if (fgThread != 0 && fgThread != me) AttachThreadInput(me, fgThread, false);

        if (!ok || GetForegroundWindow() != h)
        {
            // Classic foreground-lock bypass: a synthetic Alt tap unlocks SetForegroundWindow.
            keybd_event(0x12, 0, 0, IntPtr.Zero);
            keybd_event(0x12, 0, 2, IntPtr.Zero);
            ok = SetForegroundWindow(h);
        }
        return ok || GetForegroundWindow() == h;
    }

    public static IntPtr MonitorOf(IntPtr h)
    {
        return MonitorFromWindow(h, 2 /*MONITOR_DEFAULTTONEAREST*/);
    }

    public static RECT MonitorBounds(IntPtr monitor)
    {
        var mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        if (monitor != IntPtr.Zero && GetMonitorInfo(monitor, ref mi)) return mi.rcMonitor;
        return new RECT { Left = 0, Top = 0, Right = 0, Bottom = 0 };
    }

    public static RECT WindowBounds(IntPtr h)
    {
        RECT r; GetWindowRect(h, out r); return r;
    }

    public static bool IsBorderless(IntPtr h)
    {
        int style = GetWindowLong(h, GWL_STYLE);
        int stripped = WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_BORDER;
        return (style & stripped) == 0 && (style & unchecked((int)0x80000000)) != 0; // no frame + WS_POPUP
    }

    public static void MakeBorderless(IntPtr h, RECT target)
    {
        int style = GetWindowLong(h, GWL_STYLE);
        style &= ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_BORDER);
        style |= WS_POPUP_VIS;
        SetWindowLong(h, GWL_STYLE, style);
        SetWindowLong(h, GWL_EXSTYLE, GetWindowLong(h, GWL_EXSTYLE) & ~0x00000100); // drop WS_EX_WINDOWEDGE
        SetWindowPos(h, IntPtr.Zero,
            target.Left, target.Top, target.Right - target.Left, target.Bottom - target.Top,
            SWP_NOACTIVATE);
    }

    public static void SetTopmost(IntPtr h, bool on)
    {
        SetWindowPos(h, on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    public static bool IsTopmost(IntPtr h)
    {
        return (GetWindowLong(h, GWL_EXSTYLE) & 0x00000008) != 0;
    }

    public static uint ProcessIdOf(IntPtr h)
    {
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        return pid;
    }

    public static string TitleOf(IntPtr h)
    {
        int len = GetWindowTextLength(h);
        if (len <= 0) return string.Empty;
        var sb = new StringBuilder(len + 2);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string ClassOf(IntPtr h)
    {
        var sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }
}
'@
[PesFix]::SetProcessDPIAware() | Out-Null

# GPU enumeration through DXGI. Gives the real adapter list with its LUIDs, which is what
# Windows uses internally for the per-app "High performance" preference. No vendor names
# are assumed, so this works the same on Intel/NVIDIA, AMD, Snapdragon and so on.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class GpuAdapters
{
    [StructLayout(LayoutKind.Sequential)]
    public struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DXGI_ADAPTER_DESC1
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId;
        public uint DeviceId;
        public uint SubSysId;
        public uint Revision;
        public UIntPtr DedicatedVideoMemory;
        public UIntPtr DedicatedSystemMemory;
        public UIntPtr SharedSystemMemory;
        public LUID AdapterLuid;
        public uint Flags;
    }

    [DllImport("dxgi.dll", ExactSpelling = true)]
    static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr factory);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int EnumAdapters1Fn(IntPtr self, uint index, out IntPtr adapter);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int GetDesc1Fn(IntPtr self, out DXGI_ADAPTER_DESC1 desc);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate int ReleaseFn(IntPtr self);

    static T Fn<T>(IntPtr obj, int slot) where T : class
    {
        IntPtr vtbl = Marshal.ReadIntPtr(obj);
        IntPtr fp = Marshal.ReadIntPtr(vtbl, slot * IntPtr.Size);
        return (T)(object)Marshal.GetDelegateForFunctionPointer(fp, typeof(T));
    }

    // Returns one line per adapter:
    //   name \t vramMB \t vendorId \t flags \t highpart \t lowpart
    // flags bit 1 (DXGI_ADAPTER_FLAG_SOFTWARE) marks software renderers.
    public static string[] Enumerate()
    {
        var rows = new List<string>();
        Guid iid = new Guid("770aae78-f26f-4dba-a829-253c83d1b387"); // IDXGIFactory1
        IntPtr factory;
        if (CreateDXGIFactory1(ref iid, out factory) != 0) return rows.ToArray();

        EnumAdapters1Fn enumFn = Fn<EnumAdapters1Fn>(factory, 12);
        ReleaseFn releaseFn = Fn<ReleaseFn>(factory, 2);
        try
        {
            for (uint i = 0; ; i++)
            {
                IntPtr adapter;
                if (enumFn(factory, i, out adapter) != 0 || adapter == IntPtr.Zero) break;
                try
                {
                    DXGI_ADAPTER_DESC1 d;
                    if (Fn<GetDesc1Fn>(adapter, 10)(adapter, out d) == 0)
                    {
                        rows.Add(string.Concat(
                            d.Description.Replace("\t", " "), "\t",
                            ((ulong)d.DedicatedVideoMemory.ToUInt64() / (1024UL * 1024UL)).ToString(), "\t",
                            d.VendorId.ToString(), "\t",
                            d.Flags.ToString(), "\t",
                            d.AdapterLuid.HighPart.ToString(), "\t",
                            d.AdapterLuid.LowPart.ToString()));
                    }
                }
                finally { Fn<ReleaseFn>(adapter, 2)(adapter); }
            }
        }
        finally { releaseFn(factory); }
        return rows.ToArray();
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms

# --------------------------------------------------------------------------- output
function Write-Step([string]$Text, [string]$Color = 'Gray') {
    if (-not $Quiet) { Write-Host $Text -ForegroundColor $Color }
    try { Add-Content -LiteralPath $script:LogFile -Value ("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Text) } catch { }
}

function Write-Ok([string]$Text) { Write-Step "  [ok]   $Text" 'Green' }
function Write-Warn([string]$Text) { Write-Step "  [note] $Text" 'Yellow' }
function Write-Fail([string]$Text) { Write-Step "  [fail] $Text" 'Red' }

# --------------------------------------------------------------------------- detection
function Find-GameDir {
    if ($GameDir) {
        $exe = Join-Path $GameDir 'PES2021.exe'
        if (Test-Path -LiteralPath $exe) { return (Resolve-Path -LiteralPath $GameDir).Path }
        throw "PES2021.exe not found in '$GameDir'."
    }

    # 1) next to this script (normal case when the fix travels with the game)
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'PES2021.exe'))) {
        return (Resolve-Path -LiteralPath $PSScriptRoot).Path
    }

    # 2) registered install location
    $regRoots = @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $regRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($key in Get-ChildItem $root -ErrorAction SilentlyContinue) {
            $p = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue)
            if (-not $p) { continue }
            if ($p.DisplayName -match 'PES 2021|eFootball PES') {
                foreach ($candidate in @($p.InstallLocation, $p.DisplayIcon)) {
                    if (-not $candidate) { continue }
                    $dir = if (Test-Path -LiteralPath $candidate -PathType Leaf) { Split-Path -Parent $candidate } else { $candidate }
                    if ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'PES2021.exe'))) { return $dir.TrimEnd('\') }
                }
            }
        }
    }

    # 3) shallow search on every fixed drive
    foreach ($drive in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue) {
        if (-not (Test-Path -LiteralPath $drive.Root)) { continue }
        try {
            $hit = Get-ChildItem -LiteralPath $drive.Root -Filter 'PES2021.exe' -File -Depth 3 -ErrorAction SilentlyContinue |
            Select-Object -First 1
            if ($hit) { return $hit.DirectoryName }
        }
        catch { }
    }

    throw 'Could not find PES2021.exe. Run this script from the game folder or pass -GameDir "D:\path\to\game".'
}

function Find-SettingsFile {
    $docs = @(
        [Environment]::GetFolderPath('MyDocuments'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'OneDrive\Documents')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $found = @()
    foreach ($d in $docs) {
        $konami = Join-Path $d 'KONAMI'
        if (-not (Test-Path -LiteralPath $konami)) { continue }
        foreach ($sub in Get-ChildItem -LiteralPath $konami -Directory -ErrorAction SilentlyContinue) {
            $candidate = Join-Path $sub.FullName 'settings.dat'
            if (-not (Test-Path -LiteralPath $candidate)) { continue }
            $bytes = [IO.File]::ReadAllBytes($candidate)
            if ($bytes.Length -gt 0x20 -and $bytes[0] -eq 0x57 -and $bytes[1] -eq 0x45 -and $bytes[2] -eq 0x43 -and $bytes[3] -eq 0x46) {
                $found += $candidate
            }
        }
    }
    if ($found.Count -gt 0) {
        # prefer the folder that actually belongs to PES 2021
        $pes = $found | Where-Object { $_ -match 'PES 2021' } | Select-Object -First 1
        if ($pes) { return $pes }
        return $found[0]
    }
    return $null
}

function New-SettingsFile([string]$Root) {
    $settingsExe = Join-Path $Root 'Settings.exe'
    if (-not (Test-Path -LiteralPath $settingsExe)) {
        throw 'settings.dat is missing and Settings.exe was not found. Start the game once, then run this fix again.'
    }
    Write-Warn 'settings.dat not found - running Settings.exe once to create it...'
    $proc = Start-Process -FilePath $settingsExe -WorkingDirectory $Root -PassThru
    $deadline = (Get-Date).AddSeconds(25)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        $file = Find-SettingsFile
        if ($file) { break }
    }
    Start-Sleep -Seconds 2
    # close the dialog if it is still open
    $p = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($p) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2; Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    $file = Find-SettingsFile
    if (-not $file) { throw 'Could not create settings.dat. Open Settings.exe manually, press OK, then run this fix again.' }
    return $file
}

function Get-TargetMonitor {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    if ($MonitorIndex -ge 0 -and $MonitorIndex -lt $screens.Count) {
        $s = $screens[$MonitorIndex]
    }
    else {
        $s = $screens | Where-Object { $_.Primary } | Select-Object -First 1
        if (-not $s) { $s = $screens[0] }
    }
    return $s.Bounds
}

# --------------------------------------------------------------------------- repairs
function Set-DisplaySettings([string]$File, [System.Drawing.Rectangle]$Bounds) {
    $bytes = [IO.File]::ReadAllBytes($File)
    if ($bytes.Length -lt 0x20) { throw "Unexpected settings.dat size ($($bytes.Length) bytes)." }
    if (-not ($bytes[0] -eq 0x57 -and $bytes[1] -eq 0x45 -and $bytes[2] -eq 0x43 -and $bytes[3] -eq 0x46)) {
        throw 'settings.dat has an unknown format (WECF header missing).'
    }

    $backup = "$File$script:SettingsBackupSuffix"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $File -Destination $backup -Force
        Write-Ok "Backup created: $(Split-Path -Leaf $backup)"
    }

    $wanted = if ($Mode -eq 'Fullscreen') { 0x67 } else { 0x66 }
    $before = $bytes[0x08]
    $beforeW = [BitConverter]::ToInt32($bytes, 0x0C)
    $beforeH = [BitConverter]::ToInt32($bytes, 0x10)

    $bytes[0x08] = [byte]$wanted
    [Array]::Copy([BitConverter]::GetBytes([int]$Bounds.Width), 0, $bytes, 0x0C, 4)
    [Array]::Copy([BitConverter]::GetBytes([int]$Bounds.Height), 0, $bytes, 0x10, 4)
    [IO.File]::WriteAllBytes($File, $bytes)

    if ($before -ne $wanted -or $beforeW -ne $Bounds.Width -or $beforeH -ne $Bounds.Height) {
        Write-Ok ("Screen mode 0x{0:X2} -> 0x{1:X2} ({2}), resolution {3}x{4} -> {5}x{6}" -f `
                $before, $wanted, $(if ($Mode -eq 'Fullscreen') { 'Full Screen' } else { 'Window Mode' }),
            $beforeW, $beforeH, $Bounds.Width, $Bounds.Height)
    }
    else {
        Write-Ok ("Settings already correct ({0}, {1}x{2})" -f `
            $(if ($Mode -eq 'Fullscreen') { 'Full Screen' } else { 'Window Mode' }), $Bounds.Width, $Bounds.Height)
    }
}

function Set-CompatLayers([string]$Exe) {
    $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    $value = '~ DISABLEDXMAXIMIZEDWINDOWEDMODE HIGHDPIAWARE'
    $current = (Get-ItemProperty -Path $key -Name $Exe -ErrorAction SilentlyContinue).$Exe
    if ($current -ne $value) {
        Set-ItemProperty -Path $key -Name $Exe -Value $value -Type String
        Write-Ok 'Disabled fullscreen optimizations + set DPI scaling = Application'
    }
    else {
        Write-Ok 'Fullscreen optimizations / DPI flags already set'
    }
}

# --------------------------------------------------------------------------- gpus
function Get-AdapterKind {
    param([string]$Name, [uint32]$VendorId, [uint64]$VramMB, [uint32]$Flags)

    # DXGI_ADAPTER_FLAG_SOFTWARE (2) = software renderer, never useful for a game.
    if (($Flags -band 2) -ne 0) { return 'Virtual' }
    if ($Name -match 'Basic Render|Basic Display|Remote Display|Indirect Display|Virtual|Hyper-V|Parsec|Citrix|VMware|VirtualBox|DameWare') { return 'Virtual' }

    # Strip trademark noise so vendor names match reliably, e.g.
    # "Intel(R) Arc(TM) A770 Graphics" -> "Intel Arc A770 Graphics".
    $clean = $Name -replace '\((?:TM|R|C)\)', '' -replace '\s+', ' '
    $clean = $clean.Trim()

    switch ($VendorId) {
        0x8086 {
            # Intel: Arc A/B and Arc Pro are discrete cards, everything else is integrated.
            if ($clean -match 'Arc\s+(?:A\d|B\d|Pro\b|Graphics\s+Pro)') { return 'Discrete' }
            return 'Integrated'
        }
        0x10DE { return 'Discrete' }          # NVIDIA (GeForce / RTX / Quadro / MX)
        0x1002 {
            # AMD / ATI
            if ($clean -match 'Radeon\s+(?:RX|Pro\b|VII|R9|R7|Instinct)|FirePro|FireGL') { return 'Discrete' }
            return 'Integrated'               # Radeon Graphics, Vega 8/11, 6xxM/7xxM, HD
        }
        0x1022 { return 'Integrated' }         # AMD iGPU reported through the CPU vendor id
        0x5143 { return 'Integrated' }         # Qualcomm Adreno
        0x13B5 { return 'Integrated' }         # ARM Mali
        0x1AF4 { return 'Virtual' }            # virtio-gpu
        0x15AD { return 'Virtual' }            # VMware SVGA
        0x80EE { return 'Virtual' }            # VirtualBox
    }

    # Unknown vendor: use the amount of dedicated memory as a hint.
    if ($VramMB -ge 1024) { return 'Discrete' }
    return 'Unknown'
}

function Get-GraphicsAdapters {
    $adapters = @()

    try {
        foreach ($row in [GpuAdapters]::Enumerate()) {
            $f = $row -split "`t"
            if ($f.Count -lt 6) { continue }
            $vram = [uint64]$f[1]
            $vendor = [uint32]$f[2]
            $flags = [uint32]$f[3]
            $adapters += [pscustomobject]@{
                Name     = $f[0]
                VramMB   = $vram
                VendorId = $vendor
                Flags    = $flags
                Kind     = (Get-AdapterKind -Name $f[0] -VendorId $vendor -VramMB $vram -Flags $flags)
                Luid     = ('0x{0:x8}_0x{1:x8}' -f [int]$f[4], [int]$f[5])
                HighPart = [int]$f[4]
                LowPart  = [int]$f[5]
            }
        }
    }
    catch {
        Write-Step ("DXGI adapter query failed: {0}" -f $_.Exception.Message) 'DarkGray'
    }

    # Fallback for very old systems / broken drivers.
    if ($adapters.Count -eq 0) {
        try {
            foreach ($vc in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
                $vram = if ($vc.AdapterRAM) { [uint64]([Math]::Round($vc.AdapterRAM / 1MB)) } else { 0 }
                $adapters += [pscustomobject]@{
                    Name     = $vc.Name
                    VramMB   = $vram
                    VendorId = 0
                    Flags    = 0
                    Kind     = (Get-AdapterKind -Name $vc.Name -VendorId 0 -VramMB $vram -Flags 0)
                    Luid     = ''
                    HighPart = 0
                    LowPart  = 0
                }
            }
            if ($adapters.Count -gt 0) { Write-Step 'Used WMI for GPU detection (DXGI unavailable)' 'DarkGray' }
        }
        catch { }
    }

    return @($adapters)
}

function Get-RealGpus {
    return @((Get-GraphicsAdapters) | Where-Object { $_.Kind -ne 'Virtual' })
}

function Get-AppGpuPreferenceRaw([string]$Exe) {
    $key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    return (Get-ItemProperty -Path $key -Name $Exe -ErrorAction SilentlyContinue).$Exe
}

function ConvertFrom-GpuPreferenceValue([string]$Raw) {
    if (-not $Raw -or $Raw -notmatch 'GpuPreference\s*=\s*(\d+)') { return -1 }
    return [int]$matches[1]
}

function ConvertTo-GpuPreferenceText([int]$Value) {
    switch ($Value) {
        1 { return 'Power saving (integrated GPU)' }
        2 { return 'High performance (discrete GPU)' }
        0 { return 'Let Windows decide' }
        default { return 'not set' }
    }
}

function Set-AppGpuPreferenceValue([string]$Exe, [int]$Value) {
    $key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }

    $current = Get-AppGpuPreferenceRaw -Exe $Exe
    $token = "GpuPreference=$Value;"

    if ($current -and $current -match 'GpuPreference\s*=') {
        $merged = [regex]::Replace($current, 'GpuPreference\s*=\s*\d+\s*;?', $token)
        if ($merged -notmatch 'GpuPreference\s*=') { $merged = $merged.TrimEnd(';') + ';' + $token }
    }
    elseif ($current) {
        $merged = $current.TrimEnd(';') + ';' + $token
    }
    else {
        $merged = $token
    }

    Set-ItemProperty -Path $key -Name $Exe -Value $merged -Type String

    # Verify by reading back - Windows sometimes appends its own AppStatus token.
    return ((ConvertFrom-GpuPreferenceValue (Get-AppGpuPreferenceRaw -Exe $Exe)) -eq $Value)
}

function Get-DesiredGpuPreference {
    if ($NoGpuFix) { return -1 }
    switch ($GpuPreference) {
        'Skip' { return -1 }
        'Default' { return 0 }
        'PowerSaving' { return 1 }
        'High' { return 2 }
        'Auto' { return 2 }
    }
    return -1
}

function Set-GpuPreference([string]$Exe) {
    $desired = Get-DesiredGpuPreference
    if ($desired -lt 0) {
        Write-Ok 'GPU selection left unchanged (-GpuPreference Skip / -NoGpuFix)'
        return
    }

    $gpus = Get-RealGpus
    $discrete = @($gpus | Where-Object { $_.Kind -eq 'Discrete' })
    $current = ConvertFrom-GpuPreferenceValue (Get-AppGpuPreferenceRaw -Exe $Exe)

    # Only one graphics processor: there is nothing to choose, and touching the value would
    # just be noise. Still report reality so other PCs get an honest answer.
    if ($gpus.Count -le 1) {
        $name = if ($gpus.Count -eq 1) { $gpus[0].Name } else { 'unknown' }
        if ($current -eq 2) {
            Write-Ok ("Single graphics processor ({0}) - high-performance preference already set" -f $name)
        }
        else {
            Write-Ok ("Single graphics processor ({0}) - no GPU selection needed" -f $name)
        }
        return
    }

    # Several GPUs but no discrete one (e.g. two integrated) - nothing better to switch to.
    if ($GpuPreference -eq 'Auto' -and $discrete.Count -eq 0) {
        Write-Warn 'Two graphics processors found but neither is a discrete GPU - leaving Windows to decide'
        return
    }

    $target = if ($GpuPreference -eq 'Auto') { $discrete[0] } else { $null }
    if ((ConvertFrom-GpuPreferenceValue (Get-AppGpuPreferenceRaw -Exe $Exe)) -eq $desired) {
        Write-Ok ("Graphics preference already set: {0}" -f (ConvertTo-GpuPreferenceText $desired))
        return
    }

    $ok = Set-AppGpuPreferenceValue -Exe $Exe -Value $desired
    if ($ok) {
        if ($target) {
            Write-Ok ("Graphics preference = {0} ({1})" -f (ConvertTo-GpuPreferenceText $desired), $target.Name)
        }
        else {
            Write-Ok ("Graphics preference = {0}" -f (ConvertTo-GpuPreferenceText $desired))
        }
    }
    else {
        Write-Fail 'Could not set the graphics preference (permission or policy problem)'
    }
}

# Which GPU the game is actually rendering on, matched back to a name via its LUID.
function Get-GameGpuUsage([int]$ProcessId) {
    $gpus = Get-GraphicsAdapters
    $byLuid = @{}
    foreach ($g in $gpus) { if ($g.Luid) { $byLuid[$g.Luid.ToLower()] = $g } }

    $usage = @{}

    # Two samples, keeping the highest value per adapter: a single reading can land on an
    # idle moment and would otherwise produce a wrong conclusion.
    for ($pass = 0; $pass -lt 2; $pass++) {
        try {
            $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples |
            Where-Object { $_.InstanceName -match "pid_$ProcessId`_" }
        }
        catch { return @() }

        foreach ($s in $samples) {
            if ($s.InstanceName -notmatch 'luid_(0x[0-9a-fA-F]+)_(0x[0-9a-fA-F]+)_') { continue }
            $luid = ('{0}_{1}' -f $matches[1], $matches[2]).ToLower()
            $engine = if ($s.InstanceName -match 'engtype_([a-z0-9 ]+)$') { $matches[1] } else { 'other' }
            $value = [double]$s.CookedValue
            if (-not $usage.ContainsKey($luid)) {
                $usage[$luid] = [pscustomobject]@{ Luid = $luid; Gpu = $byLuid[$luid]; Total = 0.0; Engines = @() }
            }
            if ($value -gt $usage[$luid].Total) { $usage[$luid].Total = $value }
            if ($value -gt 0.5) {
                $list = @($usage[$luid].Engines) + $engine
                $usage[$luid].Engines = $list
            }
        }
        if ($pass -eq 0) { Start-Sleep -Milliseconds 800 }
    }

    # Ignore adapters that show no measurable work - an idle adapter is not "in use".
    $busy = @($usage.Values | Where-Object { $_.Total -ge 0.5 })
    return @($busy | Sort-Object -Property Total -Descending)
}

function Show-GpuReport([string]$Exe, [string]$ProcessName) {
    Write-Step 'Graphics processors' 'Cyan'
    $adapters = Get-GraphicsAdapters
    if ($adapters.Count -eq 0) { Write-Fail 'Could not enumerate any graphics processor'; return }
    foreach ($a in $adapters) {
        $vram = if ($a.VramMB -gt 0) { "{0} MB" -f $a.VramMB } else { 'n/a' }
        Write-Step ("  {0,-32} {1,-11} {2,10}" -f $a.Name, $a.Kind, $vram)
    }

    $real = @($adapters | Where-Object { $_.Kind -ne 'Virtual' })
    Write-Step ''
    if ($real.Count -le 1) {
        Write-Step 'Only one graphics processor - there is nothing to choose, the game will use it.' 'Gray'
    }
    else {
        Write-Step ("{0} graphics processors found - pick the strong one, see below." -f $real.Count) 'Gray'
    }

    Write-Step ''
    Write-Step 'Game graphics setting' 'Cyan'
    $raw = Get-AppGpuPreferenceRaw -Exe $Exe
    $value = ConvertFrom-GpuPreferenceValue $raw
    Write-Step ("  App : {0}" -f $Exe)
    Write-Step ("  Set : {0}" -f (ConvertTo-GpuPreferenceText $value))
    if ($raw) { Write-Step ("  Raw : {0}" -f $raw) 'DarkGray' }

    $game = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $game) {
        Write-Step ''
        Write-Step 'Start the game and run -Action Gpu again to confirm which GPU it really uses.' 'DarkGray'
        return
    }

    Write-Step ''
    Write-Step ("GPU actually used by {0} (pid {1})" -f $ProcessName, $game.Id) 'Cyan'
    $used = Get-GameGpuUsage -ProcessId $game.Id
    if ($used.Count -eq 0) {
        Write-Step '  no measurable GPU activity yet - run this again once the menu or a match is showing' 'DarkGray'
        return
    }

    $top = $used | Select-Object -First 1
    foreach ($u in $used) {
        $label = if ($u.Gpu) { $u.Gpu.Name } else { "adapter $($u.Luid)" }
        $engines = ($u.Engines | Select-Object -Unique) -join ', '
        Write-Step ("  {0,-32} {1,7:N1}%  {2}" -f $label, $u.Total, $engines)
    }

    $discrete = @($adapters | Where-Object { $_.Kind -eq 'Discrete' })
    if ($top.Gpu -and $discrete.Count -gt 0) {
        $isDiscrete = @($discrete | Where-Object { $_.Luid -eq $top.Gpu.Luid }).Count -gt 0
        Write-Step ''
        if ($isDiscrete) { Write-Step ("Confirmed: rendering on the discrete GPU ({0})." -f $top.Gpu.Name) 'Green' }
        else { Write-Step ("Rendering on {0}. If the game feels slow, run -Action Fix to switch it." -f $top.Gpu.Name) 'Yellow' }
    }
}

function Get-StartupShortcut {
    $dir = [Environment]::GetFolderPath('Startup')
    return (Join-Path $dir 'PES2021 Fullscreen Keeper.lnk')
}

function Install-Startup {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = Join-Path $PSScriptRoot 'PES2021-Fullscreen.ps1' }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Get-StartupShortcut))
    $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -Action Keep -Quiet"
    $lnk.WorkingDirectory = Split-Path -Parent $scriptPath
    $lnk.WindowStyle = 7
    $lnk.Description = 'Keeps eFootball PES 2021 in fullscreen'
    $lnk.Save()
    Write-Ok 'Logon watchdog installed (runs hidden at every logon)'
}

function Remove-Startup {
    $lnk = Get-StartupShortcut
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Ok 'Logon watchdog removed' }
    else { Write-Ok 'No logon watchdog installed' }
}

function Undo-All([string]$Exe, [string]$SettingsFile) {
    if ($SettingsFile) {
        $backup = "$SettingsFile$script:SettingsBackupSuffix"
        if (Test-Path -LiteralPath $backup) {
            Copy-Item -LiteralPath $backup -Destination $SettingsFile -Force
            Remove-Item -LiteralPath $backup -Force
            Write-Ok 'settings.dat restored from backup'
        }
    }
    $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    if (Test-Path $layers) { Remove-ItemProperty -Path $layers -Name $Exe -ErrorAction SilentlyContinue; Write-Ok 'Compatibility flags removed' }
    $gpu = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    if (Test-Path $gpu) { Remove-ItemProperty -Path $gpu -Name $Exe -ErrorAction SilentlyContinue; Write-Ok 'GPU preference removed' }
    Restore-GameBar
    Restore-FocusTweaks
    Remove-DefenderExclusion
    Remove-Startup
}

# --------------------------------------------------------------------------- overlays
# Processes that draw always-on-top overlay windows and steal focus from
# exclusive-fullscreen games. Kill = $true  -> terminated while playing.
# Kill = $false -> only reported, because closing it would stop real work
# (streaming, chatting, recording that the user started on purpose).
$script:OverlayCatalog = @(
    @{ Name = 'ScreenRec'; Kill = $true; Processes = @('screenrec'); Note = 'screen recorder with an always-on-top toolbar' }
    @{ Name = 'Xbox Game Bar'; Kill = $true; Processes = @('GameBar', 'GameBarFTServer'); Note = 'Windows overlay (also switched off in the registry)' }
    @{ Name = 'NVIDIA overlay'; Kill = $true; Processes = @('NVIDIA Share', 'NVIDIA Overlay'); Note = 'GeForce Experience in-game overlay' }
    @{ Name = 'AMD overlay'; Kill = $true; Processes = @('amdow'); Note = 'Radeon Software in-game overlay' }
    @{ Name = 'Overwolf'; Kill = $true; Processes = @('Overwolf', 'OverwolfBrowser', 'OverwolfHelper', 'OverwolfHelper64'); Note = 'Overwolf in-game apps' }
    @{ Name = 'RivaTuner / Afterburner'; Kill = $true; Processes = @('RTSS', 'RTSSHooksLoader64', 'MSIAfterburner'); Note = 'on-screen display hook' }
    @{ Name = 'Fraps / Bandicam'; Kill = $true; Processes = @('fraps', 'bdcam'); Note = 'legacy screen recorders' }
    @{ Name = 'Steam overlay'; Kill = $true; Processes = @('GameOverlayUI'); Note = 'only the overlay helper closes, Steam keeps running' }
    @{ Name = 'Discord'; Kill = $false; Processes = @('Discord'); Note = 'chat app - switch its overlay off in Discord settings' }
    @{ Name = 'OBS Studio'; Kill = $false; Processes = @('obs64', 'obs32'); Note = 'kept because you record/stream on purpose' }
)

function Get-RunningOverlays {
    $result = @()

    foreach ($entry in $script:OverlayCatalog) {
        if ($script:PreservedOverlays -contains $entry.Name) { continue }
        $running = @()
        foreach ($procName in $entry.Processes) {
            foreach ($p in @(Get-Process -Name $procName -ErrorAction SilentlyContinue)) { $running += $p }
        }
        if ($running.Count -gt 0) {
            $result += [pscustomobject]@{
                Name      = $entry.Name
                Kill      = [bool]$entry.Kill
                Note      = $entry.Note
                Processes = @($running)
            }
        }
    }

    foreach ($extra in $script:ExtraOverlays) {
        if (-not $extra) { continue }
        $running = @(Get-Process -Name $extra -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            $result += [pscustomobject]@{
                Name      = $running[0].ProcessName
                Kill      = $true
                Note      = 'requested with -ExtraOverlay'
                Processes = @($running)
            }
        }
    }

    return $result
}

function Invoke-OverlaySweep {
    param([switch]$ReportOnly)

    if ($OverlayAction -eq 'Off') { return }

    $found = @(Get-RunningOverlays)
    if ($found.Count -eq 0) { return }

    foreach ($overlay in $found) {
        $mayClose = (-not $ReportOnly) -and ($OverlayAction -eq 'Close') -and $overlay.Kill

        if (-not $mayClose) {
            if (-not $script:OverlayNoted.ContainsKey($overlay.Name)) {
                $script:OverlayNoted[$overlay.Name] = $true
                $reason = if ($overlay.Kill) { 'not closed because overlay closing is off' } else { $overlay.Note }
                Write-Step ("overlay running: {0} ({1})" -f $overlay.Name, $reason) 'DarkGray'
            }
            continue
        }

        $closed = @()
        foreach ($proc in $overlay.Processes) {
            $name = $proc.ProcessName
            try {
                if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
                    $proc.CloseMainWindow() | Out-Null
                    Start-Sleep -Milliseconds 350
                }
            }
            catch { }

            try {
                $stillRunning = $true
                try { $stillRunning = -not $proc.HasExited } catch { $stillRunning = $false }
                if ($stillRunning) { Stop-Process -Id $proc.Id -Force -ErrorAction Stop }
                $closed += $name
            }
            catch {
                Write-Step ("could not close {0}: {1}" -f $name, $_.Exception.Message) 'DarkGray'
            }
        }

        if ($closed.Count -gt 0) {
            $list = ($closed | Select-Object -Unique) -join ', '
            $count = 1 + [int]$script:OverlayCloseCount[$overlay.Name]
            $script:OverlayCloseCount[$overlay.Name] = $count

            if ($count -le 3) {
                Write-Step ("[{0:HH:mm:ss}] closed overlay: {1} ({2})" -f (Get-Date), $overlay.Name, $list) 'Cyan'
            }
            elseif ($count -eq 4) {
                Write-Step ("{0} keeps restarting - it will keep being closed quietly while you play." -f $overlay.Name) 'DarkGray'
            }
        }
    }
}

function Disable-GameBar {
    if ($NoGameBarFix) { return }
    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    }

    $targets = @(
        @{ Path = 'HKCU:\System\GameConfigStore'; Name = 'GameDVR_Enabled'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'AppCaptureEnabled'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'HistoricalCaptureEnabled'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'ShowStartupPanel'; Value = 0 }
        @{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'UseNexusForGameBarEnabled'; Value = 0 }
    )

    $stateFile = Join-Path $script:StateDir 'gamebar.json'
    if (-not (Test-Path -LiteralPath $stateFile)) {
        $original = @{}
        foreach ($t in $targets) {
            if (-not (Test-Path $t.Path)) { New-Item -Path $t.Path -Force | Out-Null }
            $current = (Get-ItemProperty -Path $t.Path -Name $t.Name -ErrorAction SilentlyContinue).($t.Name)
            $original["$($t.Path)|$($t.Name)"] = if ($null -eq $current) { $null } else { [int]$current }
        }
        $original | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    }

    $changed = 0
    foreach ($t in $targets) {
        if (-not (Test-Path $t.Path)) { New-Item -Path $t.Path -Force | Out-Null }
        $current = (Get-ItemProperty -Path $t.Path -Name $t.Name -ErrorAction SilentlyContinue).($t.Name)
        if ($null -eq $current -or [int]$current -ne [int]$t.Value) {
            Set-ItemProperty -Path $t.Path -Name $t.Name -Value $t.Value -Type DWord
            $changed++
        }
    }

    if ($changed -gt 0) { Write-Ok 'Xbox Game Bar / Game DVR overlay switched off' }
    else { Write-Ok 'Xbox Game Bar / Game DVR already off' }
}

function Restore-GameBar {
    $stateFile = Join-Path $script:StateDir 'gamebar.json'
    if (-not (Test-Path -LiteralPath $stateFile)) { return }

    $original = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    foreach ($prop in $original.PSObject.Properties) {
        $parts = $prop.Name -split '\|', 2
        $path = $parts[0]
        $name = $parts[1]
        if (-not (Test-Path $path)) { continue }
        if ($null -eq $prop.Value) {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
        else {
            Set-ItemProperty -Path $path -Name $name -Value ([int]$prop.Value) -Type DWord
        }
    }

    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    Write-Ok 'Xbox Game Bar / Game DVR settings restored'
}

# --------------------------------------------------------------------------- focus lock
function Get-FocusStateFile { Join-Path $script:StateDir 'focus.json' }

function Get-ForegroundLockTimeout {
    # The registry is authoritative here; SPI_GETFOREGROUNDLOCKTIMEOUT returns a cached
    # value on Windows 11 (verified), so it cannot be trusted for reading.
    $value = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'ForegroundLockTimeout' -ErrorAction SilentlyContinue).ForegroundLockTimeout
    if ($null -eq $value) { return [uint32]200000 }   # Windows default
    return [uint32]$value
}

function Read-FocusState {
    $file = Get-FocusStateFile
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { return (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) } catch { return $null }
}

function Set-FocusLock {
    # Windows' documented foreground-lock. Default is 200000 ms; a much larger value means
    # background apps practically never get to pull focus away from the game.
    if ($NoForegroundLock) { Write-Ok 'Windows foreground lock left unchanged (-NoForegroundLock)'; return }
    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    }

    $current = Get-ForegroundLockTimeout
    $state = Read-FocusState
    if (-not $state) {
        $state = [pscustomobject]@{ ForegroundLockOriginal = $current; ToastsOriginal = $null; ToastsGlobalOriginal = $null; NotificationsChanged = $false }
    }
    if ($null -eq $state.PSObject.Properties['ForegroundLockOriginal']) {
        $state | Add-Member -NotePropertyName ForegroundLockOriginal -NotePropertyValue $current -Force
    }

    if ([uint32]$current -ne [uint32]$ForegroundLockMs) {
        $applied = [PesFix]::SetForegroundLockTimeout([uint32]$ForegroundLockMs)

        # Windows flushes this through the "Control Panel\Desktop" hive asynchronously, so
        # poll briefly instead of failing on a single immediate read.
        $after = $current
        for ($try = 0; $try -lt 12; $try++) {
            $after = Get-ForegroundLockTimeout
            if ([uint32]$after -eq [uint32]$ForegroundLockMs) { break }
            Start-Sleep -Milliseconds 120
        }

        # If the SPI call did not take (some sessions refuse SENDCHANGE), write the value
        # straight into the same registry location the API maintains.
        if ([uint32]$after -ne [uint32]$ForegroundLockMs) {
            try {
                Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ForegroundLockTimeout' `
                    -Value ([int]$ForegroundLockMs) -Type DWord -ErrorAction Stop
                Start-Sleep -Milliseconds 250
                $after = Get-ForegroundLockTimeout
            }
            catch { }
        }

        if ([uint32]$after -eq [uint32]$ForegroundLockMs) {
            Write-Ok ("Focus protection raised: ForegroundLockTimeout {0} -> {1} ms" -f $current, $after)
        }
        else {
            Write-Warn ("Could not raise the foreground lock (policy?) - the watchdog still restores the game")
        }
    }
    else {
        Write-Ok ("Focus protection already set (ForegroundLockTimeout {0} ms)" -f $current)
    }

    $state | ConvertTo-Json | Set-Content -LiteralPath (Get-FocusStateFile) -Encoding UTF8
}

function Set-NotificationSilence {
    if (-not $SilenceNotifications) { return }
    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    }

    $state = Read-FocusState
    if (-not $state) {
        $state = [pscustomobject]@{ ForegroundLockOriginal = $null }
        $state | Add-Member -NotePropertyName ToastsOriginal -NotePropertyValue $null -Force
    }

    $push = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
    $notif = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    foreach ($p in @($push, $notif)) { if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null } }

    $toastOriginal = (Get-ItemProperty -Path $push  -Name 'ToastEnabled' -ErrorAction SilentlyContinue).ToastEnabled
    $globalOriginal = (Get-ItemProperty -Path $notif -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -ErrorAction SilentlyContinue).NOC_GLOBAL_SETTING_TOASTS_ENABLED

    if ($null -eq $state.PSObject.Properties['ToastsOriginal'] -or -not $state.NotificationsChanged) {
        $state | Add-Member -NotePropertyName ToastsOriginal -NotePropertyValue $(if ($null -eq $toastOriginal) { $null } else { [int]$toastOriginal }) -Force
        $state | Add-Member -NotePropertyName ToastsGlobalOriginal -NotePropertyValue $(if ($null -eq $globalOriginal) { $null } else { [int]$globalOriginal }) -Force
        $state | Add-Member -NotePropertyName NotificationsChanged -NotePropertyValue $true -Force
    }

    Set-ItemProperty -Path $push  -Name 'ToastEnabled' -Value 0 -Type DWord
    Set-ItemProperty -Path $notif -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Value 0 -Type DWord
    $state | ConvertTo-Json | Set-Content -LiteralPath (Get-FocusStateFile) -Encoding UTF8
    Write-Ok 'Notification banners switched off (restored by -Action Restore)'
}

function Restore-FocusTweaks {
    $state = Read-FocusState
    if (-not $state) { return }

    if ($null -ne $state.PSObject.Properties['ForegroundLockOriginal'] -and $null -ne $state.ForegroundLockOriginal) {
        [PesFix]::SetForegroundLockTimeout([uint32]$state.ForegroundLockOriginal) | Out-Null
        Write-Ok ("Windows foreground lock restored to {0} ms" -f $state.ForegroundLockOriginal)
    }

    if ($state.PSObject.Properties['NotificationsChanged'] -and $state.NotificationsChanged) {
        $push = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
        $notif = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'

        if ($null -eq $state.ToastsOriginal) { Remove-ItemProperty -Path $push -Name 'ToastEnabled' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $push -Name 'ToastEnabled' -Value ([int]$state.ToastsOriginal) -Type DWord }

        if ($null -eq $state.ToastsGlobalOriginal) { Remove-ItemProperty -Path $notif -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $notif -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -Value ([int]$state.ToastsGlobalOriginal) -Type DWord }

        Write-Ok 'Notification settings restored'
    }

    Remove-Item -LiteralPath (Get-FocusStateFile) -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------- defender
function Get-DefenderStateFile { Join-Path $script:StateDir 'defender.json' }

function Test-IsAdmin {
    try {
        return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Add-DefenderExclusion([string]$Folder) {
    if (-not $DefenderExclusion) { return }
    if (-not (Get-Command Add-MpPreference -ErrorAction SilentlyContinue)) {
        Write-Warn 'Microsoft Defender is not available on this PC - skipping the antivirus exclusion'
        return
    }
    if (-not (Test-IsAdmin)) {
        Write-Warn 'Antivirus exclusion needs an elevated window. Right-click PowerShell > Run as administrator and run with -DefenderExclusion'
        return
    }

    try {
        $existing = @((Get-MpPreference).ExclusionPath | Where-Object { $_ })
        if ($existing -contains $Folder) { Write-Ok 'Defender already excludes the game folder'; return }
        Add-MpPreference -ExclusionPath $Folder -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $script:StateDir)) {
            New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
        }
        $stateFile = Get-DefenderStateFile
        $added = if (Test-Path -LiteralPath $stateFile) { @(Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json) } else { @() }
        $added = @($added) + $Folder | Select-Object -Unique
        $added | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
        Write-Ok 'Game folder excluded from Microsoft Defender'
    }
    catch {
        Write-Warn ("Could not add the Defender exclusion: {0}" -f $_.Exception.Message)
    }
}

function Remove-DefenderExclusion {
    $stateFile = Get-DefenderStateFile
    if (-not (Test-Path -LiteralPath $stateFile)) { return }
    if (-not (Get-Command Remove-MpPreference -ErrorAction SilentlyContinue)) { return }
    if (-not (Test-IsAdmin)) { return }

    foreach ($path in @(Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json)) {
        try { Remove-MpPreference -ExclusionPath $path -ErrorAction Stop; Write-Ok ("Defender exclusion removed: {0}" -f $path) } catch { }
    }
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------- diagnose
function Invoke-FocusDiagnostics([int]$Seconds) {
    Write-Step ("Watching the foreground window for {0} seconds - play or click around as usual." -f $Seconds) 'Cyan'
    Write-Step 'Press Ctrl+C to stop early.' 'DarkGray'
    Write-Step ''

    $counts = @{}
    $lastKey = ''
    $lastTitle = ''
    $deadline = (Get-Date).AddSeconds($Seconds)

    while ((Get-Date) -lt $deadline) {
        $fg = [PesFix]::GetForegroundWindow()
        $info = Get-ForegroundInfo -Handle $fg
        $key = "$($info.ProcessId)|$($info.Class)"
        if ($key -ne $lastKey) {
            $counts[$key] = 1 + [int]$counts[$key]
            if ($lastKey -ne '' -and $info.ProcessName -ne 'powershell' -and $info.ProcessName -ne 'conhost' -and $info.ProcessName -ne 'WindowsTerminal') {
                if (-not $lastTitle -or $true) { }
            }
            Write-Step ("[{0:HH:mm:ss}] foreground -> {1} (pid {2}) class='{3}' title='{4}'" -f (Get-Date), $info.ProcessName, $info.ProcessId, $info.Class, $info.Title) 'Gray'
            $lastKey = $key
            $lastTitle = $info.Title
        }
        Start-Sleep -Milliseconds 120
    }

    Write-Step ''
    Write-Step 'Foreground switches during the test:' 'Cyan'
    foreach ($pair in ($counts.GetEnumerator() | Sort-Object -Property Value -Descending)) {
        $parts = $pair.Key -split '\|', 2
        $procName = '?'
        try { $procName = (Get-Process -Id ([int]$parts[0]) -ErrorAction SilentlyContinue).ProcessName } catch { }
        Write-Step ("  {0,4}x  {1} (pid {2}) class='{3}'" -f $pair.Value, $procName, $parts[0], $parts[1])
    }
    Write-Step ''
    Write-Step 'If an unexpected process keeps appearing, add it to the overlay list:' 'Cyan'
    Write-Step '  ... -ExtraOverlay "<that process name>"' 'DarkGray'
}

function Get-ForegroundInfo([IntPtr]$Handle) {
    $processId = 0
    $title = ''
    $class = ''
    $processName = ''
    if ($Handle -ne [IntPtr]::Zero) {
        $processId = [int][PesFix]::ProcessIdOf($Handle)
        $title = [PesFix]::TitleOf($Handle)
        $class = [PesFix]::ClassOf($Handle)
        try { $processName = (Get-Process -Id $processId -ErrorAction SilentlyContinue).ProcessName } catch { }
    }
    return [pscustomobject]@{ ProcessId = $processId; ProcessName = $processName; Title = $title; Class = $class }
}

# --------------------------------------------------------------------------- keeper
function Invoke-Keeper([string]$ProcessName, [bool]$ExitWhenGameCloses) {
    # Only one watchdog per Windows session.
    try {
        $script:keeperMutex = New-Object System.Threading.Mutex($false, 'Local\PES2021FullscreenKeeper')
        if (-not $script:keeperMutex.WaitOne(0)) {
            if ($ExitWhenGameCloses) {
                # The background (logon) watchdog is already protecting the game. Stay in the
                # foreground as a passive tail so this window behaves the way the player expects
                # and simply closes when the game does.
                Write-Step 'Background watchdog is already active - it is protecting the game.' 'Green'
                Write-Step 'This window now just waits for the game to close.' 'DarkGray'
                while (@(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count -gt 0) {
                    Start-Sleep -Seconds 2
                }
            }
            else {
                Write-Step 'Another PES 2021 watchdog is already running - this one will exit.' 'DarkGray'
            }
            return
        }
    }
    catch {
        Write-Step "Could not create the watchdog lock: $($_.Exception.Message)" 'DarkGray'
    }

    $restores = 0
    $lastWindow = [IntPtr]::Zero
    $graceUntil = $null
    $gameHadFocus = $false
    $iconicStreak = 0
    $lastSkipNote = $null
    $waitNotified = $false
    $requiredStreak = 3      # ~1.2 s of continuous "minimized, not deliberate"
    $nextOverlaySweep = Get-Date
    $sweepInterval = [Math]::Max(5, $OverlayScanSeconds)
    $gpuCheckAt = $null
    $gpuReported = $false

    while ($true) {
        $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) {
            if ($ExitWhenGameCloses) { break }
            if (-not $waitNotified) {
                Write-Step 'Waiting for eFootball PES 2021 to start...' 'DarkGray'
                $waitNotified = $true
            }
            $lastWindow = [IntPtr]::Zero
            $graceUntil = $null
            $gameHadFocus = $false
            $iconicStreak = 0
            $gpuCheckAt = $null
            $gpuReported = $false
            Start-Sleep -Milliseconds 750
            continue
        }
        $waitNotified = $false

        # Close overlays before they can steal focus; re-checked so recorders that
        # restart themselves are closed again.
        if ((Get-Date) -ge $nextOverlaySweep) {
            Invoke-OverlaySweep
            $nextOverlaySweep = (Get-Date).AddSeconds($sweepInterval)
        }

        foreach ($p in $procs) {
            try { $p.Refresh() } catch { continue }
            $h = $p.MainWindowHandle
            if ($h -eq [IntPtr]::Zero) { continue }

            # A new game window (fresh launch) re-arms the startup grace period.
            if ($h -ne $lastWindow) {
                $lastWindow = $h
                $graceUntil = (Get-Date).AddSeconds($StartupGraceSeconds)
                $gameHadFocus = $false
                $iconicStreak = 0
                $gpuCheckAt = (Get-Date).AddSeconds(25)
                $gpuReported = $false
            }

            # Once per launch, confirm which GPU the game actually renders on.
            if (-not $gpuReported -and $null -ne $gpuCheckAt -and (Get-Date) -ge $gpuCheckAt) {
                $gpuReported = $true
                try {
                    $used = @(Get-GameGpuUsage -ProcessId $p.Id)
                    if ($used.Count -gt 0 -and $used[0].Gpu) {
                        $realGpus = @(Get-RealGpus)
                        $discrete = @($realGpus | Where-Object { $_.Kind -eq 'Discrete' })
                        $topIsDiscrete = @($discrete | Where-Object { $_.Luid -eq $used[0].Gpu.Luid }).Count -gt 0
                        if ($discrete.Count -gt 0 -and $topIsDiscrete) {
                            Write-Step ("GPU in use: {0} (discrete - as intended)" -f $used[0].Gpu.Name) 'Green'
                        }
                        elseif ($discrete.Count -gt 0) {
                            Write-Step ("GPU in use: {0} - not the discrete GPU. Run with -Action Gpu to check." -f $used[0].Gpu.Name) 'Yellow'
                        }
                        else {
                            Write-Step ("GPU in use: {0}" -f $used[0].Gpu.Name) 'DarkGray'
                        }
                    }
                }
                catch { }
            }

            if ([PesFix]::GetForegroundWindow() -eq $h) { $gameHadFocus = $true }

            if ([PesFix]::IsIconic($h)) {
                $deliberate = $false
                $why = ''
                $fg = [PesFix]::GetForegroundWindow()

                if ([PesFix]::UserWantsOut()) {
                    $deliberate = $true
                    $why = 'Alt/Win key held'
                }
                elseif ($fg -eq $h) {
                    # The minimized game itself owns the foreground - nothing to respect.
                    $deliberate = $false
                }
                elseif ($AlwaysRestore) {
                    $deliberate = $false
                }
                elseif ([PesFix]::ForegroundShowsUserLeft() -and ($gameHadFocus -or (Get-Date) -gt $graceUntil)) {
                    $deliberate = $true
                    $why = 'you switched to another app'
                }

                if ($deliberate) {
                    $iconicStreak = 0
                    if ($lastSkipNote -ne $why) {
                        Write-Step ("[{0:HH:mm:ss}] minimized intentionally ({1}) - leaving it alone" -f (Get-Date), $why) 'DarkGray'
                        $lastSkipNote = $why
                    }
                    continue
                }

                $iconicStreak++
                if ($iconicStreak -lt $requiredStreak) { continue }

                [PesFix]::Focus($h, [uint32](Get-ForegroundLockTimeout)) | Out-Null
                $restores++
                $iconicStreak = 0
                $lastSkipNote = $null
                Write-Step ("[{0:HH:mm:ss}] game had been minimized - restored (#{1})" -f (Get-Date), $restores) 'Yellow'
                Start-Sleep -Milliseconds 350
                continue
            }

            $iconicStreak = 0
            $lastSkipNote = $null

            if ($Mode -eq 'Borderless') {
                $monitor = [PesFix]::MonitorOf($h)
                $target = [PesFix]::MonitorBounds($monitor)
                if ($target.Right -le $target.Left) { continue }

                if (-not [PesFix]::IsBorderless($h)) {
                    [PesFix]::MakeBorderless($h, $target)
                    Write-Step 'Applied borderless fullscreen' 'Green'
                }
                else {
                    $r = [PesFix]::WindowBounds($h)
                    if ($r.Left -ne $target.Left -or $r.Top -ne $target.Top -or
                        ($r.Right - $r.Left) -ne ($target.Right - $target.Left) -or
                        ($r.Bottom - $r.Top) -ne ($target.Bottom - $target.Top)) {
                        [PesFix]::MakeBorderless($h, $target)
                    }
                }
            }
        }

        Start-Sleep -Milliseconds 400
    }
}

# =========================================================================== main
$targetBounds = Get-TargetMonitor
$exe = $null
$processName = 'PES2021'

if ($Action -eq 'Overlays') {
    Write-Step 'eFootball PES 2021 overlay cleaner' 'Cyan'
    if ($OverlayAction -eq 'Off') {
        Write-Step 'Overlay handling is off (-OverlayAction Off).' 'DarkGray'
        return
    }
    $running = @(Get-RunningOverlays)
    if ($running.Count -eq 0) { Write-Step 'No known overlays are running.' 'Green'; return }
    Write-Step ("Found {0} overlay group(s)." -f $running.Count)
    Invoke-OverlaySweep
    Write-Step 'Done.' 'Cyan'
    return
}

if ($Action -eq 'Diagnose') {
    Write-Step 'eFootball PES 2021 focus diagnostics' 'Cyan'
    Write-Step 'This only observes - it changes nothing on your PC.' 'DarkGray'
    Write-Step ''
    Invoke-FocusDiagnostics -Seconds ([Math]::Max(10, $DiagnoseSeconds))
    return
}

if ($Action -eq 'Gpu') {
    $root = Find-GameDir
    $exePath = Join-Path $root 'PES2021.exe'
    $procName = [IO.Path]::GetFileNameWithoutExtension($exePath)

    Write-Step 'eFootball PES 2021 graphics processor' 'Cyan'
    Write-Step ("Game folder : {0}" -f $root)
    Write-Step ''

    if ((Get-DesiredGpuPreference) -ge 0) {
        Set-GpuPreference -Exe $exePath
        Write-Step ''
    }
    Show-GpuReport -Exe $exePath -ProcessName $procName
    return
}

if ($Action -ne 'Keep') {
    $root = Find-GameDir
    $exe = Join-Path $root 'PES2021.exe'
    $processName = [IO.Path]::GetFileNameWithoutExtension($exe)

    if (Test-Path -LiteralPath $script:LogFile) { Remove-Item -LiteralPath $script:LogFile -Force -ErrorAction SilentlyContinue }
    Write-Step "eFootball PES 2021 fullscreen fix" 'Cyan'
    Write-Step "Game folder : $root"
    Write-Step "Mode        : $Mode"
    Write-Step ("Monitor     : {0}x{1}" -f $targetBounds.Width, $targetBounds.Height)
    Write-Step ''

    $settingsFile = Find-SettingsFile
    if (-not $settingsFile) { $settingsFile = New-SettingsFile $root }

    if ($Action -eq 'Restore') {
        Undo-All -Exe $exe -SettingsFile $settingsFile
        Write-Step ''
        Write-Step 'All changes reverted.' 'Cyan'
        return
    }

    Set-DisplaySettings -File $settingsFile -Bounds $targetBounds
    Set-CompatLayers -Exe $exe
    Set-GpuPreference -Exe $exe
    Disable-GameBar
    Set-FocusLock
    Set-NotificationSilence
    Add-DefenderExclusion -Folder $root
    if ($InstallStartup) { Install-Startup }
    if ($RemoveStartup) { Remove-Startup }
    if ($Action -eq 'Fix') {
        if ($OverlayAction -eq 'Close') { Invoke-OverlaySweep }
        elseif ($OverlayAction -eq 'Report') { Invoke-OverlaySweep -ReportOnly }
    }
    Write-Step ''
}

if ($Action -eq 'Fix') {
    Write-Step 'Done. Launch the game from its normal shortcut.' 'Cyan'
    if (-not $InstallStartup) {
        Write-Step 'Tip: add -InstallStartup once to keep the fix active no matter how you start the game.' 'DarkGray'
    }
    return
}

if ($Action -eq 'Play') {
    if ($OverlayAction -eq 'Close') { Invoke-OverlaySweep }
    if (-not (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
        Write-Step 'Starting the game...' 'Cyan'
        Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
    }
    else {
        Write-Step 'Game already running - attaching.' 'Cyan'
    }
    Write-Step 'Keep this window open while you play (it closes itself when the game exits).' 'DarkGray'
    Write-Step ''
    Invoke-Keeper -ProcessName $processName -ExitWhenGameCloses $true
    Write-Step 'Game closed. Bye.' 'Cyan'
    return
}

# Action = Keep
Invoke-Keeper -ProcessName $processName -ExitWhenGameCloses $false
