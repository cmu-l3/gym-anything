#!/bin/bash
set -euo pipefail

echo "=== Setting up Jolly Lobby Track environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Initialize 32-bit Wine prefix for ga user
# CRITICAL: Lobby Track is a 32-bit .NET app. Use WINEARCH=win32
# to avoid 64-bit compatibility issues with .NET.
# ============================================================
echo "Initializing 32-bit Wine prefix for ga user..."
su - ga -c "rm -rf /home/ga/.wine" 2>/dev/null || true
su - ga -c "WINEARCH=win32 WINEDEBUG=-all DISPLAY=:1 wineboot --init" 2>&1 | tail -5 || true
# Wait for wineserver to finish all initialization tasks
su - ga -c "WINEDEBUG=-all wineserver -w" 2>/dev/null || true
sleep 10

# Retry wineboot if prefix wasn't created properly
if [ ! -d "/home/ga/.wine/drive_c/windows" ]; then
    echo "Wine prefix incomplete, retrying wineboot..."
    su - ga -c "WINEARCH=win32 WINEDEBUG=-all DISPLAY=:1 wineboot --init" 2>&1 | tail -5 || true
    su - ga -c "WINEDEBUG=-all wineserver -w" 2>/dev/null || true
    sleep 10
fi

echo "Wine prefix created:"
su - ga -c "ls /home/ga/.wine/drive_c/" 2>/dev/null || true

# ============================================================
# Add fake .NET 4.5.2 registry keys to bypass prerequisite
# The Lobby Track installer checks for .NET 4.5.2 and tries to
# install it (which hangs/fails under Wine 6.0.3). By faking
# the registry keys, the prerequisite check passes and the
# installer proceeds directly to Lobby Track installation.
# wine-mono provides sufficient .NET 4.0 compat for the app.
# ============================================================
echo "Adding .NET 4.5.2 fake registry keys..."
su - ga -c 'WINEDEBUG=-all wine reg add "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Release /t REG_DWORD /d 0x605b1 /f' 2>/dev/null || true
su - ga -c 'WINEDEBUG=-all wine reg add "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Version /t REG_SZ /d "4.5.51209" /f' 2>/dev/null || true
su - ga -c 'WINEDEBUG=-all wine reg add "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v Install /t REG_DWORD /d 1 /f' 2>/dev/null || true
su - ga -c 'WINEDEBUG=-all wine reg add "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full" /v TargetVersion /t REG_SZ /d "4.0.0" /f' 2>/dev/null || true
sleep 2

echo "Verifying .NET registry:"
su - ga -c 'WINEDEBUG=-all wine reg query "HKLM\\SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full"' 2>/dev/null || true

# ============================================================
# Install Lobby Track via the original installer
# Strategy: With .NET fake registry, the installer skips the
# .NET prerequisite and goes directly to the InstallShield
# wizard for Lobby Track. Automate the dialog sequence.
# ============================================================
echo "Installing Lobby Track via Wine..."

INSTALLER="/opt/lobbytrack/LobbyTrackFreeSetup.exe"
INSTALLER_SIZE=$(stat -c%s "$INSTALLER" 2>/dev/null || echo 0)

if [ "$INSTALLER_SIZE" -lt 5000000 ]; then
    echo "ERROR: Lobby Track installer not found or too small (${INSTALLER_SIZE} bytes)."
    exit 1
fi

# Copy installer to ga home
cp "$INSTALLER" /home/ga/LobbyTrackSetup.exe
chown ga:ga /home/ga/LobbyTrackSetup.exe

# Launch installer in background
su - ga -c "DISPLAY=:1 WINEDEBUG=-all wine /home/ga/LobbyTrackSetup.exe > /tmp/lt_install.log 2>&1" &
INSTALL_PID=$!

echo "Waiting for language dialog (20s)..."
sleep 20

# Step 1: Language dialog - press Enter to accept English
echo "Step 1: Accepting English language..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
sleep 8

