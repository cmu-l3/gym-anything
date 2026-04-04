#!/bin/bash
set -e

echo "=== Setting up GDPR Data Lineage Task ==="

# 1. create directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Starter Diagram (XML)
# Contains "Data Collection Layer" with Customer, Website, App, Call Center
cat > /home/ga/Diagrams/gdpr_data_lineage.drawio << 'EOF'
<mxfile host="Electron" modified="2023-10-01T12:00:00.000Z" agent="Mozilla/5.0" version="21.6.8" type="device">
  <diagram id="Page-1" name="Data Lineage">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="2" value="Data Subject (Customer)" style="shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;html=1;outlineConnect=0;" vertex="1" parent="1">
          <mxGeometry x="80" y="240" width="30" height="60" as="geometry" />
        </mxCell>
        <mxCell id="3" value="Data Collection Layer" style="swimlane;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="200" y="80" width="200" height="400" as="geometry" />
        </mxCell>
        <mxCell id="4" value="Website Registration" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="3">
          <mxGeometry x="20" y="60" width="160" height="60" as="geometry" />
        </mxCell>
        <mxCell id="5" value="Mobile App Onboarding" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="3">
          <mxGeometry x="20" y="170" width="160" height="60" as="geometry" />
        </mxCell>
        <mxCell id="6" value="Customer Service Call Center" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="3">
          <mxGeometry x="20" y="280" width="160" height="60" as="geometry" />
        </mxCell>
        <mxCell id="7" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="4">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="8" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="5">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="9" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="6">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="10" value="ACME E-Commerce Ltd - GDPR Data Map" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=18;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="200" y="20" width="400" height="30" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# 3. Create Requirements Document
cat > /home/ga/Desktop/gdpr_processing_inventory.txt << 'EOF'
GDPR ARTICLE 30 RECORD OF PROCESSING ACTIVITIES (ROPA) - INVENTORY
ACME E-Commerce Ltd

SYSTEM INVENTORY & DATA FLOWS:

1. CRM System (Salesforce)
   - Source: Website, Mobile App
   - Data: Name, Email, Address, Phone
   - Legal Basis: Art. 6(1)(b) Contract (Account Management)
   - Retention: Duration of account + 2 years
   - Sensitivity: Blue (Contact)

2. Payment Processing Gateway
   - Source: Website Checkout
   - Data: Credit Card Number, CVV, Expiry
   - Legal Basis: Art. 6(1)(b) Contract (Payment Performance)
   - Retention: 7 years (Tax obligation)
   - Sensitivity: Orange (Financial)

3. Third-Party Processor: Stripe (US)
   - Role: Payment Processor
   - Source: Payment Processing Gateway
   - Transfer Mechanism: Standard Contractual Clauses (SCCs)
   - Retention: Per contract (7 years)

4. Order Management System
   - Source: Website, App
   - Data: Order history, Shipping address
   - Legal Basis: Art. 6(1)(b) Contract
   - Retention: 10 years (Warranty/Recall)

5. Email Marketing Platform (Internal)
   - Source: CRM
   - Data: Email, Name, Preferences
   - Legal Basis: Art. 6(1)(a) Consent (Newsletter)
   - Retention: Until Consent Withdrawn
   
6. Third-Party Processor: Mailchimp (US)
   - Role: Email Delivery
   - Source: Email Marketing Platform
   - Transfer Mechanism: SCCs
   - Sensitivity: Blue

7. Analytics & Reporting Engine
   - Source: Website Cookies, App Events
   - Data: IP Address, Device ID, Browsing Behavior
   - Legal Basis: Art. 6(1)(f) Legitimate Interest (Fraud prevention) or Consent (Cookies)
   - Sensitivity: Green (Behavioral)

8. Third-Party Processor: Google Analytics (US)
   - Role: Analytics Provider
   - Source: Analytics Engine
   - Transfer Mechanism: EU-US Data Privacy Framework / SCCs
   - Retention: 26 months

9. Third-Party Processor: AWS EU-West-1 (Ireland)
   - Role: Cloud Hosting Provider for all internal systems
   - Note: Intra-EU transfer (No additional mechanism needed)

10. Third-Party Processor: Zendesk (US/EU)
    - Role: Customer Support Ticketing
    - Source: Call Center
    - Data: Support tickets, Voice recordings
    - Legal Basis: Art. 6(1)(f) Legitimate Interest (Service Improvement)
    - Retention: 3 years

11. HR System
    - Data: Employee records (who accessed customer data)
    - Source: Internal Logs
    - Sensitivity: Red (contains some health data for sick leave, though not used in this flow)

INSTRUCTIONS FOR DIAGRAM:
- Visualize all systems above.
- Color code shapes based on Sensitivity.
- Add text labels to shapes with Legal Basis and Retention.
- Label arrows with data categories.
- Create a specific page for "Cross-Border Transfers" detailing the US transfers (Stripe, Mailchimp, Google, Zendesk).
EOF

# Set permissions
chown ga:ga /home/ga/Diagrams/gdpr_data_lineage.drawio
chown ga:ga /home/ga/Desktop/gdpr_processing_inventory.txt
chmod 644 /home/ga/Diagrams/gdpr_data_lineage.drawio
chmod 644 /home/ga/Desktop/gdpr_processing_inventory.txt

# Remove any previous exports
rm -f /home/ga/Diagrams/gdpr_data_lineage.pdf

# Record Task Start Time
date +%s > /tmp/task_start_time.txt

# Record Initial File Stats
stat -c %s /home/ga/Diagrams/gdpr_data_lineage.drawio > /tmp/initial_file_size.txt
echo "1" > /tmp/initial_page_count.txt # We know start has 1 page

# Launch draw.io with the file
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/gdpr_data_lineage.drawio &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io" | grep -v "grep"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Dismiss Update Dialog (Aggressive)
echo "Attempting to dismiss update dialogs..."
for i in {1..5}; do
    # Try Escape
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
    # Try Tab -> Enter (Cancel button usually)
    DISPLAY=:1 xdotool key Tab
    sleep 0.1
    DISPLAY=:1 xdotool key Return
    sleep 0.5
done

# Maximize Window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="