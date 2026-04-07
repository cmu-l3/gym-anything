#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Campaign Finance Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/election_investigation"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"

# ──────────────────────────────────────────────────────────
# 1. Create the public dataset (what the agent sees)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/itcont_sample_2024.txt" << 'EOF'
DONOR_NAME,ZIP_CODE,TRANSACTION_DT,TRANSACTION_AMT,ELECTION_TP
TESTER, ALICE,12345-0000,10202024,1000,P2024
Tester, Alice ,12345,10212024,3000,P2024
TESTER, ALICE,12345,10222024,-500,P2024
VARGAS, LUIS,54321,11052024,2000,P2024
VARGAS, LUIS,54321,11062024,2000,G2024
DOE, JOHN,99999,03152024,3500,P2024
EOF
chown ga:ga "$WORKSPACE_DIR/data/itcont_sample_2024.txt"

# ──────────────────────────────────────────────────────────
# 2. Create the hidden ground truth dataset (for anti-gaming)
# ──────────────────────────────────────────────────────────
mkdir -p /var/lib/app/ground_truth
cat > /var/lib/app/ground_truth/secret_itcont.txt << 'EOF'
DONOR_NAME,ZIP_CODE,TRANSACTION_DT,TRANSACTION_AMT,ELECTION_TP
DATE, TEST,11111,10152024,100,P2024
SMITH, JANE,12345,01012024,3500,P2024
SMITH, JANE,12345,01052024,-500,P2024
WILLIAMS, TOM,44444-1111,04012024,2000,P2024
Williams, Tom ,44444,05012024,2000,P2024
JOHNSON, ANN,22222,06012024,2500,P2024
JOHNSON, ANN,22222,09012024,2500,G2024
EOF
# Ensure the agent cannot read the secret dataset manually
chmod -R 700 /var/lib/app/ground_truth
chown -R root:root /var/lib/app/ground_truth

# ──────────────────────────────────────────────────────────
# 3. Create the buggy Python pipeline
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/fec_analysis.py" << 'PYEOF'
import pandas as pd
import os

DATA_PATH = os.environ.get('FEC_DATA_PATH', 'data/itcont_sample_2024.txt')
OUT_DIR = os.environ.get('FEC_OUT_DIR', 'output/')
LEGAL_LIMIT = 3300

def run_analysis():
    os.makedirs(OUT_DIR, exist_ok=True)
    # Load data
    df = pd.read_csv(DATA_PATH, dtype={'ZIP_CODE': str})

    # 1. Clean amounts
    # BUG: Drops refunds which should offset contributions to find NET total
    df = df[df['TRANSACTION_AMT'] > 0]

    # 2. Parse dates
    # BUG: Incorrect format string for MMDDYYYY causing late months to become NaT
    df['DATE'] = pd.to_datetime(df['TRANSACTION_DT'].astype(str).str.zfill(8), format='%d%m%Y', errors='coerce')

    # 3. Monthly trends
    # Group by month and sum amounts
    monthly = df.groupby(df['DATE'].dt.month)['TRANSACTION_AMT'].sum().reset_index()
    monthly.columns = ['MONTH', 'TOTAL_AMT']
    monthly.to_csv(os.path.join(OUT_DIR, 'monthly_trends.csv'), index=False)

    # 4. Identify violators
    # BUG: Fails to normalize names and zip codes (5-digit) before grouping
    # BUG: Fails to separate contributions by election (ELECTION_TP)
    donor_totals = df.groupby(['DONOR_NAME', 'ZIP_CODE'])['TRANSACTION_AMT'].sum().reset_index()
    
    violators = donor_totals[donor_totals['TRANSACTION_AMT'] > LEGAL_LIMIT]
    violators.to_csv(os.path.join(OUT_DIR, 'flagged_violators.csv'), index=False)

if __name__ == "__main__":
    run_analysis()
    print(f"Analysis complete. Outputs saved to {OUT_DIR}")
PYEOF
chown ga:ga "$WORKSPACE_DIR/fec_analysis.py"

# ──────────────────────────────────────────────────────────
# 4. Launch VS Code
# ──────────────────────────────────────────────────────────
# Kill any existing VSCode instances
pkill -f "code" 2>/dev/null || true
sleep 2

# Start VS Code in the workspace
echo "Launching VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/fec_analysis.py &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="