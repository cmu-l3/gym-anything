#!/bin/bash
# Do NOT use set -e: xdotool/wmctrl commands can return non-zero harmlessly

echo "=== Setting up Portfolio Performance ==="

# Ensure X11 works when running as root
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Wait for desktop to be ready
sleep 5

# Create workspace and config directories for ga user
mkdir -p /home/ga/.eclipse
mkdir -p /home/ga/.portfolio-performance
mkdir -p /home/ga/Documents/PortfolioData

# Configure Portfolio Performance workspace settings
# The app uses Eclipse RCP, so we configure the workspace via eclipse preferences
mkdir -p /home/ga/.portfolio-performance/.metadata/.plugins/org.eclipse.core.runtime/.settings

# Suppress welcome screen and tips
cat > /home/ga/.portfolio-performance/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.ui.prefs << 'EOF'
eclipse.preferences.version=1
showIntro=false
showHelp=false
EOF

cat > /home/ga/.portfolio-performance/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.ui.ide.prefs << 'EOF'
eclipse.preferences.version=1
SHOW_WORKSPACE_SELECTION_DIALOG=false
RECENT_WORKSPACES=/home/ga/.portfolio-performance
EOF

# Set proper ownership
chown -R ga:ga /home/ga/.eclipse
chown -R ga:ga /home/ga/.portfolio-performance
chown -R ga:ga /home/ga/Documents

# Create launcher script
cat > /home/ga/Desktop/launch_pp.sh << 'LAUNCHEOF'
#!/bin/bash
export DISPLAY=:1
export SWT_GTK3=1
export GDK_BACKEND=x11
/opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &
LAUNCHEOF
chmod +x /home/ga/Desktop/launch_pp.sh
chown ga:ga /home/ga/Desktop/launch_pp.sh

# Launch Portfolio Performance as ga user
echo "Launching Portfolio Performance..."
su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

# Wait for the application window to appear
echo "Waiting for Portfolio Performance to start..."
STARTED=false
for i in $(seq 1 120); do
    if wmctrl -l 2>/dev/null | grep -qi "Portfolio Performance\|PortfolioPerformance\|unnamed"; then
        STARTED=true
        echo "Portfolio Performance window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$STARTED" = true ]; then
    sleep 5

    # Maximize the window
    WID=$(wmctrl -l | grep -i "Portfolio Performance\|PortfolioPerformance\|unnamed" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        wmctrl -ia "$WID" 2>/dev/null || true
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Window maximized"
    fi

    # Dismiss any welcome/first-run dialogs with Escape (safe, doesn't close main window)
    sleep 3
    xdotool key Escape 2>/dev/null || true
    sleep 1
    xdotool key Escape 2>/dev/null || true

    echo "Portfolio Performance is running and ready"
else
    echo "WARNING: Portfolio Performance window not detected after 120s"
    echo "Checking process..."
    ps aux | grep -i portfolio || true
    echo "PP log output:"
    cat /tmp/pp.log 2>/dev/null || true
fi

echo "=== Portfolio Performance setup complete ==="
