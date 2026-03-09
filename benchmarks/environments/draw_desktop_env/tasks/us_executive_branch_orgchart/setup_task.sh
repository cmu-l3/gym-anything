#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero harmlessly

echo "=== Setting up us_executive_branch_orgchart task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any previous outputs
rm -f /home/ga/Desktop/us_executive_branch.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/us_executive_branch.png 2>/dev/null || true

# Create the source data file on the Desktop
cat > /home/ga/Desktop/executive_branch_structure.txt << 'DATAEOF'
US EXECUTIVE BRANCH ORGANIZATIONAL STRUCTURE
=============================================

HIERARCHY:
  President of the United States
    └── Vice President of the United States
    └── Executive Office of the President
    └── 15 Cabinet Departments (listed below)

CABINET DEPARTMENTS (by establishment date):
─────────────────────────────────────────────
 #  Department                                  Est.   Employees (approx.)
 1  Department of State                         1789      77,243
 2  Department of the Treasury                  1789      91,856
 3  Department of Defense                       1947     742,208
 4  Department of Justice                       1870     115,423
 5  Department of the Interior                  1849      68,563
 6  Department of Agriculture                   1862      96,164
 7  Department of Commerce                      1903      47,432
 8  Department of Labor                         1913      16,376
 9  Department of Health and Human Services     1953      89,628
10  Department of Housing and Urban Development 1965       8,326
11  Department of Transportation                1966      54,724
12  Department of Energy                        1977      16,236
13  Department of Education                     1979       4,133
14  Department of Veterans Affairs              1989     412,158
15  Department of Homeland Security             2002     240,853

SUGGESTED COLOR GROUPINGS:
─────────────────────────
National Security (red/orange tones):
  - State, Defense, Homeland Security, Justice

Economic & Fiscal (blue/teal tones):
  - Treasury, Commerce, Labor

Domestic & Social (green/purple tones):
  - HHS, Education, HUD, Veterans Affairs,
    Interior, Agriculture, Transportation, Energy

KEY INDEPENDENT AGENCIES (for Page 2):
──────────────────────────────────────
  - NASA (National Aeronautics and Space Administration), Est. 1958
  - EPA (Environmental Protection Agency), Est. 1970
  - CIA (Central Intelligence Agency), Est. 1947
  - FCC (Federal Communications Commission), Est. 1934
  - SEC (Securities and Exchange Commission), Est. 1934
  - SSA (Social Security Administration), Est. 1935
  - SBA (Small Business Administration), Est. 1953
  - NSF (National Science Foundation), Est. 1950
  - USPS (United States Postal Service), Est. 1971
  - FEMA (Federal Emergency Management Agency), Est. 1979
DATAEOF
chown ga:ga /home/ga/Desktop/executive_branch_structure.txt
chmod 644 /home/ga/Desktop/executive_branch_structure.txt

# Record baseline state
ls -la /home/ga/Desktop/*.drawio 2>/dev/null | wc -l > /tmp/initial_drawio_count
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5
# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (ESC creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="