#!/bin/bash
echo "=== Setting up holiday_calendar_multisite task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for Sentrifugo web service to be fully responsive
wait_for_http "$SENTRIFUGO_URL" 60

# ---- Clean up any prior run artifacts (Idempotency) ----
echo "Cleaning up prior run artifacts..."
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
DELETE hd FROM main_holidaydates hd 
INNER JOIN main_holidaygroups hg ON hd.groupid = hg.id 
WHERE hg.groupname IN ('Texas Plant Holidays', 'California Plant Holidays', 'Pennsylvania Plant Holidays');
" 2>/dev/null || true

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
DELETE FROM main_holidaygroups 
WHERE groupname IN ('Texas Plant Holidays', 'California Plant Holidays', 'Pennsylvania Plant Holidays');
" 2>/dev/null || true

# ---- Create the Operations Memo on the Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/2026_holiday_schedule.txt << 'EOF'
ACME GLOBAL BIOMASS POWER
Operations Memo — 2026 Regional Holiday Schedules
To: HR System Administrator
==================================================

Please configure the Sentrifugo Holiday Management module with the 2026 schedules
for our three regional plants.

Create THREE distinct holiday groups and add the exact 7 holidays listed for each.

--------------------------------------------------
GROUP 1: Texas Plant Holidays
--------------------------------------------------
1. New Year's Day      - January 1, 2026
2. Memorial Day        - May 25, 2026
3. Juneteenth          - June 19, 2026
4. Independence Day    - July 3, 2026 (Observed - actual falls on a Saturday)
5. Labor Day           - September 7, 2026
6. Thanksgiving Day    - November 26, 2026
7. Christmas Day       - December 25, 2026

--------------------------------------------------
GROUP 2: California Plant Holidays
--------------------------------------------------
1. New Year's Day      - January 1, 2026
2. César Chávez Day    - March 31, 2026
3. Memorial Day        - May 25, 2026
4. Independence Day    - July 3, 2026 (Observed)
5. Labor Day           - September 7, 2026
6. Thanksgiving Day    - November 26, 2026
7. Christmas Day       - December 25, 2026

--------------------------------------------------
GROUP 3: Pennsylvania Plant Holidays
--------------------------------------------------
1. New Year's Day      - January 1, 2026
2. Presidents' Day     - February 16, 2026
3. Memorial Day        - May 25, 2026
4. Independence Day    - July 3, 2026 (Observed)
5. Labor Day           - September 7, 2026
6. Thanksgiving Day    - November 26, 2026
7. Christmas Day       - December 25, 2026

==================================================
NOTE: Please ensure dates are accurate, especially the observed
Independence Day (July 3) and state-specific holidays.
EOF

chown ga:ga /home/ga/Desktop/2026_holiday_schedule.txt
echo "Memo created at ~/Desktop/2026_holiday_schedule.txt"

# ---- Ensure Sentrifugo is logged in and navigate to Holidays page ----
# We navigate to the dashboard so the agent has to find the Holidays section itself
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"

# Take initial screenshot for evidence
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="