#!/bin/bash
echo "=== Setting up NIH Grant Formatting Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Cleanup any previous runs and kill running instances
cleanup_temp_files
kill_onlyoffice ga
sleep 1

# Ensure directories exist
DOC_DIR="/home/ga/Documents/TextDocuments"
mkdir -p "$DOC_DIR"

# Generate the raw text dataset (Realistic NIH proposal snippet)
cat > "$DOC_DIR/research_strategy_raw.txt" << 'EOF'
Title: Targeting Cellular Senescence in Intervertebral Disc Degeneration

[SECTION] Specific Aims
Intervertebral disc (IVD) degeneration is a leading cause of chronic low back pain, resulting in immense socioeconomic burden. Current treatments are palliative and fail to address the underlying cellular pathogenesis. We propose a novel therapeutic strategy targeting cellular senescence.
Aim 1: Elucidate the role of senescent cells in driving IVD degeneration.
Aim 2: Evaluate the efficacy of targeted senolytic compounds in a pre-clinical model.

[SECTION] Significance
Chronic low back pain affects up to 80% of adults at some point in their lives. The proposed research addresses a critical gap in our understanding of IVD aging and degeneration, potentially shifting the paradigm from symptom management to disease modification.

[SECTION] Innovation
This proposal utilizes a cutting-edge senolytic compound coupled with a novel sustained-release delivery system. The table below compares our proposed method with current standards.

Feature	Current Standard	Proposed Method
Sensitivity	85%	98%
Specificity	80%	95%
Cost per assay	$50	$10

[SECTION] Approach
We will utilize a well-established puncture-induced disc degeneration model in wild-type mice. Disc height index (DHI) and histological grading will be assessed at 4, 8, and 12 weeks post-injury.
EOF

chown -R ga:ga /home/ga/Documents

# Launch OnlyOffice Document Editor
echo "Starting ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:word > /tmp/onlyoffice.log 2>&1 &"

# Wait for the application window to appear
wait_for_window "ONLYOFFICE" 30

# Maximize and focus the window
WID=$(wmctrl -l | grep -i "ONLYOFFICE" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial state screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="