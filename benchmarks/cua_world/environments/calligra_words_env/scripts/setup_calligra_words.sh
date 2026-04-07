#!/bin/bash
set -e

echo "=== Setting up Calligra Words ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Wait for desktop to be ready
sleep 5

# Create user directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/.config
mkdir -p /home/ga/Desktop

# Create the user config before the first launch.
cat > /home/ga/.config/calligrawordsrc << 'CONFEOF'
[RecentFiles]

[MainWindow]
Height 768=1048
Width 1024=1920

[Notification Messages]
DoNotAskAgain=true
CONFEOF

# Create a launch script for Calligra Words
cat > /home/ga/Desktop/launch_calligra_words.sh << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority
setsid calligrawords "$@" >/tmp/calligra_words_launch.log 2>&1 < /dev/null &
LAUNCHEOF
chmod +x /home/ga/Desktop/launch_calligra_words.sh

# Set ownership
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/.config

# Warm Calligra once so first-run prompts do not appear during tasks.
pkill -TERM -f calligrawords 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid calligrawords >/tmp/calligra_words_warmup.log 2>&1 < /dev/null &"

for _ in $(seq 1 45); do
    if wmctrl -l | grep -qi 'Calligra Words\|calligrawords'; then
        break
    fi
    sleep 1
done

warmup_wid=$(wmctrl -l | grep -i 'Calligra Words\|calligrawords' | awk '{print $1; exit}')
if [ -n "$warmup_wid" ]; then
    wmctrl -ia "$warmup_wid" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" || true
    sleep 1
fi

pkill -TERM -f calligrawords 2>/dev/null || true
sleep 2
pkill -KILL -f calligrawords 2>/dev/null || true
rm -f /home/ga/Documents/.~lock.* 2>/dev/null || true

echo "=== Calligra Words setup complete ==="
