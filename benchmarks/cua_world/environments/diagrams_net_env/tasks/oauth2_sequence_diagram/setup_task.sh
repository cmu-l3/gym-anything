#!/bin/bash
set -e

echo "=== Setting up OAuth 2.0 Sequence Diagram Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create Specification Document
cat > /home/ga/Desktop/oauth2_sequence_spec.txt << 'EOF'
OAuth 2.0 Authorization Code Flow - Engineering Specification
===========================================================
Ref: RFC 6749

PARTICIPANTS:
1. User (Browser)
2. Client Application
3. Authorization Server
4. Token Store (Database/Cache for tokens) - NEW
5. Resource Server (API) - NEW

EXISTING FLOW (Already in diagram):
Steps 1-6: User authorizes client, Authorization Code returned.

MISSING FLOWS TO IMPLEMENT:

Phase 2: Token Exchange (Synchronous)
-------------------------------------
7. Client Application -> Authorization Server: POST /token (grant_type=authorization_code)
8. Authorization Server -> Token Store: Validate code & Generate tokens
9. Token Store --> Authorization Server: (Tokens stored)
10. Authorization Server --> Client Application: 200 OK (access_token, refresh_token)

Phase 3: Resource Access (Synchronous)
--------------------------------------
11. Client Application -> Resource Server: GET /api/data (Authorization: Bearer <token>)
12. Resource Server -> Authorization Server: Introspect Token
13. Authorization Server --> Resource Server: Token Active/Claims

[COMBINED FRAGMENT: 'alt' - Token Validation]
  [Condition: Valid Token]
    14. Resource Server --> Client Application: 200 OK (Protected Resource)
    15. Client Application --> User: Display Data
  [Condition: Invalid Token]
    14b. Resource Server --> Client Application: 401 Unauthorized

NEW PAGE: Token Refresh Flow
----------------------------
Page Name: "Token Refresh Flow"
Participants: Client Application, Authorization Server, Token Store

Flow:
1. Client -> Auth Server: POST /token (grant_type=refresh_token)
2. Auth Server -> Token Store: Validate refresh_token
3. [alt] Valid vs Invalid/Expired
4. Return new access_token to Client

EXPORT REQUIREMENTS:
- Format: SVG
- Path: ~/Diagrams/exports/oauth2_flow.svg
EOF

