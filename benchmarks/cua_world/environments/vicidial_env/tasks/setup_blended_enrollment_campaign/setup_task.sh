#!/bin/bash
set -e

echo "=== Setting up Blended Enrollment Campaign task ==="

source /workspace/scripts/task_utils.sh

# Ensure Vicidial services are running
vicidial_ensure_running

# Wait for DB ready
echo "Waiting for Vicidial MySQL..."
for i in $(seq 1 60); do
    if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
        echo "MySQL ready after ${i}s"
        break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "WARNING: MySQL did not become ready in 120s; continuing anyway"
    fi
done

DB_CMD="docker exec vicidial mysql -ucron -p1234 -D asterisk -e"

# ---------------------------------------------------------------
# Phase 1: Generate enrollment leads CSV
# ---------------------------------------------------------------
echo "Generating enrollment leads CSV..."
mkdir -p /home/ga/Documents/VicidialData

python3 << 'PYEOF' > /home/ga/Documents/VicidialData/enrollment_leads.csv
# Generate 50 realistic health insurance enrollment leads in Vicidial standard format
# Tab-separated, no header row
# Columns: vendor_lead_code  source_id  list_id  gmt_offset_now  called_since_last_reset
#   phone_code  phone_number  title  first_name  middle_initial  last_name
#   address1  address2  address3  city  state  province  postal_code  country_code
#   gender  date_of_birth  alt_phone  email  security_phrase  comments
#   called_count  last_local_call_time  rank  owner  entry_list_id

