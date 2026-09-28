<#
.SYNOPSIS
  Read-only audit of the Hybride Bakbrommer repository.

.DESCRIPTION
  One command that checks:
    1. Git state (branches, merges, commits, uncommitted changes, tracked build output)
    2. Folder structure and all files
    3. Every CubeIDE project found (BAS01 / BAS02 / BAS02b): .ioc, config.h,
       debug_uart.c/.h, main.c (USER CODE markers, delays, BSP COM, loop code),
       build output age, and git state of every key file
    4. Docs: CLAUDE.md, HARDWARE_STATUS.md (table shape, conflicting rows), test logs
  Everything is written to the screen AND to a log file:
    <repo>\docs\check-logs\check_YYYY-MM-DD_HHmmss.log
  Send that log file back to Claude to get a follow-up fix script.

  This script never changes your code, never runs git add/commit/checkout.
  The only thing it writes is the log file.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check_project.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\check_project.ps1 -RepoPath "C:\path\to\repo"
#>
param(
    [string]$RepoPath = ""
)

$ErrorActionPreference = "Continue"

$script:Lines          = New-Object System.Collections.Generic.List[string]
$script:Issues         = New-Object System.Collections.Generic.List[string]
$script:CountPass      = 0
$script:CountWarn      = 0
$script:CountFail      = 0
$script:CurrentSection = ""
$script:Root           = ""
$script:IsRepo         = $false
$script:GitExit        = 0
$script:AllFiles       = @()
$script:ExitCode       = 0

# Folders that are only counted, not listed (generated or third-party code)
$ExcludedRegex = '\\(\.git|Debug|Release|Drivers|Middlewares|\.settings|\.metadata)(\\|$)'

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Add-LogLine([string]$Text, [string]$Color = "Gray") {
    $script:Lines.Add($Text)
    Write-Host $Text -ForegroundColor $Color
}

function Write-Section([string]$Title) {
    Add-LogLine ""
    Add-LogLine ("=" * 78) "Cyan"
    Add-LogLine $Title "Cyan"
    Add-LogLine ("=" * 78) "Cyan"
    $script:CurrentSection = $Title
}

function Write-Pass([string]$Msg) {
    $script:CountPass++
    Add-LogLine ("[PASS] " + $Msg) "Green"
}

function Write-Warn([string]$Msg) {
    $script:CountWarn++
    Add-LogLine ("[WARN] " + $Msg) "Yellow"
    $script:Issues.Add("[WARN] " + $Msg)
}

function Write-Fail([string]$Msg) {
    $script:CountFail++
    Add-LogLine ("[FAIL] " + $Msg) "Red"
    $script:Issues.Add("[FAIL] " + $Msg)
}

function Write-Info([string]$Msg) {
    Add-LogLine ("[INFO] " + $Msg) "Gray"
}

