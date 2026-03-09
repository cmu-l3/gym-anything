#!/bin/bash
echo "=== Exporting inventory_network_expansion_scconfig result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="inventory_network_expansion_scconfig"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
INITIAL_NETWORK_COUNT=$(cat /tmp/${TASK}_initial_network_count 2>/dev/null || echo "0")
INITIAL_STATION_COUNT=$(cat /tmp/${TASK}_initial_station_count 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# ─── 1. Check IU network in database ────────────────────────────────────────

IU_NETWORK_EXISTS=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Network WHERE code='IU'" 2>/dev/null || echo "0")
echo "IU network in DB: $IU_NETWORK_EXISTS"

# ─── 2. Check IU stations in database ───────────────────────────────────────

ANMO_IN_DB=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Station s JOIN Network n ON s._parent_oid = n._oid
     WHERE n.code='IU' AND s.code='ANMO'" 2>/dev/null || echo "0")
HRV_IN_DB=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Station s JOIN Network n ON s._parent_oid = n._oid
     WHERE n.code='IU' AND s.code='HRV'" 2>/dev/null || echo "0")
KONO_IN_DB=$(mysql -u sysop -psysop seiscomp -N -B -e \
    "SELECT COUNT(*) FROM Station s JOIN Network n ON s._parent_oid = n._oid
     WHERE n.code='IU' AND s.code='KONO'" 2>/dev/null || echo "0")

IU_STATIONS_IN_DB=0
[ "$ANMO_IN_DB" -gt 0 ] 2>/dev/null && IU_STATIONS_IN_DB=$((IU_STATIONS_IN_DB + 1))
[ "$HRV_IN_DB" -gt 0 ] 2>/dev/null && IU_STATIONS_IN_DB=$((IU_STATIONS_IN_DB + 1))
[ "$KONO_IN_DB" -gt 0 ] 2>/dev/null && IU_STATIONS_IN_DB=$((IU_STATIONS_IN_DB + 1))

echo "IU stations in DB: $IU_STATIONS_IN_DB (ANMO=$ANMO_IN_DB HRV=$HRV_IN_DB KONO=$KONO_IN_DB)"

# ─── 3. Check inventory file in etc/inventory/ ──────────────────────────────

INVENTORY_FILE_EXISTS="false"
for F in "$SEISCOMP_ROOT/etc/inventory/iu_stations.xml" \
         "$SEISCOMP_ROOT/etc/inventory/iu_stations.scml" \
         "$SEISCOMP_ROOT/etc/inventory/"*iu* \
         "$SEISCOMP_ROOT/etc/inventory/"*IU*; do
    if [ -f "$F" ] && [ -s "$F" ]; then
        INVENTORY_FILE_EXISTS="true"
        echo "Inventory file found: $F"
        break
    fi
done
echo "Inventory file in etc/inventory: $INVENTORY_FILE_EXISTS"

# ─── 4. Check station key files and bindings ────────────────────────────────

ANMO_HAS_SCAUTOPICK="false"
ANMO_HAS_SCAMP="false"
HRV_HAS_SCAUTOPICK="false"
HRV_HAS_SCAMP="false"
KONO_HAS_SCAUTOPICK="false"
KONO_HAS_SCAMP="false"

for STA in ANMO HRV KONO; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_IU_${STA}"
    if [ -f "$KEY_FILE" ]; then
        grep -qi "scautopick" "$KEY_FILE" 2>/dev/null && eval "${STA}_HAS_SCAUTOPICK=true"
        grep -qi "scamp" "$KEY_FILE" 2>/dev/null && eval "${STA}_HAS_SCAMP=true"
    fi
done

STATIONS_WITH_SCAUTOPICK=0
STATIONS_WITH_SCAMP=0
[ "$ANMO_HAS_SCAUTOPICK" = "true" ] && STATIONS_WITH_SCAUTOPICK=$((STATIONS_WITH_SCAUTOPICK + 1))
[ "$HRV_HAS_SCAUTOPICK" = "true" ] && STATIONS_WITH_SCAUTOPICK=$((STATIONS_WITH_SCAUTOPICK + 1))
[ "$KONO_HAS_SCAUTOPICK" = "true" ] && STATIONS_WITH_SCAUTOPICK=$((STATIONS_WITH_SCAUTOPICK + 1))
[ "$ANMO_HAS_SCAMP" = "true" ] && STATIONS_WITH_SCAMP=$((STATIONS_WITH_SCAMP + 1))
[ "$HRV_HAS_SCAMP" = "true" ] && STATIONS_WITH_SCAMP=$((STATIONS_WITH_SCAMP + 1))
[ "$KONO_HAS_SCAMP" = "true" ] && STATIONS_WITH_SCAMP=$((STATIONS_WITH_SCAMP + 1))

echo "Stations with scautopick: $STATIONS_WITH_SCAUTOPICK"
echo "Stations with scamp: $STATIONS_WITH_SCAMP"

# ─── 5. Check inventory listing file ────────────────────────────────────────

LISTING_FILE="/home/ga/Desktop/network_inventory.txt"
LISTING_EXISTS="false"
LISTING_SIZE=0
LISTING_HAS_IU="false"
LISTING_HAS_GE="false"
LISTING_STATION_COUNT=0

if [ -f "$LISTING_FILE" ]; then
    LISTING_EXISTS="true"
    LISTING_SIZE=$(wc -c < "$LISTING_FILE" 2>/dev/null || echo "0")
    CONTENT=$(cat "$LISTING_FILE" 2>/dev/null || echo "")
    echo "$CONTENT" | grep -qi "IU" && LISTING_HAS_IU="true"
    echo "$CONTENT" | grep -qi "GE" && LISTING_HAS_GE="true"
    # Count lines mentioning station codes
    LISTING_STATION_COUNT=$(echo "$CONTENT" | grep -ciE "(ANMO|HRV|KONO|TOLI|GSI|KWP|SANI|BKB)" || echo "0")
fi
echo "Listing file: exists=$LISTING_EXISTS size=$LISTING_SIZE has_IU=$LISTING_HAS_IU"

# ─── 6. Write result JSON ───────────────────────────────────────────────────

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "initial_network_count": $INITIAL_NETWORK_COUNT,
    "initial_station_count": $INITIAL_STATION_COUNT,
    "iu_network_in_db": $([ "${IU_NETWORK_EXISTS:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "iu_stations_in_db": $IU_STATIONS_IN_DB,
    "anmo_in_db": $([ "${ANMO_IN_DB:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "hrv_in_db": $([ "${HRV_IN_DB:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "kono_in_db": $([ "${KONO_IN_DB:-0}" -gt 0 ] 2>/dev/null && echo "true" || echo "false"),
    "inventory_file_in_etc": $INVENTORY_FILE_EXISTS,
    "anmo_has_scautopick": $ANMO_HAS_SCAUTOPICK,
    "anmo_has_scamp": $ANMO_HAS_SCAMP,
    "hrv_has_scautopick": $HRV_HAS_SCAUTOPICK,
    "hrv_has_scamp": $HRV_HAS_SCAMP,
    "kono_has_scautopick": $KONO_HAS_SCAUTOPICK,
    "kono_has_scamp": $KONO_HAS_SCAMP,
    "stations_with_scautopick": $STATIONS_WITH_SCAUTOPICK,
    "stations_with_scamp": $STATIONS_WITH_SCAMP,
    "listing_exists": $LISTING_EXISTS,
    "listing_size": $LISTING_SIZE,
    "listing_has_iu": $LISTING_HAS_IU,
    "listing_has_ge": $LISTING_HAS_GE
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
