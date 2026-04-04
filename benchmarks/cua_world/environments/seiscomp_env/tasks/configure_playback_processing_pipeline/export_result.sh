#!/bin/bash
echo "=== Exporting configure_playback_processing_pipeline result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="configure_playback_processing_pipeline"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_AUTO_ORIGINS=$(cat /tmp/${TASK}_initial_auto_origins 2>/dev/null || echo "0")
INITIAL_AUTO_PICKS=$(cat /tmp/${TASK}_initial_auto_picks 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# ─── 1. Check station bindings ──────────────────────────────────────────

STATIONS_WITH_SCAUTOPICK=0
for STA in GSI SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    if [ -f "$KEY_FILE" ] && grep -qi "scautopick" "$KEY_FILE" 2>/dev/null; then
        STATIONS_WITH_SCAUTOPICK=$((STATIONS_WITH_SCAUTOPICK + 1))
    fi
done
echo "Stations with scautopick binding: $STATIONS_WITH_SCAUTOPICK"

# ─── 2. Check scautopick config ─────────────────────────────────────────

SCAUTOPICK_CFG="$SEISCOMP_ROOT/etc/scautopick.cfg"
HAS_SCAUTOPICK_CFG="false"
SCAUTOPICK_FILTER=""

if [ -f "$SCAUTOPICK_CFG" ]; then
    HAS_SCAUTOPICK_CFG="true"
    SCAUTOPICK_FILTER=$(grep -i "filter\|BW(" "$SCAUTOPICK_CFG" 2>/dev/null | head -1 || echo "")
fi
echo "scautopick.cfg exists: $HAS_SCAUTOPICK_CFG"
echo "scautopick filter: $SCAUTOPICK_FILTER"

# ─── 3. Check scautoloc config ──────────────────────────────────────────

SCAUTOLOC_CFG="$SEISCOMP_ROOT/etc/scautoloc.cfg"
HAS_SCAUTOLOC_CFG="false"

if [ -f "$SCAUTOLOC_CFG" ]; then
    HAS_SCAUTOLOC_CFG="true"
fi
echo "scautoloc.cfg exists: $HAS_SCAUTOLOC_CFG"

# ─── 4. Count automatic picks in database ───────────────────────────────

AUTO_PICK_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")
echo "Automatic picks in DB: $AUTO_PICK_COUNT"

# Count picks per station
PICKS_GSI=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='GSI' AND evaluationMode='automatic'" 2>/dev/null || echo "0")
PICKS_BKB=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='BKB' AND evaluationMode='automatic'" 2>/dev/null || echo "0")
PICKS_SANI=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='SANI' AND evaluationMode='automatic'" 2>/dev/null || echo "0")
echo "Picks per station: GSI=$PICKS_GSI BKB=$PICKS_BKB SANI=$PICKS_SANI"

# ─── 5. Count automatic origins in database ─────────────────────────────

AUTO_ORIGIN_COUNT=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Origin WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")
echo "Automatic origins in DB: $AUTO_ORIGIN_COUNT"

# ─── 6. Check results summary file ──────────────────────────────────────

RESULTS_FILE="/home/ga/Desktop/playback_results.txt"
RESULTS_EXISTS="false"
RESULTS_SIZE=0
RESULTS_MENTIONS_PICKS="false"
RESULTS_MENTIONS_ORIGINS="false"

if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXISTS="true"
    RESULTS_SIZE=$(wc -c < "$RESULTS_FILE" 2>/dev/null || echo "0")
    CONTENT=$(cat "$RESULTS_FILE" 2>/dev/null || echo "")
    echo "$CONTENT" | grep -qiE "(pick|phase|detection|arrival)" && RESULTS_MENTIONS_PICKS="true"
    echo "$CONTENT" | grep -qiE "(origin|locat|event|hypocenter)" && RESULTS_MENTIONS_ORIGINS="true"
fi
echo "Results file exists: $RESULTS_EXISTS (size=$RESULTS_SIZE)"

# ─── 7. Escape and write JSON ───────────────────────────────────────────

FILTER_ESCAPED=$(echo "$SCAUTOPICK_FILTER" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_auto_origins": $INITIAL_AUTO_ORIGINS,
    "initial_auto_picks": $INITIAL_AUTO_PICKS,
    "stations_with_scautopick": $STATIONS_WITH_SCAUTOPICK,
    "has_scautopick_cfg": $HAS_SCAUTOPICK_CFG,
    "scautopick_filter": $FILTER_ESCAPED,
    "has_scautoloc_cfg": $HAS_SCAUTOLOC_CFG,
    "auto_pick_count": ${AUTO_PICK_COUNT:-0},
    "picks_gsi": ${PICKS_GSI:-0},
    "picks_bkb": ${PICKS_BKB:-0},
    "picks_sani": ${PICKS_SANI:-0},
    "auto_origin_count": ${AUTO_ORIGIN_COUNT:-0},
    "results_exists": $RESULTS_EXISTS,
    "results_size": $RESULTS_SIZE,
    "results_mentions_picks": $RESULTS_MENTIONS_PICKS,
    "results_mentions_origins": $RESULTS_MENTIONS_ORIGINS
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
