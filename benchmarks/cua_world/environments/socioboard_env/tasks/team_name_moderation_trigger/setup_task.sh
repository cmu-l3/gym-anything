#!/bin/bash
echo "=== Setting up team_name_moderation_trigger task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
systemctl start mariadb 2>/dev/null || true
sleep 3

# Wait for database to be ready
for i in {1..30}; do
  if mysqladmin ping -h localhost --silent 2>/dev/null; then
    echo "MariaDB ready."
    break
  fi
  sleep 1
done

# Clean up any previous attempts
mysql -u root socioboard -e "DROP TRIGGER IF EXISTS enforce_clean_team_names;" 2>/dev/null || true
mysql -u root socioboard -e "DROP TABLE IF EXISTS banned_keywords;" 2>/dev/null || true

# Download a real-world dataset of banned words (LDNOOBW public list)
echo "Downloading banned words dataset..."
DATA_FILE="/home/ga/banned_words.csv"

# Try to download the real dataset
curl -sL "https://raw.githubusercontent.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/en" -o /tmp/raw_words.txt

# Fallback if network fails (to ensure task remains payable/testable)
if [ ! -s /tmp/raw_words.txt ]; then
    echo "Network download failed, generating fallback dataset..."
    python3 -c "print('\n'.join(['badword'+str(i) for i in range(1, 401)]))" > /tmp/raw_words.txt
fi

# Format as CSV with header
echo "word" > "$DATA_FILE"
# Take first 400 words to ensure it's a solid size but performant for trigger checking
head -n 400 /tmp/raw_words.txt | tr -d '\r' | grep -v "^$" >> "$DATA_FILE"

# Set permissions so both the agent and MySQL can access it easily
chown ga:ga "$DATA_FILE"
chmod 644 "$DATA_FILE"
cp "$DATA_FILE" /tmp/banned_words.csv
chmod 666 /tmp/banned_words.csv

echo "Dataset prepared at $DATA_FILE with $(wc -l < $DATA_FILE) rows."

# Open a terminal for the user (since this is a backend/CLI task)
su - ga -c "DISPLAY=:1 gnome-terminal --maximize" &
sleep 2

# Take initial screenshot of desktop state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="