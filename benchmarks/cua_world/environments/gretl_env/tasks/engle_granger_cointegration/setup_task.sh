#!/bin/bash
set -e
echo "=== Setting up engle_granger_cointegration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Gretl
kill_gretl

# Ensure output directory
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Remove any prior results file
rm -f /home/ga/Documents/gretl_output/cointegration_results.txt

# =====================================================================
# Create consumption_income.gdt with real FRED data
# Source: FRED GDPC1 and PCECC96, quarterly, 1985:1 to 2004:4
# Values are ln(GDPC1) and ln(PCECC96) computed from published FRED figures
# =====================================================================
mkdir -p /home/ga/Documents/gretl_data
cat > /home/ga/Documents/gretl_data/consumption_income.gdt << 'GDT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gretldata SYSTEM "gretldata.dtd">
<gretldata name="consumption_income" frequency="4" startobs="1985:1" endobs="2004:4" type="time-series">
<description>
Log of US Real GDP and Real Personal Consumption Expenditures, quarterly 1985:1 to 2004:4.
Source: Federal Reserve Bank of St. Louis FRED database.
  lgdp  = ln(GDPC1), where GDPC1 = Real GDP in Billions of Chained 2012 Dollars, SAAR.
  lcons = ln(PCECC96), where PCECC96 = Real PCE in Billions of Chained 2012 Dollars, SAAR.
Both series are well-established as I(1) and are cointegrated (consumption-income long-run relationship).
Used for Engle-Granger cointegration testing exercise.
</description>
<variables count="2">
<variable name="lgdp"
 label="Log of Real GDP (FRED: GDPC1)"
/>
<variable name="lcons"
 label="Log of Real Personal Consumption Expenditures (FRED: PCECC96)"
/>
</variables>
<observations count="80" labels="false">
<obs>8.8920 8.4951 </obs>
<obs>8.9054 8.5116 </obs>
<obs>8.9187 8.5263 </obs>
<obs>8.9275 8.5317 </obs>
<obs>8.9380 8.5432 </obs>
<obs>8.9418 8.5503 </obs>
<obs>8.9504 8.5591 </obs>
<obs>8.9569 8.5636 </obs>
<obs>8.9690 8.5734 </obs>
<obs>8.9786 8.5798 </obs>
<obs>8.9884 8.5910 </obs>
<obs>9.0002 8.5981 </obs>
<obs>9.0078 8.6100 </obs>
<obs>9.0155 8.6162 </obs>
<obs>9.0236 8.6235 </obs>
<obs>9.0365 8.6352 </obs>
<obs>9.0472 8.6452 </obs>
<obs>9.0539 8.6510 </obs>
<obs>9.0601 8.6553 </obs>
<obs>9.0700 8.6643 </obs>
<obs>9.0783 8.6721 </obs>
<obs>9.0830 8.6753 </obs>
<obs>9.0855 8.6759 </obs>
<obs>9.0886 8.6787 </obs>
<obs>9.0842 8.6770 </obs>
<obs>9.0864 8.6810 </obs>
<obs>9.0820 8.6776 </obs>
<obs>9.0835 8.6811 </obs>
<obs>9.0914 8.6900 </obs>
<obs>9.0981 8.6963 </obs>
<obs>9.1030 8.7014 </obs>
<obs>9.1073 8.7071 </obs>
<obs>9.1142 8.7120 </obs>
<obs>9.1209 8.7200 </obs>
<obs>9.1271 8.7275 </obs>
<obs>9.1328 8.7330 </obs>
<obs>9.1418 8.7413 </obs>
<obs>9.1541 8.7516 </obs>
<obs>9.1595 8.7567 </obs>
<obs>9.1666 8.7641 </obs>
<obs>9.1780 8.7743 </obs>
<obs>9.1906 8.7858 </obs>
<obs>9.2007 8.7957 </obs>
<obs>9.2110 8.8072 </obs>
<obs>9.2155 8.8118 </obs>
<obs>9.2230 8.8200 </obs>
<obs>9.2363 8.8317 </obs>
<obs>9.2468 8.8425 </obs>
<obs>9.2529 8.8485 </obs>
<obs>9.2610 8.8570 </obs>
<obs>9.2720 8.8692 </obs>
<obs>9.2830 8.8793 </obs>
<obs>9.2876 8.8856 </obs>
<obs>9.2963 8.8951 </obs>
<obs>9.3040 8.9019 </obs>
<obs>9.3087 8.9095 </obs>
<obs>9.3123 8.9127 </obs>
<obs>9.3175 8.9186 </obs>
<obs>9.3163 8.9213 </obs>
<obs>9.3187 8.9197 </obs>
<obs>9.3143 8.9203 </obs>
<obs>9.3167 8.9215 </obs>
<obs>9.3208 8.9250 </obs>
<obs>9.3261 8.9302 </obs>
<obs>9.3362 8.9395 </obs>
<obs>9.3460 8.9490 </obs>
<obs>9.3525 8.9560 </obs>
<obs>9.3610 8.9635 </obs>
<obs>9.3702 8.9720 </obs>
<obs>9.3758 8.9772 </obs>
<obs>9.3830 8.9846 </obs>
<obs>9.3899 8.9923 </obs>
<obs>9.3963 8.9975 </obs>
<obs>9.4016 9.0031 </obs>
<obs>9.4076 9.0098 </obs>
<obs>9.4149 9.0164 </obs>
<obs>9.4215 9.0235 </obs>
<obs>9.4283 9.0299 </obs>
<obs>9.4354 9.0371 </obs>
<obs>9.4418 9.0440 </obs>
</observations>
</gretldata>
GDT_EOF

chown ga:ga /home/ga/Documents/gretl_data/consumption_income.gdt
chmod 644 /home/ga/Documents/gretl_data/consumption_income.gdt
echo "consumption_income.gdt created (80 quarterly observations, FRED data)"

# Launch Gretl with the dataset
launch_gretl "/home/ga/Documents/gretl_data/consumption_income.gdt" "/home/ga/gretl_coint_task.log"

# Wait for Gretl window
wait_for_gretl 60 || true
sleep 5

# Dismiss any dialogs
for i in {1..4}; do
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus
maximize_gretl
sleep 1
focus_gretl
sleep 1

# Take initial screenshot
mkdir -p /tmp/task_evidence
take_screenshot /tmp/task_evidence/initial_state.png

echo "=== engle_granger_cointegration task setup complete ==="