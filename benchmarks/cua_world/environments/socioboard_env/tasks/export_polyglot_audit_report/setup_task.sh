#!/bin/bash
set -e

echo "=== Setting up Polyglot Audit Report task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start required database services
systemctl start mariadb 2>/dev/null || true
systemctl start mongod 2>/dev/null || true
sleep 3

# Wait for databases to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Generate synthetic audit data, seed databases, and create hidden ground truth
python3 << 'EOF'
import json
import os
import subprocess
import random
from datetime import datetime, timedelta

users = [
    {"user_id": 1001, "email": "j.doe@agency.local", "first_name": "John"},
    {"user_id": 1002, "email": "s.connor@agency.local", "first_name": "Sarah"},
    {"user_id": 1003, "email": "m.smith@agency.local", "first_name": "Mike"},
    {"user_id": 1004, "email": "a.lee@agency.local", "first_name": "Amanda"}
]

networks = ["twitter", "facebook", "linkedin", "instagram"]
posts = []
ground_truth = {}

start_date = datetime(2025, 1, 15)

# Generate 25 records
for i in range(25):
    user = random.choice(users)
    net = random.choice(networks)
    p_date = (start_date + timedelta(days=i, hours=random.randint(1, 10), minutes=random.randint(0, 59))).isoformat() + "Z"
    
    # Introduce real-world messiness (commas, quotes, newlines in content)
    content_templates = [
        f"Excited to announce our Q{random.randint(1,4)} roadmap! #growth",
        f"Join us for the upcoming webinar.\n\nLink in bio! 🚀",
        f"\"Customer success is our #1 priority,\" says our CEO. Read more:",
        f"Flash sale: 20% off all enterprise plans, today only."
    ]
    content = random.choice(content_templates)
    url = f"https://{net}.com/user/{user['user_id']}/status/{100000 + i}"

    posts.append({
        "userId": user["user_id"],
        "network": net,
        "publishedDate": p_date,
        "postContent": content,
        "postUrl": url
    })

    ground_truth[url] = {
        "email": user["email"],
        "network": net,
        "date": p_date,
        "content": content
    }

# Save ground truth (hidden from agent)
os.makedirs("/var/lib/socioboard_audit", exist_ok=True)
with open("/var/lib/socioboard_audit/ground_truth.json", "w") as f:
    json.dump(ground_truth, f)

# Seed MariaDB
sql_statements = [
    "CREATE DATABASE IF NOT EXISTS socioboard;",
    "USE socioboard;",
    "CREATE TABLE IF NOT EXISTS user_details (user_id INT PRIMARY KEY, email VARCHAR(255), first_name VARCHAR(255));",
    "DELETE FROM user_details WHERE user_id >= 1001;"
]
for u in users:
    sql_statements.append(f"INSERT INTO user_details (user_id, email, first_name) VALUES ({u['user_id']}, '{u['email']}', '{u['first_name']}');")

with open("/tmp/setup_mariadb.sql", "w") as f:
    f.write("\n".join(sql_statements))

subprocess.run(["mysql", "-u", "root", "-e", "source /tmp/setup_mariadb.sql"])

# Seed MongoDB
mongo_script = f"""
use socioboard;
db.published_posts.drop();
db.published_posts.insertMany({json.dumps(posts)});
"""
with open("/tmp/setup_mongo.js", "w") as f:
    f.write(mongo_script)

# Try mongo then mongosh
if subprocess.run(["which", "mongosh"], capture_output=True).returncode == 0:
    subprocess.run(["mongosh", "socioboard", "/tmp/setup_mongo.js"], stderr=subprocess.DEVNULL)
else:
    subprocess.run(["mongo", "socioboard", "/tmp/setup_mongo.js"], stderr=subprocess.DEVNULL)

EOF

# Secure ground truth files
chmod 700 /var/lib/socioboard_audit
chmod 600 /var/lib/socioboard_audit/ground_truth.json

# Clean up previous workspace state
rm -f /workspace/audit_report.csv
rm -f /tmp/audit_report.csv
rm -f /tmp/task_result.json

# Open a terminal for the agent to start scripting
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/workspace" > /dev/null 2>&1 &
sleep 2

# Take initial screenshot of environment
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="