function Write-Raw([string[]]$Text) {
    foreach ($l in $Text) {
        Add-LogLine ("    " + $l) "DarkGray"
    }
}

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------
function Get-Rel([string]$Path) {
    if ($Path.StartsWith($script:Root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($script:Root.Length).TrimStart('\')
    }
    return $Path
}

function Read-FileText([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
}

function Invoke-Git {
    $result = & git -C $script:Root -c core.quotepath=false @args 2>&1
    $script:GitExit = $LASTEXITCODE
    return @($result | ForEach-Object { "$_" })
}

function Get-GitFileState([string]$FullPath) {
    if (-not $script:IsRepo) { return "n/a (not a git repository)" }
    if (-not (Test-Path -LiteralPath $FullPath)) { return "MISSING on disk" }
    $rel = (Get-Rel $FullPath) -replace '\\', '/'
    [void](Invoke-Git ls-files --error-unmatch $rel)
    if ($script:GitExit -ne 0) { return "UNTRACKED (never committed)" }
    $st = @(Invoke-Git status --porcelain $rel)
    if ($st.Count -gt 0 -and $st[0].Trim() -ne "") { return "MODIFIED (uncommitted changes)" }
    $last = @(Invoke-Git log -1 "--format=%h %ad %s" "--date=short" $rel)
    return ("COMMITTED - last: " + ($last -join " "))
}

# Returns non-comment lines as objects with Number and Text
function Get-CodeLines([string[]]$SourceLines) {
    $out = @()
    for ($i = 0; $i -lt $SourceLines.Count; $i++) {
        $t = $SourceLines[$i].Trim()
        if ($t.StartsWith('//') -or $t.StartsWith('/*') -or $t.StartsWith('*')) { continue }
        $out += [pscustomobject]@{ Number = ($i + 1); Text = $SourceLines[$i] }
    }
    return $out
}

# Text between /* USER CODE BEGIN name */ and /* USER CODE END name */
function Get-UserSection([string]$Text, [string]$Name) {
    if (-not $Text) { return $null }
    $pattern = '(?s)/\*\s*USER CODE BEGIN ' + [regex]::Escape($Name) + '\s*\*/(.*?)/\*\s*USER CODE END ' + [regex]::Escape($Name) + '\s*\*/'
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Assert-Match([string]$Text, [string]$Pattern, [string]$OkMsg, [string]$BadMsg, [string]$Level = "FAIL") {
    if ($Text -and ($Text -match $Pattern)) {
        Write-Pass $OkMsg
    }
    elseif ($Level -eq "WARN") {
        Write-Warn $BadMsg
    }
    else {
        Write-Fail $BadMsg
    }
}

# ---------------------------------------------------------------------------
# Per-project checks
# ---------------------------------------------------------------------------
function Test-Project([string]$Dir) {
    $rel = Get-Rel $Dir
    Add-LogLine ""
    Add-LogLine ("--- Project: " + $rel) "Cyan"

    $lower       = $Dir.ToLower()
    $board       = "unknown"
    $expectedLed = ""
    if ($lower -match 'g474') { $board = "G474RE"; $expectedLed = "LD2" }
    elseif ($lower -match 'f446') { $board = "F446ZE"; $expectedLed = "LD1" }
    Write-Info ("Board (guessed from folder name): " + $board + "   expected debug LED: " + $expectedLed)

    $failBefore = $script:CountFail
    $warnBefore = $script:CountWarn

    $cfgPath  = Join-Path $Dir "Core\Inc\config.h"
    $hPath    = Join-Path $Dir "Core\Inc\debug_uart.h"
    $cPath    = Join-Path $Dir "Core\Src\debug_uart.c"
    $mainPath = Join-Path $Dir "Core\Src\main.c"
    $keyFiles = @($cfgPath, $hPath, $cPath, $mainPath)

    # --- files exist
    foreach ($p in $keyFiles) {
        if (Test-Path -LiteralPath $p) { Write-Pass ("exists: " + (Get-Rel $p)) }
        else { Write-Fail ("MISSING: " + (Get-Rel $p)) }
    }

    # --- config.h
    $cfg    = Read-FileText $cfgPath
    $handle = ""
    if ($cfg) {
        foreach ($name in @("DEBUG_UART_HANDLE", "DEBUG_UART_BUFFER_SIZE", "DEBUG_UART_TIMEOUT_MS", "HEARTBEAT_PERIOD_MS")) {
            $m = [regex]::Match($cfg, '(?m)^\s*#define\s+' + $name + '\s+(\S+)')
            if ($m.Success) {
                Write-Pass ("config.h defines " + $name + " = " + $m.Groups[1].Value)
                if ($name -eq "DEBUG_UART_HANDLE") { $handle = $m.Groups[1].Value }
            }
            else {
                Write-Fail ("config.h does NOT define " + $name)
            }
        }
        if ($cfg -notmatch '#ifndef\s+CONFIG_H') { Write-Warn "config.h has no include guard (#ifndef CONFIG_H)" }
    }

    # --- debug_uart.h / .c
    $h = Read-FileText $hPath
    Assert-Match $h '#ifndef\s+DEBUG_UART_H' "debug_uart.h has include guard" "debug_uart.h missing include guard or file missing"
    Assert-Match $h 'void\s+Debug_Init\s*\(\s*void\s*\)' "debug_uart.h declares Debug_Init(void)" "debug_uart.h does not declare Debug_Init(void)"
    Assert-Match $h 'void\s+Debug_Printf\s*\(' "debug_uart.h declares Debug_Printf(...)" "debug_uart.h does not declare Debug_Printf(...)"

    $c = Read-FileText $cPath
    Assert-Match $c '#include\s+"config\.h"' "debug_uart.c includes config.h" "debug_uart.c does not include config.h"
    Assert-Match $c 'extern\s+UART_HandleTypeDef\s+DEBUG_UART_HANDLE' "debug_uart.c uses extern DEBUG_UART_HANDLE" "debug_uart.c does not use 'extern UART_HandleTypeDef DEBUG_UART_HANDLE' (hard-coded handle?)" "WARN"
    Assert-Match $c 'vsnprintf' "debug_uart.c uses vsnprintf (safe formatting)" "debug_uart.c does not use vsnprintf"
    Assert-Match $c 'HAL_UART_Transmit\s*\(\s*&DEBUG_UART_HANDLE' "debug_uart.c transmits via HAL_UART_Transmit(&DEBUG_UART_HANDLE, ...)" "debug_uart.c does not call HAL_UART_Transmit(&DEBUG_UART_HANDLE, ...)"

    # --- main.c
    $mainText = Read-FileText $mainPath
    if ($mainText) {
        $mainLines = $mainText -split "`r?`n"
        $codeLines = @(Get-CodeLines $mainLines)

        # USER CODE markers: duplicates and unpaired
        $begin = @([regex]::Matches($mainText, '/\*\s*USER CODE BEGIN (.+?)\s*\*/') | ForEach-Object { $_.Groups[1].Value })
        $end   = @([regex]::Matches($mainText, '/\*\s*USER CODE END (.+?)\s*\*/') | ForEach-Object { $_.Groups[1].Value })
        $dupBegin = @($begin | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($dupBegin.Count -eq 0) {
            Write-Pass "main.c: no duplicated USER CODE BEGIN markers"
        }
        else {
            foreach ($g in $dupBegin) {
                Write-Warn ("main.c: 'USER CODE BEGIN " + $g.Name + "' appears " + $g.Count + " times (delete the duplicate pair)")
            }
        }
        $unpaired = @($begin | Where-Object { $end -notcontains $_ })
        if ($unpaired.Count -eq 0) { Write-Pass "main.c: every USER CODE BEGIN has a matching END" }
        else { Write-Warn ("main.c: BEGIN without END: " + ($unpaired -join ", ")) }

        # includes
        $inc = Get-UserSection $mainText "Includes"
        Assert-Match $inc '#include\s+"config\.h"' "main.c includes config.h (USER CODE Includes)" "main.c: config.h not included inside USER CODE BEGIN/END Includes"
        Assert-Match $inc '#include\s+"debug_uart\.h"' "main.c includes debug_uart.h (USER CODE Includes)" "main.c: debug_uart.h not included inside USER CODE BEGIN/END Includes"

        # USER CODE 1: heartbeat counter
        $s1 = Get-UserSection $mainText "1"
        Assert-Match $s1 'uint32_t\s+heartbeat_count' "main.c declares heartbeat_count (USER CODE 1)" "main.c: 'uint32_t heartbeat_count' not found in USER CODE 1" "WARN"

        # USER CODE 2: Debug_Init
        $s2 = Get-UserSection $mainText "2"
        Assert-Match $s2 'Debug_Init\s*\(\s*\)\s*;' "main.c calls Debug_Init() (USER CODE 2)" "main.c: Debug_Init(); not found in USER CODE 2"

        # Debug_Init after the UART init
        $mx = [regex]::Match($mainText, 'MX_\w*UART\w*_Init\s*\(\s*\)\s*;')
        $di = [regex]::Match($mainText, 'Debug_Init\s*\(\s*\)\s*;')
        if ($mx.Success -and $di.Success) {
            if ($di.Index -gt $mx.Index) { Write-Pass "Debug_Init() is called after the UART init" }
            else { Write-Fail "Debug_Init() is called BEFORE the UART init (nothing can print yet)" }
        }
        elseif (-not $mx.Success) {
            Write-Fail "main.c: no MX_..._UART_Init() call found (is the UART enabled in CubeMX?)"
        }

        # loop block
        $s3 = Get-UserSection $mainText "3"
        if ($s3) {
            Write-Info "USER CODE 3 (main loop) content:"
            Write-Raw ($s3 -split "`r?`n")
            Assert-Match $s3 'Debug_Printf\s*\(' "loop calls Debug_Printf()" "loop (USER CODE 3) does not call Debug_Printf()"
            Assert-Match $s3 'heartbeat_count\s*\+\+' "loop increments heartbeat_count" "loop does not increment heartbeat_count" "WARN"
            Assert-Match $s3 'HAL_Delay\s*\(\s*HEARTBEAT_PERIOD_MS\s*\)' "loop delays with HEARTBEAT_PERIOD_MS" "loop does not call HAL_Delay(HEARTBEAT_PERIOD_MS)"
            if ($expectedLed -ne "") {
                Assert-Match $s3 ('HAL_GPIO_TogglePin\s*\(\s*' + $expectedLed + '_GPIO_Port') ("loop toggles " + $expectedLed) ("loop does not toggle " + $expectedLed + " (wrong LED name for " + $board + "?)") "WARN"
            }
            $dp = $s3.IndexOf('Debug_Printf')
            if ($dp -ge 0) {
                $prefix = $s3.Substring(0, $dp)
                $bal = ([regex]::Matches($prefix, '\{')).Count - ([regex]::Matches($prefix, '\}')).Count
                if ($bal -ge 0) { Write-Pass "Debug_Printf is inside the while(1) loop" }
                else { Write-Fail "Debug_Printf sits AFTER the closing brace of while(1): it never runs" }
            }
        }
        else {
            Write-Fail "main.c: USER CODE BEGIN 3 / END 3 block not found"
        }

        # all HAL_Delay calls in real code
        $delays = @($codeLines | Where-Object { $_.Text -match 'HAL_Delay\s*\(' })
        Write-Info ("HAL_Delay calls in main.c (code only): " + $delays.Count)
        foreach ($d in $delays) { Write-Raw ("line " + $d.Number + ": " + $d.Text.Trim()) }
        if ($delays.Count -eq 1) { Write-Pass "exactly one HAL_Delay in main.c" }
        elseif ($delays.Count -eq 0) { Write-Fail "no HAL_Delay in main.c" }
        else { Write-Fail ("" + $delays.Count + " HAL_Delay calls in main.c: old blink delay still there? (caused a 3 s interval on the F446ZE)") }
        $hardDelays = @($delays | Where-Object { $_.Text -match 'HAL_Delay\s*\(\s*\d' })
        if ($hardDelays.Count -gt 0) { Write-Warn "HAL_Delay with a hard-coded number found (magic number, use config.h)" }

        # BSP COM leftovers
        $bsp = @($codeLines | Where-Object { $_.Text -match 'BSP_COM_Init|BspCOMInit|BSP_COM_SelectLogPort' })
        if ($bsp.Count -eq 0) { Write-Pass "main.c has no BSP COM code" }
        else {
            Write-Warn "main.c has BSP COM code (this froze BAS02 earlier: double UART init -> Error_Handler)"
            foreach ($b in $bsp) { Write-Raw ("line " + $b.Number + ": " + $b.Text.Trim()) }
        }

        # UART handles declared in main.c
        $handles = @([regex]::Matches($mainText, 'UART_HandleTypeDef\s+(\w+)\s*;') | ForEach-Object { $_.Groups[1].Value })
        Write-Info ("UART handles declared in main.c: " + ($handles -join ", "))
        if ($handle -ne "") {
            if ($handles -contains $handle) { Write-Pass ("DEBUG_UART_HANDLE (" + $handle + ") matches a handle in main.c") }
            else { Write-Fail ("DEBUG_UART_HANDLE is '" + $handle + "' but main.c declares: " + ($handles -join ", ")) }
        }
    }

    # --- .ioc
    $iocFiles = @(Get-ChildItem -LiteralPath $Dir -Filter *.ioc -File -ErrorAction SilentlyContinue)
    if ($iocFiles.Count -eq 0) {
        Write-Fail "no .ioc file in the project folder"
    }
    foreach ($f in $iocFiles) {
        $keyFiles += $f.FullName
        Write-Pass ("found .ioc: " + $f.Name + " (last write " + $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm") + ")")
        $iocLines = @(Get-Content -LiteralPath $f.FullName)
        $relevant = @($iocLines | Where-Object { $_ -match '^(Mcu\.(UserName|Family|Name)=|ProjectManager\.(ProjectName|FirmwarePackage)|P[A-Z]\d+\.(Signal|Mode)=.*(UART|USART)|(USART|UART|LPUART)\d+\.|Mcu\.IP\d+=.*(UART|USART)|.*BSP.*|.*COM[0-9].*)' })
        Write-Info ".ioc lines about MCU, UART and BSP:"
        Write-Raw $relevant

        $uartIps = @($iocLines | Where-Object { $_ -match '^Mcu\.IP\d+=(USART|UART|LPUART)\d+$' } | ForEach-Object { ($_ -split '=')[1] })
        Write-Info ("UART peripherals enabled in .ioc: " + ($uartIps -join ", "))
        if ($uartIps.Count -gt 1) { Write-Warn ("more than one UART enabled in .ioc (" + ($uartIps -join ", ") + "); BAS02 expects only the debug UART") }
        if ($uartIps.Count -eq 0) { Write-Fail "no UART enabled in .ioc" }

        if ($handle -match '^h(lp)?u(s)?art(\d+)$') {
            $isLp = $Matches[1]
            $num  = $Matches[3]
            if ($isLp) { $cands = @("LPUART" + $num) } else { $cands = @(("USART" + $num), ("UART" + $num)) }
            $found = @($cands | Where-Object { $uartIps -contains $_ })
            if ($found.Count -gt 0) {
                Write-Pass ("handle " + $handle + " matches enabled peripheral " + ($found -join "/"))
                foreach ($inst in $found) {
                    $bl = @($iocLines | Where-Object { $_ -match ('^' + $inst + '\.BaudRate=(\d+)') })
                    if ($bl.Count -gt 0) {
                        $baud = ($bl[0] -split '=')[1]
                        if ($baud -eq "115200") { Write-Pass ($inst + " baud rate = 115200") }
                        else { Write-Warn ($inst + " baud rate = " + $baud + " (terminal is set to 115200)") }
                    }
                    else {
                        Write-Info ($inst + ".BaudRate not stored in .ioc (CubeMX default applies); the generated main.c is the reference")
                    }
                }
            }
            else {
                Write-Fail ("handle " + $handle + " does not match any UART enabled in the .ioc (" + ($uartIps -join ", ") + ")")
            }
        }

        $pins = @($iocLines | Where-Object { $_ -match '^P[A-Z]\d+\.Signal=.*(UART|USART)' })
        Write-Info ("UART pin signals in .ioc: " + ($pins -join "  "))
        if ($board -eq "G474RE") {
            if (($pins -contains 'PA2.Signal=USART2_TX') -and ($pins -contains 'PA3.Signal=USART2_RX')) {
                Write-Pass "G474RE: PA2 = USART2_TX and PA3 = USART2_RX (ST-LINK virtual COM port pins)"
            }
            else {
                Write-Warn "G474RE: PA2/PA3 are not both set to USART2 TX/RX in the .ioc"
            }
        }
        elseif ($board -eq "F446ZE") {
            Write-Info "F446ZE: script cannot verify these are the ST-LINK VCP pins; compare with the board manual UM1974"
        }
    }

    # --- BSP COM feature flag in the nucleo conf header
    $confFiles = @(Get-ChildItem -LiteralPath (Join-Path $Dir "Core\Inc") -Filter "*nucleo_conf.h" -File -ErrorAction SilentlyContinue)
    if ($confFiles.Count -eq 0) {
        Write-Info "no *_nucleo_conf.h found (BSP not used in this project)"
    }
    foreach ($cf in $confFiles) {
        $ct = Read-FileText $cf.FullName
        $m = [regex]::Match($ct, '(?m)^\s*#define\s+USE_BSP_COM_FEATURE\s+(\w+)')
        if ($m.Success) {
            $v = $m.Groups[1].Value
            if ($v -match '^0') { Write-Pass ($cf.Name + ": USE_BSP_COM_FEATURE = " + $v + " (BSP COM off)") }
            else { Write-Warn ($cf.Name + ": USE_BSP_COM_FEATURE = " + $v + " (BSP COM on: can conflict with our own UART init)") }
        }
        else {
            Write-Info ($cf.Name + ": USE_BSP_COM_FEATURE not found")
        }
    }

    # --- build output vs source age
    $elfs = @()
    $debugDir = Join-Path $Dir "Debug"
    if (Test-Path -LiteralPath $debugDir) {
        $elfs = @(Get-ChildItem -LiteralPath $debugDir -Filter *.elf -File -ErrorAction SilentlyContinue)
    }
    if ($elfs.Count -eq 0) {
        Write-Warn "no .elf in Debug\ (project not built yet?)"
    }
    else {
        $elf = $elfs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $srcTimes = @()
        foreach ($p in @($cfgPath, $hPath, $cPath, $mainPath)) {
            if (Test-Path -LiteralPath $p) { $srcTimes += (Get-Item -LiteralPath $p).LastWriteTime }
        }
        Write-Info ("newest .elf: " + $elf.Name + "  " + $elf.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
        if ($srcTimes.Count -gt 0) {
            $newestSrc = ($srcTimes | Sort-Object -Descending | Select-Object -First 1)
            Write-Info ("newest source file: " + $newestSrc.ToString("yyyy-MM-dd HH:mm:ss"))
            if ($elf.LastWriteTime -ge $newestSrc) { Write-Pass ".elf is newer than the source files" }
            else { Write-Warn ".elf is OLDER than the source files: rebuild and reflash before trusting a test result" }
        }
    }

    # --- git state of key files
    foreach ($p in $keyFiles) {
        $state = Get-GitFileState $p
        if ($state -like 'COMMITTED*') { Write-Pass ("git: " + (Get-Rel $p) + " -> " + $state) }
        elseif ($state -like 'n/a*') { Write-Info ("git: " + (Get-Rel $p) + " -> " + $state) }
        else { Write-Warn ("git: " + (Get-Rel $p) + " -> " + $state) }
    }

    return [pscustomobject]@{
        Rel    = $rel
        Board  = $board
        Handle = $handle
        Fails  = ($script:CountFail - $failBefore)
        Warns  = ($script:CountWarn - $warnBefore)
        HPath  = $hPath
        CPath  = $cPath
    }
}

# ---------------------------------------------------------------------------
# Docs checks
# ---------------------------------------------------------------------------
function Test-Docs {
    # --- CLAUDE.md
    $claudeRoot = Join-Path $script:Root "CLAUDE.md"
    if (Test-Path -LiteralPath $claudeRoot) {
        Write-Pass "CLAUDE.md found in the repo root"
        $cl = @(Get-Content -LiteralPath $claudeRoot)
        Write-Info ("CLAUDE.md length: " + $cl.Count + " lines (advice: keep under about 200)")
        if ($cl.Count -gt 200) { Write-Warn "CLAUDE.md is longer than 200 lines" }
        $clText = $cl -join "`n"
        if ($clText -match '@docs/HARDWARE_STATUS\.md') {
            if (Test-Path -LiteralPath (Join-Path $script:Root "docs\HARDWARE_STATUS.md")) { Write-Pass "CLAUDE.md imports @docs/HARDWARE_STATUS.md and that file exists" }
            else { Write-Fail "CLAUDE.md imports @docs/HARDWARE_STATUS.md but docs\HARDWARE_STATUS.md does not exist" }
        }
        else {
            Write-Warn "CLAUDE.md has no '@docs/HARDWARE_STATUS.md' import line"
        }
        if ($clText -match 'moet nog toegevoegd') { Write-Info "CLAUDE.md: Fardriver CAN protocol section is still a placeholder" }
    }
    else {
        $others = @($script:AllFiles | Where-Object { $_.Name -eq "CLAUDE.md" -and ("\" + (Get-Rel $_.FullName)) -notmatch $ExcludedRegex })
        if ($others.Count -gt 0) { Write-Warn ("CLAUDE.md is not in the repo root, found at: " + ((@($others | ForEach-Object { Get-Rel $_.FullName })) -join ", ")) }
        else { Write-Warn "CLAUDE.md not found anywhere in the repo" }
    }

    # --- HARDWARE_STATUS.md
    $hwFiles = @($script:AllFiles | Where-Object { $_.Name -eq "HARDWARE_STATUS.md" -and ("\" + (Get-Rel $_.FullName)) -notmatch $ExcludedRegex })
    if ($hwFiles.Count -eq 0) {
        Write-Fail "HARDWARE_STATUS.md not found"
    }
    else {
        if ($hwFiles.Count -gt 1) { Write-Warn ("multiple HARDWARE_STATUS.md files: " + ((@($hwFiles | ForEach-Object { Get-Rel $_.FullName })) -join ", ")) }
        $hw = $hwFiles[0]
        Write-Info ("HARDWARE_STATUS.md: " + (Get-Rel $hw.FullName) + "  (last write " + $hw.LastWriteTime.ToString("yyyy-MM-dd HH:mm") + ")")
        if ((Get-Rel $hw.FullName) -notlike 'docs\*') { Write-Warn "HARDWARE_STATUS.md is not in docs\ (CLAUDE.md expects docs/HARDWARE_STATUS.md)" }

        $hwLines = @(Get-Content -LiteralPath $hw.FullName)
        $byKey   = @{}
        $rowInfo = @()
        for ($i = 0; $i -lt $hwLines.Count; $i++) {
            $t = $hwLines[$i].Trim()
            if (-not $t.StartsWith('|')) { continue }

            $prevIsTable = ($i -gt 0) -and $hwLines[$i - 1].Trim().StartsWith('|')
            if (-not $prevIsTable) {
                $next = ""
                if ($i + 1 -lt $hwLines.Count) { $next = $hwLines[$i + 1].Trim() }
                if ($next -notmatch '^\|[\s\-:|]+\|$') {
                    $snippet = $t.Substring(0, [Math]::Min(60, $t.Length))
                    Write-Warn ("HARDWARE_STATUS.md line " + ($i + 1) + ": table has no header/separator row, Markdown will not render it: " + $snippet)
                }
            }
            if (-not $t.EndsWith('|')) {
                $snippet2 = $t.Substring(0, [Math]::Min(60, $t.Length))
                Write-Warn ("HARDWARE_STATUS.md line " + ($i + 1) + ": row does not end with '|' (unfinished line): " + $snippet2)
            }
            if ($t -match '^\|[\s\-:|]+\|$') { continue }

            $cells  = @($t.Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
            $status = ""
            foreach ($cell in $cells) {
                if ($cell -match '^(NOT TESTED|IN PROGRESS|VERIFIED|FAILED)') { $status = $Matches[1]; break }
            }
            if ($status -eq "") { continue }
            $key = $cells[0]
            if (-not $byKey.ContainsKey($key)) { $byKey[$key] = @() }
            $byKey[$key] += $status
            $rowInfo += [pscustomobject]@{ Line = ($i + 1); Key = $key; Status = $status; Text = $t }
        }

        # conflicting duplicates
        $conflict = $false
        foreach ($k in $byKey.Keys) {
            $distinct = @($byKey[$k] | Select-Object -Unique)
            if ($byKey[$k].Count -gt 1) {
                if ($distinct.Count -gt 1) { Write-Warn ("HARDWARE_STATUS.md: '" + $k + "' appears " + $byKey[$k].Count + " times with different statuses: " + ($byKey[$k] -join " / ")); $conflict = $true }
                else { Write-Warn ("HARDWARE_STATUS.md: '" + $k + "' appears " + $byKey[$k].Count + " times (duplicate row)"); $conflict = $true }
            }
        }
        if (-not $conflict) { Write-Pass "HARDWARE_STATUS.md: no duplicate or conflicting rows" }

        $notTested = @($rowInfo | Where-Object { $_.Status -eq "NOT TESTED" }).Count
        Write-Info ("status rows: " + $rowInfo.Count + " total, " + $notTested + " NOT TESTED")
        Write-Info "rows that are not NOT TESTED:"
        foreach ($r in @($rowInfo | Where-Object { $_.Status -ne "NOT TESTED" })) {
            Write-Raw ("line " + $r.Line + ": [" + $r.Status + "] " + $r.Key)
        }

        # BAS02 / BAS02b rows
        $bas02  = @($rowInfo | Where-Object { $_.Text -match 'BAS02(?!b)' })
        $bas02b = @($rowInfo | Where-Object { $_.Text -match 'BAS02b' })
        if ($bas02.Count -eq 0) { Write-Warn "HARDWARE_STATUS.md: no BAS02 row (UART debug G474RE)" }
        elseif (@($bas02 | Where-Object { $_.Status -eq "VERIFIED" }).Count -gt 0) { Write-Pass "HARDWARE_STATUS.md: BAS02 is VERIFIED" }
        else { Write-Warn ("HARDWARE_STATUS.md: BAS02 status is " + $bas02[0].Status + ", expected VERIFIED") }
        if ($bas02b.Count -eq 0) { Write-Warn "HARDWARE_STATUS.md: no BAS02b row (UART debug F446ZE)" }
        elseif (@($bas02b | Where-Object { $_.Status -eq "VERIFIED" }).Count -gt 0) { Write-Pass "HARDWARE_STATUS.md: BAS02b is VERIFIED" }
        else { Write-Warn ("HARDWARE_STATUS.md: BAS02b status is " + $bas02b[0].Status + ", expected VERIFIED") }

        # placeholders left in the table
        $ph = @($hwLines | Where-Object { $_ -match 'invullen|USART\?|P\?\?|\(datum\)' })
        if ($ph.Count -gt 0) { Write-Warn "HARDWARE_STATUS.md still contains unfilled placeholders (invullen / USART? / P?? / (datum))" }

        # decisions
        $decisions = @()
        $inDec = $false
        foreach ($l in $hwLines) {
            if ($l -match '^##\s+Decisions made') { $inDec = $true; continue }
            if ($inDec -and ($l -match '^(##\s|---)')) { break }
            if ($inDec -and ($l -match '^-\s+\S')) { $decisions += $l }
        }
        if ($decisions.Count -eq 0) { Write-Warn "HARDWARE_STATUS.md: 'Decisions made' has no entries yet" }
        else { Write-Pass ("HARDWARE_STATUS.md: " + $decisions.Count + " decision line(s)"); Write-Raw $decisions }
    }

    # --- test logs
    $tlDir = Join-Path $script:Root "docs\test-log"
    if (-not (Test-Path -LiteralPath $tlDir)) {
        Write-Fail "docs\test-log folder does not exist"
        return
    }
    $tl = @(Get-ChildItem -LiteralPath $tlDir -Filter *.md -File -ErrorAction SilentlyContinue | Sort-Object Name)
    Write-Info ("test log files: " + $tl.Count)
    foreach ($f in $tl) { Write-Raw ($f.Name + "  (" + $f.Length + " bytes)") }

    if (@($tl | Where-Object { $_.Name -match 'bas01' }).Count -eq 0) { Write-Warn "no BAS01 (blink) test log in docs\test-log" }
    if (@($tl | Where-Object { $_.Name -match 'bas02(?!b)' }).Count -eq 0) { Write-Warn "no BAS02 (G474RE UART debug) test log in docs\test-log" }
    if (@($tl | Where-Object { $_.Name -match 'bas02b' }).Count -eq 0) { Write-Warn "no BAS02b (F446ZE UART debug) test log in docs\test-log" }

    $labels = @("Goal:", "Board(s):", "Wiring", "CubeMX settings", "Code location", "Result:", "What I measured", "Gotchas", "Promoted into module")
    foreach ($f in $tl) {
        $txt = Read-FileText $f.FullName
        if (-not $txt) { Write-Warn ($f.Name + ": file is empty"); continue }
        $missing = @($labels | Where-Object { $txt -notmatch [regex]::Escape($_) })
        if ($missing.Count -eq 0) { Write-Pass ($f.Name + ": all template fields present") }
        else { Write-Warn ($f.Name + ": missing template fields: " + ($missing -join ", ")) }
        if ($txt -match 'USART\?|P\?\?|\(datum\)|invullen|\$Uart|\$Pins') { Write-Warn ($f.Name + ": contains an unfilled placeholder (USART? / P?? / `$Uart / `$Pins)") }
        $res = [regex]::Match($txt, '(?m)^Result:\s*(.*)$')
        if ($res.Success) { Write-Info ($f.Name + " -> Result: " + $res.Groups[1].Value.Trim()) }
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
$startDir = $RepoPath
if ($startDir -eq "") {
    if ($PSScriptRoot) { $startDir = $PSScriptRoot } else { $startDir = (Get-Location).Path }
}
if (-not (Test-Path -LiteralPath $startDir)) {
    Write-Host ("Path not found: " + $startDir) -ForegroundColor Red
    exit 2
}
$script:Root = (Resolve-Path -LiteralPath $startDir).Path.TrimEnd('\')

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $top = & git -C $script:Root rev-parse --show-toplevel 2>$null
    if (($LASTEXITCODE -eq 0) -and $top) {
        $script:Root   = (Resolve-Path -LiteralPath ([string]$top)).Path.TrimEnd('\')
        $script:IsRepo = $true
    }
}

# Log folder is created BEFORE the log file is written
$stamp  = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logDir = Join-Path $script:Root "docs\check-logs"
try {
    New-Item -ItemType Directory -Force -Path $logDir -ErrorAction Stop | Out-Null
}
catch {
    $logDir = Join-Path $env:TEMP "bakbrommer-check-logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}
$logFile = Join-Path $logDir ("check_" + $stamp + ".log")

try {
    # ------------------------------------------------------------------ 0
    Write-Section "0. RUN INFO"
    Add-LogLine ("Date/time      : " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    Add-LogLine "Script        : check_project.ps1 v1 (read-only)"
    Add-LogLine ("Repo root      : " + $script:Root)
    Add-LogLine ("Is git repo    : " + $script:IsRepo)
    Add-LogLine ("PowerShell     : " + $PSVersionTable.PSVersion.ToString())
    Add-LogLine ("Log file       : " + $logFile)

    # ------------------------------------------------------------------ 1
    Write-Section "1. GIT STATE"
    if (-not $script:IsRepo) {
        Write-Fail "Not a git repository, or git is not installed. Git checks skipped."
    }
    else {
        Write-Info ("git version: " + ((Invoke-Git --version) -join ""))
        $branch = (@(Invoke-Git branch --show-current) -join "")
        Write-Info ("current branch: " + $branch)
        Write-Info ("HEAD: " + ((@(Invoke-Git log -1 "--format=%h %ad %s" "--date=short")) -join " "))

        $branches = @(Invoke-Git for-each-ref "--format=%(refname:short)" refs/heads)
        $default = ""
        foreach ($cand in @("main", "master")) {
            if ($branches -contains $cand) { $default = $cand; break }
        }
        Write-Info "local branches with upstream info:"
        Write-Raw (Invoke-Git branch -vv)

        if ($default -eq "") {
            Write-Warn "no 'main' or 'master' branch exists yet"
        }
        else {
            Write-Info ("default branch: " + $default)
            if ($branch -ne $default) { Write-Info ("you are on '" + $branch + "', not on '" + $default + "'") }
            foreach ($b in $branches) {
                if ($b -eq $default) { continue }
                [void](Invoke-Git merge-base --is-ancestor $b $default)
                if ($script:GitExit -eq 0) { Write-Pass ("branch '" + $b + "' is merged into " + $default) }
                else { Write-Warn ("branch '" + $b + "' has commits that are NOT in " + $default + " yet (not merged)") }
            }
        }

        Write-Info "last commits (all branches):"
        Write-Raw (Invoke-Git log --all --oneline --decorate -20)

        $bas = @(Invoke-Git log --all --oneline "--grep=BAS0")
        if (@($bas | Where-Object { $_ -match 'BAS02:' }).Count -gt 0) { Write-Pass "a commit for BAS02 exists" } else { Write-Warn "no commit with 'BAS02:' in its message" }
        if (@($bas | Where-Object { $_ -match 'BAS02b' }).Count -gt 0) { Write-Pass "a commit for BAS02b exists" } else { Write-Warn "no commit with 'BAS02b' in its message" }

        $remotes = @(Invoke-Git remote -v)
        if ($remotes.Count -eq 0 -or ($remotes.Count -eq 1 -and $remotes[0].Trim() -eq "")) {
            Write-Info "no remote configured (nothing is backed up online)"
        }
        else {
            Write-Info "remotes:"
            Write-Raw $remotes
            $ab = @(Invoke-Git rev-list --left-right --count "@{u}...HEAD")
            if ($script:GitExit -eq 0 -and $ab.Count -gt 0) { Write-Info ("behind/ahead of upstream: " + ($ab[0] -replace '\s+', " / ")) }
            else { Write-Info "current branch has no upstream" }
        }

        $stash = @(Invoke-Git stash list)
        if ($stash.Count -eq 0 -or $stash[0].Trim() -eq "") { Write-Pass "no stashed changes" }
        else { Write-Warn ("" + $stash.Count + " stash entries exist"); Write-Raw $stash }

        # .gitignore
        $gi = Join-Path $script:Root ".gitignore"
        if (Test-Path -LiteralPath $gi) {
            Write-Info ".gitignore content:"
            Write-Raw (Get-Content -LiteralPath $gi)
        }
        else {
            Write-Info "no .gitignore in the repo root"
        }

        # tracked build output
        $tracked = @(Invoke-Git ls-files)
        $trackedBuild = @($tracked | Where-Object { $_ -match '(^|/)(Debug|Release)/' })
        Write-Info ("tracked files in total: " + $tracked.Count)
        if ($trackedBuild.Count -gt 0) { Write-Warn ("" + $trackedBuild.Count + " build-output files (Debug/Release) are tracked by git; they change on every build (add them to .gitignore)") }
        else { Write-Pass "no build output is tracked by git" }

        # working tree status
        $status     = @(Invoke-Git status --porcelain -uall)
        $srcChanges = @()
        $buildCount = 0
        $logCount   = 0
        foreach ($line in $status) {
            if ($line.Length -lt 4) { continue }
            $code = $line.Substring(0, 2)
            $p    = $line.Substring(3)
            if ($p -match '(^|/)(Debug|Release)/') { $buildCount++; continue }
            if ($p -like 'docs/check-logs/*') { $logCount++; continue }
            $srcChanges += ($code + " " + $p)
        }
        Write-Info ("changed/untracked build-output files (Debug/Release): " + $buildCount)
        Write-Info ("check-log files (ignored in this list): " + $logCount)
        if ($srcChanges.Count -eq 0) { Write-Pass "no uncommitted source or doc changes" }
        else {
            Write-Warn ("" + $srcChanges.Count + " uncommitted source/doc changes (' M' modified, 'M ' staged, '??' untracked):")
            Write-Raw $srcChanges
        }
    }

    # ------------------------------------------------------------------ 2
    Write-Section "2. FOLDER STRUCTURE AND FILES"
    $allDirs = @(Get-ChildItem -LiteralPath $script:Root -Recurse -Directory -Force -ErrorAction SilentlyContinue)
    $script:AllFiles = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File -Force -ErrorAction SilentlyContinue)

    $rootFiles = @($script:AllFiles | Where-Object { $_.DirectoryName -eq $script:Root })
    Add-LogLine ("[root]  (" + $rootFiles.Count + " files)")
    $shownDirs = @($allDirs | Where-Object { ("\" + (Get-Rel $_.FullName)) -notmatch $ExcludedRegex } | Sort-Object FullName)
    foreach ($d in $shownDirs) {
        $relDir = Get-Rel $d.FullName
        $depth  = ($relDir.Split('\')).Count
        $count  = @($script:AllFiles | Where-Object { $_.DirectoryName -eq $d.FullName }).Count
        Add-LogLine (("  " * $depth) + $d.Name + "\   (" + $count + " files)")
    }

    Add-LogLine ""
    Write-Info "folders that are only counted (generated or third-party):"
    $hidden = @{}
    foreach ($f in $script:AllFiles) {
        $relFile = Get-Rel $f.FullName
        if (("\" + $relFile) -match $ExcludedRegex) {
            $m = [regex]::Match($relFile, '^(?:.*?\\)?(?:\.git|Debug|Release|Drivers|Middlewares|\.settings|\.metadata)(?=\\|$)')
            $hk = $m.Value
            if (-not $hidden.ContainsKey($hk)) { $hidden[$hk] = @{ Files = 0; Size = 0 } }
            $hidden[$hk].Files++
            $hidden[$hk].Size += $f.Length
        }
    }
    foreach ($hk in ($hidden.Keys | Sort-Object)) {
        Add-LogLine (("    {0,-72} {1,6} files {2,9} KB" -f $hk, $hidden[$hk].Files, [Math]::Round($hidden[$hk].Size / 1KB)))
    }

    Add-LogLine ""
    Write-Info "all other files (size in bytes, last write, path):"
    $listed = @($script:AllFiles | Where-Object { ("\" + (Get-Rel $_.FullName)) -notmatch $ExcludedRegex } | Sort-Object FullName)
    foreach ($f in $listed) {
        Add-LogLine (("    {0,9}  {1}  {2}" -f $f.Length, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), (Get-Rel $f.FullName)))
    }
    Write-Info ("files listed: " + $listed.Count)

    # ------------------------------------------------------------------ 3
    Write-Section "3. PROJECT CHECKS (BAS01 blink / BAS02 and BAS02b UART debug)"
    $mainFiles = @($script:AllFiles | Where-Object {
            $_.Name -eq "main.c" -and
            $_.FullName -match '\\Core\\Src\\main\.c$' -and
            ("\" + (Get-Rel $_.FullName)) -notmatch $ExcludedRegex
        })
    $results = @()
    if ($mainFiles.Count -eq 0) {
        Write-Fail "no CubeIDE project found (no Core\Src\main.c)"
    }
    else {
        Write-Info ("projects found: " + $mainFiles.Count)
        foreach ($mf in $mainFiles) {
            $projDir = $mf.Directory.Parent.Parent.FullName
            $results += Test-Project $projDir
        }
    }

    # compare the shared module between boards
    if ($results.Count -ge 2) {
        Add-LogLine ""
        Add-LogLine "--- Shared module comparison between projects" "Cyan"
        foreach ($which in @("HPath", "CPath")) {
            $hashes = @()
            foreach ($r in $results) {
                $p = $r.$which
                if (Test-Path -LiteralPath $p) { $hashes += [pscustomobject]@{ Proj = $r.Rel; Hash = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } }
            }
            $name = Split-Path -Leaf ($results[0].$which)
            if ($hashes.Count -ge 2) {
                $distinct = @($hashes | Select-Object -ExpandProperty Hash -Unique)
                if ($distinct.Count -eq 1) { Write-Pass ($name + " is identical in all projects") }
                else {
                    Write-Warn ($name + " DIFFERS between projects (the module should be the same on every board)")
                    foreach ($h in $hashes) { Write-Raw ($h.Hash.Substring(0, 12) + "  " + $h.Proj) }
                }
            }
        }
    }

    # ------------------------------------------------------------------ 4
    Write-Section "4. DOCS (CLAUDE.md, HARDWARE_STATUS.md, test logs)"
    Test-Docs

    # ------------------------------------------------------------------ 5
    Write-Section "5. SUMMARY"
    Add-LogLine ("PASS: " + $script:CountPass + "    WARN: " + $script:CountWarn + "    FAIL: " + $script:CountFail)
    Add-LogLine ""
    Write-Info "per project:"
    foreach ($r in $results) {
        $verdict = "OK"
        if ($r.Fails -gt 0) { $verdict = "HAS FAILS" } elseif ($r.Warns -gt 0) { $verdict = "WARNINGS" }
        Add-LogLine (("    {0,-58} {1,-7} handle={2,-9} FAIL={3} WARN={4}  {5}" -f $r.Rel, $r.Board, $r.Handle, $r.Fails, $r.Warns, $verdict))
    }
    Add-LogLine ""
    if ($script:Issues.Count -eq 0) {
        Write-Info "no warnings or failures"
    }
    else {
        Write-Info "all warnings and failures in one list:"
        $n = 1
        foreach ($i in $script:Issues) {
            Add-LogLine (("    {0,3}. {1}" -f $n, $i)) "Yellow"
            $n++
        }
    }
    Add-LogLine ""
    Add-LogLine "NEXT STEP: send this log file back to Claude:" "Cyan"
    Add-LogLine ("    " + $logFile) "Cyan"

    if ($script:CountFail -gt 0) { $script:ExitCode = 1 }
}
catch {
    Add-LogLine ("SCRIPT ERROR: " + $_.Exception.Message + "  (script line " + $_.InvocationInfo.ScriptLineNumber + ")") "Red"
    $script:ExitCode = 2
}
finally {
    try {
        Set-Content -LiteralPath $logFile -Value $script:Lines -Encoding UTF8
        Write-Host ""
        Write-Host ("Log written: " + $logFile) -ForegroundColor Green
    }
    catch {
        Write-Host ("Could not write the log file: " + $_.Exception.Message) -ForegroundColor Red
    }
}
exit $script:ExitCode
