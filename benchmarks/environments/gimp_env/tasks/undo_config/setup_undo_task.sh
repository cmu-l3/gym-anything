#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up undo configuration task ==="

# Wait a moment to ensure system is ready
sleep 1

# Open GIMP as ga user (no specific file)
echo "🎨 Opening GIMP for preferences configuration..."
su - ga -c "DISPLAY=:1 gimp > /tmp/gimp_undo.log 2>&1 &"

# Wait for GIMP to start
sleep 5

echo "=== Undo configuration task setup completed! ==="
echo "💡 Instructions for agent:"
echo "   1. GIMP is now open"
echo "   2. Go to Edit > Preferences (or use keyboard shortcut)"
echo "   3. Navigate to System Resources section"
echo "   4. Find 'Undo' or 'Undo levels' setting"
echo "   5. Set the value to 100"
echo "   6. Apply/OK the changes"
echo "   7. GIMP will be closed automatically to save config"
