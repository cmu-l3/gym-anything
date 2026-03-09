#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Theme Installation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot to capture theme appearance
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/theme_final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved to /tmp/theme_final_screenshot.png"
fi

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/theme_final_url.txt
fi

# Gracefully close Chrome to ensure theme settings are persisted to disk
echo "Closing Chrome to save theme configuration..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_final.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_final.json"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_final.json
    echo "✓ Preferences exported from alternative location"
else
    echo "⚠ Warning: Preferences file not found"
fi

# Export theme extension information
echo "Exporting theme extension data..."
EXPORT_DIR="/tmp/theme_verification"
mkdir -p "$EXPORT_DIR"

# Create a manifest of all extensions with theme information
for profile_path in "$CHROME_PROFILE" "$ALT_PROFILE"; do
    EXT_DIR="$profile_path/Extensions"
    if [ -d "$EXT_DIR" ]; then
        echo "Scanning extensions in: $EXT_DIR"
        
        # Find and copy theme extensions
        for ext_dir in "$EXT_DIR"/*; do
            if [ -d "$ext_dir" ]; then
                ext_id=$(basename "$ext_dir")
                
                # Check all version directories for theme manifests
                for version_dir in "$ext_dir"/*; do
                    if [ -d "$version_dir" ]; then
                        manifest_file="$version_dir/manifest.json"
                        
                        if [ -f "$manifest_file" ]; then
                            # Check if this is a theme extension
                            if grep -q '"theme"' "$manifest_file" 2>/dev/null; then
                                echo "Found theme extension: $ext_id"
                                
                                # Copy the manifest to export directory
                                mkdir -p "$EXPORT_DIR/extensions/$ext_id"
                                cp "$manifest_file" "$EXPORT_DIR/extensions/$ext_id/manifest.json"
                                
                                # Record extension ID
                                echo "$ext_id" >> "$EXPORT_DIR/theme_extension_ids.txt"
                            fi
                        fi
                    fi
                done
            fi
        done
        
        # If we found extensions, no need to check alternative location
        if [ -f "$EXPORT_DIR/theme_extension_ids.txt" ]; then
            break
        fi
    fi
done

# List what we found
if [ -f "$EXPORT_DIR/theme_extension_ids.txt" ]; then
    echo "Theme extensions found:"
    cat "$EXPORT_DIR/theme_extension_ids.txt"
else
    echo "No theme extensions found in Extensions directory"
    touch "$EXPORT_DIR/theme_extension_ids.txt"
fi

echo "✅ Export complete"
echo "Theme verification data exported to: $EXPORT_DIR"