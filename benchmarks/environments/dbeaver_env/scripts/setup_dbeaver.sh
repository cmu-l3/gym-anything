#!/bin/bash
# DBeaver Setup Script (post_start hook)
# Configures DBeaver and sets up sample databases

echo "=== Setting up DBeaver Environment ==="

# Wait for desktop to be ready
sleep 5

# Create working directories
echo "Creating working directories..."
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/.local/share/DBeaverData/workspace6/General

# Copy sample database (Chinook SQLite)
echo "Setting up sample databases..."
if [ -f "/workspace/data/chinook.db" ]; then
    cp /workspace/data/chinook.db /home/ga/Documents/databases/chinook.db
    chmod 644 /home/ga/Documents/databases/chinook.db
    chown ga:ga /home/ga/Documents/databases/chinook.db
    echo "Chinook database copied to /home/ga/Documents/databases/chinook.db"
else
    echo "WARNING: Chinook database not found at /workspace/data/chinook.db"
    # Try to download it
    echo "Attempting to download Chinook database..."
    wget -q -O /tmp/chinook.db "https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite" 2>/dev/null || \
    wget -q -O /tmp/chinook.db "https://www.sqlitetutorial.net/wp-content/uploads/2018/03/chinook.zip" 2>/dev/null && unzip -o /tmp/chinook.zip -d /tmp/ || true

    if [ -f "/tmp/chinook.db" ]; then
        cp /tmp/chinook.db /home/ga/Documents/databases/chinook.db
        chmod 644 /home/ga/Documents/databases/chinook.db
        chown ga:ga /home/ga/Documents/databases/chinook.db
        echo "Chinook database downloaded and installed"
    fi
fi

# Set ownership for all directories
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/.local 2>/dev/null || true

# Create a DBeaver launcher script
cat > /home/ga/Desktop/DBeaver.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=DBeaver
Comment=Universal Database Manager
Exec=/usr/share/dbeaver-ce/dbeaver
Icon=/usr/share/dbeaver-ce/dbeaver.png
StartupNotify=true
Terminal=false
Type=Application
Categories=Development;Database;
DESKTOPEOF
chmod +x /home/ga/Desktop/DBeaver.desktop
chown ga:ga /home/ga/Desktop/DBeaver.desktop

# Create utility script to query SQLite database
cat > /usr/local/bin/chinook-query << 'QUERYEOF'
#!/bin/bash
# Execute SQL query against Chinook SQLite database
sqlite3 -header -column /home/ga/Documents/databases/chinook.db "$1"
QUERYEOF
chmod +x /usr/local/bin/chinook-query

# Create DBeaver config directory structure
mkdir -p /home/ga/.local/share/DBeaverData/workspace6/.metadata/.plugins/org.eclipse.e4.workbench
mkdir -p /home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver

# Disable first-run wizard by creating marker file
mkdir -p /home/ga/.local/share/DBeaverData
touch /home/ga/.local/share/DBeaverData/.metadata

# Set ownership
chown -R ga:ga /home/ga/.local

# Start DBeaver for the ga user
echo "Launching DBeaver..."
su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"

# Wait for DBeaver window to appear
sleep 10
DBEAVER_STARTED=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
        DBEAVER_STARTED=true
        echo "DBeaver window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$DBEAVER_STARTED" = true ]; then
    sleep 5
    # Maximize DBeaver window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "dbeaver" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Dismiss initial dialogs (Statistics collection, Create sample database, etc.)
    echo "Dismissing any initial dialogs..."

    # Wait for potential dialogs to appear
    sleep 3

    # Check for Statistics collection dialog and dismiss with Enter (clicks Confirm)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "statistics"; then
        DISPLAY=:1 wmctrl -a "Statistics" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 2
    fi

    # Check for Create sample database dialog and dismiss with Escape (clicks No/closes)
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sample database"; then
        DISPLAY=:1 wmctrl -a "sample database" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 2
    fi

    # Final Escape to close any remaining dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true

    echo "Initial dialog handling complete"
fi

echo ""
echo "=== DBeaver Setup Complete ==="
echo ""
echo "Sample Database: /home/ga/Documents/databases/chinook.db (SQLite)"
echo "Export Directory: /home/ga/Documents/exports/"
echo ""
echo "Chinook Database Info:"
echo "  - Digital media store data (artists, albums, tracks, customers, invoices)"
echo "  - Based on real iTunes Library data"
echo ""
echo "Quick query: chinook-query \"SELECT COUNT(*) FROM tracks;\""
echo ""
