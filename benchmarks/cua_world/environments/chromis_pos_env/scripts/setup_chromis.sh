#!/bin/bash
set -e

echo "=== Setting up Chromis POS ==="

export DISPLAY=:1
export XAUTHORITY=/run/user/1000/gdm/Xauthority

# ── 1. Ensure MariaDB is running ────────────────────────────────────────────
echo "--- Ensuring MariaDB is running ---"
systemctl start mariadb 2>/dev/null || true
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
        echo "MariaDB is ready"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: MariaDB not ready"
    exit 1
fi

# ── 2. Wait for desktop ─────────────────────────────────────────────────────
echo "--- Waiting for desktop ---"
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null; then
        echo "Desktop is ready"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Allow X access
DISPLAY=:1 xhost +local: 2>/dev/null || true

# ── 3. Warm-up launch (initializes database schema via Liquibase) ────────────
echo "--- Warm-up launch of Chromis POS ---"
echo "This will initialize the database schema on first run..."

# Launch Chromis as ga user with setsid so it survives hook exit
su - ga -c "setsid bash -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; cd /opt/chromispos; /usr/local/bin/launch-chromispos > /tmp/chromis_warmup.log 2>&1' &"

# Wait for Chromis POS window to appear (Java Swing app, can take 30-60s on first run)
echo "Waiting for Chromis POS window..."
TIMEOUT=120
ELAPSED=0
WINDOW_FOUND=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "chromis\|unicenta\|pos\|point.*sale\|login"; then
        echo "Chromis POS window detected at ${ELAPSED}s"
        WINDOW_FOUND=1
        break
    fi
    # Also check for Java windows (generic)
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "javax\|swing\|java\|FocusProxy"; then
        echo "Java window detected at ${ELAPSED}s"
        WINDOW_FOUND=1
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $WINDOW_FOUND -eq 0 ]; then
    echo "WARNING: Chromis POS window not detected after ${TIMEOUT}s"
    echo "Checking Java processes..."
    ps aux | grep -i "java\|chromis" | grep -v grep
    echo "Checking warmup log..."
    tail -50 /tmp/chromis_warmup.log 2>/dev/null || true
fi

# Give the app time to fully initialize (Liquibase schema creation)
echo "Waiting for database initialization..."
sleep 30

# Dismiss any first-run dialogs
echo "Dismissing any dialogs..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 2

# Take a screenshot of the warm-up state
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/chromis_warmup_state.png 2>/dev/null || true

# ── 4. Close Chromis POS gracefully ─────────────────────────────────────────
echo "--- Closing warm-up instance ---"
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4 2>/dev/null || true
sleep 3
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 5

# Force kill if still running
pkill -f "chromispos\|ChromisPOS" 2>/dev/null || true
pkill -f "java.*chromis" 2>/dev/null || true
sleep 2

# ── 5. Populate database with real product data ─────────────────────────────
echo "--- Populating database with UCI Online Retail product data ---"

# Check if tables exist (Liquibase should have created them)
TABLE_COUNT=$(mysql -u root chromispos -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='chromispos'" 2>/dev/null || echo "0")
echo "Tables in database: $TABLE_COUNT"

if [ "$TABLE_COUNT" -gt "0" ]; then
    # Check if products already exist
    PRODUCT_COUNT=$(mysql -u root chromispos -N -e "SELECT COUNT(*) FROM PRODUCTS" 2>/dev/null || echo "0")
    echo "Existing products: $PRODUCT_COUNT"

    if [ "$PRODUCT_COUNT" -eq "0" ] || [ "$PRODUCT_COUNT" = "0" ]; then
        echo "Loading product data from UCI Online Retail dataset..."
        mysql -u root chromispos < /workspace/data/chromis_data.sql 2>/dev/null || {
            echo "SQL import failed, trying line by line..."
            while IFS= read -r line; do
                # Skip comments and empty lines
                [[ "$line" =~ ^--.*$ ]] && continue
                [[ -z "$line" ]] && continue
                mysql -u root chromispos -e "$line" 2>/dev/null || true
            done < /workspace/data/chromis_data.sql
        }

        # Verify import
        PRODUCT_COUNT=$(mysql -u root chromispos -N -e "SELECT COUNT(*) FROM PRODUCTS" 2>/dev/null || echo "0")
        CAT_COUNT=$(mysql -u root chromispos -N -e "SELECT COUNT(*) FROM CATEGORIES" 2>/dev/null || echo "0")
        echo "Products loaded: $PRODUCT_COUNT"
        echo "Categories loaded: $CAT_COUNT"
    else
        echo "Products already loaded ($PRODUCT_COUNT products)"
    fi
else
    echo "WARNING: Database tables not yet created. Schema may need manual initialization."
    echo "Will attempt to populate after next Chromis launch."
fi

# ── 6. Create a second warm-up launch to verify data loads in UI ─────────────
echo "--- Second warm-up launch to verify data ---"
su - ga -c "setsid bash -c 'export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; cd /opt/chromispos; /usr/local/bin/launch-chromispos > /tmp/chromis_warmup2.log 2>&1' &"

# Wait for window
TIMEOUT=90
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -qi "chromis\|unicenta\|pos\|login\|java\|FocusProxy"; then
        echo "Chromis POS window detected on second launch at ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 15

# Dismiss dialogs again
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 2

# Take screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/chromis_ready_state.png 2>/dev/null || true

# Close gracefully
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4 2>/dev/null || true
sleep 3
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return 2>/dev/null || true
sleep 5
pkill -f "chromispos\|ChromisPOS" 2>/dev/null || true
pkill -f "java.*chromis" 2>/dev/null || true
sleep 2

echo "=== Chromis POS setup complete ==="
echo "Database: chromispos (MariaDB on localhost:3306)"
echo "Products: $(mysql -u root chromispos -N -e 'SELECT COUNT(*) FROM PRODUCTS' 2>/dev/null || echo 'unknown')"
echo "Categories: $(mysql -u root chromispos -N -e 'SELECT COUNT(*) FROM CATEGORIES' 2>/dev/null || echo 'unknown')"
