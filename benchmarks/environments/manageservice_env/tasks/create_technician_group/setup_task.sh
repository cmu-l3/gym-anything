#!/bin/bash
echo "=== Setting up Create Technician Group Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Record Initial Group Count
INITIAL_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM techniciangroup;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_group_count.txt

# 4. Create Pre-requisite Technicians (Sarah, Marcus, Priya)
# We use a Python script with psycopg2 to handle the relational inserts cleanly
echo "Creating required technicians..."

cat > /tmp/create_techs.py << 'PYEOF'
import psycopg2
import sys

def get_db_connection():
    try:
        return psycopg2.connect(
            host="127.0.0.1",
            port="65432",
            database="servicedesk",
            user="postgres"
        )
    except:
        return psycopg2.connect(
            host="127.0.0.1",
            port="65432",
            database="servicedesk",
            user="sdpadmin"
        )

technicians = [
    {"name": "Sarah Chen", "login": "sarah.chen", "email": "sarah.chen@meridianfinancial.com"},
    {"name": "Marcus Williams", "login": "marcus.williams", "email": "marcus.williams@meridianfinancial.com"},
    {"name": "Priya Sharma", "login": "priya.sharma", "email": "priya.sharma@meridianfinancial.com"}
]

conn = get_db_connection()
cur = conn.cursor()

try:
    for tech in technicians:
        # Check if exists
        cur.execute("SELECT user_id FROM AaaLogin WHERE NAME = %s", (tech['login'],))
        res = cur.fetchone()
        
        if res:
            print(f"Technician {tech['login']} already exists (ID: {res[0]})")
            continue

        print(f"Creating technician {tech['name']}...")
        
        # 1. AaaUser
        cur.execute("INSERT INTO AaaUser (FIRST_NAME) VALUES (%s) RETURNING USER_ID", (tech['name'],))
        user_id = cur.fetchone()[0]
        
        # 2. AaaLogin
        cur.execute("INSERT INTO AaaLogin (USER_ID, NAME, DOMAINNAME) VALUES (%s, %s, '-') RETURNING LOGIN_ID", (user_id, tech['login']))
        login_id = cur.fetchone()[0]
        
        # 3. AaaAccount (Service_ID 1 is usually System/SDP)
        cur.execute("INSERT INTO AaaAccount (LOGIN_ID, SERVICE_ID) VALUES (%s, 1) RETURNING ACCOUNT_ID", (login_id,))
        account_id = cur.fetchone()[0]
        
        # 4. AaaContactInfo
        cur.execute("INSERT INTO AaaContactInfo (USER_ID, EMAILID) VALUES (%s, %s)", (user_id, tech['email']))
        
        # 5. SDUser (Status ACTIVE)
        cur.execute("INSERT INTO SDUser (USERID, STATUS) VALUES (%s, 'ACTIVE')", (user_id,))
        
        # 6. HelpDeskCrew (Makes them a technician)
        cur.execute("INSERT INTO HelpDeskCrew (TECHNICIANID) VALUES (%s)", (user_id,))

    conn.commit()
    print("Technicians created successfully.")

except Exception as e:
    conn.rollback()
    print(f"Error creating technicians: {e}")
    sys.exit(1)
finally:
    conn.close()
PYEOF

python3 /tmp/create_techs.py >> /tmp/sdp_setup.log 2>&1

# 5. Launch Firefox to Login Page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox detected."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="