#!/bin/bash
set -e
echo "=== Setting up Customer Journey Map task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
su - ga -c "mkdir -p /home/ga/Diagrams/exports"
su - ga -c "mkdir -p /home/ga/Desktop"

# Create the starting drawio file (scaffold only)
# Using a template with headers and row labels but empty content
cat > /home/ga/Diagrams/return_journey.drawio << 'DRAWIOEOF'
<mxfile host="Electron" modified="2024-03-01T10:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" version="21.6.8" type="device">
  <diagram id="journey-map-1" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1654" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="title" value="&lt;b&gt;E-Commerce Product Return: Customer Journey Map&lt;/b&gt;" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=18;" vertex="1" parent="1">
          <mxGeometry x="327" y="10" width="1000" height="40" as="geometry" />
        </mxCell>
        <mxCell id="legend" value="&lt;b&gt;Emotion Colors:&lt;/b&gt;&lt;br&gt;🟢 Positive (#d5e8d4)&lt;br&gt;🟡 Neutral (#fff2cc)&lt;br&gt;🔴 Negative (#f8cecc)" style="text;html=1;strokeColor=#666666;fillColor=#f5f5f5;align=left;verticalAlign=top;whiteSpace=wrap;rounded=1;fontSize=10;fontColor=#333333;" vertex="1" parent="1">
          <mxGeometry x="1370" y="10" width="170" height="70" as="geometry" />
        </mxCell>
        <mxCell id="s1" value="&lt;b&gt;Discover Return Policy&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="220" y="70" width="210" height="40" as="geometry" />
        </mxCell>
        <mxCell id="s2" value="&lt;b&gt;Initiate Return&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="450" y="70" width="210" height="40" as="geometry" />
        </mxCell>
        <mxCell id="s3" value="&lt;b&gt;Prepare &amp;amp; Ship&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="680" y="70" width="210" height="40" as="geometry" />
        </mxCell>
        <mxCell id="s4" value="&lt;b&gt;Await Processing&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="910" y="70" width="210" height="40" as="geometry" />
        </mxCell>
        <mxCell id="s5" value="&lt;b&gt;Receive Resolution&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="1140" y="70" width="210" height="40" as="geometry" />
        </mxCell>
        <mxCell id="r1" value="&lt;b&gt;Customer Actions&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="20" y="130" width="180" height="80" as="geometry" />
        </mxCell>
        <mxCell id="r2" value="&lt;b&gt;Touchpoints / Channels&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="20" y="230" width="180" height="80" as="geometry" />
        </mxCell>
        <mxCell id="r3" value="&lt;b&gt;Emotional State&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="20" y="330" width="180" height="80" as="geometry" />
        </mxCell>
        <mxCell id="r4" value="&lt;b&gt;Pain Points&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="20" y="430" width="180" height="80" as="geometry" />
        </mxCell>
        <mxCell id="r5" value="&lt;b&gt;Opportunities&lt;/b&gt;" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="20" y="530" width="180" height="80" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
DRAWIOEOF
chown ga:ga /home/ga/Diagrams/return_journey.drawio

# Create the specification file
cat > /home/ga/Desktop/return_journey_spec.txt << 'SPECEOF'
============================================================
E-COMMERCE PRODUCT RETURN: CUSTOMER JOURNEY MAP SPECIFICATION
Based on Baymard Institute, NNGroup, and Narvar Research
============================================================

