#!/bin/bash
set -e

echo "=== Setting up 2N Access Commander (nested QEMU) ==="

XAUTH="/run/user/1000/gdm/Xauthority"
AC_INNER_PORT=9443           # outer VM port forwarded to inner VM :443
AC_USER="admin"
AC_PASS="2n"
OVA_PATH="/workspace/data/access_commander.ova"
VM_DIR="/home/ga/ac_vm"
DISK_IMG="/home/ga/ac_disk.qcow2"

# Firefox profile dir — under snap path since Ubuntu installs snap firefox
SNAP_FF_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
SYS_FF_BASE="/home/ga/.mozilla/firefox"

# Determine actual firefox profile location based on what's installed
if [ -d "$SNAP_FF_BASE" ] || (firefox --version 2>/dev/null | grep -q snap) 2>/dev/null; then
    FF_DIR="$SNAP_FF_BASE"
    FF_CMD="firefox"   # snap firefox is the system firefox on Ubuntu 22.04
else
    FF_DIR="$SYS_FF_BASE"
    FF_CMD="firefox"
fi
PROFILE_DIR="$FF_DIR/accommander.profile"

# Wait for GNOME desktop
sleep 5

# -------------------------------------------------------
# Helper functions (defined before use)
# -------------------------------------------------------
_setup_firefox_profile() {
    local homepage="$1"
    mkdir -p "$PROFILE_DIR"

    cat > "$PROFILE_DIR/user.js" << USERJS
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.startup.homepage", "${homepage}");
user_pref("browser.startup.page", 1);
user_pref("browser.tabs.warnOnClose", false);
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("security.tls.insecure_fallback_hosts", "localhost");
user_pref("network.dns.disableIPv6", true);
USERJS

    mkdir -p "$FF_DIR"
    cat > "$FF_DIR/profiles.ini" << PROFINI
[Profile0]
Name=accommander
IsRelative=1
Path=accommander.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
PROFINI

    chown -R ga:ga "$FF_DIR" 2>/dev/null || true
}

_launch_firefox() {
    local url="$1"
    local wait_sec="${2:-10}"

    # Kill existing Firefox
    pkill -9 -f "firefox" 2>/dev/null || true
    sleep 2

    rm -f "$PROFILE_DIR/.parentlock" "$PROFILE_DIR/lock" 2>/dev/null || true

    su - ga -c "DISPLAY=:1 XAUTHORITY=$XAUTH DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus' \
        setsid $FF_CMD \
        --new-instance \
        -profile '$PROFILE_DIR' \
        '$url' &"

    sleep "$wait_sec"

    # Dismiss first-run dialogs / security warnings
    DISPLAY=:1 XAUTHORITY=$XAUTH xdotool key Escape 2>/dev/null || true
    sleep 2
    DISPLAY=:1 XAUTHORITY=$XAUTH xdotool key Return 2>/dev/null || true
    sleep 1
    DISPLAY=:1 XAUTHORITY=$XAUTH xdotool key Escape 2>/dev/null || true
    sleep 1

    # Maximize
    DISPLAY=:1 XAUTHORITY=$XAUTH wmctrl -r "Mozilla Firefox" \
        -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
}

# -------------------------------------------------------
# 1. Validate OVA presence
# -------------------------------------------------------
if [ ! -f "$OVA_PATH" ]; then
    echo "WARNING: OVA not found at $OVA_PATH"
    echo "Place the 2N Access Commander OVA at that path before starting."
    echo "Setting up Firefox profile pointing to local AC (will work once OVA is present)."
    AC_URL="https://localhost:${AC_INNER_PORT}"
    _setup_firefox_profile "$AC_URL"
    _launch_firefox "$AC_URL" 8
    DISPLAY=:1 XAUTHORITY=$XAUTH scrot /home/ga/setup_complete.png 2>/dev/null || true
    echo "=== Setup complete (no OVA — Firefox opened to AC URL) ==="
    echo "AC URL: $AC_URL (inner VM not running)"
    exit 0
fi

# -------------------------------------------------------
# 2. Extract OVA and convert VMDK → QCOW2 (idempotent)
# -------------------------------------------------------
mkdir -p "$VM_DIR"

if [ ! -f "$DISK_IMG" ]; then
    echo "Extracting OVA..."
    tar xf "$OVA_PATH" -C "$VM_DIR"

    # Find the VMDK (OVA may contain multiple; pick the largest = disk)
    VMDK=$(find "$VM_DIR" -name "*.vmdk" | xargs ls -S 2>/dev/null | head -1)
    if [ -z "$VMDK" ]; then
        echo "ERROR: No VMDK found in OVA"
        exit 1
    fi
    echo "Converting $VMDK → $DISK_IMG ..."
    qemu-img convert -f vmdk -O qcow2 "$VMDK" "$DISK_IMG"
    echo "Disk image ready: $(du -sh "$DISK_IMG" | cut -f1)"
fi

chown ga:ga "$DISK_IMG"

AC_URL="https://localhost:${AC_INNER_PORT}"

# -------------------------------------------------------
# 3. Launch inner QEMU VM (KVM if available, else TCG)
# -------------------------------------------------------
pkill -f "qemu-system-x86_64.*ac_disk" 2>/dev/null || true
sleep 2