# 3. Create Starter Draw.io File (Uncompressed XML for readability/compatibility)
# Contains 3 lifelines and 6 messages
cat > /home/ga/Diagrams/oauth2_flow.drawio << 'XML_EOF'
<mxfile host="Electron" modified="2024-03-01T10:00:00.000Z" agent="Mozilla/5.0" version="22.1.0" type="device">
  <diagram id="Page-1" name="Page-1">
    <mxGraphModel dx="1000" dy="1000" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- Lifelines -->
        <mxCell id="L1" value="User (Browser)" style="shape=umlLifeline;perimeter=lifelinePerimeter;whiteSpace=wrap;html=1;container=1;collapsible=0;recursiveResize=0;outlineConnect=0;" vertex="1" parent="1">
          <mxGeometry x="100" y="80" width="100" height="600" as="geometry" />
        </mxCell>
        <mxCell id="L2" value="Client Application" style="shape=umlLifeline;perimeter=lifelinePerimeter;whiteSpace=wrap;html=1;container=1;collapsible=0;recursiveResize=0;outlineConnect=0;" vertex="1" parent="1">
          <mxGeometry x="300" y="80" width="120" height="600" as="geometry" />
        </mxCell>
        <mxCell id="L3" value="Authorization Server" style="shape=umlLifeline;perimeter=lifelinePerimeter;whiteSpace=wrap;html=1;container=1;collapsible=0;recursiveResize=0;outlineConnect=0;" vertex="1" parent="1">
          <mxGeometry x="500" y="80" width="140" height="600" as="geometry" />
        </mxCell>

        <!-- Messages 1-6 -->
        <mxCell id="M1" value="1. Request Resource" style="html=1;verticalAlign=bottom;endArrow=block;rounded=0;" edge="1" parent="1" source="L1" target="L2">
          <mxGeometry width="80" relative="1" as="geometry">
            <mxPoint x="150" y="160" as="sourcePoint" />
            <mxPoint x="360" y="160" as="targetPoint" />
            <Array as="points">
              <mxPoint x="200" y="160" />
            </Array>
          </mxGeometry>
        </mxCell>
        <mxCell id="M2" value="2. 302 Redirect to /authorize" style="html=1;verticalAlign=bottom;endArrow=block;rounded=0;" edge="1" parent="1" source="L2" target="L3">
          <mxGeometry width="80" relative="1" as="geometry">
            <mxPoint x="360" y="200" as="sourcePoint" />
            <mxPoint x="570" y="200" as="targetPoint" />
            <Array as="points">
              <mxPoint x="400" y="200" />
            </Array>
          </mxGeometry>
        </mxCell>
        <mxCell id="M3" value="3. Login Page" style="html=1;verticalAlign=bottom;endArrow=open;dashed=1;endSize=8;rounded=0;" edge="1" parent="1" source="L3" target="L1">
          <mxGeometry width="80" relative="1" as="geometry">
            <mxPoint x="570" y="240" as="sourcePoint" />
            <mxPoint x="150" y="240" as="targetPoint" />
            <Array as="points">
              <mxPoint x="300" y="240" />
            </Array>
          </mxGeometry>
        </mxCell>
        <mxCell id="M4" value="4. Submit Credentials" style="html=1;verticalAlign=bottom;endArrow=block;rounded=0;" edge="1" parent="1" source="L1" target="L3">
          <mxGeometry width="80" relative="1" as="geometry">
            <mxPoint x="150" y="280" as="sourcePoint" />
            <mxPoint x="570" y="280" as="targetPoint" />
            <Array as="points">
              <mxPoint x="300" y="280" />
            </Array>
          </mxGeometry>
        </mxCell>
        <mxCell id="M5" value="5. 302 Redirect (code)" style="html=1;verticalAlign=bottom;endArrow=open;dashed=1;endSize=8;rounded=0;" edge="1" parent="1" source="L3" target="L1">
          <mxGeometry width="80" relative="1" as="geometry">
            <mxPoint x="570" y="320" as="sourcePoint" />
            <mxPoint x="150" y="320" as="targetPoint" />
            <Array as="points">
              <mxPoint x="300" y="320" />
            </Array>
          </mxGeometry>
        </mxCell>
        <mxCell id="M6" value="6. GET callback?code=..." style="html=1;verticalAlign=bottom;endArrow=block;rounded=0;" edge="1" parent="1" source="L1" target="L2">
          <mxGeometry width="80" relative="1" as="geometry">
            <mxPoint x="150" y="360" as="sourcePoint" />
            <mxPoint x="360" y="360" as="targetPoint" />
            <Array as="points">
              <mxPoint x="200" y="360" />
            </Array>
          </mxGeometry>
        </mxCell>

        <!-- TODO Note -->
        <mxCell id="Note1" value="TODO: Complete Token Exchange&#xa;and Resource Access phases&#xa;See: ~/Desktop/oauth2_sequence_spec.txt" style="shape=note;whiteSpace=wrap;html=1;backgroundOutline=1;darkOpacity=0.05;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="650" y="400" width="180" height="100" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML_EOF

# 4. Set Permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop
chmod 644 /home/ga/Diagrams/oauth2_flow.drawio
chmod 644 /home/ga/Desktop/oauth2_sequence_spec.txt

# 5. Record Start State
date +%s > /tmp/task_start_time.txt
# Simple line count as a baseline proxy (since it's XML)
wc -l < /home/ga/Diagrams/oauth2_flow.drawio > /tmp/initial_line_count.txt

# 6. Launch Draw.io
echo "Launching draw.io..."
# Use --no-sandbox for container environments
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/oauth2_flow.drawio > /dev/null 2>&1 &"

# 7. Wait and Handle Update Dialogs (Critical)
sleep 5
echo "Attempting to dismiss potential update dialogs..."
# Try multiple dismissal strategies
for i in {1..5}; do
    # Escape key
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Click generic 'Cancel' location (approximate)
    DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true
done

# 8. Maximize Window
DISPLAY=:1 wmctrl -r "diagrams.net" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Alternative window name match
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="