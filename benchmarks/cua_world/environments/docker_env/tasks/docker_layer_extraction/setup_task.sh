#!/bin/bash
# Setup script for docker_layer_extraction task
set -e

echo "=== Setting up Docker Layer Forensics Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for wait_for_docker if utils not present
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

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create a build context directory
BUILD_CTX=$(mktemp -d)
echo "Using build context: $BUILD_CTX"

# 1. Create the proprietary source code (The "Golden Ticket")
cat > "$BUILD_CTX/risk_model.py" << 'EOF'
import math

class CreditRiskScorer:
    """
    AcmeCorp Proprietary Credit Scoring Model v4.2
    CONFIDENTIAL - DO NOT DISTRIBUTE
    """
    
    def __init__(self, base_score=600):
        self.base_score = base_score
        # Secret proprietary weight factors
        self._income_weight = 0.85
        self._debt_weight = 1.2
        self._history_decay = 0.95

    def calculate_score(self, income, debt, history_years):
        """
        Calculates the risk score based on FICO-adjusted internal metrics.
        """
        if debt == 0:
            debt_ratio = 0
        else:
            debt_ratio = debt / (income + 1.0)
            
        risk_factor = (debt_ratio * self._debt_weight) - (math.log(income) * self._income_weight)
        history_bonus = history_years * 15 * self._history_decay
        
        final_score = self.base_score - (risk_factor * 100) + history_bonus
        return max(300, min(850, int(final_score)))

if __name__ == "__main__":
    print("Risk Model Loaded. Use via API.")
EOF

# Calculate and save the hash of the ground truth file for verification
sha256sum "$BUILD_CTX/risk_model.py" | awk '{print $1}' > /tmp/ground_truth_hash.txt
echo "Ground truth hash saved: $(cat /tmp/ground_truth_hash.txt)"

# 2. Create a dummy entrypoint that complains about the missing file
cat > "$BUILD_CTX/main.py" << 'EOF'
import sys
import os

def main():
    print("Starting Credit Score Service...")
    # Attempt to load the model
    if not os.path.exists("risk_model.py"):
        print("CRITICAL ERROR: risk_model.py not found!")
        print("The proprietary module seems to be missing.")
        # In a real app this would crash, but we keep it running for the task feel
    else:
        import risk_model
        print("Service Ready.")

if __name__ == "__main__":
    main()
EOF

# 3. Create Dockerfile with the "Delete" step
# Using multiple RUN instructions ensures separate layers
cat > "$BUILD_CTX/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Layer: Install dependencies
RUN pip install --no-cache-dir requests

# Layer: Copy ALL source code (including the secret file)
COPY . /app

# Layer: "Cleanup" - The developer deletes the secret file to hide it
RUN rm /app/risk_model.py && \
    echo "Cleaned up source code for production release"

CMD ["python", "main.py"]
EOF

# 4. Build the image
echo "Building target image acme/credit-score:v1..."
# Ensure DOCKER_BUILDKIT=1 to match modern behavior, though legacy builder also works
export DOCKER_BUILDKIT=1
docker build -t acme/credit-score:v1 "$BUILD_CTX"

# 5. Clean up evidence
echo "Destroying build artifacts..."
rm -rf "$BUILD_CTX"

# Verify the file is NOT in the running container
echo "Verifying file is deleted in final image..."
if docker run --rm acme/credit-score:v1 ls /app/risk_model.py 2>/dev/null; then
    echo "ERROR: risk_model.py is still visible in the container! Setup failed."
    exit 1
else
    echo "Confirmed: risk_model.py is missing from the final image (as expected)."
fi

# Ensure Desktop exists for the agent to save to
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=/home/ga/Desktop -- bash -c 'echo \"Docker Layer Forensics Task\"; echo \"Target Image: acme/credit-score:v1\"; echo \"Objective: Recover deleted file risk_model.py\"; echo; docker history acme/credit-score:v1; exec bash'" > /tmp/terminal.log 2>&1 &

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="