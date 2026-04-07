#!/bin/bash
set -e

echo "=== Installing Sugar Learning Platform ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Update package lists
apt-get update

# Install Sugar Desktop Environment and core activities
# 'sucrose' is the metapackage that pulls in Sugar shell + core activities
apt-get install -y \
    sucrose \
    sugar-session \
    sugar-write-activity \
    sugar-browse-activity \
    sugar-calculate-activity \
    sugar-chat-activity \
    sugar-imageviewer-activity \
    sugar-jukebox-activity \
    sugar-log-activity \
    sugar-pippy-activity \
    sugar-read-activity \
    sugar-terminal-activity \
    sugar-memorize-activity \
    sugar-flipsticks-activity \
    sugar-sliderpuzzle-activity \
    sugar-etoys-activity || {
    echo "Some activity packages not found, installing core only..."
    apt-get install -y sucrose sugar-session
}

# Install dbus-x11 (provides dbus-launch needed by Sugar)
apt-get install -y dbus-x11

# Install utility packages for screenshots and window management
apt-get install -y \
    scrot \
    wmctrl \
    xdotool \
    python3-pip \
    imagemagick \
    curl \
    wget \
    unzip

# Install TurtleArt activity from Sugar Labs GitHub
# (not available as an Ubuntu package)
echo "Installing TurtleArt activity from GitHub..."
wget -q -O /tmp/turtleart.zip \
    "https://github.com/sugarlabs/turtleart-activity/archive/refs/heads/master.zip" || {
    echo "WARNING: Could not download TurtleArt from GitHub"
}
if [ -f /tmp/turtleart.zip ]; then
    cd /tmp && unzip -q turtleart.zip
    mv /tmp/turtleart-activity-master /usr/share/sugar/activities/TurtleArt.activity
    chown -R root:root /usr/share/sugar/activities/TurtleArt.activity
    rm -f /tmp/turtleart.zip
    echo "TurtleArt activity installed"
fi

# Fix Sugar GSettings schema bug on Ubuntu 22.04:
# The sugar3 Python library (profile.py) references a 'favorites-layout' key
# that doesn't exist in the org.sugarlabs.desktop schema.
SCHEMA_FILE="/usr/share/glib-2.0/schemas/org.sugarlabs.gschema.xml"
if [ -f "$SCHEMA_FILE" ] && ! grep -q "favorites-layout" "$SCHEMA_FILE"; then
    echo "Patching Sugar GSettings schema to add missing favorites-layout key..."
    python3 << 'PYEOF'
schema_file = "/usr/share/glib-2.0/schemas/org.sugarlabs.gschema.xml"
with open(schema_file, "r") as f:
    content = f.read()

new_key = '''        <key name="favorites-layout" type="s">
            <default>'ring-layout'</default>
            <summary>Favorites Layout</summary>
            <description>Layout of favorite activities on the home view.</description>
        </key>
'''
content = content.replace(
    '<key name="launcher-interval"',
    new_key + '        <key name="launcher-interval"'
)
with open(schema_file, "w") as f:
    f.write(content)
print("Schema file patched")
PYEOF
    glib-compile-schemas /usr/share/glib-2.0/schemas/
    echo "Schema compiled successfully"
fi

# Configure GDM to use Sugar session instead of GNOME
# This ensures Sugar runs as the actual desktop environment
echo "Configuring Sugar as default desktop session..."
sed -i 's/DefaultSession=ubuntu-xorg.desktop/DefaultSession=sugar.desktop/' /etc/gdm3/custom.conf

# Set the user session via AccountsService
mkdir -p /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/ga << 'EOF'
[User]
Language=
XSession=sugar
SystemAccount=false
EOF

# Set SUGAR_PROFILE_NAME to skip the first-run intro screen
echo 'SUGAR_PROFILE_NAME=Learner' >> /etc/environment

# Download real data: Alice's Adventures in Wonderland from Project Gutenberg
mkdir -p /home/ga/Documents
wget -q -O /home/ga/Documents/alice_in_wonderland.txt \
    "https://www.gutenberg.org/cache/epub/11/pg11.txt" || {
    echo "WARNING: Could not download from Gutenberg, using mounted fallback"
    cp /workspace/data/alice_in_wonderland_excerpt.txt /home/ga/Documents/alice_in_wonderland.txt 2>/dev/null || true
}

# Copy TurtleArt program files from mounted data
mkdir -p /home/ga/Documents/turtleart
cp /workspace/data/turtleart/*.ta /home/ga/Documents/turtleart/ 2>/dev/null || {
    echo "Creating TurtleArt programs..."
    cat > /home/ga/Documents/turtleart/spiral.ta << 'TAEOF'
[[0, "start", 218, 163, [null, 1]],
[1, "repeat", 218, 205, [0, 2, 3, null]],
[2, ["number", 36], 304, 205, [1, null]],
[3, "forward", 260, 247, [1, 4, 5]],
[4, ["number", 100], 340, 247, [3, null]],
[5, "right", 260, 289, [3, 6, 7]],
[6, ["number", 170], 332, 289, [5, null]],
[7, "forward", 260, 331, [5, 8, 9]],
[8, ["number", 100], 340, 331, [7, null]],
[9, "right", 260, 373, [7, 10, null]],
[10, ["number", 180], 332, 373, [9, null]]]
TAEOF

    cat > /home/ga/Documents/turtleart/flower.ta << 'TAEOF'
[[0, "start", 218, 113, [null, 1]],
[1, "repeat", 218, 155, [0, 2, 3, null]],
[2, ["number", 36], 304, 155, [1, null]],
[3, "setcolor", 260, 197, [1, 4, 5]],
[4, "heading", 338, 197, [3, null]],
[5, "repeat", 260, 239, [3, 6, 7, 8]],
[6, ["number", 10], 346, 239, [5, null]],
[7, "forward", 302, 281, [5, 9, 10]],
[8, "right", 260, 365, [5, 12, null]],
[9, ["number", 50], 382, 281, [7, null]],
[10, "right", 302, 323, [7, 11, null]],
[11, ["number", 36], 374, 323, [10, null]],
[12, ["number", 10], 332, 365, [8, null]]]
TAEOF
}

# Set ownership
chown -R ga:ga /home/ga/Documents

echo "=== Sugar Learning Platform installation complete ==="