# Step 2: With .NET fake registry, should skip directly to InstallShield
# If .NET dialog appears anyway, it should be a simple OK/skip
# Take a screenshot to see current state
echo "Step 2: Checking current state..."
DISPLAY=:1 import -window root /tmp/lt_step2.png 2>/dev/null || true

# Check if installer is still running
if kill -0 $INSTALL_PID 2>/dev/null; then
    echo "Installer still running. Navigating remaining dialogs..."

    # Navigate through InstallShield wizard: Welcome, License, Directory, etc.
    # Use Tab+Enter for "I accept" on license, and Enter/Next for others
    for step in $(seq 3 12); do
        echo "  Dialog step $step..."
        if ! kill -0 $INSTALL_PID 2>/dev/null; then
            echo "  Installer finished at step $step"
            break
        fi

        # For license agreement step, need to accept: Tab to radio button + Space + Enter
        if [ "$step" -eq 4 ]; then
            echo "  (License step - accepting agreement)"
            su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Tab Tab Tab Tab space" 2>/dev/null || true
            sleep 1
        fi

        # Press Alt+N for Next, or Enter for OK/default buttons
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers alt+n" 2>/dev/null || true
        sleep 1
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
        sleep 4
    done
fi

# Wait for installation to finish (up to 5 minutes)
echo "Waiting for installation to complete..."
for i in $(seq 1 60); do
    if ! kill -0 $INSTALL_PID 2>/dev/null; then
        echo "Installer completed at attempt $i ($((i*5))s)"
        break
    fi
    sleep 5
    if [ $((i % 12)) -eq 0 ]; then
        echo "Still installing... ($((i*5))s elapsed)"
    fi
done

# Force-kill installer if still running after 5 minutes
if kill -0 $INSTALL_PID 2>/dev/null; then
    echo "Installer still running after timeout — killing..."
    kill $INSTALL_PID 2>/dev/null || true
    sleep 2
fi
sleep 3

echo "Installer log tail:"
tail -30 /tmp/lt_install.log 2>/dev/null || true

# ============================================================
# Check if Lobby Track was installed. If not, find and install
# the cached MSI directly via wine msiexec.
# ============================================================
echo "Checking installation result..."
LOBBYTRACK_EXE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" -not -iname "*NDP*" -not -iname "*dotnet*" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -1)

