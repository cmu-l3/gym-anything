#!/bin/bash
set -e
echo "=== Setting up Mixed ANOVA Conscientiousness task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATASET="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$DATASET" ]; then
    echo "Generating BFI25.csv..."
    if [ -f "/opt/jamovi_datasets/extract_bfi25.py" ]; then
        python3 /opt/jamovi_datasets/extract_bfi25.py
    else
        echo "ERROR: Extraction script not found."
        exit 1
    fi
fi
chown ga:ga "$DATASET"

# 3. Install dependencies and Compute Ground Truth (Hidden)
echo "Installing pingouin for ground truth generation..."
pip3 install pingouin pandas numpy scipy --break-system-packages > /dev/null 2>&1 || true

echo "Computing ground truth..."
mkdir -p /var/lib/jamovi_ground_truth
python3 << 'PYEOF'
import pandas as pd
import pingouin as pg
import json
import os
import sys

try:
    df = pd.read_csv('/home/ga/Documents/Jamovi/BFI25.csv')
    
    # Add Subject ID
    df['Subject'] = range(len(df))
    
    # Reshape to long format
    df_long = df.melt(
        id_vars=['Subject', 'gender'],
        value_vars=['C1', 'C2', 'C3', 'C4', 'C5'],
        var_name='CItem',
        value_name='Score'
    )
    
    # Filter valid gender (1=Male, 2=Female) and drop NAs
    df_long = df_long[df_long['gender'].isin([1, 2])].dropna()
    
    # Run Mixed ANOVA
    # within='CItem', between='gender'
    aov = pg.mixed_anova(data=df_long, dv='Score', within='CItem', between='gender', subject='Subject')
    
    results = {}
    
    # 1. Within-Subjects (CItem)
    row_item = aov[aov['Source'] == 'CItem'].iloc[0]
    results['Item_F'] = float(row_item['F'])
    results['Item_p'] = float(row_item['p-unc'])
    
    # 2. Between-Subjects (gender)
    row_gender = aov[aov['Source'] == 'gender'].iloc[0]
    results['Gender_F'] = float(row_gender['F'])
    results['Gender_p'] = float(row_gender['p-unc'])
    
    # 3. Interaction (CItem * gender)
    row_inter = aov[aov['Source'] == 'Interaction'].iloc[0]
    results['Interaction_F'] = float(row_inter['F'])
    results['Interaction_p'] = float(row_inter['p-unc'])
    
    # 4. Sphericity (Mauchly) & Epsilon (GG)
    # Pingouin's mixed_anova usually assumes sphericity by default for the main table,
    # but we can check properties or run separate epsilon function.
    spher = pg.sphericity(df_long, dv='Score', within='CItem', subject='Subject')
    # spher returns (spher, W, chi2, dof, pval)
    results['Mauchly_p'] = float(spher.pval)
    results['Mauchly_significant'] = 'yes' if results['Mauchly_p'] < 0.05 else 'no'
    
    eps = pg.epsilon(df_long, dv='Score', within='CItem', subject='Subject')
    results['GG_epsilon'] = float(eps)

    # Save
    with open('/var/lib/jamovi_ground_truth/mixed_anova_results.json', 'w') as f:
        json.dump(results, f, indent=2)
        
    print("Ground truth computed successfully.")

except Exception as e:
    print(f"Error computing ground truth: {e}")
    sys.exit(1)
PYEOF

chmod 644 /var/lib/jamovi_ground_truth/mixed_anova_results.json

# 4. Clean previous artifacts
rm -f "/home/ga/Documents/Jamovi/MixedANOVA_Conscientiousness.omv"
rm -f "/home/ga/Documents/Jamovi/mixed_anova_report.txt"

# 5. Launch Jamovi (Clean State)
echo "Launching Jamovi..."
# We launch without a file so the agent has to open it (as per task description step 1)
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi_task.log 2>&1 &"

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "jamovi"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Initial Screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="