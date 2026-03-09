#!/bin/bash
set -e

echo "=== Setting up Jamovi environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Validate datasets were downloaded in pre_start
# ============================================================
for dataset in "Sleep.csv" "Invisibility Cloak.csv" "Viagra.csv" "Exam Anxiety.csv" "ToothGrowth.csv" "TitanicSurvival.csv" "InsectSprays.csv"; do
    size=$(stat -c%s "/opt/jamovi_datasets/$dataset" 2>/dev/null || echo 0)
    if [ "$size" -lt 100 ]; then
        echo "ERROR: /opt/jamovi_datasets/$dataset missing or too small (${size} bytes)"
        exit 1
    fi
    echo "Confirmed: $dataset is ${size} bytes"
done
for script in "extract_bfi_neuroticism.py" "extract_bfi25.py"; do
    if [ ! -f "/opt/jamovi_datasets/$script" ]; then
        echo "ERROR: $script not found in /opt/jamovi_datasets"
        exit 1
    fi
done
echo "Confirmed: all extraction scripts are present"

# ============================================================
# Create user workspace and copy datasets with space-free names.
# CRITICAL: Filenames with spaces cause quoting issues through
# multiple shell layers (su - ga -c -> setsid -> flatpak).
# Rename datasets to remove spaces to avoid this problem.
# ============================================================
mkdir -p /home/ga/Documents/Jamovi
cp "/opt/jamovi_datasets/Sleep.csv"                          "/home/ga/Documents/Jamovi/Sleep.csv"
cp "/opt/jamovi_datasets/Invisibility Cloak.csv"             "/home/ga/Documents/Jamovi/InvisibilityCloak.csv"
cp "/opt/jamovi_datasets/Viagra.csv"                         "/home/ga/Documents/Jamovi/Viagra.csv"
cp "/opt/jamovi_datasets/Exam Anxiety.csv"                   "/home/ga/Documents/Jamovi/ExamAnxiety.csv"
# Extract real N1-N5 Neuroticism items from bfi dataset (Revelle 2010, psych R package)
python3 /opt/jamovi_datasets/extract_bfi_neuroticism.py
# Copy additional datasets for new tasks (Rdatasets sources)
cp "/opt/jamovi_datasets/ToothGrowth.csv"               "/home/ga/Documents/Jamovi/ToothGrowth.csv"
cp "/opt/jamovi_datasets/TitanicSurvival.csv"            "/home/ga/Documents/Jamovi/TitanicSurvival.csv"
cp "/opt/jamovi_datasets/InsectSprays.csv"               "/home/ga/Documents/Jamovi/InsectSprays.csv"
# Extract full BFI-25 items (all 25 personality items + gender + age)
python3 /opt/jamovi_datasets/extract_bfi25.py
chown -R ga:ga /home/ga/Documents/Jamovi
chmod -R 644 /home/ga/Documents/Jamovi/*.csv
echo "Datasets prepared in /home/ga/Documents/Jamovi/ (with space-free names)"

# ============================================================
# Create system-wide Jamovi launcher script.
# CRITICAL: Jamovi is Electron-based and crashes in QEMU without
# --no-sandbox (Chromium kernel namespace sandbox fails in VMs).
# The -- separator passes flags to the Electron binary inside Flatpak.
# Using setsid ensures the process survives when su exits.
# ============================================================
cat > /usr/local/bin/launch-jamovi << 'EOF'
#!/bin/bash
export DISPLAY=:1
# CRITICAL: Jamovi uses zypak (Flatpak Electron sandbox) which requires a D-Bus session bus.
# When launched from hook scripts via 'su - ga -c', the D-Bus session bus address is not
# inherited. Set it explicitly to the systemd user session socket for uid 1000 (ga user).
# --no-sandbox disables the Chromium sandbox (required in QEMU VMs).
# --disable-gpu avoids Vulkan/GPU errors in software-rendered VMs.
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
export XDG_RUNTIME_DIR=/run/user/1000
exec flatpak run org.jamovi.jamovi -- --no-sandbox --disable-gpu "$@"
EOF
chmod +x /usr/local/bin/launch-jamovi
echo "Created /usr/local/bin/launch-jamovi"

# ============================================================
# Warm-up launch: start Jamovi to settle first-run state
# (creates config dirs, caches UI resources, dismisses any
# first-run welcome dialogs), then kill it.
# ============================================================
echo "Performing warm-up launch of Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_warmup.log 2>&1 &"

# Jamovi (Electron) typically takes 10-18s to fully initialize
sleep 20

# Dismiss any first-run dialogs (welcome screen, update notifier)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2

# Kill Jamovi after warm-up
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 3

echo "Jamovi warm-up complete."

# ============================================================
# Verify Jamovi is installed and accessible
# ============================================================
if flatpak list --system 2>/dev/null | grep -q "org.jamovi.jamovi"; then
    echo "Jamovi is installed via flatpak (system-wide)"
else
    echo "ERROR: Jamovi not found in flatpak system list"
    exit 1
fi

echo "=== Jamovi setup complete ==="