COLOR CODING LEGEND (Emotional State row):
  Positive  → Green fill (#d5e8d4, border #82b366)
  Neutral   → Yellow fill (#fff2cc, border #d6b656)
  Negative  → Red fill   (#f8cecc, border #b85450)

============================================================
STAGE 1: DISCOVER RETURN POLICY
============================================================

Customer Actions:
  "Search for return policy link on product page and site footer;
   Read return window, conditions, and restocking fees;
   Check if free return shipping is offered"

Touchpoints / Channels:
  "Product detail page, FAQ section, footer links,
   mobile app policy screen, order confirmation email"

Emotional State: NEUTRAL
  "Cautious and evaluating — 67% of shoppers check returns
   page before buying (Narvar 2023)"

Pain Points:
  "Return policy buried in footer or legal pages;
   Ambiguous language about 'acceptable condition';
   No mention of who pays return shipping"

Opportunities:
  "Surface return policy summary on product pages;
   Use plain language instead of legal jargon;
   Display free returns badge prominently"

============================================================
STAGE 2: INITIATE RETURN
============================================================

Customer Actions:
  "Log into account and locate order history;
   Select item and reason for return;
   Choose refund vs exchange vs store credit"

Touchpoints / Channels:
  "Account dashboard, order history page,
   return request form, customer service chat,
   automated email confirmation"

Emotional State: NEGATIVE
  "Frustrated — 46% of sites make the return initiation
   process unnecessarily complex (Baymard 2023)"

Pain Points:
  "Forced to call customer service instead of self-serve;
   Return reason dropdown lacks relevant options;
   Unclear whether item qualifies for return"

Opportunities:
  "One-click return initiation from order history;
   Smart reason categorization with free-text option;
   Real-time eligibility checker before submission"

============================================================
STAGE 3: PREPARE & SHIP
============================================================

Customer Actions:
  "Print return shipping label;
   Repackage item in original or suitable packaging;
   Drop off at carrier location or schedule pickup"

Touchpoints / Channels:
  "Email with return label PDF, carrier website,
   carrier drop-off location, QR code for label-free return,
   packaging instructions page"

Emotional State: NEUTRAL
  "Inconvenienced but manageable — effort depends on
   whether pre-paid label and packaging are provided"

Pain Points:
  "No printer available for return label;
   Original packaging discarded — unclear requirements;
   Nearest drop-off location is far away"

Opportunities:
  "QR-code label-free returns at carrier locations;
   Provide packaging guidelines with visual examples;
   Offer home pickup scheduling integration"

============================================================
STAGE 4: AWAIT PROCESSING
============================================================

Customer Actions:
  "Track return shipment via carrier;
   Check email for warehouse receipt confirmation;
   Monitor account for refund status updates"

Touchpoints / Channels:
  "Carrier tracking page, email notifications,
   account returns dashboard, SMS status updates,
   customer service inquiry"

Emotional State: NEGATIVE
  "Anxious — average processing takes 5-10 business days;
   lack of proactive updates is the #1 return complaint"

Pain Points:
  "No confirmation when warehouse receives package;
   Refund timeline is vague or not communicated;
   Status page shows no updates for days"

Opportunities:
  "Proactive SMS/email at each processing milestone;
   Real-time returns dashboard with estimated dates;
   Instant refund on carrier scan (pre-trust model)"

============================================================
STAGE 5: RECEIVE RESOLUTION
============================================================

Customer Actions:
  "Receive refund notification;
   Verify refund amount on payment statement;
   Decide whether to repurchase or shop elsewhere"

Touchpoints / Channels:
  "Refund confirmation email, bank/credit card statement,
   store credit notification, post-return survey,
   personalized repurchase recommendations"

Emotional State: POSITIVE
  "Relieved and satisfied if process was smooth —
   92% will buy again if returns are easy (Narvar 2023)"

Pain Points:
  "Refund amount less than expected due to restocking fee;
   Store credit issued instead of original payment refund;
   No acknowledgment or apology for the inconvenience"

Opportunities:
  "Transparent refund breakdown with line items;
   Loyalty bonus or discount for return inconvenience;
   Post-return survey to capture improvement feedback"

============================================================
REQUIRED CROSS-ROW CONNECTIONS (minimum 5 arrows):
============================================================
Draw arrows connecting these related elements:
1. Stage 1 Pain Point "policy buried" → Stage 1 Opportunity "surface on product pages"
2. Stage 2 Pain Point "forced to call" → Stage 2 Opportunity "one-click return"
3. Stage 3 Pain Point "no printer" → Stage 3 Opportunity "QR-code label-free"
4. Stage 4 Pain Point "no confirmation" → Stage 4 Opportunity "proactive SMS/email"
5. Stage 5 Pain Point "store credit instead" → Stage 5 Opportunity "transparent refund breakdown"
============================================================
SPECEOF
chown ga:ga /home/ga/Desktop/return_journey_spec.txt

# Count initial shapes for verification baseline
INITIAL_SHAPES=$(grep -o '<mxCell' /home/ga/Diagrams/return_journey.drawio | wc -l)
echo "$INITIAL_SHAPES" > /tmp/initial_shape_count.txt
echo "Initial shape count: $INITIAL_SHAPES"

# Kill any existing draw.io processes
pkill -f "drawio" 2>/dev/null || true
sleep 2

# Launch draw.io with the template file
echo "Launching draw.io with return_journey.drawio..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/return_journey.drawio > /tmp/drawio.log 2>&1 &"
sleep 8

# Dismiss update dialog if present (common issue in draw.io automation)
for i in 1 2 3 4 5; do
    if DISPLAY=:1 wmctrl -l | grep -qi "update\|confirm"; then
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 0.5
    fi
done

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw\|diagram"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "diagrams" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "draw" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="