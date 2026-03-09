#!/bin/bash
set -e
echo "=== Setting up NREL Phase VI Validation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ensure directories exist
mkdir -p /home/ga/Documents/airfoils
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents

# 1. Prepare S809 Airfoil Data
# Try to download real data from UIUC database
AIRFOIL_PATH="/home/ga/Documents/airfoils/s809.dat"
UIUC_URL="https://m-selig.ae.illinois.edu/ads/coord/s809.dat"

if [ ! -f "$AIRFOIL_PATH" ]; then
    echo "Downloading S809 airfoil data..."
    if wget -q -O "$AIRFOIL_PATH" "$UIUC_URL"; then
        echo "Download successful."
    else
        echo "Download failed, using backup header/data..."
        # Create a valid backup S809 file if download fails
        cat > "$AIRFOIL_PATH" << EOF
NREL S809 Airfoil
 1.00000  0.00000
 0.99605  0.00046
 0.98467  0.00223
 0.96705  0.00539
 0.94411  0.00984
 0.91637  0.01538
 0.88448  0.02165
 0.84914  0.02826
 0.81105  0.03487
 0.77093  0.04113
 0.72922  0.04684
 0.68652  0.05183
 0.64332  0.05601
 0.60007  0.05933
 0.55716  0.06180
 0.51486  0.06338
 0.47350  0.06411
 0.43323  0.06399
 0.39423  0.06305
 0.35670  0.06132
 0.32077  0.05892
 0.28666  0.05596
 0.25439  0.05247
 0.22416  0.04856
 0.19602  0.04427
 0.17006  0.03964
 0.14629  0.03473
 0.12470  0.02960
 0.10528  0.02431
 0.08801  0.01897
 0.07281  0.01366
 0.05963  0.00845
 0.04838  0.00346
 0.03896 -0.00115
 0.03125 -0.00529
 0.02511 -0.00885
 0.02041 -0.01177
 0.01694 -0.01402
 0.01454 -0.01560
 0.01300 -0.01657
 0.01217 -0.01700
 0.01199 -0.01702
 0.01243 -0.01651
 0.01348 -0.01550
 0.01509 -0.01408
 0.01726 -0.01229
 0.02002 -0.01018
 0.02340 -0.00780
 0.02747 -0.00517
 0.03224 -0.00236
 0.03774  0.00062
 0.04400  0.00369
 0.05101  0.00680
 0.05879  0.00991
 0.06734  0.01297
 0.07667  0.01594
 0.08679  0.01878
 0.09769  0.02146
 0.10939  0.02394
 0.12188  0.02619
 0.13516  0.02821
 0.14923  0.02996
 0.16409  0.03144
 0.17973  0.03265
 0.19616  0.03358
 0.21338  0.03423
 0.23136  0.03463
 0.25009  0.03478
 0.26955  0.03472
 0.28974  0.03448
 0.31064  0.03411
 0.33223  0.03362
 0.35449  0.03303
 0.37739  0.03236
 0.40090  0.03164
 0.42498  0.03087
 0.44960  0.03008
 0.47473  0.02928
 0.50033  0.02847
 0.52636  0.02766
 0.55279  0.02684
 0.57956  0.02602
 0.60663  0.02517
 0.63394  0.02430
 0.66144  0.02339
 0.68908  0.02244
 0.71679  0.02144
 0.74450  0.02037
 0.77215  0.01923
 0.79967  0.01802
 0.82697  0.01673
 0.85397  0.01535
 0.88056  0.01387
 0.90663  0.01229
 0.93206  0.01058
 0.95672  0.00874
 0.98048  0.00673
 1.00000  0.00000
EOF
    fi
fi

# Ensure permissions
chown ga:ga "$AIRFOIL_PATH"
chmod 644 "$AIRFOIL_PATH"

# Cleanup previous results
rm -f /home/ga/Documents/nrel_phase6_report.txt
rm -f /home/ga/Documents/projects/nrel_phase6.wpa

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for window
wait_for_qblade 60

# Maximize
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="