leads = [
    ("ENR001","2125550101","James","R","Morrison","142 Broadway","","New York","NY","10006","M","1968-03-15","Gold PPO - Family"),
    ("ENR002","2125550102","Maria","L","Santos","88 Fulton St","Apt 4B","New York","NY","10038","F","1975-07-22","Silver HMO - Individual"),
    ("ENR003","2125550103","David","A","Chen","250 Park Ave S","","New York","NY","10003","M","1982-11-04","Bronze HDHP - Individual"),
    ("ENR004","7185550104","Patricia","M","O'Brien","3401 Broadway","","Bronx","NY","10463","F","1959-01-28","Gold PPO - Family"),
    ("ENR005","7185550105","Robert","J","Williams","1520 York Ave","","New York","NY","10028","M","1971-06-10","Platinum PPO - Couple"),
    ("ENR006","3105550106","Jennifer","K","Nguyen","1200 Wilshire Blvd","Ste 300","Los Angeles","CA","90017","F","1988-04-18","Silver HMO - Family"),
    ("ENR007","4155550107","Michael","S","Garcia","580 Market St","","San Francisco","CA","94104","M","1965-12-03","Gold PPO - Individual"),
    ("ENR008","6195550108","Lisa","T","Patel","3940 Fourth Ave","","San Diego","CA","92103","F","1979-08-27","Bronze HDHP - Couple"),
    ("ENR009","9165550109","Christopher","D","Kim","1015 K St","","Sacramento","CA","95814","M","1984-02-14","Silver HMO - Individual"),
    ("ENR010","4085550110","Angela","N","Ramirez","55 S Market St","","San Jose","CA","95113","F","1972-10-31","Gold PPO - Family"),
    ("ENR011","7135550111","William","E","Johnson","1100 Louisiana St","","Houston","TX","77002","M","1963-05-20","Platinum PPO - Family"),
    ("ENR012","2145550112","Sarah","F","Martinez","2001 Ross Ave","","Dallas","TX","75201","F","1990-09-08","Bronze HDHP - Individual"),
    ("ENR013","5125550113","Daniel","G","Thompson","301 Congress Ave","","Austin","TX","78701","M","1977-03-12","Gold PPO - Couple"),
    ("ENR014","2105550114","Michelle","H","Brown","100 W Houston St","","San Antonio","TX","78205","F","1986-07-04","Silver HMO - Family"),
    ("ENR015","8175550115","Kevin","B","Davis","500 Throckmorton St","","Fort Worth","TX","76102","M","1969-11-25","Gold PPO - Individual"),
    ("ENR016","3055550116","Stephanie","C","Jean-Baptiste","1200 Brickell Ave","","Miami","FL","33131","F","1981-06-17","Silver HMO - Family"),
    ("ENR017","4075550117","Richard","W","Clark","200 S Orange Ave","","Orlando","FL","32801","M","1974-01-09","Bronze HDHP - Individual"),
    ("ENR018","8135550118","Amanda","P","Washington","100 N Tampa St","","Tampa","FL","33602","F","1992-12-22","Gold PPO - Couple"),
    ("ENR019","9045550119","Brian","V","Hernandez","40 E Adams St","","Jacksonville","FL","32202","M","1967-04-30","Platinum PPO - Family"),
    ("ENR020","5615550120","Nicole","Q","Taylor","300 Clematis St","","West Palm Beach","FL","33401","F","1985-08-13","Silver HMO - Individual"),
    ("ENR021","3125550121","Thomas","I","Kowalski","200 E Randolph St","","Chicago","IL","60601","M","1970-02-28","Gold PPO - Family"),
    ("ENR022","3125550122","Cynthia","O","Robinson","111 S Wacker Dr","","Chicago","IL","60606","F","1983-10-05","Bronze HDHP - Couple"),
    ("ENR023","2175550123","Marcus","U","Freeman","500 Main St","","Springfield","IL","62701","M","1976-07-19","Silver HMO - Individual"),
    ("ENR024","3095550124","Diane","Y","Anderson","401 Main St","","Peoria","IL","61602","F","1961-09-14","Platinum PPO - Individual"),
    ("ENR025","8155550125","Jason","Z","Mitchell","1 Gateway Dr","","Collinsville","IL","62234","M","1989-05-07","Gold PPO - Family"),
    ("ENR026","2155550126","Karen","A","Rossi","1500 Market St","","Philadelphia","PA","19102","F","1973-11-11","Silver HMO - Family"),
    ("ENR027","4125550127","Steven","B","Washington","300 Sixth Ave","","Pittsburgh","PA","15222","M","1966-08-23","Gold PPO - Individual"),
    ("ENR028","6105550128","Rachel","C","Schwartz","645 Hamilton St","","Allentown","PA","18101","F","1991-03-06","Bronze HDHP - Individual"),
    ("ENR029","7175550129","Paul","D","Murphy","101 S Second St","","Harrisburg","PA","17101","M","1978-12-18","Gold PPO - Couple"),
    ("ENR030","5705550130","Deborah","E","Volkov","200 Adams Ave","","Scranton","PA","18503","F","1964-04-02","Platinum PPO - Family"),
    ("ENR031","2165550131","Gregory","F","Jackson","127 Public Sq","","Cleveland","OH","44114","M","1980-01-16","Silver HMO - Individual"),
    ("ENR032","6145550132","Laura","G","Singh","250 Civic Center Dr","","Columbus","OH","43215","F","1987-06-29","Gold PPO - Family"),
    ("ENR033","5135550133","Jeffrey","H","Moore","312 Walnut St","","Cincinnati","OH","45202","M","1962-10-21","Bronze HDHP - Couple"),
    ("ENR034","3305550134","Andrea","I","Lewis","1 Cascade Plz","","Akron","OH","44308","F","1993-02-08","Silver HMO - Family"),
    ("ENR035","4195550135","Eric","J","Baker","405 Madison Ave","","Toledo","OH","43604","M","1975-07-14","Gold PPO - Individual"),
    ("ENR036","4045550136","Tiffany","K","Carter","233 Peachtree St NE","","Atlanta","GA","30303","F","1984-09-26","Gold PPO - Family"),
    ("ENR037","7065550137","Charles","L","Adams","100 Tenth St","","Augusta","GA","30901","M","1968-05-03","Silver HMO - Individual"),
    ("ENR038","9125550138","Monica","M","Scott","2 E Bryan St","","Savannah","GA","31401","F","1979-11-17","Bronze HDHP - Individual"),
    ("ENR039","7705550139","Dennis","N","Phillips","240 Third St","","Macon","GA","31201","M","1971-03-24","Platinum PPO - Couple"),
    ("ENR040","7625550140","Tamara","O","Reed","100 W Park Ave","","Valdosta","GA","31601","F","1986-08-09","Silver HMO - Family"),
    ("ENR041","7045550141","Ryan","P","Turner","201 S College St","","Charlotte","NC","28202","M","1982-12-01","Gold PPO - Family"),
    ("ENR042","9195550142","Elizabeth","Q","Campbell","300 Fayetteville St","","Raleigh","NC","27601","F","1974-04-16","Silver HMO - Couple"),
    ("ENR043","3365550143","Anthony","R","Stewart","200 N Main St","","Winston-Salem","NC","27101","M","1967-07-28","Bronze HDHP - Individual"),
    ("ENR044","9105550144","Kimberly","S","Hall","301 N Elm St","","Greensboro","NC","27401","F","1990-10-13","Gold PPO - Individual"),
    ("ENR045","8285550145","Travis","T","Young","200 Haywood St","","Asheville","NC","28801","M","1983-01-05","Platinum PPO - Family"),
    ("ENR046","3135550146","Sandra","U","Howard","1001 Woodward Ave","","Detroit","MI","48226","F","1976-06-20","Silver HMO - Family"),
    ("ENR047","6165550147","Douglas","V","Wright","333 Bridge St NW","","Grand Rapids","MI","49504","M","1969-09-11","Gold PPO - Individual"),
    ("ENR048","5175550148","Heather","W","Nelson","124 Allegan St","","Lansing","MI","48933","F","1988-02-24","Bronze HDHP - Couple"),
    ("ENR049","2485550149","Raymond","X","Collins","600 Woodbridge St","","Detroit","MI","48226","M","1964-11-07","Gold PPO - Family"),
    ("ENR050","7345550150","Valerie","Y","Diaz","100 S Capitol Ave","","Lansing","MI","48933","F","1981-05-30","Silver HMO - Individual"),
]

