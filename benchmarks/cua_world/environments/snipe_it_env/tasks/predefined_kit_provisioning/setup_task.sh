#!/bin/bash
echo "=== Setting up predefined_kit_provisioning task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Ensure required items exist in Snipe-IT via API
# ---------------------------------------------------------------
echo "--- Seeding exact required catalog items ---"

# Get a valid manufacturer ID
MAN_ID=$(snipeit_api GET "manufacturers" | jq -r '.rows[0].id // empty')
if [ -z "$MAN_ID" ]; then
    MAN_ID=$(snipeit_api POST "manufacturers" '{"name":"Generic IT Vendor"}' | jq -r '.payload.id')
fi

# Get or create category IDs
CAT_ASSET=$(snipeit_api GET "categories" | jq -r '.rows[] | select(.category_type=="asset") | .id' | head -1)
if [ -z "$CAT_ASSET" ]; then
    CAT_ASSET=$(snipeit_api POST "categories" '{"name":"Hardware Models","category_type":"asset"}' | jq -r '.payload.id')
fi

CAT_ACC=$(snipeit_api GET "categories" | jq -r '.rows[] | select(.category_type=="accessory") | .id' | head -1)
if [ -z "$CAT_ACC" ]; then
    CAT_ACC=$(snipeit_api POST "categories" '{"name":"IT Accessories","category_type":"accessory"}' | jq -r '.payload.id')
fi

CAT_LIC=$(snipeit_api GET "categories" | jq -r '.rows[] | select(.category_type=="license") | .id' | head -1)
if [ -z "$CAT_LIC" ]; then
    CAT_LIC=$(snipeit_api POST "categories" '{"name":"Software Licenses","category_type":"license"}' | jq -r '.payload.id')
fi

CAT_CONS=$(snipeit_api GET "categories" | jq -r '.rows[] | select(.category_type=="consumable") | .id' | head -1)
if [ -z "$CAT_CONS" ]; then
    CAT_CONS=$(snipeit_api POST "categories" '{"name":"IT Consumables","category_type":"consumable"}' | jq -r '.payload.id')
fi

# Helpers to inject items safely
inject_model() {
    local name="$1"
    local exists=$(snipeit_db_query "SELECT id FROM models WHERE name='${name}' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$exists" ]; then
        snipeit_api POST "models" "{\"name\":\"${name}\",\"category_id\":${CAT_ASSET},\"manufacturer_id\":${MAN_ID}}" > /dev/null
    fi
}
inject_acc() {
    local name="$1"
    local exists=$(snipeit_db_query "SELECT id FROM accessories WHERE name='${name}' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$exists" ]; then
        snipeit_api POST "accessories" "{\"name\":\"${name}\",\"category_id\":${CAT_ACC},\"manufacturer_id\":${MAN_ID},\"qty\":50}" > /dev/null
    fi
}
inject_lic() {
    local name="$1"
    local exists=$(snipeit_db_query "SELECT id FROM licenses WHERE name='${name}' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$exists" ]; then
        snipeit_api POST "licenses" "{\"name\":\"${name}\",\"category_id\":${CAT_LIC},\"manufacturer_id\":${MAN_ID},\"seats\":100}" > /dev/null
    fi
}
inject_cons() {
    local name="$1"
    local exists=$(snipeit_db_query "SELECT id FROM consumables WHERE name='${name}' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    if [ -z "$exists" ]; then
        snipeit_api POST "consumables" "{\"name\":\"${name}\",\"category_id\":${CAT_CONS},\"manufacturer_id\":${MAN_ID},\"qty\":100}" > /dev/null
    fi
}

echo "Injecting Models..."
inject_model "Dell Latitude 5520"
inject_model "Dell UltraSharp U2722D"
inject_model "HP EliteDesk 800 G6"
inject_model "Apple MacBook Pro 16"

echo "Injecting Accessories..."
inject_acc "Logitech C920 Webcam"
inject_acc "Dell USB-C Dock WD19"
inject_acc "Logitech MX Master 3"
inject_acc "CalDigit TS4 Thunderbolt"
inject_acc "Jabra Evolve2 75"

echo "Injecting Licenses..."
inject_lic "Microsoft Office 365 Enterprise"
inject_lic "Microsoft Windows 11 Enterprise"
inject_lic "Adobe Creative Cloud"
inject_lic "Zoom Workplace"
inject_lic "Slack Business+"

echo "Injecting Consumables..."
inject_cons "HDMI Cables"
inject_cons "USB-C Cables"

sleep 2

# ---------------------------------------------------------------
# 2. Record initial Predefined Kits baseline
# ---------------------------------------------------------------
# We use Python inline to dynamically resolve table names just in case Snipe-IT version differs
python3 << 'PYEOF'
import subprocess

def query(sql):
    cmd = ["docker", "exec", "snipeit-db", "mysql", "-u", "snipeit", "-psnipeit_pass", "snipeit", "-N", "-e", sql]
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except:
        return ""

kits_table = query("SELECT table_name FROM information_schema.tables WHERE table_name IN ('kits', 'predefined_kits') AND table_schema='snipeit' LIMIT 1")
if not kits_table:
    kits_table = "predefined_kits"

count = query(f"SELECT COUNT(*) FROM {kits_table} WHERE deleted_at IS NULL")
if not count: count = "0"

with open("/tmp/initial_kit_count.txt", "w") as f:
    f.write(count)
PYEOF

echo "Initial kit count recorded."

# ---------------------------------------------------------------
# 3. Setup Firefox Interface
# ---------------------------------------------------------------
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="