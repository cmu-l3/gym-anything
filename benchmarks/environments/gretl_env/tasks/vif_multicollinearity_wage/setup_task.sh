#!/bin/bash
set -e
echo "=== Setting up VIF Multicollinearity Wage task ==="
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Kill any running Gretl instances
kill_gretl

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/vif_analysis.inp
rm -f /home/ga/Documents/gretl_output/wage_model.txt
rm -f /home/ga/Documents/gretl_output/vif_results.txt
chown -R ga:ga /home/ga/Documents/gretl_output

# =====================================================================
# Create CPS wage dataset (Realistically structured data)
# =====================================================================
echo "Creating CPS wage dataset..."
mkdir -p /home/ga/Documents/gretl_data

cat > /home/ga/Documents/gretl_data/cps_wages.gdt << 'CPSDATA_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gretldata SYSTEM "gretldata.dtd">
<gretldata name="cps_wages" frequency="1" startobs="1" endobs="60" type="cross-section">
<description>
CPS Wage Data: Hourly wage rates and worker characteristics.
Source: Derived from Current Population Survey (CPS), March Supplement.
60 observations of prime-age workers.
</description>
<variables count="8">
<variable name="wage" label="hourly wage rate in dollars"/>
<variable name="educ" label="years of education"/>
<variable name="exper" label="years of potential work experience"/>
<variable name="female" label="1 if female, 0 if male" discrete="true"/>
<variable name="black" label="1 if black, 0 otherwise" discrete="true"/>
<variable name="metro" label="1 if metropolitan area" discrete="true"/>
<variable name="south" label="1 if southern region" discrete="true"/>
<variable name="west" label="1 if western region" discrete="true"/>
</variables>
<observations count="60" labels="false">
<obs>22.50 16 12 0 0 1 0 0 </obs>
<obs>14.75 12 20 1 0 1 1 0 </obs>
<obs>45.00 20 15 0 0 1 0 0 </obs>
<obs>11.25 12 8 1 1 1 0 0 </obs>
<obs>18.00 14 18 0 0 1 0 1 </obs>
<obs>9.50 11 5 1 0 0 1 0 </obs>
<obs>32.00 18 10 0 0 1 0 0 </obs>
<obs>16.50 13 22 0 0 1 1 0 </obs>
<obs>12.00 12 3 0 1 1 0 0 </obs>
<obs>28.75 16 20 0 0 1 0 1 </obs>
<obs>10.50 10 15 1 0 0 1 0 </obs>
<obs>38.00 18 18 0 0 1 0 0 </obs>
<obs>15.25 14 6 1 0 1 0 0 </obs>
<obs>20.00 16 8 0 0 1 1 0 </obs>
<obs>8.75 10 2 1 1 0 1 0 </obs>
<obs>55.00 20 22 0 0 1 0 0 </obs>
<obs>13.50 12 12 1 0 1 0 1 </obs>
<obs>25.00 16 15 0 0 1 0 0 </obs>
<obs>17.75 14 25 0 0 0 0 0 </obs>
<obs>11.00 12 4 1 0 1 1 0 </obs>
<obs>42.00 20 10 0 0 1 0 0 </obs>
<obs>19.50 14 20 0 1 1 0 0 </obs>
<obs>14.00 13 8 1 0 1 0 1 </obs>
<obs>30.00 18 12 0 0 1 0 0 </obs>
<obs>10.00 11 3 1 1 0 1 0 </obs>
<obs>23.50 16 14 0 0 1 0 0 </obs>
<obs>35.00 18 16 0 0 1 1 0 </obs>
<obs>12.75 12 10 1 0 1 0 0 </obs>
<obs>27.00 16 22 0 0 1 0 1 </obs>
<obs>9.00 10 6 1 0 0 1 0 </obs>
<obs>48.00 20 18 0 0 1 0 0 </obs>
<obs>16.00 14 9 0 0 1 0 0 </obs>
<obs>21.00 16 11 0 1 1 0 0 </obs>
<obs>13.00 12 15 1 0 0 0 0 </obs>
<obs>36.50 18 14 0 0 1 0 1 </obs>
<obs>11.50 11 7 1 0 1 1 0 </obs>
<obs>26.00 16 18 0 0 1 0 0 </obs>
<obs>15.50 13 20 1 0 1 0 0 </obs>
<obs>40.00 20 8 0 0 1 0 0 </obs>
<obs>18.50 14 25 0 0 1 1 0 </obs>
<obs>10.25 12 2 0 1 0 0 0 </obs>
<obs>33.00 18 12 0 0 1 0 0 </obs>
<obs>14.50 12 16 1 0 1 0 1 </obs>
<obs>22.00 16 10 0 0 1 0 0 </obs>
<obs>8.50 9 4 1 1 0 1 0 </obs>
<obs>29.00 16 20 0 0 1 0 0 </obs>
<obs>12.50 12 6 1 0 1 1 0 </obs>
<obs>50.00 20 20 0 0 1 0 0 </obs>
<obs>17.00 14 14 0 0 1 0 1 </obs>
<obs>24.00 16 16 0 0 0 0 0 </obs>
<obs>11.75 12 5 1 0 1 0 0 </obs>
<obs>37.00 18 15 0 0 1 0 0 </obs>
<obs>13.75 13 10 1 1 1 0 0 </obs>
<obs>20.50 14 22 0 0 1 1 0 </obs>
<obs>9.25 10 3 1 0 0 1 0 </obs>
<obs>31.00 18 8 0 0 1 0 0 </obs>
<obs>15.00 13 12 0 0 1 0 1 </obs>
<obs>43.00 20 14 0 0 1 0 0 </obs>
<obs>19.00 14 18 1 0 1 0 0 </obs>
<obs>7.75 9 1 1 1 0 1 0 </obs>
</observations>
</gretldata>
CPSDATA_EOF

chown ga:ga /home/ga/Documents/gretl_data/cps_wages.gdt
chmod 644 /home/ga/Documents/gretl_data/cps_wages.gdt

# =====================================================================
# Generate Ground Truth for Verification
# =====================================================================
echo "Generating ground truth values..."
mkdir -p /tmp/ground_truth

cat > /tmp/ground_truth/generate_truth.inp << 'GT_EOF'
open "/home/ga/Documents/gretl_data/cps_wages.gdt"
series lwage = ln(wage)
series exper2 = exper^2
ols lwage const educ exper exper2 female black metro south west
vif
GT_EOF

# Run using gretlcli
su - ga -c "gretlcli -b /tmp/ground_truth/generate_truth.inp" > /tmp/ground_truth/expected_output.txt 2>&1

# =====================================================================
# Launch Gretl
# =====================================================================
echo "Launching Gretl with dataset..."
launch_gretl "/home/ga/Documents/gretl_data/cps_wages.gdt" "/home/ga/gretl_task.log"

wait_for_gretl 60 || true
sleep 2

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

maximize_gretl
focus_gretl

# Capture initial screenshot
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="