#!/bin/bash
set -e
echo "=== Exporting conformance test results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size.txt 2>/dev/null || echo "0")
INITIAL_WINDOW_COUNT=$(cat /tmp/initial_window_count.txt 2>/dev/null || echo "0")

# --- Device Detection via New Log Lines ---
# Only analyze log lines written AFTER the task started
LOG_FILE="/home/ga/openice/logs/openice.log"
NEW_LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    CURRENT_LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    if [ "$CURRENT_LOG_SIZE" -gt "$INITIAL_LOG_SIZE" ]; then
        # Extract new content
        NEW_LOG_CONTENT=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")
    fi
fi

# Device 1: Multiparameter Monitor
MONITOR_IN_LOG=false
if echo "$NEW_LOG_CONTENT" | grep -qiE "multiparameter|multi.parameter|multi.param.*monitor"; then
    MONITOR_IN_LOG=true
fi

# Device 2: NIBP / Noninvasive Blood Pressure
NIBP_IN_LOG=false
if echo "$NEW_LOG_CONTENT" | grep -qiE "nibp|noninvasive|non.invasive|blood.pressure"; then
    NIBP_IN_LOG=true
fi

# Vital Signs app
VITALS_IN_LOG=false
if echo "$NEW_LOG_CONTENT" | grep -qiE "vital|vitalsign|vital.sign"; then
    VITALS_IN_LOG=true
fi

# --- Device Detection via Window Titles ---
# OpenICE creates specific windows for devices
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
CURRENT_WINDOW_COUNT=$(echo "$CURRENT_WINDOWS" | wc -l)

MONITOR_IN_WINDOW=false
if echo "$CURRENT_WINDOWS" | grep -qiE "multiparameter|multi.parameter"; then
    MONITOR_IN_WINDOW=true
fi

NIBP_IN_WINDOW=false
if echo "$CURRENT_WINDOWS" | grep -qiE "nibp|noninvasive|non.invasive|blood.pressure"; then
    NIBP_IN_WINDOW=true
fi

VITALS_IN_WINDOW=false
if echo "$CURRENT_WINDOWS" | grep -qiE "vital|vitalsign"; then
    VITALS_IN_WINDOW=true
fi

WINDOW_INCREASE=$((CURRENT_WINDOW_COUNT - INITIAL_WINDOW_COUNT))

# --- Screenshot Evidence ---
SCREENSHOT_VITALS_EXISTS=false
SCREENSHOT_VITALS_SIZE=0
SCREENSHOT_VITALS_MTIME=0
if [ -f "/home/ga/Desktop/conformance_evidence_vitals.png" ]; then
    SCREENSHOT_VITALS_EXISTS=true
    SCREENSHOT_VITALS_SIZE=$(stat -c%s "/home/ga/Desktop/conformance_evidence_vitals.png" 2>/dev/null || echo "0")
    SCREENSHOT_VITALS_MTIME=$(stat -c%Y "/home/ga/Desktop/conformance_evidence_vitals.png" 2>/dev/null || echo "0")
fi

SCREENSHOT_DEVICES_EXISTS=false
SCREENSHOT_DEVICES_SIZE=0
SCREENSHOT_DEVICES_MTIME=0
if [ -f "/home/ga/Desktop/conformance_evidence_devices.png" ]; then
    SCREENSHOT_DEVICES_EXISTS=true
    SCREENSHOT_DEVICES_SIZE=$(stat -c%s "/home/ga/Desktop/conformance_evidence_devices.png" 2>/dev/null || echo "0")
    SCREENSHOT_DEVICES_MTIME=$(stat -c%Y "/home/ga/Desktop/conformance_evidence_devices.png" 2>/dev/null || echo "0")
fi

# --- Report Analysis ---
REPORT_FILE="/home/ga/Desktop/dec_conformance_report.txt"
REPORT_EXISTS=false
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT=""

# Section detection flags
SECTION_TEST_ID=false
SECTION_DUT=false
SECTION_DOC=false
SECTION_DATAFLOW=false
SECTION_CONFORMANCE=false

