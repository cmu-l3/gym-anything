#!/bin/bash
set -euo pipefail

echo "=== Setting up WPS Presentation environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Validate that the real PPTX was downloaded in pre_start
# ============================================================
PPTX_SIZE=$(stat -c%s /opt/wps_samples/performance.pptx 2>/dev/null || echo 0)
if [ "$PPTX_SIZE" -lt 50000 ]; then
    echo "ERROR: /opt/wps_samples/performance.pptx is missing or too small."
    echo "The pre_start hook may have failed. Expected ~633KB (48-slide Apache performance deck)."
    exit 1
fi
echo "Confirmed: performance.pptx is ${PPTX_SIZE} bytes (real 48-slide Apache performance presentation)"

# ============================================================
# Configure WPS Office to suppress first-run dialogs
# Layer 1: Pre-write Office.conf with known bypass keys
# ============================================================
echo "Configuring WPS Office for user ga..."

mkdir -p /home/ga/.config/Kingsoft

# Write Office.conf with all known EULA/first-run suppression keys
# WPS Office reads this INI-format config file on startup
cat > /home/ga/.config/Kingsoft/Office.conf << 'EOF'
[general]
openWithSingleBrowser=true
bCheckUpdate=false

[agreement]
AgreementAccepted=1

[Privacy]
bPrivacyPolicyAgreed=1
PrivacyPolicyVer=2

[InstallFirstRun]
bFirstRunFinished=1

[WPSUpdater]
bAskUpdate=false
bAutoCheckUpdate=false

[EULADialog]
bAgreed=true
version=11.1.0.11723
EOF

chown -R ga:ga /home/ga/.config/Kingsoft
echo "Office.conf written to /home/ga/.config/Kingsoft/Office.conf"

# ============================================================
# Create user workspace for presentations
# ============================================================
mkdir -p /home/ga/Documents/presentations
cp /opt/wps_samples/performance.pptx /home/ga/Documents/presentations/performance.pptx
chown -R ga:ga /home/ga/Documents/presentations
echo "Copied performance.pptx to /home/ga/Documents/presentations/"

# ============================================================
# Warm-up launch: open WPS WITH the PPTX file to trigger and
# dismiss ALL first-run dialogs in one pass:
#   1. EULA dialog (Kingsoft Office Software License Agreement)
#   2. "WPS Office" file format check dialog (first PPTX open)
# Subsequent task launches will start cleanly.
# ============================================================
echo "Performing WPS warm-up launch to accept all first-run dialogs..."

su - ga -c "DISPLAY=:1 wpp '/home/ga/Documents/presentations/performance.pptx' > /tmp/wpp_warmup.log 2>&1 &"

# Wait for the EULA dialog to appear (window title contains "Kingsoft Office")
# The dialog is a native Qt window: "Kingsoft Office Software License Agreement and Privacy Policy"
EULA_WID=""
for i in $(seq 1 15); do
    sleep 2
    # Try xdotool search first (returns decimal WID)
    EULA_WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Kingsoft Office" 2>/dev/null | head -1 || true)
    if [ -n "$EULA_WID" ]; then
        echo "EULA dialog found via xdotool (WID=$EULA_WID) after $((i*2))s"
        break
    fi
    # Fallback: check wmctrl
    WMC_LINE=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "Kingsoft\|License Agreement" | head -1 || true)
    if [ -n "$WMC_LINE" ]; then
        EULA_WID=$(echo "$WMC_LINE" | awk '{print $1}')
        echo "EULA dialog found via wmctrl (WID=$EULA_WID) after $((i*2))s"
        break
    fi
done

if [ -n "$EULA_WID" ]; then
    echo "Accepting EULA via mouse clicks..."

    # Kill Firefox: WPS opens it to display the EULA web page.
    # Firefox can appear on top of the native Qt dialog and intercept clicks.
    pkill -f firefox 2>/dev/null || true
    sleep 2

    # Raise the EULA dialog to the foreground
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -ia "$EULA_WID" 2>/dev/null || true
    sleep 1

    # Click the "I have read and agreed" checkbox (screen coords verified on 1920x1080)
    # Dialog is a centered Qt window; checkbox is at the dialog's bottom-left area.
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 645 648 click 1 2>/dev/null || true
    sleep 1

    # Click the "I Confirm" button (enabled once checkbox is checked)
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1290 648 click 1 2>/dev/null || true
    sleep 5

    echo "EULA acceptance clicks completed"
else
    echo "EULA dialog not detected after 30s - may already be accepted or WPS failed to launch"
    cat /tmp/wpp_warmup.log 2>/dev/null | head -20 || true
fi

# Wait for WPS to settle and for the PPTX to begin loading
sleep 5

# Dismiss any "WPS Office" dialogs that appear after EULA acceptance.
# These include:
#   - "Set WPS Office as default office software" (window title: "WPS Office")
#   - "Allow automatic file format check" dialog (also titled "WPS Office")
# Both have an OK button at approximately screen (1280, 630) on 1920x1080.
for attempt in 1 2 3; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
        echo "Dismissing 'WPS Office' dialog (attempt $attempt)..."
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
        sleep 2
    else
        break
    fi
done

# Kill WPS and any lingering Firefox
pkill -f "/opt/kingsoft/wps-office/office6/wpp" 2>/dev/null || true
pkill -f "firefox" 2>/dev/null || true
sleep 2
pkill -9 -f "/opt/kingsoft/wps-office/office6/wpp" 2>/dev/null || true

echo "WPS warm-up complete"

# ============================================================
# Verify WPS installation is working
# ============================================================
if which wpp > /dev/null 2>&1; then
    echo "WPS Presentation binary found: $(which wpp)"
else
    echo "ERROR: wpp binary not found after setup"
    exit 1
fi

echo "=== WPS Presentation setup complete ==="
echo "  Real PPTX: /home/ga/Documents/presentations/performance.pptx (${PPTX_SIZE} bytes)"
echo "  Config: /home/ga/.config/Kingsoft/Office.conf"
