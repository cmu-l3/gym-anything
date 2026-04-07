#!/bin/bash
# export_result.sh - Post-task hook for configure_tls_interception_and_hardening
# Extracts the NSS certificate DB state, preference changes, and validates the exported file.

echo "=== Exporting configure_tls_interception_and_hardening task results ==="

# 1. Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Task Start Time
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 3. Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

# 4. Check Firefox NSS Certificate Database for Imported Root CA
PROXY_IMPORTED="false"
PROXY_TRUSTED="false"

if [ -n "$PROFILE_DIR" ]; then
    # Create a temporary directory and copy NSS DB to avoid lock conflicts
    TMP_NSS=$(mktemp -d)
    cp "$PROFILE_DIR/"*.db "$TMP_NSS/" 2>/dev/null || true
    cp "$PROFILE_DIR/pkcs11.txt" "$TMP_NSS/" 2>/dev/null || true

    # Check certutil list
    if command -v certutil &> /dev/null; then
        # Firefox usually uses 'sql:' prefix for modern NSS DBs
        CERT_LIST=$(certutil -L -d sql:"$TMP_NSS" 2>/dev/null || echo "")
        
        # Check if ProxyRootCA is in the DB
        PROXY_CERT_LINE=$(echo "$CERT_LIST" | grep -i "ProxyRootCA" || echo "")
        
        if [ -n "$PROXY_CERT_LINE" ]; then
            PROXY_IMPORTED="true"
            # Trust flags usually appear as "C,," or "CT,,". We look for 'C' indicating trusted CA for SSL.
            if echo "$PROXY_CERT_LINE" | grep -q "C.*,.*,"; then
                PROXY_TRUSTED="true"
            fi
        fi
    else
        echo "WARNING: certutil not found."
    fi
    rm -rf "$TMP_NSS"
fi

# 5. Check Exported Backup Certificate
BACKUP_PATH="/home/ga/Documents/ISRG_Root_Backup.crt"
BACKUP_EXISTS="false"
BACKUP_CREATED_DURING_TASK="false"
BACKUP_VALID="false"

if [ -f "$BACKUP_PATH" ]; then
    BACKUP_EXISTS="true"
    BACKUP_MTIME=$(stat -c %Y "$BACKUP_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified after task start
    if [ "$BACKUP_MTIME" -gt "$TASK_START_TIME" ]; then
        BACKUP_CREATED_DURING_TASK="true"
    fi
    
    # Check if it is a valid x509 cert and matches ISRG Root X1
    if command -v openssl &> /dev/null; then
        CERT_TEXT=$(openssl x509 -in "$BACKUP_PATH" -text -noout 2>/dev/null || echo "")
        if echo "$CERT_TEXT" | grep -qi "ISRG Root X1"; then
            BACKUP_VALID="true"
        fi
    fi
fi

# 6. Check about:config preferences
TLS_MIN_VER="-1"
CERT_PINNING_LEVEL="-1"

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    
    TLS_MATCH=$(grep -oP 'user_pref\("security\.tls\.version\.min",\s*\K[0-9]+' "$PREFS_FILE" || echo "-1")
    if [ -n "$TLS_MATCH" ]; then
        TLS_MIN_VER="$TLS_MATCH"
    fi
    
    PINNING_MATCH=$(grep -oP 'user_pref\("security\.cert_pinning\.enforcement_level",\s*\K[0-9]+' "$PREFS_FILE" || echo "-1")
    if [ -n "$PINNING_MATCH" ]; then
        CERT_PINNING_LEVEL="$PINNING_MATCH"
    fi
fi

# 7. Write Results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "proxy_imported": $PROXY_IMPORTED,
    "proxy_trusted": $PROXY_TRUSTED,
    "backup_exists": $BACKUP_EXISTS,
    "backup_created_during_task": $BACKUP_CREATED_DURING_TASK,
    "backup_valid": $BACKUP_VALID,
    "tls_min_version": $TLS_MIN_VER,
    "cert_pinning_level": $CERT_PINNING_LEVEL,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json