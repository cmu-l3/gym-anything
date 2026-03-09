#!/bin/bash
set -e

echo "=== Setting up Calligra Words ==="

# Wait for desktop to be ready
sleep 5

# Create user directories
mkdir -p /home/ga/Documents
mkdir -p /home/ga/.config
mkdir -p /home/ga/Desktop

# Create Calligra Words config as an INI-style file (not a directory)
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
calligrawords "$@" &
LAUNCHEOF
chmod +x /home/ga/Desktop/launch_calligra_words.sh

# Set ownership
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/.config

echo "=== Calligra Words setup complete ==="
