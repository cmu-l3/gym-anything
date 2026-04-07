#!/bin/bash
echo "=== Exporting Debug Fix Clinical Pipeline Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/clinical-trial-analytics"

# Helper: grep -c returns exit code 1 when count is 0; suppress that.
gcount() { grep -c "$@" 2>/dev/null || true; }

# ── Bug 1: PatientFilter — check for > instead of >= ───────────────────────
BUG1_FIXED="false"
FILTER_FILE="$PROJECT_DIR/trial-engine/src/main/java/com/clinicaltrial/engine/PatientFilter.java"
if [ -f "$FILTER_FILE" ]; then
    HAS_GTE=$(gcount "getWeeksEnrolled().*>=.*getMinWeeks" "$FILTER_FILE")
    HAS_GT=$(gcount "getWeeksEnrolled().*>.*getMinWeeks" "$FILTER_FILE")
    if [ "$HAS_GTE" = "0" ] && [ "$HAS_GT" != "0" ]; then
        BUG1_FIXED="true"
    fi
fi

# ── Bug 2: StatisticalAnalyzer — check for computePopulationBaseline ───────
BUG2_FIXED="false"
ANALYZER_FILE="$PROJECT_DIR/trial-engine/src/main/java/com/clinicaltrial/engine/StatisticalAnalyzer.java"
if [ -f "$ANALYZER_FILE" ]; then
    HAS_POPULATION=$(gcount "computePopulationBaseline" "$ANALYZER_FILE")
    if [ "$HAS_POPULATION" != "0" ]; then
        BUG2_FIXED="true"
    fi
fi

# ── Bug 3: TrialSummary Builder — check for sampleSize copy ────────────────
BUG3_FIXED="false"
SUMMARY_FILE="$PROJECT_DIR/trial-model/src/main/java/com/clinicaltrial/model/TrialSummary.java"
if [ -f "$SUMMARY_FILE" ]; then
    HAS_SAMPLE_COPY=$(gcount "s\.sampleSize.*=.*this\.sampleSize" "$SUMMARY_FILE")
    if [ "$HAS_SAMPLE_COPY" != "0" ]; then
        BUG3_FIXED="true"
    fi
fi

# ── Build config: trial-report Java version ─────────────────────────────────
BUILD_CONFIG_FIXED="false"
REPORT_POM="$PROJECT_DIR/trial-report/pom.xml"
if [ -f "$REPORT_POM" ]; then
    HAS_JAVA17=$(gcount "maven.compiler.source>17\|maven.compiler.source>21" "$REPORT_POM")
    HAS_JAVA11=$(gcount "maven.compiler.source>11" "$REPORT_POM")
    if [ "$HAS_JAVA17" != "0" ] && [ "$HAS_JAVA11" = "0" ]; then
        BUILD_CONFIG_FIXED="true"
    fi
fi

# ── File change detection ───────────────────────────────────────────────────
FILTER_CHANGED="false"
ANALYZER_CHANGED="false"
SUMMARY_CHANGED="false"
REPORT_POM_CHANGED="false"

CURRENT_FILTER_HASH=$(md5sum "$FILTER_FILE" 2>/dev/null | awk '{print $1}')
INITIAL_FILTER_HASH=$(cat /tmp/initial_filter_hash 2>/dev/null || echo "")
if [ "$CURRENT_FILTER_HASH" != "$INITIAL_FILTER_HASH" ] && [ -n "$INITIAL_FILTER_HASH" ]; then
    FILTER_CHANGED="true"
fi

CURRENT_ANALYZER_HASH=$(md5sum "$ANALYZER_FILE" 2>/dev/null | awk '{print $1}')
INITIAL_ANALYZER_HASH=$(cat /tmp/initial_analyzer_hash 2>/dev/null || echo "")
if [ "$CURRENT_ANALYZER_HASH" != "$INITIAL_ANALYZER_HASH" ] && [ -n "$INITIAL_ANALYZER_HASH" ]; then
    ANALYZER_CHANGED="true"
fi

CURRENT_SUMMARY_HASH=$(md5sum "$SUMMARY_FILE" 2>/dev/null | awk '{print $1}')
INITIAL_SUMMARY_HASH=$(cat /tmp/initial_summary_hash 2>/dev/null || echo "")
if [ "$CURRENT_SUMMARY_HASH" != "$INITIAL_SUMMARY_HASH" ] && [ -n "$INITIAL_SUMMARY_HASH" ]; then
    SUMMARY_CHANGED="true"
fi

CURRENT_RPT_POM_HASH=$(md5sum "$REPORT_POM" 2>/dev/null | awk '{print $1}')
INITIAL_RPT_POM_HASH=$(cat /tmp/initial_report_pom_hash 2>/dev/null || echo "")
if [ "$CURRENT_RPT_POM_HASH" != "$INITIAL_RPT_POM_HASH" ] && [ -n "$INITIAL_RPT_POM_HASH" ]; then
    REPORT_POM_CHANGED="true"
fi

# ── Run Maven build ────────────────────────────────────────────────────────
BUILD_SUCCESS="false"
BUILD_EXIT=1
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERROR=0

if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test --no-transfer-progress" > /tmp/mvn_output.txt 2>&1
    BUILD_EXIT=$?
    if [ $BUILD_EXIT -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    # Parse surefire summary lines: "Tests run: X, Failures: Y, Errors: Z"
    TESTS_RUN=$(grep -oP 'Tests run: \K[0-9]+' /tmp/mvn_output.txt | paste -sd+ | bc 2>/dev/null || echo "0")
    TESTS_FAILED=$(grep -oP 'Failures: \K[0-9]+' /tmp/mvn_output.txt | paste -sd+ | bc 2>/dev/null || echo "0")
    TESTS_ERROR=$(grep -oP 'Errors: \K[0-9]+' /tmp/mvn_output.txt | paste -sd+ | bc 2>/dev/null || echo "0")
fi

# ── Write result JSON ──────────────────────────────────────────────────────
cat > /tmp/clinical_pipeline_result.json << EOF
{
  "task_start": $TASK_START,
  "bug1_fixed": $BUG1_FIXED,
  "bug2_fixed": $BUG2_FIXED,
  "bug3_fixed": $BUG3_FIXED,
  "build_config_fixed": $BUILD_CONFIG_FIXED,
  "filter_changed": $FILTER_CHANGED,
  "analyzer_changed": $ANALYZER_CHANGED,
  "summary_changed": $SUMMARY_CHANGED,
  "report_pom_changed": $REPORT_POM_CHANGED,
  "build_success": $BUILD_SUCCESS,
  "build_exit_code": $BUILD_EXIT,
  "tests_run": $TESTS_RUN,
  "tests_failed": $TESTS_FAILED,
  "tests_error": $TESTS_ERROR
}
EOF

echo "Result saved to /tmp/clinical_pipeline_result.json"
cat /tmp/clinical_pipeline_result.json

echo "=== Export Complete ==="
