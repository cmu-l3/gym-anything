#!/bin/bash
# setup_task.sh for corporate_network_topology

echo "=== Setting up Corporate Network Topology Task ==="

# 1. create the inventory file
cat > /home/ga/Desktop/network_inventory.txt << 'EOF'
================================================================
CORPORATE NETWORK DEVICE INVENTORY
Meridian Financial Services — Austin Office
Exported from ServiceNow CMDB: 2024-11-15
================================================================

ZONE: WAN/Edge
──────────────────────────────────────────
  Device: ISP-RTR-01        Type: Router (ISP CPE)
    IP: 203.0.113.1/30      VLAN: N/A
    Connects-to: EDGE-RTR-01

  Device: EDGE-RTR-01       Type: Router (Cisco ISR 4331)
    IP: 203.0.113.2/30, 10.1.0.1/30   VLAN: N/A
    Connects-to: FW-01

ZONE: DMZ (VLAN 10 — 10.1.1.0/24)
──────────────────────────────────────────
  Device: FW-01              Type: Firewall (Palo Alto PA-850)
    IP: 10.1.0.2/30 (inside), 10.1.1.1/24 (DMZ), 10.1.0.5/30 (core)
    Connects-to: DMZ-SW-01, CORE-SW-01

  Device: DMZ-SW-01          Type: Switch (Cisco Catalyst 2960-X)
    IP: 10.1.1.2/24          VLAN: 10
    Connects-to: WEB-SRV-01, MAIL-GW-01, DNS-EXT-01

  Device: WEB-SRV-01         Type: Server (Nginx Reverse Proxy)
    IP: 10.1.1.10/24         VLAN: 10
    Connects-to: DMZ-SW-01

  Device: MAIL-GW-01         Type: Server (Barracuda Email GW)
    IP: 10.1.1.11/24         VLAN: 10
    Connects-to: DMZ-SW-01

  Device: DNS-EXT-01         Type: Server (BIND External DNS)
    IP: 10.1.1.12/24         VLAN: 10
    Connects-to: DMZ-SW-01

ZONE: Core/Distribution
──────────────────────────────────────────
  Device: CORE-SW-01         Type: L3 Switch (Cisco Catalyst 9300 Stack)
    IP: 10.1.0.6/30 (to FW), SVI multiple   VLAN: All (trunk)
    Connects-to: FW-01, DIST-SW-F1, DIST-SW-F2, SRV-SW-01, WLC-01, MGMT-SW-01

  Device: DIST-SW-F1         Type: Switch (Cisco Catalyst 3850 — Floor 1)
    IP: 10.1.10.1/24         VLAN: 100
    Connects-to: CORE-SW-01

  Device: DIST-SW-F2         Type: Switch (Cisco Catalyst 3850 — Floor 2)
    IP: 10.1.20.1/24         VLAN: 200
    Connects-to: CORE-SW-01

ZONE: Server Farm (VLAN 20 — 10.1.2.0/24)
──────────────────────────────────────────
  Device: SRV-SW-01          Type: Switch (Cisco Nexus 3048)
    IP: 10.1.2.1/24          VLAN: 20
    Connects-to: CORE-SW-01, AD-DC-01, FILE-SRV-01, DB-SRV-01, APP-SRV-01, BKP-SRV-01

  Device: AD-DC-01           Type: Server (Windows AD Domain Controller)
    IP: 10.1.2.10/24         VLAN: 20
    Connects-to: SRV-SW-01

  Device: FILE-SRV-01        Type: Server (Synology NAS)
    IP: 10.1.2.11/24         VLAN: 20
    Connects-to: SRV-SW-01

  Device: DB-SRV-01          Type: Server (PostgreSQL Database)
    IP: 10.1.2.12/24         VLAN: 20
    Connects-to: SRV-SW-01

  Device: APP-SRV-01         Type: Server (Java Application Server)
    IP: 10.1.2.13/24         VLAN: 20
    Connects-to: SRV-SW-01

  Device: BKP-SRV-01         Type: Server (Veeam Backup)
    IP: 10.1.2.14/24         VLAN: 20
    Connects-to: SRV-SW-01

ZONE: Wireless (VLAN 300 — 10.1.30.0/24)
──────────────────────────────────────────
  Device: WLC-01             Type: Wireless Controller (Cisco 9800-L)
    IP: 10.1.30.1/24         VLAN: 300
    Connects-to: CORE-SW-01, AP-F1-01, AP-F2-01

  Device: AP-F1-01           Type: Access Point (Cisco Aironet — Floor 1)
    IP: 10.1.30.10/24        VLAN: 300
    Connects-to: WLC-01, DIST-SW-F1

  Device: AP-F2-01           Type: Access Point (Cisco Aironet — Floor 2)
    IP: 10.1.30.11/24        VLAN: 300
    Connects-to: WLC-01, DIST-SW-F2

ZONE: Management (VLAN 999 — 10.1.99.0/24)
──────────────────────────────────────────
  Device: MGMT-SW-01         Type: Switch (Cisco 2960-X)
    IP: 10.1.99.1/24         VLAN: 999
    Connects-to: CORE-SW-01, NMS-01, SYSLOG-01, RADIUS-01

  Device: NMS-01             Type: Server (PRTG Network Monitor)
    IP: 10.1.99.10/24        VLAN: 999
    Connects-to: MGMT-SW-01

  Device: SYSLOG-01          Type: Server (Graylog Syslog)
    IP: 10.1.99.11/24        VLAN: 999
    Connects-to: MGMT-SW-01

  Device: RADIUS-01          Type: Server (FreeRADIUS AAA)
    IP: 10.1.99.12/24        VLAN: 999
    Connects-to: MGMT-SW-01

================================================================
SUBNET ALLOCATION TABLE
──────────────────────────────────────────
  WAN Link:        203.0.113.0/30     (N/A)
  Firewall Transit: 10.1.0.0/30      (N/A)
  Core Transit:    10.1.0.4/30        (N/A)
  DMZ:             10.1.1.0/24        VLAN 10
  Server Farm:     10.1.2.0/24        VLAN 20
  Users Floor 1:   10.1.10.0/24       VLAN 100
  Users Floor 2:   10.1.20.0/24       VLAN 200
  Wireless:        10.1.30.0/24       VLAN 300
  Management:      10.1.99.0/24       VLAN 999
================================================================
EOF
chown ga:ga /home/ga/Desktop/network_inventory.txt

# 2. Record timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at $(cat /tmp/task_start_time.txt)"

# 3. Clean up previous artifacts
rm -f /home/ga/Desktop/network_topology.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/network_topology.png 2>/dev/null || true

# 4. Find and launch draw.io
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio";
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio";
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="