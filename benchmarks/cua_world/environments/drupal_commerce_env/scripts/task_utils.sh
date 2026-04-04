#!/bin/bash
# Shared utility functions for Drupal Commerce tasks

# Drupal installation directory
DRUPAL_DIR="/var/www/html/drupal"
DRUSH="$DRUPAL_DIR/vendor/bin/drush"

# Debug log location
VERIFIER_DEBUG_LOG="/tmp/verifier_debug.log"

# Database connection via Docker
drupal_db_query() {
    local query="$1"
    local result
    local exit_code

    result=$(docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$query" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "DB_ERROR: Query failed with exit code $exit_code" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        echo ""
        return 1
    fi

    if echo "$result" | grep -qi "ERROR"; then
        echo "DB_ERROR: MySQL error in result" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        echo ""
        return 1
    fi

    echo "$result"
    return 0
}

# Execute Drush command
drush_cmd() {
    local result
    local exit_code

    cd "$DRUPAL_DIR"
    result=$($DRUSH "$@" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "DRUSH_ERROR: Command failed with exit code $exit_code" >> "$VERIFIER_DEBUG_LOG"
        echo "DRUSH_ERROR: Args: $@" >> "$VERIFIER_DEBUG_LOG"
        echo "DRUSH_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
    fi

    echo "$result"
    return $exit_code
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Get product count
get_product_count() {
    drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE status = 1"
}

# Get promotion count
get_promotion_count() {
    drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data WHERE status = 1"
}

# Get coupon count
get_coupon_count() {
    drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon WHERE status = 1"
}

# Get order count
get_order_count() {
    drupal_db_query "SELECT COUNT(*) FROM commerce_order" 2>/dev/null || echo "0"
}

# Check if product exists by title (case-insensitive)
product_exists_by_title() {
    local title="$1"
    local count=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE LOWER(TRIM(title)) = LOWER(TRIM('$title')) AND status = 1")
    [ "$count" -gt 0 ]
}

# Get product ID by title
get_product_id_by_title() {
    local title="$1"
    drupal_db_query "SELECT product_id FROM commerce_product_field_data WHERE LOWER(TRIM(title)) = LOWER(TRIM('$title')) ORDER BY product_id DESC LIMIT 1"
}

# Get product variation by SKU
get_variation_by_sku() {
    local sku="$1"
    drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE LOWER(TRIM(sku)) = LOWER(TRIM('$sku')) LIMIT 1"
}

# Get product price by SKU
get_product_price_by_sku() {
    local sku="$1"
    drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE LOWER(TRIM(sku)) = LOWER(TRIM('$sku')) LIMIT 1"
}

# Check if coupon exists by code
coupon_exists_by_code() {
    local code="$1"
    local count=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon WHERE LOWER(TRIM(code)) = LOWER(TRIM('$code')) AND status = 1")
    [ "$count" -gt 0 ]
}

# Get user count
get_user_count() {
    drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE uid > 0"
}

# Check if user exists by name
user_exists() {
    local username="$1"
    local count=$(drupal_db_query "SELECT COUNT(*) FROM users_field_data WHERE LOWER(name) = LOWER('$username')")
    [ "$count" -gt 0 ]
}

# Get Firefox window ID
get_firefox_window_id() {
    DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}'
}

# Focus a window by ID
focus_window() {
    local wid="$1"
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
}

# Navigate Firefox to a URL
navigate_firefox_to() {
    local url="$1"
    local timeout=${2:-30}

    # Use xdotool to open URL bar and type URL
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "$url"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 3
}

# Wait for Drupal page to load (check window title)
wait_for_drupal_page() {
    local keyword="${1:-drupal}"
    local timeout=${2:-60}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$WINDOW_TITLE" | grep -qi "$keyword"; then
            echo "Page with keyword '$keyword' detected after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "WARNING: Page with keyword '$keyword' not detected after ${timeout}s"
    return 1
}

# Ensure Drupal admin is shown in Firefox (not blank tab)
ensure_drupal_shown() {
    local timeout=${1:-60}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        # Check for Drupal-specific text (not just "Mozilla Firefox")
        if echo "$WINDOW_TITLE" | grep -qi "drupal\|commerce\|store\|admin\|products\|orders"; then
            echo "Drupal admin page confirmed loaded after ${elapsed}s"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Try navigating using Drush one-time login link
    echo "Attempting to login via Drush ULI and navigate to Drupal admin..."
    LOGIN_URL=$(cd "$DRUPAL_DIR" && $DRUSH uli --uri=http://localhost --no-browser --uid=1 2>/dev/null)
    if [ -n "$LOGIN_URL" ]; then
        navigate_firefox_to "${LOGIN_URL}?destination=admin/commerce"
    else
        navigate_firefox_to "http://localhost/admin/commerce"
    fi
    sleep 8

    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
    if echo "$WINDOW_TITLE" | grep -qi "drupal\|commerce\|store\|admin"; then
        return 0
    fi

    return 1
}

# Safe JSON string escape
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
}

# Create result JSON with proper escaping
create_result_json() {
    local temp_file="$1"
    shift

    echo "{" > "$temp_file"
    local first=true
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local value="${1#*=}"

        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$temp_file"
        fi

        if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]] || [ "$value" = "true" ] || [ "$value" = "false" ] || [ "$value" = "null" ]; then
            printf '    "%s": %s' "$key" "$value" >> "$temp_file"
        else
            printf '    "%s": "%s"' "$key" "$(json_escape "$value")" >> "$temp_file"
        fi

        shift
    done
    echo "" >> "$temp_file"
    echo "}" >> "$temp_file"
}

