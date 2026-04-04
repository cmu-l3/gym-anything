#!/bin/bash
# setup_task.sh for tcp_state_machine_diagram
# Do NOT use set -e to prevent premature exit on non-critical failures

echo "=== Setting up TCP State Machine Task ==="

# 1. Create the Reference Text File (RFC 793/9293 excerpt)
cat > /home/ga/Desktop/tcp_states_rfc793.txt << 'EOF'
TCP STATE MACHINE REFERENCE (RFC 793 / RFC 9293)
================================================

STATES:
1.  CLOSED       - represents no connection state at all.
2.  LISTEN       - represents waiting for a connection request from any remote TCP and port.
3.  SYN-SENT     - represents waiting for a matching connection request after having sent a connection request.
4.  SYN-RECEIVED - represents waiting for a confirming connection request acknowledgment after having both received and sent a connection request.
5.  ESTABLISHED  - represents an open connection, data received can be delivered to the user.
6.  FIN-WAIT-1   - represents waiting for a connection termination request from the remote TCP, or an acknowledgment of the connection termination request previously sent.
7.  FIN-WAIT-2   - represents waiting for a connection termination request from the remote TCP.
8.  CLOSE-WAIT   - represents waiting for a connection termination request from the local user.
9.  CLOSING      - represents waiting for a connection termination request acknowledgment from the remote TCP.
10. LAST-ACK     - represents waiting for an acknowledgment of the connection termination request previously sent to the remote TCP.
11. TIME-WAIT    - represents waiting for enough time to pass to be sure the remote TCP received the acknowledgment of its connection termination request.

TRANSITIONS (Event / Action):

-- Connection Establishment (Phase 1) --
1.  CLOSED -> LISTEN        (Passive Open)
2.  CLOSED -> SYN-SENT      (Active Open / Send SYN)
3.  LISTEN -> SYN-RECEIVED  (Recv SYN / Send SYN,ACK)
4.  SYN-SENT -> SYN-RECEIVED (Recv SYN / Send ACK)
5.  SYN-SENT -> ESTABLISHED (Recv SYN,ACK / Send ACK)
6.  SYN-RECEIVED -> ESTABLISHED (Recv ACK)

-- Connection Teardown (Phase 2) --
7.  ESTABLISHED -> FIN-WAIT-1  (Close / Send FIN)
8.  ESTABLISHED -> CLOSE-WAIT  (Recv FIN / Send ACK)
9.  FIN-WAIT-1 -> FIN-WAIT-2   (Recv ACK)
10. FIN-WAIT-1 -> CLOSING      (Recv FIN / Send ACK)
11. FIN-WAIT-1 -> TIME-WAIT    (Recv FIN,ACK / Send ACK)
12. FIN-WAIT-2 -> TIME-WAIT    (Recv FIN / Send ACK)
13. CLOSE-WAIT -> LAST-ACK     (Close / Send FIN)
14. CLOSING -> TIME-WAIT       (Recv ACK)
15. LAST-ACK -> CLOSED         (Recv ACK)
16. TIME-WAIT -> CLOSED        (Timeout=2MSL)

-- Reset / Failures --
17. LISTEN -> CLOSED           (Close)
18. SYN-SENT -> CLOSED         (Close or Timeout)
19. SYN-RECEIVED -> FIN-WAIT-1 (Close / Send FIN)

INSTRUCTIONS:
1. Draw all 11 states.
2. Draw all transitions with arrows.
3. Label transitions with "Event / Action".
4. Color code: GREEN for Establishment, RED/ORANGE for Teardown.
EOF

chown ga:ga /home/ga/Desktop/tcp_states_rfc793.txt
chmod 644 /home/ga/Desktop/tcp_states_rfc793.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Desktop/tcp_state_machine.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/tcp_state_machine.png 2>/dev/null || true

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# 4. Launch draw.io
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio"; 
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

sleep 3
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (ESC creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial state
DISPLAY=:1 import -window root /tmp/tcp_task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="