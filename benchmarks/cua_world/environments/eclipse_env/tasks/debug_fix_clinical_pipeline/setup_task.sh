#!/bin/bash
echo "=== Setting up Debug Fix Clinical Pipeline Task ==="
source /workspace/scripts/task_utils.sh

# ── Copy project to home directory ──────────────────────────────────────────
echo "[SETUP] Copying clinical-trial-analytics to /home/ga/..."
rm -rf /home/ga/clinical-trial-analytics
cp -r /workspace/data/clinical-trial-analytics /home/ga/clinical-trial-analytics
chown -R ga:ga /home/ga/clinical-trial-analytics

# ── Delete any stale outputs BEFORE recording timestamp ─────────────────────
rm -f /tmp/clinical_pipeline_result.json
rm -f /tmp/mvn_output.txt
rm -f /tmp/task_start_timestamp

# ── Record start timestamp ──────────────────────────────────────────────────
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# ── Record initial baselines for delta comparison ───────────────────────────
# Snapshot of the buggy code so we can detect what the agent changed
INITIAL_FILTER_HASH=$(md5sum /home/ga/clinical-trial-analytics/trial-engine/src/main/java/com/clinicaltrial/engine/PatientFilter.java 2>/dev/null | awk '{print $1}')
echo "$INITIAL_FILTER_HASH" > /tmp/initial_filter_hash

INITIAL_ANALYZER_HASH=$(md5sum /home/ga/clinical-trial-analytics/trial-engine/src/main/java/com/clinicaltrial/engine/StatisticalAnalyzer.java 2>/dev/null | awk '{print $1}')
echo "$INITIAL_ANALYZER_HASH" > /tmp/initial_analyzer_hash

INITIAL_SUMMARY_HASH=$(md5sum /home/ga/clinical-trial-analytics/trial-model/src/main/java/com/clinicaltrial/model/TrialSummary.java 2>/dev/null | awk '{print $1}')
echo "$INITIAL_SUMMARY_HASH" > /tmp/initial_summary_hash

INITIAL_REPORT_POM_HASH=$(md5sum /home/ga/clinical-trial-analytics/trial-report/pom.xml 2>/dev/null | awk '{print $1}')
echo "$INITIAL_REPORT_POM_HASH" > /tmp/initial_report_pom_hash

# Count initial Java files
INITIAL_JAVA_COUNT=$(find /home/ga/clinical-trial-analytics -name "*.java" -type f 2>/dev/null | wc -l)
echo "$INITIAL_JAVA_COUNT" > /tmp/initial_java_count
echo "Initial Java file count: $INITIAL_JAVA_COUNT"

# ── Ensure Eclipse is running and display is ready ──────────────────────────
ensure_display_ready
wait_for_eclipse 60 || echo "WARNING: Eclipse not detected within 60s"
focus_eclipse_window
dismiss_dialogs 3
close_welcome_tab
sleep 2

# ── Take initial screenshot ─────────────────────────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
