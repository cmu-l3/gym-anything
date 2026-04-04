#!/bin/bash
set -e

echo "=== Setting up TCP State Machine Task ==="

# Ensure directories exist
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# Define paths
DIAGRAM_FILE="/home/ga/Diagrams/tcp_state_machine.drawio"
RFC_FILE="/home/ga/Desktop/tcp_rfc793_state_machine.txt"

# 1. Create the RFC Reference Text File
cat > "$RFC_FILE" << 'EOF'
RFC 793 - TRANSMISSION CONTROL PROTOCOL - STATE MACHINE EXCERPT

3.2. Terminology
  The maintenance of a TCP connection requires the remembering of several variables. 
  We conceive of these variables as being stored in a connection record called a 
  Transmission Control Block or TCB. Among the variables stored in the TCB are 
  the local and remote socket numbers, the security and precedence of the connection, 
  pointers to the user's send and receive buffers, pointers to the retransmit queue 
  and to the current segment. In addition several variables relating to the send and 
  receive sequence numbers are stored in the TCB.

  Connection State:
    The state of the connection is represented by the state variable.
    The states are:
      LISTEN      - represents waiting for a connection request from any remote TCP and port.
      
      SYN-SENT    - represents waiting for a matching connection request after having sent a connection request.
      
      SYN-RECEIVED - represents waiting for a confirming connection request acknowledgment after having both received and sent a connection request.
      
      ESTABLISHED - represents an open connection, data received can be delivered to the user.  The normal state for the data transfer phase of the connection.
      
      FIN-WAIT-1  - represents waiting for a connection termination request from the remote TCP, or an acknowledgment of the connection termination request previously sent.
      
      FIN-WAIT-2  - represents waiting for a connection termination request from the remote TCP.
      
      CLOSE-WAIT  - represents waiting for a connection termination request from the local user.
      
      CLOSING     - represents waiting for a connection termination request acknowledgment from the remote TCP.
      
      LAST-ACK    - represents waiting for an acknowledgment of the connection termination request previously sent to the remote TCP (which includes an acknowledgment of its connection termination request).
      
      TIME-WAIT   - represents waiting for enough time to pass to be sure the remote TCP received the acknowledgment of its connection termination request.
      
      CLOSED      - represents no connection state at all.

TCP CONNECTION STATE DIAGRAM (Figure 6)

                              +---------+ ---------\      active OPEN
                              |  CLOSED |            \    -----------
                              +---------+<---------\   \   create TCB
                                |     ^              \   \  snd SYN
                   passive OPEN |     |   close        \   \
                   ------------ |     | ----------       \   \
                    create TCB  |     | delete TCB         \   \
                                V     |                      \   \
                              +---------+            close    |    \
                              |  LISTEN |          ---------- |     |
                              +---------+          delete TCB |     |
                   rcv SYN      |     |     snd SYN,ACK       |     |
                  -----------   |     |    ----------------   |     V
 +---------+      snd SYN,ACK  /       \   rcv SYN          +---------+
 |         |<-----------------           ------------------>|         |
 |   SYN   |                    rcv SYN                     |   SYN   |
 |   RCVD  |<-----------------------------------------------|   SENT  |
 |         |                    snd ACK                     |         |
 |         |------------------           -------------------|         |
 +---------+   snd SYN,ACK    \       /     rcv SYN,ACK     +---------+
   |     |    ---------------- \     /     -----------
   |     |    rcv ACK of SYN     \ /       snd ACK
   |     |   ------------------  / \
   |     |        x             /   \
   |     V                     V     V
   |  +---------+        +---------+
   |  |  ESTAB  |        |  ESTAB  |
   |  +---------+        +---------+
   |      |
   |      |    (Close Transitions Follow Below)
   |      V
   |  (Active Close)
   |  +---------+
   |  |FIN-WAIT-1|
   |  +---------+
   |    |    |
   |    |    +------------------+
   |    V                       V
   |  +---------+          +---------+
   |  |FIN-WAIT-2|         | CLOSING |
   |  +---------+          +---------+
   |    |                    |     |
   |    V                    V     V
   |  +---------+          +---------+
   |  |TIME-WAIT|          |TIME-WAIT|
   |  +---------+          +---------+
   |    |
   |    V
   |  +---------+
   |  | CLOSED  |
   |  +---------+

   (Passive Close Path)
   ESTABLISHED -> rcv FIN / snd ACK -> CLOSE-WAIT
   CLOSE-WAIT  -> close / snd FIN   -> LAST-ACK
   LAST-ACK    -> rcv ACK           -> CLOSED

EOF

