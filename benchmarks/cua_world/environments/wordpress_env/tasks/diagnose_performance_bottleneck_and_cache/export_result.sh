#!/bin/bash
# Export script for diagnose_performance_bottleneck_and_cache task
# Verifies plugin statuses, wp-config changes, and benchmarks page load time.

echo "=== Exporting diagnose_performance_bottleneck_and_cache result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Check Rogue Plugin Status
# ============================================================
ROGUE_PLUGIN="wp-social-share-pro"
ROGUE_IS_ACTIVE="false"
ROGUE_IS_INSTALLED="false"

if wp plugin is-installed "$ROGUE_PLUGIN" --allow-root 2>/dev/null; then
    ROGUE_IS_INSTALLED="true"
    if wp plugin is-active "$ROGUE_PLUGIN" --allow-root 2>/dev/null; then
        ROGUE_IS_ACTIVE="true"
    fi
fi

# ============================================================
# Check Essential Plugin Status (Control)
# ============================================================
ESSENTIAL_PLUGIN="wordpress-importer"
ESSENTIAL_IS_ACTIVE="false"

if wp plugin is-active "$ESSENTIAL_PLUGIN" --allow-root 2>/dev/null; then
    ESSENTIAL_IS_ACTIVE="true"
fi

# ============================================================
# Check WP Super Cache Status
# ============================================================
CACHE_PLUGIN="wp-super-cache"
CACHE_IS_ACTIVE="false"

if wp plugin is-active "$CACHE_PLUGIN" --allow-root 2>/dev/null; then
    CACHE_IS_ACTIVE="true"
fi

# ============================================================
# Check wp-config.php for WP_CACHE constant
# ============================================================
WP_CACHE_ENABLED="false"
if grep -q "define( *'WP_CACHE', *true *)" wp-config.php || grep -q 'define( *"WP_CACHE", *true *)' wp-config.php; then
    WP_CACHE_ENABLED="true"
fi

# ============================================================
# Performance Benchmark (Time To First Byte / Total Time)
# ============================================================
echo "Running performance benchmark..."
# Hit the frontend
PERF_TIME=$(curl -s -w "%{time_total}" -o /dev/null http://localhost/ 2>/dev/null || echo "99.99")
echo "Load time: $PERF_TIME seconds"

# Determine if target met
TARGET_MET="false"
if $(python3 -c "print(True if float('$PERF_TIME') < 1.5 else False)"); then
    TARGET_MET="true"
fi

# ============================================================
# Build JSON Export
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rogue_plugin": {
        "installed": $ROGUE_IS_INSTALLED,
        "active": $ROGUE_IS_ACTIVE
    },
    "essential_plugin": {
        "active": $ESSENTIAL_IS_ACTIVE
    },
    "cache_plugin": {
        "active": $CACHE_IS_ACTIVE
    },
    "config": {
        "wp_cache_enabled": $WP_CACHE_ENABLED
    },
    "performance": {
        "load_time_seconds": $PERF_TIME,
        "target_met": $TARGET_MET
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/perf_task_result.json 2>/dev/null || sudo rm -f /tmp/perf_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/perf_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/perf_task_result.json
chmod 666 /tmp/perf_task_result.json 2>/dev/null || sudo chmod 666 /tmp/perf_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result Export:"
cat /tmp/perf_task_result.json
echo ""
echo "=== Export Complete ==="