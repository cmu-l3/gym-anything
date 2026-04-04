#!/bin/bash
set -e

echo "=== Setting up UML Design Pattern Refactoring task ==="

# 1. Create directory structure
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Create the 'Bad' Initial Diagram (Uncompressed XML for readability)
# This represents the "God Class" state
cat > /home/ga/Diagrams/order_system.drawio << 'EOF'
<mxfile host="Electron" modified="2023-10-01T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" etag="r_XX" version="21.6.8" type="device">
  <diagram id="init-diagram" name="Page-1">
    <mxGraphModel dx="1422" dy="808" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- OrderProcessor (God Class) -->
        <mxCell id="2" value="OrderProcessor" style="swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;startSize=26;horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=1;marginBottom=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="320" y="80" width="280" height="300" as="geometry" />
        </mxCell>
        <mxCell id="3" value="- paymentGatewayUrl: String&#xa;- emailServer: String&#xa;- smsGateway: String&#xa;- fedexApiKey: String&#xa;- dhlApiKey: String" style="text;strokeColor=none;fillColor=none;align=left;verticalAlign=top;spacingLeft=4;spacingRight=4;overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];portConstraint=eastwest;whiteSpace=wrap;html=1;" vertex="1" parent="2">
          <mxGeometry y="26" width="280" height="94" as="geometry" />
        </mxCell>
        <mxCell id="4" value="" style="line;strokeWidth=1;fillColor=none;align=left;verticalAlign=middle;spacingTop=-1;spacingLeft=3;spacingRight=3;rotatable=0;labelPosition=right;points=[];portConstraint=eastwest;strokeColor=inherit;" vertex="1" parent="2">
          <mxGeometry y="120" width="280" height="8" as="geometry" />
        </mxCell>
        <mxCell id="5" value="+ processOrder(order): void&#xa;+ processCreditCard(cc): bool&#xa;+ processPayPal(email): bool&#xa;+ processBankTransfer(iban): bool&#xa;+ sendEmail(msg): void&#xa;+ sendSMS(msg): void&#xa;+ logAudit(msg): void&#xa;+ shipFedEx(order): String&#xa;+ shipDHL(order): String" style="text;strokeColor=none;fillColor=none;align=left;verticalAlign=top;spacingLeft=4;spacingRight=4;overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];portConstraint=eastwest;whiteSpace=wrap;html=1;" vertex="1" parent="2">
          <mxGeometry y="128" width="280" height="172" as="geometry" />
        </mxCell>
        <!-- Order Class -->
        <mxCell id="6" value="Order" style="swimlane;fontStyle=1;align=center;verticalAlign=top;childLayout=stackLayout;horizontal=1;startSize=26;horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=1;marginBottom=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="80" y="120" width="160" height="120" as="geometry" />
        </mxCell>
        <mxCell id="7" value="- id: String&#xa;- amount: double" style="text;strokeColor=none;fillColor=none;align=left;verticalAlign=top;spacingLeft=4;spacingRight=4;overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];portConstraint=eastwest;whiteSpace=wrap;html=1;" vertex="1" parent="6">
          <mxGeometry y="26" width="160" height="94" as="geometry" />
        </mxCell>
        <!-- Association -->
        <mxCell id="8" value="" style="endArrow=open;html=1;rounded=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;exitX=1;exitY=0.5;exitDx=0;exitDy=0;" edge="1" parent="1" source="6" target="2">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="240" y="240" as="sourcePoint" />
            <mxPoint x="320" y="230" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Annotation -->
        <mxCell id="9" value="Start Here: This class does too much!" style="shape=note;whiteSpace=wrap;html=1;backgroundOutline=1;darkOpacity=0.05;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="640" y="80" width="140" height="80" as="geometry" />
        </mxCell>
        <mxCell id="10" value="" style="endArrow=none;dashed=1;html=1;rounded=0;exitX=0;exitY=0.5;exitDx=0;exitDy=0;exitPerimeter=0;entryX=1;entryY=0.25;entryDx=0;entryDy=0;" edge="1" parent="1" source="9" target="2">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="630" y="260" as="sourcePoint" />
            <mxPoint x="680" y="210" as="targetPoint" />
          </mxGeometry>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# 4. Create Requirements Document
cat > /home/ga/Desktop/refactoring_review.txt << 'EOF'
================================================================================
       DESIGN REVIEW: Order Processing System — Refactoring Requirements
================================================================================
Reviewer: Sarah Chen, Principal Architect
Date: 2025-10-24
Status: CHANGES REQUIRED

The 'OrderProcessor' class is a "God Class" that violates the Single Responsibility 
Principle. It currently handles payment, notification, and shipping concerns 
all in one place.

Please refactor the UML diagram to apply the following GoF Design Patterns:

1. STRATEGY PATTERN (Payment Processing)
   - Extract payment logic into an interface named 'PaymentStrategy'.
   - Create 3 concrete implementations:
     * 'CreditCardPayment'
     * 'PayPalPayment'
     * 'BankTransferPayment'
   - OrderProcessor should depend on PaymentStrategy.

2. OBSERVER PATTERN (Notifications)
   - Extract notification logic into an interface named 'OrderObserver'.
   - Create 3 concrete implementations:
     * 'EmailNotifier'
     * 'InventoryUpdater'
     * 'AuditLogger'
   - OrderProcessor should maintain a list of OrderObservers.

3. FACTORY METHOD PATTERN (Shipping)
   - Create a 'ShippingProvider' interface.
   - Create 2 concrete providers: 'FedExProvider' and 'DHLProvider'.
   - Create an abstract 'ShippingProviderFactory'.
   - Create 2 concrete factories: 'DomesticShippingFactory' and 'InternationalShippingFactory'.

INSTRUCTIONS:
- Open ~/Diagrams/order_system.drawio
- Add the new classes and interfaces with proper Stereotypes (e.g., <<interface>>, <<abstract>>).
- Draw the correct relationships:
  * Realization (dashed line with hollow triangle) for interface implementation.
  * Association (solid line) for dependencies.
- Remove the old hardcoded methods from OrderProcessor (or mark them as deprecated).
- Export the result to ~/Diagrams/exports/order_system_refactored.png
================================================================================
EOF

# Set permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop

# 5. Launch draw.io
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio || true

# Launch as user 'ga'
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/order_system.drawio > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Handle potential update dialog (common in AppImages)
sleep 5
echo "Attempting to dismiss update dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="