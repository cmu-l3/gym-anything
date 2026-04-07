#!/bin/bash
set -e

echo "=== Setting up merge_project_phases task ==="

# 1. Prepare Directories
PHASE_DIR="/home/ga/Projects/phases"
OUTPUT_DIR="/home/ga/Projects/output"
mkdir -p "$PHASE_DIR"
mkdir -p "$OUTPUT_DIR"

# Ensure output directory is clean
rm -f "$OUTPUT_DIR/full_release.xml"

# 2. Generate Source XML Files (MSPDI Format)
# Frontend Phase
cat > "$PHASE_DIR/frontend_phase.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/project">
    <Name>Frontend Phase</Name>
    <Title>Frontend Phase</Title>
    <Tasks>
        <Task>
            <UID>0</UID><ID>0</ID><Name>Frontend Phase</Name><Type>1</Type><IsNull>0</IsNull><CreateDate>2025-01-01T08:00:00</CreateDate><WBS>0</WBS><OutlineNumber>0</OutlineNumber><OutlineLevel>0</OutlineLevel><Priority>500</Priority><Start>2025-01-01T08:00:00</Start><Finish>2025-01-10T17:00:00</Finish><Duration>PT80H0M0S</Duration><Manual>0</Manual><Summary>1</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
        <Task>
            <UID>1</UID><ID>1</ID><Name>Wireframe Design</Name><Type>0</Type><IsNull>0</IsNull><CreateDate>2025-01-01T08:00:00</CreateDate><WBS>1</WBS><OutlineNumber>1</OutlineNumber><OutlineLevel>1</OutlineLevel><Priority>500</Priority><Start>2025-01-01T08:00:00</Start><Finish>2025-01-03T17:00:00</Finish><Duration>PT24H0M0S</Duration><Manual>0</Manual><Summary>0</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
        <Task>
            <UID>2</UID><ID>2</ID><Name>Login UI Component</Name><Type>0</Type><IsNull>0</IsNull><CreateDate>2025-01-01T08:00:00</CreateDate><WBS>2</WBS><OutlineNumber>2</OutlineNumber><OutlineLevel>1</OutlineLevel><Priority>500</Priority><Start>2025-01-06T08:00:00</Start><Finish>2025-01-08T17:00:00</Finish><Duration>PT24H0M0S</Duration><Manual>0</Manual><Summary>0</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
        <Task>
            <UID>3</UID><ID>3</ID><Name>Dashboard Layout</Name><Type>0</Type><IsNull>0</IsNull><CreateDate>2025-01-01T08:00:00</CreateDate><WBS>3</WBS><OutlineNumber>3</OutlineNumber><OutlineLevel>1</OutlineLevel><Priority>500</Priority><Start>2025-01-08T08:00:00</Start><Finish>2025-01-10T17:00:00</Finish><Duration>PT24H0M0S</Duration><Manual>0</Manual><Summary>0</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
    </Tasks>
    <Resources>
        <Resource><UID>1</UID><ID>1</ID><Name>UI Designer</Name><Type>1</Type><IsNull>0</IsNull><Initials>UD</Initials><MaxUnits>1.00</MaxUnits><PeakUnits>0.00</PeakUnits><OverAllocated>0</OverAllocated><CanLevel>1</CanLevel><AccrueAt>3</AccrueAt><Work>PT0H0M0S</Work><RegularWork>PT0H0M0S</RegularWork><OvertimeWork>PT0H0M0S</OvertimeWork><ActualWork>PT0H0M0S</ActualWork><RemainingWork>PT0H0M0S</RemainingWork><ActualOvertimeWork>PT0H0M0S</ActualOvertimeWork><PercentWorkComplete>0</PercentWorkComplete><StandardRate>50.00</StandardRate><StandardRateFormat>3</StandardRateFormat><Cost>0</Cost><OvertimeRate>0</OvertimeRate><OvertimeRateFormat>3</OvertimeRateFormat><CostPerUse>0</CostPerUse><ActualCost>0</ActualCost><ActualOvertimeCost>0</ActualOvertimeCost><RemainingCost>0</RemainingCost><BCWS>0</BCWS><BCWP>0</BCWP><ACWP>0</ACWP><WorkVariance>0</WorkVariance><CostVariance>0</CostVariance><SV>0</SV><CV>0</CV><ACWP>0</ACWP><CalendarUID>1</CalendarUID><Notes></Notes><Active>1</Active></Resource>
    </Resources>
</Project>
EOF

