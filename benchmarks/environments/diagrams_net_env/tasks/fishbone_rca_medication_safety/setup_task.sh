#!/bin/bash
set -e

echo "=== Setting up Fishbone RCA Task ==="

# Define paths
DIAGRAM_DIR="/home/ga/Diagrams"
EXPORT_DIR="/home/ga/Diagrams/exports"
DESKTOP_DIR="/home/ga/Desktop"
DIAGRAM_FILE="$DIAGRAM_DIR/medication_rca.drawio"
REPORT_FILE="$DESKTOP_DIR/incident_investigation_report.txt"

# Create directories
mkdir -p "$DIAGRAM_DIR" "$EXPORT_DIR" "$DESKTOP_DIR"

# 1. Create the Incident Investigation Report
cat > "$REPORT_FILE" << 'EOF'
INCIDENT INVESTIGATION REPORT
Incident ID: RCA-2024-0847
Date: October 14, 2024
Event: Medication Dosing Error - 10x Heparin Overdose
Patient Impact: Temporary coagulation abnormality, reversed with protamine, no permanent harm.

ROOT CAUSE ANALYSIS FINDINGS (Categorized)

1. PEOPLE / STAFF FACTORS
- Nurse fatigue: Administering nurse was on 3rd consecutive 12-hour night shift.
- Failure to verify: Pharmacist verified order without cross-checking weight-based protocol.
- Ambiguous order: Resident wrote order as "bolus" without specifying units clearly.
- No independent double-check: Second nurse signed off without actually viewing the pump settings ("visual confirmation only").

2. PROCESS / PROCEDURES
- Protocol deviation: No standardized weight-based heparin protocol was available in the unit.
- BCMA failure: Barcode medication administration (BCMA) scanner was bypassed due to low battery.
- Verbal order: Order was given verbally during emergency and not read back.
- No Time-out: No high-alert medication "time-out" performed prior to administration.

3. EQUIPMENT / TECHNOLOGY
- Smart Pump configuration: "Guardrails" (soft limits) for Heparin were not configured in the library.
  > Why? Drug library had not been updated in 18 months.
  > Why? No clear ownership between Pharmacy and Biomed.
- Alert fatigue: Clinicians override 95% of alerts due to high volume of nuisance alarms.
- Automated Dispensing Cabinet: No "High Alert" warning popup configured for Heparin retrieval.

4. ENVIRONMENT
- Poor lighting: Medication preparation area light was flickering/dim.
- Noise levels: High ambient noise/overhead paging during preparation.
- Interruptions: Nurse was interrupted 3 times during programming of the pump.
- Workspace: Cluttered medication room counter led to confusion.

5. MATERIALS / MEDICATION
- Look-Alike Sound-Alike (LASA): 10,000 units/mL and 1,000 units/mL vials look nearly identical.
- Stocking: Multiple concentrations of Heparin stocked in the same bin.
- Labeling: "Tall-man" lettering not used on vial labels to distinguish concentrations.
- Packaging: Manufacturer changed vial cap color recently, causing confusion.

6. MANAGEMENT / POLICY
- Policy gap: No specific policy for high-alert medication handling in ED.
- Staffing ratios: Unit was exceeding recommended nurse-to-patient ratios (1:6 vs 1:4).
  > Why? Sick calls were not backfilled.
- Fatigue management: No mandatory rest period policy for consecutive shifts.
- Reporting culture: Near-misses with Heparin previously unreported/ignored.

RECOMMENDATIONS
- Immediate implementation of independent double-check.
- Standardize Heparin concentrations.
- Update Smart Pump libraries immediately.
EOF

