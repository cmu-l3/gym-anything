#!/bin/bash
echo "=== Setting up sherlock_case_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Download Sherlock Holmes text if not exists
if [ ! -f /home/ga/Documents/sherlock_holmes.txt ]; then
    echo "Downloading Sherlock Holmes text..."
    wget -q -O /home/ga/Documents/sherlock_holmes.txt "https://www.gutenberg.org/cache/epub/1661/pg1661.txt" || true
    
    # Fallback if download fails (for offline or restricted network)
    if ! grep -q "A SCANDAL IN BOHEMIA" /home/ga/Documents/sherlock_holmes.txt 2>/dev/null; then
        echo "Download failed or blocked. Using fallback excerpt."
        cat > /home/ga/Documents/sherlock_holmes.txt << 'EOF'
THE ADVENTURES OF SHERLOCK HOLMES
by Arthur Conan Doyle

I. A SCANDAL IN BOHEMIA

To Sherlock Holmes she is always THE woman. I have seldom heard him mention her under any other name. In his eyes she eclipses and predominates the whole of her sex...

He was employed by the King of Bohemia to recover a compromising photograph from a woman named Irene Adler, who lived at Briony Lodge. Holmes disguised himself as a drunken-looking groom, and later as an amiable and simple-minded nonconformist clergyman. A staged fire allowed him to discover where the photograph was hidden. However, Irene Adler outsmarted him, escaping with the photograph and leaving a letter and her own portrait behind. Holmes asked for her photograph as his only reward.
EOF
    fi
fi
chown ga:ga /home/ga/Documents/sherlock_holmes.txt

# Remove any pre-existing output
rm -f /home/ga/Documents/case_analysis.odt 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/sherlock_case_analysis_start_ts
chmod 666 /tmp/sherlock_case_analysis_start_ts

# Close any open activity to return to home view cleanly
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch Write activity
echo "Launching Write activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.AbiWordActivity" &
sleep 12

# Verify Write is running
if pgrep -f "AbiWordActivity\|abiword" > /dev/null 2>&1; then
    echo "Write activity is running"
else
    echo "WARNING: Write activity may not have started properly"
fi

# Take verification screenshot of initial state
su - ga -c "$SUGAR_ENV scrot /tmp/sherlock_task_start.png" 2>/dev/null || true

echo "=== sherlock_case_analysis task setup complete ==="