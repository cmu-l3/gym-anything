#!/system/bin/sh
echo "=== Setting up audit_chemo_regimen_interaction_ritonavir task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /sdcard/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /sdcard/ritonavir_chemo_audit.txt

# 3. Ensure the app is in a clean state (Force stop)
PKG="com.liverpooluni.ichartoncology"
am force-stop $PKG
sleep 1

# 4. Go to Home Screen
input keyevent KEYCODE_HOME
sleep 1

# 5. Launch the app fresh
echo "Launching Cancer iChart..."
monkey -p $PKG -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 6. Take initial screenshot for evidence
screencap -p /sdcard/task_initial.png

echo "=== Task setup complete ==="