# 2. Create the "Broken" draw.io File
# This XML defines the starting state: 
# - 6 states (missing teardown states)
# - The erroneous ESTABLISHED->CLOSED transition
# - Standard UML rounded rectangles
cat > "$DIAGRAM_FILE" << 'XML'
<mxfile host="Electron" modified="2023-10-01T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" etag="starting_state" version="21.6.8" type="device">
  <diagram id="tcp_diagram" name="TCP State Machine">
    <mxGraphModel dx="1000" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- STATES -->
        <mxCell id="state_closed" value="CLOSED" style="rounded=1;whiteSpace=wrap;html=1;arcSize=40;fillColor=#f5f5f5;fontColor=#333333;strokeColor=#666666;" vertex="1" parent="1">
          <mxGeometry x="360" y="40" width="120" height="60" as="geometry" />
        </mxCell>
        
        <mxCell id="state_listen" value="LISTEN" style="rounded=1;whiteSpace=wrap;html=1;arcSize=40;" vertex="1" parent="1">
          <mxGeometry x="360" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        
        <mxCell id="state_syn_sent" value="SYN_SENT" style="rounded=1;whiteSpace=wrap;html=1;arcSize=40;" vertex="1" parent="1">
          <mxGeometry x="560" y="280" width="120" height="60" as="geometry" />
        </mxCell>
        
        <mxCell id="state_syn_rcvd" value="SYN_RCVD" style="rounded=1;whiteSpace=wrap;html=1;arcSize=40;" vertex="1" parent="1">
          <mxGeometry x="160" y="280" width="120" height="60" as="geometry" />
        </mxCell>
        
        <mxCell id="state_estab" value="ESTABLISHED" style="rounded=1;whiteSpace=wrap;html=1;arcSize=40;fontStyle=1;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="1">
          <mxGeometry x="360" y="400" width="120" height="60" as="geometry" />
        </mxCell>

        <mxCell id="state_fin_wait_1" value="FIN_WAIT_1" style="rounded=1;whiteSpace=wrap;html=1;arcSize=40;" vertex="1" parent="1">
          <mxGeometry x="160" y="520" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- TRANSITIONS -->
        
        <!-- Passive Open: CLOSED -> LISTEN -->
        <mxCell id="edge_1" value="passive open" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="state_closed" target="state_listen">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        
        <!-- Active Open: CLOSED -> SYN_SENT -->
        <mxCell id="edge_2" value="active open / snd SYN" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="state_closed" target="state_syn_sent">
          <mxGeometry relative="1" as="geometry">
            <Array as="points">
              <mxPoint x="620" y="70" />
            </Array>
          </mxGeometry>
        </mxCell>
        
        <!-- LISTEN -> SYN_RCVD (Missing label planted here) -->
        <mxCell id="edge_3" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="state_listen" target="state_syn_rcvd">
          <mxGeometry relative="1" as="geometry">
             <Array as="points">
              <mxPoint x="220" y="190" />
            </Array>
          </mxGeometry>
        </mxCell>

        <!-- SYN_SENT -> ESTABLISHED -->
        <mxCell id="edge_4" value="rcv SYN,ACK / snd ACK" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="state_syn_sent" target="state_estab">
          <mxGeometry relative="1" as="geometry">
            <Array as="points">
              <mxPoint x="620" y="430" />
            </Array>
          </mxGeometry>
        </mxCell>

        <!-- SYN_RCVD -> ESTABLISHED -->
        <mxCell id="edge_5" value="rcv ACK" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="state_syn_rcvd" target="state_estab">
          <mxGeometry relative="1" as="geometry">
             <Array as="points">
              <mxPoint x="220" y="430" />
            </Array>
          </mxGeometry>
        </mxCell>

        <!-- ESTABLISHED -> FIN_WAIT_1 (Partial active close) -->
        <mxCell id="edge_6" value="active close / snd FIN" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="state_estab" target="state_fin_wait_1">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>

        <!-- THE ERROR: ESTABLISHED -> CLOSED (Shortcut) -->
        <mxCell id="edge_error" value="close" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#FF0000;" edge="1" parent="1" source="state_estab" target="state_closed">
          <mxGeometry relative="1" as="geometry">
            <Array as="points">
              <mxPoint x="420" y="380" />
              <mxPoint x="750" y="380" />
              <mxPoint x="750" y="70" />
            </Array>
          </mxGeometry>
        </mxCell>

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML

# Set permissions
chown ga:ga "$DIAGRAM_FILE" "$RFC_FILE"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox '$DIAGRAM_FILE' > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        break
    fi
    sleep 1
done

# Dismiss update dialog (Aggressive)
echo "Dismissing dialogs..."
for i in {1..10}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.2
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="