# Backend Phase
cat > "$PHASE_DIR/backend_phase.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/project">
    <Name>Backend Phase</Name>
    <Title>Backend Phase</Title>
    <Tasks>
        <Task>
            <UID>0</UID><ID>0</ID><Name>Backend Phase</Name><Type>1</Type><IsNull>0</IsNull><CreateDate>2025-02-01T08:00:00</CreateDate><WBS>0</WBS><OutlineNumber>0</OutlineNumber><OutlineLevel>0</OutlineLevel><Priority>500</Priority><Start>2025-02-01T08:00:00</Start><Finish>2025-02-10T17:00:00</Finish><Duration>PT80H0M0S</Duration><Manual>0</Manual><Summary>1</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
        <Task>
            <UID>1</UID><ID>1</ID><Name>Database Schema</Name><Type>0</Type><IsNull>0</IsNull><CreateDate>2025-02-01T08:00:00</CreateDate><WBS>1</WBS><OutlineNumber>1</OutlineNumber><OutlineLevel>1</OutlineLevel><Priority>500</Priority><Start>2025-02-01T08:00:00</Start><Finish>2025-02-03T17:00:00</Finish><Duration>PT16H0M0S</Duration><Manual>0</Manual><Summary>0</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
        <Task>
            <UID>2</UID><ID>2</ID><Name>Auth API Endpoint</Name><Type>0</Type><IsNull>0</IsNull><CreateDate>2025-02-01T08:00:00</CreateDate><WBS>2</WBS><OutlineNumber>2</OutlineNumber><OutlineLevel>1</OutlineLevel><Priority>500</Priority><Start>2025-02-04T08:00:00</Start><Finish>2025-02-07T17:00:00</Finish><Duration>PT32H0M0S</Duration><Manual>0</Manual><Summary>0</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
        <Task>
            <UID>3</UID><ID>3</ID><Name>Data Migration</Name><Type>0</Type><IsNull>0</IsNull><CreateDate>2025-02-01T08:00:00</CreateDate><WBS>3</WBS><OutlineNumber>3</OutlineNumber><OutlineLevel>1</OutlineLevel><Priority>500</Priority><Start>2025-02-08T08:00:00</Start><Finish>2025-02-10T17:00:00</Finish><Duration>PT24H0M0S</Duration><Manual>0</Manual><Summary>0</Summary><PercentComplete>0</PercentComplete><Active>1</Active><Estimated>0</Estimated>
        </Task>
    </Tasks>
    <Resources>
        <Resource><UID>1</UID><ID>1</ID><Name>Backend Dev</Name><Type>1</Type><IsNull>0</IsNull><Initials>BD</Initials><MaxUnits>1.00</MaxUnits><PeakUnits>0.00</PeakUnits><OverAllocated>0</OverAllocated><CanLevel>1</CanLevel><AccrueAt>3</AccrueAt><Work>PT0H0M0S</Work><RegularWork>PT0H0M0S</RegularWork><OvertimeWork>PT0H0M0S</OvertimeWork><ActualWork>PT0H0M0S</ActualWork><RemainingWork>PT0H0M0S</RemainingWork><ActualOvertimeWork>PT0H0M0S</ActualOvertimeWork><PercentWorkComplete>0</PercentWorkComplete><StandardRate>60.00</StandardRate><StandardRateFormat>3</StandardRateFormat><Cost>0</Cost><OvertimeRate>0</OvertimeRate><OvertimeRateFormat>3</OvertimeRateFormat><CostPerUse>0</CostPerUse><ActualCost>0</ActualCost><ActualOvertimeCost>0</ActualOvertimeCost><RemainingCost>0</RemainingCost><BCWS>0</BCWS><BCWP>0</BCWP><ACWP>0</ACWP><WorkVariance>0</WorkVariance><CostVariance>0</CostVariance><SV>0</SV><CV>0</CV><ACWP>0</ACWP><CalendarUID>1</CalendarUID><Notes></Notes><Active>1</Active></Resource>
    </Resources>
</Project>
EOF

chown -R ga:ga "/home/ga/Projects"

# 3. Timestamp for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch Application
# We launch ProjectLibre empty. The agent must open the files.
if ! pgrep -f "projectlibre" > /dev/null; then
    echo "Starting ProjectLibre..."
    su - ga -c "DISPLAY=:1 setsid projectlibre > /tmp/pl.log 2>&1 &"
fi

# 5. Wait for Window and Maximize
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre"; then
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for Java UI
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="