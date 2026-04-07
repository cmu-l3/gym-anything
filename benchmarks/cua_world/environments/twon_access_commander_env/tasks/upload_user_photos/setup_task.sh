#!/bin/bash
echo "=== Setting up upload_user_photos task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the photo directory
PHOTO_DIR="/home/ga/Documents/SecurityPhotos"
mkdir -p "$PHOTO_DIR"

# Download 3 real, public-domain/CC portrait photos to use as realistic test data
echo "Downloading realistic profile photos..."
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a0/Pierre-Person.jpg/400px-Pierre-Person.jpg" -o "$PHOTO_DIR/victor_schulz.jpg"
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/8/85/Smiley_Headshot.jpg/400px-Smiley_Headshot.jpg" -o "$PHOTO_DIR/tamara_kowalski.jpg"
curl -sL "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a4/A._A._Milne.jpg/400px-A._A._Milne.jpg" -o "$PHOTO_DIR/leon_fischer.jpg"

chown -R ga:ga "$PHOTO_DIR"

# Wait for 2N Access Commander to be ready
wait_for_ac_demo

# Log into the REST API
ac_login > /dev/null 2>&1

# Clear any existing photos for these three users to ensure a clean slate
echo "Clearing any pre-existing images for targets..."
USERS_JSON=$(ac_api GET "/users" 2>/dev/null)

clear_user_image() {
    local first=$1
    local last=$2
    local uid=$(echo "$USERS_JSON" | jq -r ".[] | select(.firstName==\"$first\" and .lastName==\"$last\") | .id" 2>/dev/null)
    if [ -n "$uid" ] && [ "$uid" != "null" ]; then
        ac_api DELETE "/users/${uid}/image" > /dev/null 2>&1 || true
        echo "  Cleared image for $first $last (id=$uid)"
    fi
}

clear_user_image "Victor" "Schulz"
clear_user_image "Tamara" "Kowalski"
clear_user_image "Leon" "Fischer"

# Record the initial total user count to prevent destructive behavior
INITIAL_USER_COUNT=$(echo "$USERS_JSON" | jq length 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt

# Launch Firefox and navigate to the Access Commander Users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="