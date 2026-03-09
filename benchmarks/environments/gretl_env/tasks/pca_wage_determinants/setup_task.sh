#!/bin/bash
set -e
echo "=== Setting up PCA Wage Determinants task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty
rm -rf /home/ga/Documents/gretl_output/*
mkdir -p /home/ga/Documents/gretl_output
chown ga:ga /home/ga/Documents/gretl_output

# Create the specific wage_survey.gdt dataset
# This ensures we have a known starting state with 6 variables and 60 observations
cat > /home/ga/Documents/gretl_data/wage_survey.gdt << 'GDT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE gretldata SYSTEM "gretldata.dtd">
<gretldata name="wage_survey" frequency="1" startobs="1" endobs="60" type="cross-section">
<description>
Wage survey data for 60 workers. Variables derived from US Current Population Survey patterns.
</description>
<variables count="6">
<variable name="wage" label="hourly wage in dollars"/>
<variable name="educ" label="years of education"/>
<variable name="exper" label="years of work experience"/>
<variable name="age" label="age in years"/>
<variable name="hrswk" label="usual hours worked per week"/>
<variable name="tenure" label="years with current employer"/>
</variables>
<observations count="60" labels="false">
<obs>12.50 12 8 26 40 3 </obs>
<obs>24.00 16 10 32 45 5 </obs>
<obs>8.75 10 15 31 35 8 </obs>
<obs>45.00 18 12 36 50 7 </obs>
<obs>15.80 12 20 38 40 12 </obs>
<obs>18.50 14 8 28 42 4 </obs>
<obs>35.00 16 15 37 48 10 </obs>
<obs>10.50 11 5 22 30 2 </obs>
<obs>22.00 14 18 38 40 10 </obs>
<obs>55.00 20 10 36 50 6 </obs>
<obs>9.25 9 25 40 35 15 </obs>
<obs>28.00 16 5 27 45 3 </obs>
<obs>14.00 12 12 30 38 6 </obs>
<obs>32.50 17 8 31 45 5 </obs>
<obs>19.75 13 22 41 40 14 </obs>
<obs>11.00 10 30 46 32 18 </obs>
<obs>42.00 18 15 39 50 8 </obs>
<obs>16.50 12 5 23 38 2 </obs>
<obs>27.50 15 20 41 42 12 </obs>
<obs>7.50 8 20 34 25 10 </obs>
<obs>38.00 17 12 35 48 7 </obs>
<obs>20.00 14 10 30 40 5 </obs>
<obs>13.75 11 18 35 36 9 </obs>
<obs>30.00 16 8 30 44 4 </obs>
<obs>23.50 14 25 45 40 16 </obs>
<obs>17.00 13 5 24 38 2 </obs>
<obs>48.00 19 10 35 52 6 </obs>
<obs>12.00 10 22 38 34 12 </obs>
<obs>26.00 15 15 36 42 8 </obs>
<obs>21.00 14 12 32 40 6 </obs>
<obs>33.00 16 18 40 46 10 </obs>
<obs>9.50 9 28 43 30 16 </obs>
<obs>40.00 18 8 32 50 5 </obs>
<obs>15.00 12 10 28 38 4 </obs>
<obs>29.00 15 22 43 42 14 </obs>
<obs>18.00 13 15 34 38 8 </obs>
<obs>52.00 20 5 31 50 3 </obs>
<obs>11.50 10 12 28 34 6 </obs>
<obs>24.50 14 20 40 40 12 </obs>
<obs>36.00 17 10 33 48 6 </obs>
<obs>14.50 11 25 42 36 14 </obs>
<obs>22.50 14 8 28 40 4 </obs>
<obs>31.00 16 12 34 44 7 </obs>
<obs>10.00 9 30 45 28 18 </obs>
<obs>44.00 18 18 42 50 10 </obs>
<obs>16.00 12 8 26 38 3 </obs>
<obs>25.00 15 10 31 42 5 </obs>
<obs>19.00 13 18 37 38 10 </obs>
<obs>37.00 17 15 38 48 8 </obs>
<obs>8.00 8 25 39 26 12 </obs>
<obs>28.50 15 18 39 42 10 </obs>
<obs>34.00 16 20 42 46 12 </obs>
<obs>13.00 11 10 27 36 4 </obs>
<obs>46.00 19 8 33 50 5 </obs>
<obs>20.50 14 5 25 40 2 </obs>
<obs>15.50 12 15 33 38 8 </obs>
<obs>27.00 15 12 33 42 6 </obs>
<obs>41.00 18 10 34 50 6 </obs>
<obs>23.00 14 22 42 40 13 </obs>
<obs>50.00 20 8 34 52 5 </obs>
</observations>
</gretldata>
GDT_EOF

chown ga:ga /home/ga/Documents/gretl_data/wage_survey.gdt
chmod 644 /home/ga/Documents/gretl_data/wage_survey.gdt

# Launch Gretl with the dataset loaded
launch_gretl "/home/ga/Documents/gretl_data/wage_survey.gdt" "/home/ga/gretl_task.log"

# Wait for Gretl window
wait_for_gretl 60 || true
sleep 5

# Dismiss potential dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize and focus
maximize_gretl
focus_gretl
sleep 1

# Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="