#!/bin/bash
echo "=== Exporting perseid_meteor_plan result ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Terminate Stellarium to force writing config.ini
echo "Terminating Stellarium..."
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait gracefully
for i in {1..15}; do
    if ! pgrep stellarium > /dev/null; then break; fi
    sleep 1
done

# Force kill if hung
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Parse config.ini
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
res = {
    "config_exists": False,
    "lat_rad": 0.0, 
    "lon_rad": 0.0,
    "flag_atmosphere": False, 
    "flag_landscape": False,
    "flag_constellation_drawing": False, 
    "flag_constellation_name": False
}

if os.path.exists(config_path):
    res["config_exists"] = True
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)
        
        def get_bool(s, k, default):
            try: return cfg.get(s, k).lower().strip() == 'true'
            except: return default
            
        def get_float(s, k, default):
            try: return float(cfg.get(s, k))
            except: return default
            
        res["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        res["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        res["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', False)
        res["flag_landscape"] = get_bool('landscape', 'flag_landscape', False)
        res["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', False)
        res["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', False)
    except Exception as e:
        res["error"] = str(e)
print(json.dumps(res))
PYEOF
)

# 4. Check screenshot count
INITIAL_SS=$(cat /tmp/initial_ss_count 2>/dev/null || echo "0")
CURRENT_SS=$(find /home/ga/Pictures/stellarium/ -maxdepth 1 -name "*.png" 2>/dev/null | wc -l)
NEW_SS=$((CURRENT_SS - INITIAL_SS))

SS_NEW_TIME=$(find /home/ga/Pictures/stellarium/ -maxdepth 1 -type f -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# Use whatever count is higher (time-based vs baseline subtraction)
if [ "$SS_NEW_TIME" -gt "$NEW_SS" ]; then
    NEW_SS="$SS_NEW_TIME"
fi

# 5. Check observation plan file
PLAN_CREATED="false"
PLAN_EXISTS="false"
PLAN_PATH="/home/ga/Desktop/perseid_plan.txt"

if [ -f "$PLAN_PATH" ]; then
    PLAN_EXISTS="true"
    cp "$PLAN_PATH" /tmp/perseid_plan.txt
    chmod 666 /tmp/perseid_plan.txt
    
    PLAN_MTIME=$(stat -c %Y "$PLAN_PATH" 2>/dev/null || echo "0")
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    
    if [ "$PLAN_MTIME" -gt "$TASK_START" ]; then
        PLAN_CREATED="true"
    fi
fi

# 6. Build Result JSON
cat > /tmp/task_result.json << EOF
{
    "config": $CONFIG_JSON,
    "new_screenshots": $NEW_SS,
    "plan_exists": $PLAN_EXISTS,
    "plan_created_during_task": $PLAN_CREATED
}
EOF
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="