#!/bin/bash
set -e
echo "=== Setting up Teacher Salary Schedule Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Create Documents directory
sudo -u ga mkdir -p /home/ga/Documents

# 2. clean up previous artifacts
rm -f /home/ga/Documents/Maplewood_Salary_Schedule_2024_2025.odt
rm -f /home/ga/Documents/district_compensation_data.json

# 3. Write the JSON data file
cat > /home/ga/Documents/district_compensation_data.json << 'JSONEOF'
{
  "district": {
    "name": "Maplewood Consolidated School District #18",
    "address": "2100 Maplewood Drive, Maplewood, IL 62863",
    "superintendent": "Dr. Franklin T. Okafor",
    "board_president": "Catherine M. Lindstrom"
  },
  "document": {
    "title": "Certified Staff Compensation Schedule",
    "fiscal_year": "2024-2025",
    "board_approval_date": "June 18, 2024"
  },
  "salary_schedule": {
    "lanes": [
      "BA", "BA+15", "MA", "MA+15", "MA+30", "EdD_PhD"
    ],
    "grid": [
      {"step": 1,  "BA": 42500, "BA+15": 44125, "MA": 47600, "MA+15": 49350, "MA+30": 51100, "EdD_PhD": 54500},
      {"step": 2,  "BA": 43925, "BA+15": 45580, "MA": 49075, "MA+15": 50860, "MA+30": 52645, "EdD_PhD": 56125},
      {"step": 3,  "BA": 45390, "BA+15": 47100, "MA": 50615, "MA+15": 52435, "MA+30": 54260, "EdD_PhD": 57820},
      {"step": 4,  "BA": 46900, "BA+15": 48660, "MA": 52215, "MA+15": 54075, "MA+30": 55940, "EdD_PhD": 59590},
      {"step": 5,  "BA": 48455, "BA+15": 50270, "MA": 53880, "MA+15": 55785, "MA+30": 57690, "EdD_PhD": 61435},
      {"step": 6,  "BA": 50060, "BA+15": 51930, "MA": 55610, "MA+15": 57560, "MA+30": 59515, "EdD_PhD": 63360},
      {"step": 7,  "BA": 51715, "BA+15": 53645, "MA": 57410, "MA+15": 59410, "MA+30": 61415, "EdD_PhD": 65365},
      {"step": 8,  "BA": 53420, "BA+15": 55415, "MA": 59280, "MA+15": 61335, "MA+30": 63390, "EdD_PhD": 67455},
      {"step": 9,  "BA": 55585, "BA+15": 57660, "MA": 61690, "MA+15": 63815, "MA+30": 65940, "EdD_PhD": 70175},
      {"step": 10, "BA": 58215, "BA+15": 60390, "MA": 64620, "MA+15": 66820, "MA+30": 69020, "EdD_PhD": 73440},
      {"step": 11, "BA": 61340, "BA+15": 63630, "MA": 68500, "MA+15": 70930, "MA+30": 73360, "EdD_PhD": 78830},
      {"step": 12, "BA": 64890, "BA+15": 67486, "MA": 72835, "MA+15": 75505, "MA+30": 78175, "EdD_PhD": 84750}
    ]
  },
  "extra_duty_stipends": {
    "categories": {
      "Athletics": [
        {"position": "Head Football Coach", "annual_stipend": 6200},
        {"position": "Head Basketball Coach", "annual_stipend": 5800},
        {"position": "Head Track Coach", "annual_stipend": 4500},
        {"position": "Assistant Coach", "annual_stipend": 3100}
      ],
      "Activities": [
        {"position": "Department Chair", "annual_stipend": 3400},
        {"position": "Yearbook Advisor", "annual_stipend": 2500},
        {"position": "Student Council", "annual_stipend": 1800},
        {"position": "Chess Club", "annual_stipend": 950}
      ]
    }
  },
  "benefits": {
    "plans": [
      {
        "plan": "PPO",
        "tiers": [
          {"tier": "Employee Only", "district_contrib": 620},
          {"tier": "Family", "district_contrib": 1210}
        ]
      },
      {
        "plan": "HMO",
        "tiers": [
          {"tier": "Employee Only", "district_contrib": 590},
          {"tier": "Family", "district_contrib": 1210}
        ]
      }
    ]
  }
}
JSONEOF
chown ga:ga /home/ga/Documents/district_compensation_data.json
chmod 644 /home/ga/Documents/district_compensation_data.json

# 4. Record initial state
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# 5. Launch OpenOffice Writer
if ! pgrep -f "soffice" > /dev/null; then
    echo "Starting OpenOffice..."
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
    sleep 8
fi

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "OpenOffice" | awk '{print $1}' | head -1)
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a "$WID"
        break
    fi
    sleep 1
done

# 7. Dismiss any startup dialogs (Esc key a few times)
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="