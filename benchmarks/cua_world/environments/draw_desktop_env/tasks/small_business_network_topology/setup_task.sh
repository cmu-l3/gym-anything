#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up small_business_network_topology task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/network_topology.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/network_topology.png 2>/dev/null || true

# Create the Network Inventory File
cat > /home/ga/Desktop/network_inventory.txt << 'EOF'
========================================================
APEX MANUFACTURING LLC — NETWORK DEVICE INVENTORY
Prepared for SOC 2 Type II Audit — Q1 2025
========================================================

NETWORK OVERVIEW
----------------
Location: 1847 Industrial Parkway, Building C, Portland OR
Total Devices: 16 managed devices
VLANs: 5 (DMZ=5, Servers=10, Office=20, Wireless=30, Mgmt=99)
WAN: Comcast Business 500/100 Mbps, Static IP 203.0.113.2/30

========================================================
ZONE 1: INTERNET EDGE
========================================================
Device: ISP-GW-01
  Type: ISP Gateway/Modem
  Make/Model: Comcast Business Gateway
  WAN IP: 203.0.113.2
  LAN IP: 203.0.113.1 (ISP side)
  Connects to: FW-01 (outside interface)

Device: FW-01
  Type: Perimeter Firewall
  Make/Model: Cisco ASA 5506-X
  Outside IP: 203.0.113.2
  Inside IP: 10.0.1.1
  DMZ IP: 10.0.5.1
  Connects to: ISP-GW-01 (outside), CORE-SW-01 (inside), DMZ segment (dmz)

========================================================
ZONE 2: DMZ (VLAN 5 — 10.0.5.0/24)
========================================================
Device: WEB-01
  Type: Public Web Server
  Make/Model: Dell PowerEdge R350 / Ubuntu 22.04 / Nginx
  IP: 10.0.5.10
  Connects to: FW-01 (dmz interface)

Device: DNS-EXT-01
  Type: External DNS Server
  Make/Model: Dell PowerEdge R350 / Ubuntu 22.04 / BIND9
  IP: 10.0.5.11
  Connects to: FW-01 (dmz interface)

========================================================
ZONE 3: CORE INFRASTRUCTURE
========================================================
Device: CORE-SW-01
  Type: Core/Distribution Switch (Layer 3)
  Make/Model: Cisco Catalyst 2960-X 48-port
  Management IP: 10.0.99.1 (VLAN 99)
  Connects to: FW-01 (inside), DIST-SW-A, DIST-SW-B, SRV-* (VLAN 10)

Device: DIST-SW-A
  Type: Distribution Switch (Floor 1)
  Make/Model: Cisco Catalyst 2960-L 24-port
  Management IP: 10.0.99.2 (VLAN 99)
  Connects to: CORE-SW-01, Engineering workstations, AP-FL1

Device: DIST-SW-B
  Type: Distribution Switch (Floor 2)
  Make/Model: Cisco Catalyst 2960-L 24-port
  Management IP: 10.0.99.3 (VLAN 99)
  Connects to: CORE-SW-01, Sales workstations, Admin workstations, AP-FL2

========================================================
ZONE 4: SERVER FARM (VLAN 10 — 10.0.10.0/24)
========================================================
Device: DC-01
  Type: Domain Controller / Active Directory
  Make/Model: Dell PowerEdge R550 / Windows Server 2022
  IP: 10.0.10.10
  Connects to: CORE-SW-01 (VLAN 10)

Device: FS-01
  Type: File Server (SMB/NFS shares)
  Make/Model: Dell PowerEdge R550 / Windows Server 2022
  IP: 10.0.10.11
  Connects to: CORE-SW-01 (VLAN 10)

Device: BK-01
  Type: Backup Server (Veeam)
  Make/Model: Dell PowerEdge R750 / Windows Server 2022
  IP: 10.0.10.12
  Connects to: CORE-SW-01 (VLAN 10)

Device: PRN-01
  Type: Network Print Server
  Make/Model: HP LaserJet Enterprise MFP M635
  IP: 10.0.10.20
  Connects to: CORE-SW-01 (VLAN 10)

Device: DNS-INT-01
  Type: Internal DNS + DHCP Server
  Make/Model: Dell PowerEdge R350 / Ubuntu 22.04 / dnsmasq
  IP: 10.0.10.13
  Connects to: CORE-SW-01 (VLAN 10)

========================================================
ZONE 5: OFFICE LAN (VLAN 20 — 10.0.20.0/24)
========================================================
Group: ENG-WS
  Type: Engineering Workstations (12 stations)
  IP Range: 10.0.20.50–10.0.20.69 (DHCP)
  Connects to: DIST-SW-A

Group: SALES-WS
  Type: Sales Workstations (8 stations)
  IP Range: 10.0.20.70–10.0.20.89 (DHCP)
  Connects to: DIST-SW-B

Group: ADMIN-WS
  Type: Admin Workstations (5 stations)
  IP Range: 10.0.20.90–10.0.20.99 (DHCP)
  Connects to: DIST-SW-B

========================================================
ZONE 6: WIRELESS (VLAN 30 — 10.0.30.0/24)
========================================================
Device: AP-FL1
  Type: Wireless Access Point (Floor 1)
  Make/Model: Ubiquiti UniFi U6-Pro
  Management IP: 10.0.99.10
  SSID: APEX-Corp (VLAN 20), APEX-Guest (VLAN 30)
  Connects to: DIST-SW-A

Device: AP-FL2
  Type: Wireless Access Point (Floor 2)
  Make/Model: Ubiquiti UniFi U6-Pro
  Management IP: 10.0.99.11
  SSID: APEX-Corp (VLAN 20), APEX-Guest (VLAN 30)
  Connects to: DIST-SW-B

========================================================
CONNECTION SUMMARY (16 links)
========================================================
1.  ISP-GW-01  →  FW-01        (WAN uplink)
2.  FW-01      →  CORE-SW-01   (inside interface, trunk)
3.  FW-01      →  WEB-01       (DMZ interface)
4.  FW-01      →  DNS-EXT-01   (DMZ interface)
5.  CORE-SW-01 →  DIST-SW-A    (trunk, VLANs 20,30,99)
6.  CORE-SW-01 →  DIST-SW-B    (trunk, VLANs 20,30,99)
7.  CORE-SW-01 →  DC-01        (VLAN 10)
8.  CORE-SW-01 →  FS-01        (VLAN 10)
9.  CORE-SW-01 →  BK-01        (VLAN 10)
10. CORE-SW-01 →  PRN-01       (VLAN 10)
11. CORE-SW-01 →  DNS-INT-01   (VLAN 10)
12. DIST-SW-A  →  ENG-WS       (VLAN 20)
13. DIST-SW-A  →  AP-FL1       (trunk)
14. DIST-SW-B  →  SALES-WS     (VLAN 20)
15. DIST-SW-B  →  ADMIN-WS     (VLAN 20)
16. DIST-SW-B  →  AP-FL2       (trunk)
========================================================
EOF
chown ga:ga /home/ga/Desktop/network_inventory.txt

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss the "Create New / Open Existing" dialog (Esc key) to start with blank canvas
# This is crucial so the agent starts with a usable interface
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="