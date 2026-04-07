#!/bin/bash
# Setup script for bulk_import_intranet_users task

echo "=== Setting up bulk_import_intranet_users task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# ============================================================
# Create the dataset (CSV)
# ============================================================
echo "Generating staff directory CSV..."
cat << 'EOF' > /home/ga/staff_directory.csv
username,email,first_name,last_name,department
asmith,asmith@corpnet.local,Alice,Smith,Engineering
bchen,bchen@corpnet.local,Brian,Chen,Marketing
cpatel,cpatel@corpnet.local,Chirag,Patel,Engineering
drobinson,drobinson@corpnet.local,David,Robinson,Sales
ewilliams,ewilliams@corpnet.local,Elena,Williams,Human Resources
fgarcia,fgarcia@corpnet.local,Fernando,Garcia,Sales
gkim,gkim@corpnet.local,Grace,Kim,Engineering
hnguyen,hnguyen@corpnet.local,Hannah,Nguyen,Marketing
ijohnson,ijohnson@corpnet.local,Isaac,Johnson,Legal
jlee,jlee@corpnet.local,Julia,Lee,Engineering
kmiller,kmiller@corpnet.local,Kevin,Miller,Sales
ldavis,ldavis@corpnet.local,Laura,Davis,Customer Support
mwilson,mwilson@corpnet.local,Marcus,Wilson,Engineering
ntaylor,ntaylor@corpnet.local,Natalie,Taylor,Human Resources
oanderson,oanderson@corpnet.local,Oliver,Anderson,Sales
pmartinez,pmartinez@corpnet.local,Patricia,Martinez,Customer Support
qthomas,qthomas@corpnet.local,Quinn,Thomas,Marketing
rjackson,rjackson@corpnet.local,Rachel,Jackson,Engineering
swhite,swhite@corpnet.local,Samuel,White,Legal
tharris,tharris@corpnet.local,Tara,Harris,Sales
umartin,umartin@corpnet.local,Umar,Martin,Engineering
vthompson,vthompson@corpnet.local,Victoria,Thompson,Customer Support
wmoore,wmoore@corpnet.local,William,Moore,Marketing
xclark,xclark@corpnet.local,Xavier,Clark,Engineering
yrodriguez,yrodriguez@corpnet.local,Yara,Rodriguez,Sales
EOF
chown ga:ga /home/ga/staff_directory.csv
chmod 644 /home/ga/staff_directory.csv

# ============================================================
# Reset environment state to baseline
# ============================================================
cd /var/www/html/wordpress

# Ensure subscriber role exists
wp role create subscriber "Subscriber" --allow-root 2>/dev/null || true
wp cap add subscriber read --allow-root 2>/dev/null || true

# Remove employee role if it exists from a previous run
wp role delete employee --allow-root 2>/dev/null || true

# Remove test users if they exist
for u in asmith bchen cpatel drobinson ewilliams fgarcia gkim hnguyen ijohnson jlee kmiller ldavis mwilson ntaylor oanderson pmartinez qthomas rjackson swhite tharris umartin vthompson wmoore xclark yrodriguez; do
    wp user delete "$u" --yes --allow-root 2>/dev/null || true
done

# Record initial user count
INITIAL_USER_COUNT=$(wp user list --format=count --allow-root)
echo "$INITIAL_USER_COUNT" | sudo tee /tmp/initial_user_count > /dev/null
sudo chmod 666 /tmp/initial_user_count
echo "Baseline user count: $INITIAL_USER_COUNT"

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/users.php' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# Focus Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="