# Content quality flags
HAS_BOTH_DEVICES=false
HAS_IHE_ROLES=false
HAS_DDS_REFERENCE=false
HAS_VERDICT=false

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    # Read content for analysis
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null || echo "")

    # Section checks (flexible matching)
    if echo "$REPORT_CONTENT" | grep -qiE "test.identification|test.id|test id"; then
        SECTION_TEST_ID=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "device.under.test|dut|device.inventory"; then
        SECTION_DUT=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "clinical.application|observation.consumer|doc.config"; then
        SECTION_DOC=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "data.flow|verification.result|flow.verification"; then
        SECTION_DATAFLOW=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "conformance.assessment|overall.result|overall.conformance"; then
        SECTION_CONFORMANCE=true
    fi

    # Content quality checks
    HAS_MONITOR_REF=false
    HAS_NIBP_REF=false
    if echo "$REPORT_CONTENT" | grep -qiE "multiparameter|multi.parameter"; then
        HAS_MONITOR_REF=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "nibp|noninvasive|non.invasive|blood.pressure"; then
        HAS_NIBP_REF=true
    fi
    if [ "$HAS_MONITOR_REF" = true ] && [ "$HAS_NIBP_REF" = true ]; then
        HAS_BOTH_DEVICES=true
    fi

    if echo "$REPORT_CONTENT" | grep -qiE "dor|device.observation.reporter"; then
        HAS_IHE_ROLES=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "dds|data.distribution.service"; then
        HAS_DDS_REFERENCE=true
    fi
    if echo "$REPORT_CONTENT" | grep -qiE "pass|fail"; then
        HAS_VERDICT=true
    fi
fi

# Count detected sections
SECTION_COUNT=0
[ "$SECTION_TEST_ID" = true ] && SECTION_COUNT=$((SECTION_COUNT + 1))
[ "$SECTION_DUT" = true ] && SECTION_COUNT=$((SECTION_COUNT + 1))
[ "$SECTION_DOC" = true ] && SECTION_COUNT=$((SECTION_COUNT + 1))
[ "$SECTION_DATAFLOW" = true ] && SECTION_COUNT=$((SECTION_COUNT + 1))
[ "$SECTION_CONFORMANCE" = true ] && SECTION_COUNT=$((SECTION_COUNT + 1))

# --- Build Result JSON ---
# Create safely in temp then move
cat > /tmp/result_temp.json << ENDJSON
{
    "task_start_time": $TASK_START,
    "devices": {
        "monitor_in_log": $MONITOR_IN_LOG,
        "monitor_in_window": $MONITOR_IN_WINDOW,
        "nibp_in_log": $NIBP_IN_LOG,
        "nibp_in_window": $NIBP_IN_WINDOW
    },
    "clinical_app": {
        "vitals_in_log": $VITALS_IN_LOG,
        "vitals_in_window": $VITALS_IN_WINDOW
    },
    "windows": {
        "initial_count": $INITIAL_WINDOW_COUNT,
        "final_count": $CURRENT_WINDOW_COUNT,
        "increase": $WINDOW_INCREASE
    },
    "screenshots": {
        "vitals": {
            "exists": $SCREENSHOT_VITALS_EXISTS,
            "size": $SCREENSHOT_VITALS_SIZE,
            "mtime": $SCREENSHOT_VITALS_MTIME
        },
        "devices": {
            "exists": $SCREENSHOT_DEVICES_EXISTS,
            "size": $SCREENSHOT_DEVICES_SIZE,
            "mtime": $SCREENSHOT_DEVICES_MTIME
        }
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "mtime": $REPORT_MTIME,
        "sections": {
            "test_identification": $SECTION_TEST_ID,
            "device_under_test": $SECTION_DUT,
            "clinical_application": $SECTION_DOC,
            "data_flow": $SECTION_DATAFLOW,
            "conformance_assessment": $SECTION_CONFORMANCE,
            "count": $SECTION_COUNT
        },
        "content_quality": {
            "has_both_devices": $HAS_BOTH_DEVICES,
            "has_ihe_roles": $HAS_IHE_ROLES,
            "has_dds_reference": $HAS_DDS_REFERENCE,
            "has_verdict": $HAS_VERDICT
        }
    }
}
ENDJSON

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_temp.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/result_temp.json

echo "=== Result exported to /tmp/task_result.json ==="
cat /tmp/task_result.json