# 2. Create the Skeleton Fishbone Diagram (XML)
# This creates a basic fishbone with the spine, head, and category labels but no causes.
cat > "$DIAGRAM_FILE" << 'XML_EOF'
<mxfile host="Electron" modified="2024-10-15T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.0.0 Chrome/120.0.0.0 Electron/28.0.0 Safari/537.36" etag="xyz" version="24.0.0" type="device">
  <diagram id="RCA-Fishbone" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Head / Effect -->
        <mxCell id="head" value="Medication Dosing Error&#xa;10x Heparin Overdose" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;fontStyle=1;fontSize=14;" vertex="1" parent="1">
          <mxGeometry x="960" y="360" width="180" height="80" as="geometry" />
        </mxCell>
        <!-- Spine -->
        <mxCell id="spine" value="" style="endArrow=classic;html=1;strokeWidth=4;endSize=8;" edge="1" parent="1" source="tail_point" target="head">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="160" y="400" as="sourcePoint" />
            <mxPoint x="960" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="tail_point" value="" style="ellipse;whiteSpace=wrap;html=1;aspect=fixed;fillColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="120" y="395" width="10" height="10" as="geometry" />
        </mxCell>
        <!-- Category: People -->
        <mxCell id="cat1_label" value="PEOPLE / STAFF" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="200" y="120" width="140" height="40" as="geometry" />
        </mxCell>
        <mxCell id="cat1_line" value="" style="endArrow=none;html=1;strokeWidth=2;entryX=0.25;entryY=0.5;entryDx=0;entryDy=0;entryPerimeter=0;" edge="1" parent="1" source="cat1_label" target="spine">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="270" y="160" as="sourcePoint" />
            <mxPoint x="320" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Category: Process -->
        <mxCell id="cat2_label" value="PROCESS" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="450" y="120" width="140" height="40" as="geometry" />
        </mxCell>
        <mxCell id="cat2_line" value="" style="endArrow=none;html=1;strokeWidth=2;" edge="1" parent="1" source="cat2_label" target="spine">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="520" y="160" as="sourcePoint" />
            <mxPoint x="550" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Category: Equipment -->
        <mxCell id="cat3_label" value="EQUIPMENT" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="700" y="120" width="140" height="40" as="geometry" />
        </mxCell>
        <mxCell id="cat3_line" value="" style="endArrow=none;html=1;strokeWidth=2;" edge="1" parent="1" source="cat3_label" target="spine">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="770" y="160" as="sourcePoint" />
            <mxPoint x="780" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Category: Environment -->
        <mxCell id="cat4_label" value="ENVIRONMENT" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="200" y="640" width="140" height="40" as="geometry" />
        </mxCell>
        <mxCell id="cat4_line" value="" style="endArrow=none;html=1;strokeWidth=2;" edge="1" parent="1" source="cat4_label" target="spine">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="270" y="640" as="sourcePoint" />
            <mxPoint x="320" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Category: Materials -->
        <mxCell id="cat5_label" value="MATERIALS" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="450" y="640" width="140" height="40" as="geometry" />
        </mxCell>
        <mxCell id="cat5_line" value="" style="endArrow=none;html=1;strokeWidth=2;" edge="1" parent="1" source="cat5_label" target="spine">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="520" y="640" as="sourcePoint" />
            <mxPoint x="550" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Category: Management -->
        <mxCell id="cat6_label" value="MANAGEMENT" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="700" y="640" width="140" height="40" as="geometry" />
        </mxCell>
        <mxCell id="cat6_line" value="" style="endArrow=none;html=1;strokeWidth=2;" edge="1" parent="1" source="cat6_label" target="spine">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="770" y="640" as="sourcePoint" />
            <mxPoint x="780" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML_EOF

# Set permissions
chown -R ga:ga "$DIAGRAM_DIR" "$DESKTOP_DIR"
chmod 644 "$DIAGRAM_FILE" "$REPORT_FILE"

# Record initial state for verification
# Count vertices that are NOT the root or background
INITIAL_SHAPES=$(grep -c '<mxCell' "$DIAGRAM_FILE" || echo "0")
echo "$INITIAL_SHAPES" > /tmp/initial_shape_count
date +%s > /tmp/task_start_time

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox '$DIAGRAM_FILE' > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

# Dismiss update dialog (common in AppImage)
# Try Escape multiple times
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "Setup complete."