# Ensure all Drupal Commerce services are running.
# Attempts to start/recover services that are down.
# Call this from pre_task hooks to handle cases where post_start timed out.
ensure_services_running() {
    local timeout=${1:-120}
    local all_ok=true

    echo "Checking Drupal Commerce services..."

    # 1. Check Docker is running
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        echo "Docker not running, starting..."
        sudo systemctl start docker
        sleep 3
    fi

    # 2. Check MariaDB container is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "drupal-mariadb"; then
        echo "MariaDB container not running, starting..."
        if [ -f /home/ga/drupal_commerce/docker-compose.yml ]; then
            cd /home/ga/drupal_commerce && docker-compose up -d 2>/dev/null
        fi
        # Wait for MariaDB to accept connections
        local elapsed=0
        while [ $elapsed -lt 60 ]; do
            if docker exec drupal-mariadb mysqladmin ping -h localhost -uroot -prootpass 2>/dev/null | grep -q "alive"; then
                echo "MariaDB is ready"
                break
            fi
            sleep 2
            elapsed=$((elapsed + 2))
        done
        if [ $elapsed -ge 60 ]; then
            echo "WARNING: MariaDB did not become ready in 60s"
            all_ok=false
        fi
    else
        echo "MariaDB container is running"
    fi

    # 3. Check Apache config and service
    # Recover Apache vhost config if missing (e.g., pre_start timed out before section 7)
    if [ ! -f /etc/apache2/sites-available/drupal.conf ]; then
        echo "Apache drupal.conf missing, recreating..."
        cat > /etc/apache2/sites-available/drupal.conf << 'APACHEEOF'
<VirtualHost *:80>
    ServerAdmin admin@localhost
    DocumentRoot /var/www/html/drupal/web

    <Directory /var/www/html/drupal/web>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/drupal_error.log
    CustomLog ${APACHE_LOG_DIR}/drupal_access.log combined
</VirtualHost>
APACHEEOF
        a2dissite 000-default.conf 2>/dev/null || true
        a2ensite drupal.conf 2>/dev/null || true
        a2enmod rewrite 2>/dev/null || true
        a2enmod headers 2>/dev/null || true
    fi

    if ! systemctl is-active --quiet apache2 2>/dev/null; then
        echo "Apache not running, starting..."
        sudo systemctl start apache2
        sleep 2
    fi

    # 4. Check if Drupal files exist (Composer may have timed out)
    if [ ! -f "$DRUPAL_DIR/vendor/bin/drush" ]; then
        echo "WARNING: Drupal installation appears incomplete (drush missing)"
        echo "Attempting to complete Composer installation..."
        export COMPOSER_ALLOW_SUPERUSER=1
        if [ ! -f "$DRUPAL_DIR/composer.json" ]; then
            echo "Drupal project missing entirely, running composer create-project..."
            cd /var/www/html
            rm -rf drupal 2>/dev/null || true
            composer create-project drupal/recommended-project drupal --no-interaction 2>&1
            cd "$DRUPAL_DIR"
            composer config minimum-stability RC 2>&1
        fi
        cd "$DRUPAL_DIR"
        composer require drush/drush --no-interaction 2>&1 || true
        composer require drupal/commerce -W --no-interaction 2>&1 || true
        composer require drupal/admin_toolbar --no-interaction 2>&1 || true
        chown -R www-data:www-data "$DRUPAL_DIR"
        chmod -R 755 "$DRUPAL_DIR"
    fi

    # 5. Check Drupal is accessible
    local http_ok=false
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            http_ok=true
            echo "Drupal is accessible (HTTP $HTTP_CODE)"
            break
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    if [ "$http_ok" = false ]; then
        echo "WARNING: Drupal not accessible after ${timeout}s"
        # Try restarting Apache
        sudo systemctl restart apache2
        sleep 3
        all_ok=false
    fi

    # 6. Ensure Firefox is running
    if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox not running, launching..."
        LOGIN_URL=$(cd "$DRUPAL_DIR" && $DRUSH uli --uri=http://localhost --no-browser --uid=1 2>/dev/null)
        if [ -n "$LOGIN_URL" ]; then
            su - ga -c "DISPLAY=:1 nohup firefox '${LOGIN_URL}?destination=admin/commerce' > /tmp/firefox_recovery.log 2>&1 &" 2>/dev/null || \
            sudo -u ga bash -c "DISPLAY=:1 nohup firefox '${LOGIN_URL}?destination=admin/commerce' > /tmp/firefox_recovery.log 2>&1 &"
        else
            su - ga -c "DISPLAY=:1 nohup firefox 'http://localhost/admin/commerce' > /tmp/firefox_recovery.log 2>&1 &" 2>/dev/null || \
            sudo -u ga bash -c "DISPLAY=:1 nohup firefox 'http://localhost/admin/commerce' > /tmp/firefox_recovery.log 2>&1 &"
        fi
        # Wait for Firefox window
        local ff_elapsed=0
        while [ $ff_elapsed -lt 30 ]; do
            if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
                echo "Firefox window detected"
                break
            fi
            sleep 1
            ff_elapsed=$((ff_elapsed + 1))
        done
        sleep 5  # Extra time for page to render
    else
        echo "Firefox is running"
    fi

    if [ "$all_ok" = true ]; then
        echo "All services confirmed running"
        return 0
    else
        echo "WARNING: Some services may not be fully operational"
        return 1
    fi
}

# Safe file write with permission handling
safe_write_result() {
    local content="$1"
    local dest="${2:-/tmp/task_result.json}"

    local temp_json=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$temp_json"

    rm -f "$dest" 2>/dev/null || sudo rm -f "$dest" 2>/dev/null || true
    cp "$temp_json" "$dest" 2>/dev/null || sudo cp "$temp_json" "$dest"
    chmod 666 "$dest" 2>/dev/null || sudo chmod 666 "$dest" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to $dest"
    cat "$dest"
}