# State to GMT offset mapping
gmt_offsets = {"NY":"-5.00","CA":"-8.00","TX":"-6.00","FL":"-5.00","IL":"-6.00","PA":"-5.00","OH":"-5.00","GA":"-5.00","NC":"-5.00","MI":"-5.00"}

for row in leads:
    code, phone, first, mid, last, addr1, addr2, city, state, zipcode, gender, dob, comments = row
    gmt = gmt_offsets.get(state, "-5.00")
    # Vicidial standard format: 30 tab-separated fields
    fields = [
        code,           # vendor_lead_code
        "OE2026",       # source_id
        "8800",         # list_id
        gmt,            # gmt_offset_now
        "N",            # called_since_last_reset
        "1",            # phone_code
        phone,          # phone_number
        "",             # title
        first,          # first_name
        mid,            # middle_initial
        last,           # last_name
        addr1,          # address1
        addr2,          # address2
        "",             # address3
        city,           # city
        state,          # state
        "",             # province
        zipcode,        # postal_code
        "USA",          # country_code
        gender,         # gender
        dob,            # date_of_birth
        "",             # alt_phone
        "",             # email
        "",             # security_phrase
        comments,       # comments
        "0",            # called_count
        "",             # last_local_call_time
        "0",            # rank
        "",             # owner
        "",             # entry_list_id
    ]
    print("\t".join(fields))
PYEOF

chown ga:ga /home/ga/Documents/VicidialData/enrollment_leads.csv
chmod 644 /home/ga/Documents/VicidialData/enrollment_leads.csv

LEAD_COUNT=$(wc -l < /home/ga/Documents/VicidialData/enrollment_leads.csv)
echo "Generated enrollment_leads.csv with ${LEAD_COUNT} records"

