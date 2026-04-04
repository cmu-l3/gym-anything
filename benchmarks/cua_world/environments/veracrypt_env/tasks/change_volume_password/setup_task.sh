#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Change Volume Password Task ==="

# Ensure no volumes are currently mounted
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# Verify test volume exists and is accessible with old password
if [ ! -f /home/ga/Volumes/test_volume.hc ]; then
    echo "Recreating test volume..."
    veracrypt --text --create /home/ga/Volumes/test_volume.hc \
        --size=10M \
        --password='OldPassword123' \
        --encryption=AES \
        --hash=SHA-512 \
        --filesystem=FAT \
        --pim=0 \
        --keyfiles="" \
        --random-source=/dev/urandom \
        --non-interactive || true
fi

# Record that old password works (verification baseline)
mkdir -p /tmp/vc_pwd_test
OLD_PWD_WORKS="false"
veracrypt --text --mount /home/ga/Volumes/test_volume.hc /tmp/vc_pwd_test \
    --password='OldPassword123' \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive 2>/dev/null && OLD_PWD_WORKS="true"
veracrypt --text --dismount /tmp/vc_pwd_test --non-interactive 2>/dev/null || true
rmdir /tmp/vc_pwd_test 2>/dev/null || true

echo "$OLD_PWD_WORKS" > /tmp/initial_old_pwd_works.txt
echo "Old password works: $OLD_PWD_WORKS"

# Ensure VeraCrypt is running
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# Focus VeraCrypt window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 2

echo "=== Change Volume Password Task Setup Complete ==="
