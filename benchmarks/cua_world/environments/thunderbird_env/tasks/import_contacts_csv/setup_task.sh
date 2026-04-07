#!/bin/bash
set -e
echo "=== Setting up import_contacts_csv task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Create the realistic CSV file with fictional referring physicians
cat > /home/ga/Documents/referring_physicians.csv << 'CSVEOF'
First Name,Last Name,Display Name,Primary Email,Organization,Title,Work Phone
Sarah,Chen,Dr. Sarah Chen,s.chen@northvalleymed.org,North Valley Medical Group,Cardiologist,555-0147
Michael,Okafor,Dr. Michael Okafor,m.okafor@lakeviewclinic.com,Lakeview Family Clinic,Family Medicine,555-0293
Patricia,Reeves,Dr. Patricia Reeves,p.reeves@summithealthpartners.org,Summit Health Partners,Neurologist,555-0381
James,Gupta,Dr. James Gupta,j.gupta@meridianortho.com,Meridian Orthopedics,Orthopedic Surgeon,555-0412
Linda,Nakamura,Dr. Linda Nakamura,l.nakamura@harborpulmonary.org,Harbor Pulmonary Associates,Pulmonologist,555-0528
Robert,Fernandez,Dr. Robert Fernandez,r.fernandez@cedardermatology.com,Cedar Dermatology Center,Dermatologist,555-0639
Emily,Johansson,Dr. Emily Johansson,e.johansson@valleyviewpeds.org,Valley View Pediatrics,Pediatrician,555-0741
David,Abramowitz,Dr. David Abramowitz,d.abramowitz@pinecrestgi.com,Pinecrest GI Specialists,Gastroenterologist,555-0854
Angela,Whitfield,Dr. Angela Whitfield,a.whitfield@mountainviewent.org,Mountain View ENT,Otolaryngologist,555-0962
Thomas,Patel,Dr. Thomas Patel,t.patel@riverbendurology.com,Riverbend Urology,Urologist,555-1073
Maria,Kowalski,Dr. Maria Kowalski,m.kowalski@sunriserheum.org,Sunrise Rheumatology,Rheumatologist,555-1184
William,Baptiste,Dr. William Baptiste,w.baptiste@oaklandendo.com,Oakland Endocrinology,Endocrinologist,555-1295
CSVEOF

chown ga:ga /home/ga/Documents/referring_physicians.csv

# Record initial contact count and database modification time
PROFILE_DIR="/home/ga/.thunderbird/default-release"
ABOOK="${PROFILE_DIR}/abook.sqlite"

if [ -f "$ABOOK" ]; then
    INITIAL_COUNT=$(sqlite3 "$ABOOK" "SELECT COUNT(DISTINCT card) FROM properties WHERE name='PrimaryEmail';" 2>/dev/null || echo "0")
    stat -c %Y "$ABOOK" > /tmp/initial_abook_mtime.txt
else
    INITIAL_COUNT=0
    echo "0" > /tmp/initial_abook_mtime.txt
fi

echo "$INITIAL_COUNT" > /tmp/initial_contact_count.txt
echo "Initial contact count: $INITIAL_COUNT"

# Start Thunderbird if not running
if ! pgrep -f "thunderbird" > /dev/null; then
    echo "Starting Thunderbird..."
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &"
    
    # Wait for the window to appear
    for i in {1..30}; do
        if su - ga -c "DISPLAY=:1 wmctrl -l" | grep -i "thunderbird"; then
            break
        fi
        sleep 1
    done
fi

# Give Thunderbird time to fully initialize UI
sleep 5

# Maximize and focus Thunderbird window
WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'Thunderbird' 2>/dev/null" | head -1)
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# Dismiss any startup dialogs
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot showing Thunderbird main window
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="