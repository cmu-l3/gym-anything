#!/bin/bash
echo "=== Setting up link_records task ==="
# Ensure safe PATH (guards against /etc/environment corruption)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is running
wait_for_orientdb 60

# Reset state: remove any existing HasFriend edge from domi@nek.gov to seari@ubu.edu
echo "Removing existing HasFriend edge from domi@nek.gov to seari@ubu.edu if present..."
orientdb_sql "demodb" "DELETE EDGE HasFriend WHERE (out.Email = 'domi@nek.gov') AND (in.Email = 'seari@ubu.edu')" \
    > /dev/null 2>&1 || true
sleep 1

# Ensure the two required profiles exist — insert them if missing (handles both data paths)
ensure_profile() {
    local email="$1" name="$2" surname="$3" gender="$4" bday="$5" nationality="$6"
    local count
    count=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles WHERE Email='${email}'" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    if [ "$count" = "0" ]; then
        echo "  Profile ${email} missing — inserting..."
        orientdb_sql "demodb" \
            "INSERT INTO Profiles SET Email='${email}', Name='${name}', Surname='${surname}', Gender='${gender}', Birthday='${bday}', Nationality='${nationality}'" \
            > /dev/null 2>&1
        echo "  Inserted ${email}"
    else
        echo "  Profile ${email} confirmed (${count} record(s))"
    fi
}

echo "Ensuring required profiles exist for this task..."
ensure_profile "domi@nek.gov"   "Isaac" "Black"   "Male"   "1982-07-14" "American"
ensure_profile "seari@ubu.edu"  "Rosie" "Thornton" "Female" "1990-11-03" "British"

# Final check — abort if still missing (prevents unsolvable task state)
MISSING=0
for EMAIL in "domi@nek.gov" "seari@ubu.edu"; do
    CNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles WHERE Email='${EMAIL}'" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    if [ "$CNT" = "0" ]; then
        echo "ERROR: Profile ${EMAIL} still missing after insert attempt!"
        MISSING=1
    fi
done
if [ "$MISSING" = "1" ]; then
    echo "FATAL: Required profiles for link_records are missing. Cannot proceed."
    exit 1
fi
echo "Both required profiles confirmed."

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

take_screenshot /tmp/task_start_link_records.png
echo "Initial screenshot saved to /tmp/task_start_link_records.png"

echo "=== link_records task setup complete ==="
echo "Task: Connect to demodb → Execute query → CREATE EDGE HasFriend from domi@nek.gov to seari@ubu.edu"