if [ -z "$LOBBYTRACK_EXE" ]; then
    echo "Lobby Track exe not found after installer. Looking for cached MSI..."

    # The InstallShield installer caches the MSI in Local Settings
    MSI_FILE=$(find /home/ga/.wine/drive_c -iname "Lobby*Track*.msi" 2>/dev/null | head -1)

    if [ -z "$MSI_FILE" ]; then
        # Also check common InstallShield cache locations
        MSI_FILE=$(find /home/ga/.wine/drive_c -iname "*.msi" -path "*/Downloaded*" 2>/dev/null | head -1)
    fi

    if [ -n "$MSI_FILE" ]; then
        echo "Found MSI: $MSI_FILE"
        echo "Installing via wine msiexec..."

        # Convert Linux path to Wine path
        WINE_MSI_PATH=$(echo "$MSI_FILE" | sed 's|/home/ga/.wine/drive_c/|C:\\|' | sed 's|/|\\|g')
        echo "Wine path: $WINE_MSI_PATH"

        su - ga -c "DISPLAY=:1 WINEDEBUG=-all wine msiexec /i \"$WINE_MSI_PATH\" /qn > /tmp/lt_msi_install.log 2>&1" &
        MSI_PID=$!

        echo "Waiting for MSI installation (up to 3 minutes)..."
        for i in $(seq 1 36); do
            if ! kill -0 $MSI_PID 2>/dev/null; then
                echo "MSI installation completed at $((i*5))s"
                break
            fi
            sleep 5
        done

        if kill -0 $MSI_PID 2>/dev/null; then
            echo "MSI still running — killing..."
            kill $MSI_PID 2>/dev/null || true
            sleep 2
        fi

        echo "MSI install log:"
        cat /tmp/lt_msi_install.log 2>/dev/null || true

        # Re-check for the executable
        LOBBYTRACK_EXE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" -not -iname "*NDP*" -not -iname "*dotnet*" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -1)
    else
        echo "WARNING: No MSI found in cache. Trying interactive MSI from installer again..."

        # Try running installer one more time with /qn flag approach
        su - ga -c "DISPLAY=:1 WINEDEBUG=-all wine /home/ga/LobbyTrackSetup.exe > /tmp/lt_install2.log 2>&1" &
        INSTALL2_PID=$!
        sleep 20

        # Navigate through all dialogs aggressively
        for step in $(seq 1 15); do
            if ! kill -0 $INSTALL2_PID 2>/dev/null; then
                break
            fi
            su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
            sleep 3
        done

        # Wait for completion
        for i in $(seq 1 36); do
            if ! kill -0 $INSTALL2_PID 2>/dev/null; then
                break
            fi
            sleep 5
        done
        kill $INSTALL2_PID 2>/dev/null || true
        sleep 3

        # Re-check MSI
        MSI_FILE=$(find /home/ga/.wine/drive_c -iname "*.msi" -path "*/Downloaded*" 2>/dev/null | head -1)
        if [ -n "$MSI_FILE" ]; then
            echo "Found MSI on second try: $MSI_FILE"
            WINE_MSI_PATH=$(echo "$MSI_FILE" | sed 's|/home/ga/.wine/drive_c/|C:\\|' | sed 's|/|\\|g')
            su - ga -c "DISPLAY=:1 WINEDEBUG=-all wine msiexec /i \"$WINE_MSI_PATH\" /qn > /tmp/lt_msi_install2.log 2>&1" &
            MSI2_PID=$!
            for i in $(seq 1 36); do
                if ! kill -0 $MSI2_PID 2>/dev/null; then
                    break
                fi
                sleep 5
            done
            kill $MSI2_PID 2>/dev/null || true
            sleep 3
        fi

        LOBBYTRACK_EXE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" -not -iname "*NDP*" -not -iname "*dotnet*" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -1)
    fi
fi

# ============================================================
# Also copy files from 7z extraction as additional backup
# ============================================================
echo "Checking for extracted files from installer..."
EXTRACT_DIR="/opt/lobbytrack/extracted"
DEST_DIR="/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track"
if [ -d "$EXTRACT_DIR" ]; then
    mkdir -p "$DEST_DIR"

    find "$EXTRACT_DIR" -iname "*.exe" -not -iname "*setup*" -not -iname "*dotnet*" -not -iname "*NDP*" -not -iname "*vcredist*" | while read f; do
        BNAME=$(basename "$f")
        if [ ! -f "$DEST_DIR/$BNAME" ]; then
            cp "$f" "$DEST_DIR/" 2>/dev/null && echo "  Copied: $BNAME" || true
        fi
    done

    find "$EXTRACT_DIR" -iname "*.dll" | while read f; do
        BNAME=$(basename "$f")
        if [ ! -f "$DEST_DIR/$BNAME" ]; then
            cp "$f" "$DEST_DIR/" 2>/dev/null || true
        fi
    done

    chown -R ga:ga "$DEST_DIR" 2>/dev/null || true
fi

# ============================================================
# Find installed Lobby Track paths
# ============================================================
echo "Finding Lobby Track executable..."
if [ -z "${LOBBYTRACK_EXE:-}" ]; then
    LOBBYTRACK_EXE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" -not -iname "*NDP*" -not -iname "*dotnet*" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -1)
