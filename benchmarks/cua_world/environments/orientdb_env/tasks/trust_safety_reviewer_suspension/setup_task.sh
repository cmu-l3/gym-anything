#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up trust_safety_reviewer_suspension task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# 1. Clean up previous run artifacts
echo "Cleaning up previous run data..."
orientdb_sql "demodb" "DELETE VERTEX Profiles WHERE Email LIKE '%@spamnet.com' OR Email = 'innocent.user@normal.com'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS SuspensionLog UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HasSuspensionLog UNSAFE" >/dev/null 2>&1 || true
# Note: We don't drop AccountStatus property to avoid schema thrashing, but we ensure it's null for new inserts

# 2. Inject Fraud Scenario Data
echo "Injecting fraud scenario data..."

# Helper to execute SQL quickly
run_sql() {
    orientdb_sql "demodb" "$1" > /dev/null
}

# --- Bot Alpha (The Threshold Case: Exactly 3 bad reviews) ---
run_sql "INSERT INTO Profiles SET Email='bot.alpha@spamnet.com', Name='Bot', Surname='Alpha', Gender='Male', Nationality='Unknown', AccountStatus=NULL"
for i in {1..3}; do
    run_sql "INSERT INTO Reviews SET Stars=1, Text='Terrible hotel awful service', Date='2023-01-0${i}'"
    # Link (Profile -> Review)
    run_sql "CREATE EDGE MadeReview FROM (SELECT FROM Profiles WHERE Email='bot.alpha@spamnet.com') TO (SELECT FROM Reviews WHERE Stars=1 AND Text='Terrible hotel awful service' AND Date='2023-01-0${i}' LIMIT 1)"
done

# --- Bot Beta (The Extreme Case: 4 bad reviews) ---
run_sql "INSERT INTO Profiles SET Email='bot.beta@spamnet.com', Name='Bot', Surname='Beta', Gender='Female', Nationality='Unknown', AccountStatus=NULL"
for i in {1..4}; do
    run_sql "INSERT INTO Reviews SET Stars=1, Text='Scam do not stay', Date='2023-02-0${i}'"
    run_sql "CREATE EDGE MadeReview FROM (SELECT FROM Profiles WHERE Email='bot.beta@spamnet.com') TO (SELECT FROM Reviews WHERE Stars=1 AND Text='Scam do not stay' AND Date='2023-02-0${i}' LIMIT 1)"
done

# --- Innocent User (The Boundary Case: 2 bad reviews - should NOT be suspended) ---
run_sql "INSERT INTO Profiles SET Email='innocent.user@normal.com', Name='Innocent', Surname='User', Gender='Male', Nationality='American', AccountStatus=NULL"
# 2 bad reviews
for i in {1..2}; do
    run_sql "INSERT INTO Reviews SET Stars=1, Text='Not great honestly', Date='2023-03-0${i}'"
    run_sql "CREATE EDGE MadeReview FROM (SELECT FROM Profiles WHERE Email='innocent.user@normal.com') TO (SELECT FROM Reviews WHERE Stars=1 AND Text='Not great honestly' AND Date='2023-03-0${i}' LIMIT 1)"
done
# 1 good review (to show they are active)
run_sql "INSERT INTO Reviews SET Stars=5, Text='This other hotel was great', Date='2023-03-10'"
run_sql "CREATE EDGE MadeReview FROM (SELECT FROM Profiles WHERE Email='innocent.user@normal.com') TO (SELECT FROM Reviews WHERE Stars=5 AND Text='This other hotel was great' AND Date='2023-03-10' LIMIT 1)"

echo "Injected 2 bots and 1 innocent user."

# 3. Setup Firefox
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile 'http://localhost:2480/studio/index.html' &"
sleep 8

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="