#!/bin/bash
set -e
echo "=== Setting up Orphaned Volume Rescue Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Function to wait for docker if not defined
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done
        return 1
    }
fi

wait_for_docker

# Clean up any previous state
docker rm -f recovery-service 2>/dev/null || true
docker volume prune -f > /dev/null 2>&1

# Generate a unique ID for verification (Anti-gaming: Agent can't guess this)
UNIQUE_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)
TARGET_CONTENT="{\"upload_id\": \"${UNIQUE_ID}\", \"status\": \"critical\", \"files\": [\"contract.pdf\", \"scan.png\"]}"

# Save the expected content string for the verifier
echo "$TARGET_CONTENT" > /tmp/expected_content_string.txt

# Create 4 decoy volumes with realistic junk data
echo "Creating decoy volumes..."
for i in {1..4}; do
    VOL=$(docker volume create)
    # Populate with decoy data
    docker run --rm -v "$VOL":/var/log/nginx alpine sh -c "echo 'Started at $(date)' > /var/log/nginx/access.log; mkdir -p /var/log/nginx/old"
    docker run --rm -v "$VOL":/root/.npm alpine sh -c "mkdir -p /root/.npm/_cacache; echo 'cache-data' > /root/.npm/_cacache/index.json"
done

# Create the TARGET volume
echo "Creating target volume..."
TARGET_VOL=$(docker volume create)
docker run --rm -v "$TARGET_VOL":/data alpine sh -c "mkdir -p /data/uploads; echo '$TARGET_CONTENT' > /data/uploads/critical_manifest.json"

# Save the target volume name (hidden from agent, used for precise verification)
echo "$TARGET_VOL" > /tmp/target_volume_name.txt

# Record task start time
date +%s > /tmp/task_start_timestamp

# Setup agent terminal
mkdir -p /home/ga/Desktop
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'echo \"=== Docker Rescue Mission ===\"; echo \"Find the dangling volume containing uploads/critical_manifest.json\"; echo \"Mount it to a new container named recovery-service at /app/data\"; echo; exec bash'" > /tmp/terminal.log 2>&1 &

# Take initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_start.png
fi

echo "=== Setup Complete ==="
echo "Target Volume: $TARGET_VOL"
echo "Target Content ID: $UNIQUE_ID"