fi
if [ -z "${LOBBYTRACK_EXE:-}" ]; then
    LOBBYTRACK_EXE=$(find /home/ga/.wine/drive_c -iname "Lobby*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" -not -iname "*NDP*" -not -iname "*dotnet*" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -1)
fi

echo "Lobby Track exe: ${LOBBYTRACK_EXE:-NOT FOUND}"
echo "All exe files (non-windows):"
find /home/ga/.wine/drive_c -name "*.exe" -not -path "*/windows/*" -not -path "*/temp/*" -not -path "*/Temp/*" 2>/dev/null | head -20

LOBBYTRACK_DIR=$(dirname "$LOBBYTRACK_EXE" 2>/dev/null || echo "/home/ga/.wine/drive_c/Program Files/Jolly Technologies/Lobby Track")

# ============================================================
# Create launcher script
# ============================================================
echo "Creating Lobby Track launcher script..."
if [ -n "${LOBBYTRACK_EXE:-}" ]; then
    cat > /home/ga/launch_lobbytrack.sh << LAUNCH_EOF
#!/bin/bash
export DISPLAY=:1
export WINEDEBUG=-all
export WINEPREFIX=/home/ga/.wine
cd "${LOBBYTRACK_DIR}"
exec wine "${LOBBYTRACK_EXE}"
LAUNCH_EOF
else
    cat > /home/ga/launch_lobbytrack.sh << 'LAUNCH_EOF'
#!/bin/bash
export DISPLAY=:1
export WINEDEBUG=-all
export WINEPREFIX=/home/ga/.wine
EXE=$(find /home/ga/.wine/drive_c -iname "LobbyTrack*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" 2>/dev/null | head -1)
if [ -z "$EXE" ]; then
    EXE=$(find /home/ga/.wine/drive_c -iname "Lobby*.exe" -not -iname "*Setup*" -not -iname "*uninstall*" 2>/dev/null | head -1)
fi
if [ -n "$EXE" ]; then
    cd "$(dirname "$EXE")"
    exec wine "$EXE"
else
    echo "ERROR: Lobby Track executable not found"
    exit 1
fi
LAUNCH_EOF
fi
chmod +x /home/ga/launch_lobbytrack.sh
chown ga:ga /home/ga/launch_lobbytrack.sh

# ============================================================
# Copy realistic data files to ga home
# ============================================================
echo "Copying realistic visitor data..."
mkdir -p /home/ga/LobbyTrack/data
cp /opt/lobbytrack/data/*.csv /home/ga/LobbyTrack/data/ 2>/dev/null || \
    cp /workspace/data/*.csv /home/ga/LobbyTrack/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/LobbyTrack/

# ============================================================
# Warm-up launch of Lobby Track
# ============================================================
echo "Performing warm-up launch of Lobby Track..."

pkill -f "LobbyTrack" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 2

su - ga -c "setsid /home/ga/launch_lobbytrack.sh > /tmp/lobbytrack_warmup.log 2>&1 &"

echo "Waiting 45 seconds for Lobby Track to start..."
sleep 45

# Check all windows (not just lobby-specific titles)
ALL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || true)
echo "All windows after warmup:"
echo "$ALL_WINDOWS"

WINE_WINDOWS=$(echo "$ALL_WINDOWS" | grep -v "ga-base @" | grep -v "^$" || true)
if [ -n "$WINE_WINDOWS" ]; then
    echo "Wine windows detected — dismissing startup dialogs..."
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Escape" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 import -window root /tmp/lobbytrack_warmup_screenshot.png 2>/dev/null || \
        DISPLAY=:1 scrot /tmp/lobbytrack_warmup_screenshot.png 2>/dev/null || true
fi

pkill -f "LobbyTrack" 2>/dev/null || true
pkill -x wine 2>/dev/null || true
sleep 3

echo "Warmup log tail:"
tail -20 /tmp/lobbytrack_warmup.log 2>/dev/null || true

echo "=== Jolly Lobby Track setup complete ==="
