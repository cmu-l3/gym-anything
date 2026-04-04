#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Secure Project Forking Result ==="

# Ensure everything is dismounted first to start clean checks
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 2

ALPHA_PATH="/home/ga/Volumes/project_alpha.hc"
BETA_PATH="/home/ga/Volumes/project_beta.hc"
KEYFILE_PATH="/home/ga/Keyfiles/master_key"
SAMPLE_FILE="SF312_Nondisclosure_Agreement.txt"

# Initialize result variables
ALPHA_EXISTS="false"
BETA_EXISTS="false"
KEYFILE_EXISTS="false"
ALPHA_MOUNTS="false"
ALPHA_HAS_DATA="false"
ALPHA_UUID=""
BETA_MOUNTS="false"
BETA_HAS_DATA="false"
BETA_UUID=""
BETA_HASH_ALGO=""
BETA_REJECTS_OLD_CREDS="false"
UUIDS_MATCH="false"

# Check File Existence
[ -f "$ALPHA_PATH" ] && ALPHA_EXISTS="true"
[ -f "$BETA_PATH" ] && BETA_EXISTS="true"
[ -f "$KEYFILE_PATH" ] && KEYFILE_EXISTS="true"

# --- CHECK 1: Verify Master Volume (Alpha) ---
if [ "$ALPHA_EXISTS" = "true" ] && [ "$KEYFILE_EXISTS" = "true" ]; then
    echo "Checking Alpha volume..."
    mkdir -p /tmp/vc_check_alpha
    
    # Try mounting with Password + Keyfile
    if veracrypt --text --mount "$ALPHA_PATH" /tmp/vc_check_alpha \
        --password='AlphaTeam2024!' \
        --keyfiles="$KEYFILE_PATH" \
        --pim=0 --protect-hidden=no --non-interactive > /dev/null 2>&1; then
        
        ALPHA_MOUNTS="true"
        
        # Check for data
        if [ -f "/tmp/vc_check_alpha/$SAMPLE_FILE" ]; then
            ALPHA_HAS_DATA="true"
        fi
        
        # Get UUID
        # Find loop device or mapper
        # veracrypt usually maps to /dev/mapper/veracryptX. 
        # Since we just mounted, it's likely the last one or we can query mount
        MOUNT_DEV=$(findmnt -n -o SOURCE /tmp/vc_check_alpha)
        if [ -n "$MOUNT_DEV" ]; then
            ALPHA_UUID=$(blkid -o value -s UUID "$MOUNT_DEV")
        fi
        
        # Dismount
        veracrypt --text --dismount /tmp/vc_check_alpha --non-interactive 2>/dev/null || true
    fi
    rmdir /tmp/vc_check_alpha 2>/dev/null || true
fi

# --- CHECK 2: Verify Clone Volume (Beta) ---
if [ "$BETA_EXISTS" = "true" ]; then
    echo "Checking Beta volume..."
    mkdir -p /tmp/vc_check_beta
    
    # Try mounting with NEW Password ONLY (No keyfiles)
    # Note: Explicitly passing empty keyfiles to ensure keyfile requirement was removed
    if veracrypt --text --mount "$BETA_PATH" /tmp/vc_check_beta \
        --password='BetaTeam2024!' \
        --keyfiles="" \
        --pim=0 --protect-hidden=no --non-interactive > /dev/null 2>&1; then
        
        BETA_MOUNTS="true"
        
        # Check for data (should be preserved from clone)
        if [ -f "/tmp/vc_check_beta/$SAMPLE_FILE" ]; then
            BETA_HAS_DATA="true"
        fi
        
        # Get UUID
        MOUNT_DEV=$(findmnt -n -o SOURCE /tmp/vc_check_beta)
        if [ -n "$MOUNT_DEV" ]; then
            BETA_UUID=$(blkid -o value -s UUID "$MOUNT_DEV")
        fi
        
        # Get Hash Algorithm (Volume Properties)
        # We need to know which slot it mounted to. usually slot 1 if we dismounted everything.
        # simpler approach: verify mount, then parse volume properties of the file
        PROPS=$(veracrypt --text --volume-properties "$BETA_PATH" --non-interactive 2>/dev/null)
        # Grep for "Hash Algorithm:" or "PKCS-5 PRF:" depending on version/output
        # Standard output usually has "Hash Algorithm: SHA-512" or similar
        BETA_HASH_ALGO=$(echo "$PROPS" | grep -i "Hash Algorithm" | awk -F: '{print $2}' | xargs)
        
        # Dismount
        veracrypt --text --dismount /tmp/vc_check_beta --non-interactive 2>/dev/null || true
    else
        echo "Beta failed to mount with new credentials"
    fi
    rmdir /tmp/vc_check_beta 2>/dev/null || true

    # --- CHECK 3: Negative Test (Beta should NOT mount with Old Creds) ---
    echo "Performing negative access test on Beta..."
    mkdir -p /tmp/vc_check_neg
    if veracrypt --text --mount "$BETA_PATH" /tmp/vc_check_neg \
        --password='AlphaTeam2024!' \
        --keyfiles="$KEYFILE_PATH" \
        --pim=0 --protect-hidden=no --non-interactive > /dev/null 2>&1; then
        
        BETA_REJECTS_OLD_CREDS="false" # It mounted, so it failed the test
        veracrypt --text --dismount /tmp/vc_check_neg --non-interactive 2>/dev/null || true
    else
        BETA_REJECTS_OLD_CREDS="true" # Failed to mount, passed the test
    fi
    rmdir /tmp/vc_check_neg 2>/dev/null || true
fi

# --- CHECK 4: Verify Cloning Method (UUID Match) ---
if [ -n "$ALPHA_UUID" ] && [ -n "$BETA_UUID" ]; then
    if [ "$ALPHA_UUID" = "$BETA_UUID" ]; then
        UUIDS_MATCH="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
cat > /tmp/result_gen.json << EOF
{
    "alpha_exists": $ALPHA_EXISTS,
    "beta_exists": $BETA_EXISTS,
    "keyfile_exists": $KEYFILE_EXISTS,
    "alpha_mounts_correctly": $ALPHA_MOUNTS,
    "alpha_has_data": $ALPHA_HAS_DATA,
    "alpha_uuid": "$ALPHA_UUID",
    "beta_mounts_new_creds": $BETA_MOUNTS,
    "beta_has_data": $BETA_HAS_DATA,
    "beta_uuid": "$BETA_UUID",
    "uuids_match": $UUIDS_MATCH,
    "beta_hash_algo": "$BETA_HASH_ALGO",
    "beta_rejects_old_creds": $BETA_REJECTS_OLD_CREDS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move with permissions
write_result_json "/tmp/task_result.json" "$(cat /tmp/result_gen.json)"
rm /tmp/result_gen.json

echo "=== Export Complete ==="
cat /tmp/task_result.json