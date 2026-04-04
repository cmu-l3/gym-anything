#!/bin/bash
set -euo pipefail

echo "=== Setting up Wireshark environment ==="

# Wait for desktop to be ready
sleep 5

# Create Wireshark desktop launcher
cat > /home/ga/Desktop/Wireshark.desktop << 'EOF'
[Desktop Entry]
Name=Wireshark
Comment=Network Protocol Analyzer
Exec=wireshark %f
Icon=wireshark
Terminal=false
Type=Application
MimeType=application/vnd.tcpdump.pcap;application/x-pcapng;
Categories=Network;Monitor;
EOF
chown ga:ga /home/ga/Desktop/Wireshark.desktop
chmod +x /home/ga/Desktop/Wireshark.desktop

# Create convenience symlinks on Desktop for easy access to captures
ln -sf /home/ga/Documents/captures /home/ga/Desktop/captures 2>/dev/null || true

# Configure Wireshark preferences to suppress first-run dialogs
mkdir -p /home/ga/.config/wireshark
cat > /home/ga/.config/wireshark/recent << 'EOF'
# Recent settings file for Wireshark 4.x
privs.warn_if_elevated: FALSE
gui.ask_unsaved: FALSE
gui.toolbar_main_show: TRUE
gui.toolbar_filter_show: TRUE
gui.toolbar_main_style: 0
gui.packet_list_show: TRUE
gui.tree_view_show: TRUE
gui.byte_view_show: TRUE
gui.statusbar_show: TRUE
gui.geometry_main_x: 0
gui.geometry_main_y: 0
gui.geometry_main_width: 1920
gui.geometry_main_height: 1080
gui.geometry_main_maximized: TRUE
EOF

# Create preferences file to disable update checks
cat > /home/ga/.config/wireshark/preferences << 'EOF'
# Wireshark preferences
gui.update.enabled: FALSE
gui.ask_unsaved: FALSE
EOF

chown -R ga:ga /home/ga/.config/wireshark/

# Verify Wireshark is installed and accessible
echo "Verifying Wireshark installation..."
WIRESHARK_VERSION=$(wireshark --version 2>&1 | head -1 || echo "unknown")
echo "Wireshark version: $WIRESHARK_VERSION"

TSHARK_VERSION=$(tshark --version 2>&1 | head -1 || echo "unknown")
echo "tshark version: $TSHARK_VERSION"

# Verify PCAP files are accessible
echo "Verifying PCAP data files..."
ls -la /home/ga/Documents/captures/ 2>/dev/null || echo "WARNING: No PCAP files found"

# Quick tshark test to verify PCAP files are readable
for f in /home/ga/Documents/captures/*.cap /home/ga/Documents/captures/*.pcap /home/ga/Documents/captures/*.pcapng; do
    if [ -f "$f" ]; then
        PACKET_COUNT=$(tshark -r "$f" 2>/dev/null | wc -l)
        echo "  $(basename $f): $PACKET_COUNT packets"
    fi
done

echo "=== Wireshark setup complete ==="
