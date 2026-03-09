#!/bin/bash
set -e

echo "=== Setting up JASP environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Validate datasets were downloaded in pre_start
# ============================================================
for dataset in "Sleep.csv" "Invisibility Cloak.csv" "Viagra.csv" "Exam Anxiety.csv" "Big Five Personality Traits.csv" "Tooth Growth.csv"; do
    size=$(stat -c%s "/opt/jasp_datasets/$dataset" 2>/dev/null || echo 0)
    if [ "$size" -lt 100 ]; then
        echo "ERROR: /opt/jasp_datasets/$dataset missing or too small (${size} bytes)"
        exit 1
    fi
    echo "Confirmed: $dataset is ${size} bytes"
done

# ============================================================
# Create user workspace and copy datasets with space-free names
# CRITICAL: Filenames with spaces cause quoting issues through
# multiple shell layers (su - ga -c -> setsid -> flatpak).
# Rename datasets to remove spaces to avoid this problem.
# ============================================================
mkdir -p /home/ga/Documents/JASP
cp "/opt/jasp_datasets/Sleep.csv" "/home/ga/Documents/JASP/Sleep.csv"
cp "/opt/jasp_datasets/Invisibility Cloak.csv" "/home/ga/Documents/JASP/InvisibilityCloak.csv"
cp "/opt/jasp_datasets/Viagra.csv" "/home/ga/Documents/JASP/Viagra.csv"
cp "/opt/jasp_datasets/Exam Anxiety.csv" "/home/ga/Documents/JASP/ExamAnxiety.csv"
cp "/opt/jasp_datasets/Big Five Personality Traits.csv" "/home/ga/Documents/JASP/BigFivePersonalityTraits.csv"
cp "/opt/jasp_datasets/Tooth Growth.csv" "/home/ga/Documents/JASP/ToothGrowth.csv"
chown -R ga:ga /home/ga/Documents/JASP
chmod -R 644 /home/ga/Documents/JASP/*.csv
echo "Datasets copied to /home/ga/Documents/JASP/ (with space-free names)"

# ============================================================
# Create system-wide JASP launcher script
# CRITICAL: JASP (Qt WebEngine) requires --no-sandbox in VM environments.
# The launcher must be called via: su - ga -c "setsid /usr/local/bin/launch-jasp ..."
# (setsid ensures the process survives when su exits)
# ============================================================
cat > /usr/local/bin/launch-jasp << 'EOF'
#!/bin/bash
export DISPLAY=:1
export QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"
exec flatpak run org.jaspstats.JASP "$@"
EOF
chmod +x /usr/local/bin/launch-jasp
echo "Created /usr/local/bin/launch-jasp"

# ============================================================
# Pre-create JASP flatpak config directory and suppress dialogs.
# JASP (Qt app) stores QSettings at:
#   ~/.var/app/org.jaspstats.JASP/config/JASP/JASP.conf
# Key: checkUpdatesAskUser=false prevents the update dialog on launch.
# ============================================================
JASP_CONFIG_DIR="/home/ga/.var/app/org.jaspstats.JASP/config/JASP"
mkdir -p "$JASP_CONFIG_DIR"

cat > "$JASP_CONFIG_DIR/JASP.conf" << 'EOF'
[General]
checkUpdatesAskUser=false
checkUpdatesAutomatic=false
recentFolders=/home/ga/Documents/JASP
modulesRemembered=|Data-Synch-Off|Data|Data-Resize
EOF

chown -R ga:ga /home/ga/.var
echo "JASP config pre-created at $JASP_CONFIG_DIR/JASP.conf"

# ============================================================
# Warm-up launch: start JASP to settle first-run state,
# dismiss any remaining dialogs, then kill it.
# Using setsid to ensure process isn't killed when su exits.
# ============================================================
echo "Performing warm-up launch of JASP..."
su - ga -c "setsid /usr/local/bin/launch-jasp > /tmp/jasp_warmup.log 2>&1 &"

# Wait for JASP to start (Qt+WebEngine takes 15-20s)
sleep 22

# Dismiss any first-run dialogs (e.g. check-for-updates that slips through)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Kill JASP after warm-up
pkill -f "org.jaspstats.JASP" 2>/dev/null || true
pkill -f "JASP" 2>/dev/null || true
sleep 3

echo "JASP warm-up complete."

# ============================================================
# Verify JASP is installed and accessible
# ============================================================
if flatpak list --system 2>/dev/null | grep -q "org.jaspstats.JASP"; then
    echo "JASP is installed via flatpak (system-wide)"
else
    echo "ERROR: JASP not found in flatpak system list"
    exit 1
fi

echo "=== JASP setup complete ==="
