#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Recovery Task Export: tab_recovery_restore@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/tab_recovery_verification"
mkdir -p "$VERIFY_DIR"

# Capture all tabs via CDP
echo "Capturing all open tabs via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_all_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' "$VERIFY_DIR/chrome_all_tabs.json" > "$VERIFY_DIR/chrome_page_tabs.json"
    
    TAB_COUNT=$(jq 'length' "$VERIFY_DIR/chrome_page_tabs.json")
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for easy verification
    jq -r '.[] | "\(.url)|\(.title)"' "$VERIFY_DIR/chrome_page_tabs.json" > "$VERIFY_DIR/tab_list.txt"
    
    echo ""
    echo "Currently open tabs:"
    cat "$VERIFY_DIR/tab_list.txt" | nl
    
    # Check for presence of target URLs
    echo ""
    echo "Checking for recovered tabs..."
    if grep -qi "wikipedia.org.*quantum" "$VERIFY_DIR/tab_list.txt"; then
        echo "  ✓ Wikipedia (Quantum Computing) found"
    else
        echo "  ✗ Wikipedia (Quantum Computing) NOT found"
    fi
    
    if grep -qi "stackoverflow.com" "$VERIFY_DIR/tab_list.txt"; then
        echo "  ✓ Stack Overflow found"
    else
        echo "  ✗ Stack Overflow NOT found"
    fi
    
    if grep -qi "github.com.*react" "$VERIFY_DIR/tab_list.txt"; then
        echo "  ✓ GitHub (React) found"
    else
        echo "  ✗ GitHub (React) NOT found"
    fi
    
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > "$VERIFY_DIR/chrome_page_tabs.json"
    touch "$VERIFY_DIR/tab_list.txt"
fi

# Copy verification files to standard temp location for verifier access
cp "$VERIFY_DIR/chrome_page_tabs.json" /tmp/ 2>/dev/null || true
cp "$VERIFY_DIR/tab_list.txt" /tmp/ 2>/dev/null || true

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Save final state summary
cat > "$VERIFY_DIR/summary.txt" << EOF
Tab Recovery Task Export Summary
=================================
Timestamp: $(date)
Total tabs: $TAB_COUNT
Export location: $VERIFY_DIR

Task: Recover 3 specific tabs from recently-closed list
Expected tabs:
  1. Wikipedia - Quantum Computing
  2. Stack Overflow - Binary search in Python
  3. GitHub - facebook/react repository
EOF

echo ""
echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"