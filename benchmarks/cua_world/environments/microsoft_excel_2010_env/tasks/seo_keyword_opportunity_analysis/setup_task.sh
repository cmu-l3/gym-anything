#!/bin/bash
set -e
echo "=== Setting up SEO Keyword Opportunity Analysis ==="

# 1. Setup paths and timestamps
TASK_DIR="/workspace/tasks/seo_keyword_opportunity_analysis"
DATA_DIR="/c/Users/Docker/Documents"
INPUT_FILE="$DATA_DIR/coffee_keywords.xlsx"
OUTPUT_FILE="$DATA_DIR/seo_analysis_complete.xlsx"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run
rm -f "$INPUT_FILE"
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json

# 3. Generate the Dataset using Python
# We generate this dynamically to ensure we have the Ground Truth control
echo "Generating dataset..."
python3 -c "
import pandas as pd
import numpy as np
import random

np.random.seed(42)  # Fixed seed for reproducibility

# Generate 500 keywords
modifiers = ['best', 'cheap', 'organic', 'fresh', 'buy', 'reviews', 'wholesale', 'bulk', 'fair trade', 'single origin']
roots = ['coffee beans', 'espresso', 'cold brew', 'french press', 'pour over', 'dark roast', 'light roast', 'arabica', 'robusta', 'coffee maker']
long_tail = ['near me', 'online', 'for sale', 'subscription', 'recipes', 'brewing guide', 'benefits', 'caffeine content']

keywords = []
for _ in range(500):
    k = f'{random.choice(modifiers)} {random.choice(roots)} {random.choice(long_tail)}'
    keywords.append(k)

# Generate metrics with realistic correlations
# High volume -> usually higher KD
volumes = np.random.lognormal(mean=5.5, sigma=1.5, size=500).astype(int)
volumes = np.clip(volumes, 10, 50000)

kds = []
cpcs = []

for vol in volumes:
    # KD roughly correlated with volume but with noise
    base_kd = min(100, int(np.log1p(vol) * 8))
    kd = np.clip(base_kd + np.random.randint(-20, 20), 0, 100)
    kds.append(kd)
    
    # CPC roughly correlated with KD (commercial intent)
    base_cpc = kd / 20.0
    cpc = np.clip(base_cpc + np.random.normal(0, 0.5), 0.1, 15.0)
    cpcs.append(round(cpc, 2))

df = pd.DataFrame({
    'Keyword': keywords,
    'Search_Volume': volumes,
    'Keyword_Difficulty': kds,
    'CPC_USD': cpcs
})

# Inject a known 'Golden Opportunity' to ensure filtering works
# Low KD (25), High Vol (5000), High CPC (5.00) -> High Value
df.iloc[0] = ['organic fair trade coffee beans bulk', 5000, 25, 5.00]

df.to_excel('$INPUT_FILE', index=False)
print(f'Created {len(df)} rows in $INPUT_FILE')
"

# 4. Ensure Excel 2010 is running (Empty state)
echo "Launching Excel..."
if ! tasklist.exe | grep -i "excel.exe" > /dev/null; then
    # Launch Excel in background
    cmd.exe /c "start excel" &
    sleep 5
fi

# 5. Focus and Maximize Excel
# Using powershell for window management on Windows environment
powershell.exe -Command "
\$wshell = New-Object -ComObject wscript.shell;
\$wshell.AppActivate('Microsoft Excel');
Start-Sleep -Seconds 1;
"

# 6. Take initial screenshot
echo "Capturing initial state..."
# Using screencap tool available in the env (scrot or similar if available, otherwise fallback)
# Note: The env spec says 'scrot' is available in the provided bash templates, 
# but in a pure Windows env we might need specific tools. 
# We'll stick to the standard GymAnything pattern.
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="