# Check if nested KVM is available (may be disabled in shared HPC environments)
KVM_FLAGS=""
if [ -r /dev/kvm ]; then
    KVM_FLAGS="-enable-kvm"
    echo "KVM acceleration available — inner VM will boot faster"
else
    echo "WARNING: /dev/kvm not accessible — falling back to software emulation (TCG)"
    echo "         Boot may take 30-60 min instead of ~5 min without KVM."
    # TCG multi-threaded is the best software emulation option
    KVM_FLAGS="-accel tcg,thread=multi"
fi

echo "Starting 2N Access Commander inner VM..."
qemu-system-x86_64 \
    $KVM_FLAGS \
    -m 2048 \
    -smp 2 \
    -drive file="$DISK_IMG",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${AC_INNER_PORT}-:443,hostfwd=tcp::9080-:80 \
    -device e1000,netdev=net0 \
    -display none \
    -serial file:/tmp/ac_vm_serial.log \
    -daemonize \
    -pidfile /tmp/ac_vm.pid \
    2>/tmp/ac_vm_qemu.log || {
        echo "Note: -daemonize failed, using background process..."
        nohup qemu-system-x86_64 \
            $KVM_FLAGS \
            -m 2048 \
            -smp 2 \
            -drive file="$DISK_IMG",format=qcow2,if=virtio \
            -netdev user,id=net0,hostfwd=tcp::${AC_INNER_PORT}-:443,hostfwd=tcp::9080-:80 \
            -device e1000,netdev=net0 \
            -display none \
            -serial file:/tmp/ac_vm_serial.log \
            > /tmp/ac_vm_qemu.log 2>&1 &
        echo $! > /tmp/ac_vm.pid
    }

echo "Inner VM PID: $(cat /tmp/ac_vm.pid 2>/dev/null || echo unknown)"

# -------------------------------------------------------
# 4. Wait for 2N Access Commander to be reachable
# -------------------------------------------------------
echo "Waiting for 2N Access Commander on localhost:${AC_INNER_PORT} ..."
ELAPSED=0
# KVM: ~5 min boot → 300s timeout. TCG (software emulation): 30-60 min → 3600s timeout.
if echo "$KVM_FLAGS" | grep -q "tcg"; then
    TIMEOUT=3600
    echo "TCG mode: extended wait timeout to ${TIMEOUT}s (software emulation is slow)"
else
    TIMEOUT=300
fi
while [ $ELAPSED -lt $TIMEOUT ]; do
    if curl -sk --max-time 5 "$AC_URL" > /dev/null 2>&1; then
        echo "2N Access Commander is up (after ${ELAPSED}s)"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo "  Still waiting... (${ELAPSED}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "WARNING: AC did not respond within ${TIMEOUT}s — proceeding anyway"
fi

# -------------------------------------------------------
# 5. Seed realistic data into 2N Access Commander
# -------------------------------------------------------
if curl -sk --max-time 5 "$AC_URL" > /dev/null 2>&1; then
    echo "Seeding realistic users, groups, and time profiles..."
    python3 /workspace/scripts/seed_ac_data.py "$AC_URL" "$AC_USER" "$AC_PASS" \
        > /tmp/ac_seed.log 2>&1 && echo "Data seeding complete" || \
        echo "WARNING: Data seeding had errors — see /tmp/ac_seed.log"
else
    echo "Skipping data seed: AC not reachable"
fi

# -------------------------------------------------------
# 6. Configure Firefox profile
# -------------------------------------------------------
_setup_firefox_profile "$AC_URL"

# -------------------------------------------------------
# 7. Pre-accept self-signed TLS cert via NSS/certutil
# -------------------------------------------------------
if [ -x "$(which certutil)" ]; then
    if [ ! -f "$PROFILE_DIR/cert9.db" ]; then
        certutil -N -d "sql:$PROFILE_DIR" --empty-password 2>/dev/null || true
    fi
    if curl -sk --max-time 10 "$AC_URL" > /dev/null 2>&1; then
        openssl s_client -connect "localhost:${AC_INNER_PORT}" -servername localhost \
            </dev/null 2>/dev/null | \
            openssl x509 -outform PEM > /tmp/ac_cert.pem 2>/dev/null || true
        if [ -s /tmp/ac_cert.pem ]; then
            certutil -A -d "sql:$PROFILE_DIR" -n "2NAccessCommander" \
                -t "CT,," -i /tmp/ac_cert.pem 2>/dev/null || true
            echo "Self-signed cert added to Firefox NSS store"
        fi
    fi
    chown -R ga:ga "$PROFILE_DIR" 2>/dev/null || true
fi

# -------------------------------------------------------
# 8. Launch Firefox
# -------------------------------------------------------
echo "Launching Firefox → $AC_URL ..."
_launch_firefox "$AC_URL"

# Take setup screenshot
sleep 3
DISPLAY=:1 XAUTHORITY=$XAUTH scrot /home/ga/setup_complete.png 2>/dev/null || true

echo "=== 2N Access Commander setup complete ==="
echo "Inner VM URL: $AC_URL"
echo "Credentials:  $AC_USER / $AC_PASS"
