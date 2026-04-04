#!/system/bin/sh
echo "=== Setting up select_cardiosafe_prostate_cancer_therapy ==="

# 1. Record Start Time for anti-gaming (using date +%s if available, fallback to writing string)
date +%s > /sdcard/task_start_time.txt 2>/dev/null || date > /sdcard/task_start_time.txt

# 2. Clean up previous results
rm -f /sdcard/mcrpc_therapy_choice.txt
rm -f /sdcard/task_result.json

# 3. Ensure App is Clean (Force Stop)
PACKAGE="com.liverpooluni.ichartoncology"
am force-stop $PACKAGE
sleep 2

# 4. Launch App to Welcome Screen
echo "Launching Cancer iChart..."
monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
sleep 5

# 5. Handle any startup dialogs (e.g., Database Update) if they appear
# The environment setup usually handles the initial DB download, but we wait just in case
sleep 3

echo "=== Setup Complete ==="