# ---------------------------------------------------------------
# Phase 2: Clean all target objects from DB (BEFORE timestamp)
# ---------------------------------------------------------------
echo "Cleaning up previous state..."

# Lead recycling rules for PSHLTH26
$DB_CMD "DELETE FROM vicidial_lead_recycle WHERE campaign_id='PSHLTH26';" 2>/dev/null || true

# Campaign statuses
$DB_CMD "DELETE FROM vicidial_campaign_statuses WHERE campaign_id='PSHLTH26';" 2>/dev/null || true

# Campaign hotkeys (if any)
$DB_CMD "DELETE FROM vicidial_campaign_hotkeys WHERE campaign_id='PSHLTH26';" 2>/dev/null || true

# Campaign stats
$DB_CMD "DELETE FROM vicidial_campaign_stats WHERE campaign_id='PSHLTH26';" 2>/dev/null || true

# Alt phones for leads in list 8800 (must run BEFORE deleting leads)
$DB_CMD "DELETE FROM vicidial_list_alt_phones WHERE lead_id IN (SELECT lead_id FROM vicidial_list WHERE list_id='8800');" 2>/dev/null || true

# Leads in list 8800
$DB_CMD "DELETE FROM vicidial_list WHERE list_id='8800';" 2>/dev/null || true

# List 8800
$DB_CMD "DELETE FROM vicidial_lists WHERE list_id='8800';" 2>/dev/null || true

# Script
$DB_CMD "DELETE FROM vicidial_scripts WHERE script_id='PS_ENROLL';" 2>/dev/null || true

# Inbound group
$DB_CMD "DELETE FROM vicidial_inbound_groups WHERE group_id='PS_INBOUND';" 2>/dev/null || true

# Call time
$DB_CMD "DELETE FROM vicidial_call_times WHERE call_time_id='PS_HOURS';" 2>/dev/null || true

# Voicemail
$DB_CMD "DELETE FROM vicidial_voicemail WHERE voicemail_id='8800';" 2>/dev/null || true

# Campaign itself (last, since other tables reference it)
$DB_CMD "DELETE FROM vicidial_campaigns WHERE campaign_id='PSHLTH26';" 2>/dev/null || true

# Clean stale output files
rm -f /tmp/task_result.json /tmp/task_start_time.txt /tmp/task_initial.png /tmp/task_final.png

echo "Cleanup complete."

# ---------------------------------------------------------------
# Phase 3: Record task start timestamp (AFTER cleanup)
# ---------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# ---------------------------------------------------------------
# Phase 4: Grant comprehensive permissions to user 6666
# ---------------------------------------------------------------
echo "Granting permissions to user 6666..."
$DB_CMD "UPDATE vicidial_users SET
    user_level='9',
    modify_campaigns='1',
    modify_lists='1',
    modify_leads='1',
    modify_statuses='1',
    modify_scripts='1',
    modify_call_times='1',
    modify_ingroups='1',
    modify_voicemail='1',
    modify_shifts='1',
    modify_inbound_dids='1',
    ast_admin_access='1',
    load_leads='1',
    view_reports='1'
WHERE user='6666';" 2>/dev/null || true

# ---------------------------------------------------------------
# Phase 5: Launch Firefox
# ---------------------------------------------------------------
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
for i in $(seq 1 15); do
    pgrep -f firefox >/dev/null 2>&1 || break
    sleep 1
done

ADMIN_URL="http://localhost/vicidial/admin.php"
su - ga -c "DISPLAY=:1 firefox '$ADMIN_URL' > /dev/null 2>&1 &"

wait_for_window "firefox\|mozilla\|vicidial" 30 || echo "WARNING: Firefox window not detected"
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth
sleep 3
echo "Handling Basic Auth..."
DISPLAY=:1 xdotool type --delay 50 "6666"
sleep 0.5
DISPLAY=:1 xdotool key Tab
sleep 0.5
DISPLAY=:1 xdotool type --delay 50 "andromeda"
sleep 0.5
DISPLAY=:1 xdotool key Return

sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
