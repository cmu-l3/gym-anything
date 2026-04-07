#!/bin/bash
echo "=== Setting up secure_mongodb_auth task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure MongoDB authorization is DISABLED in mongod.conf
log "Resetting mongod.conf to disable authorization..."
if grep -q "authorization:" /etc/mongod.conf; then
    sed -i 's/authorization:.*$/authorization: disabled/g' /etc/mongod.conf
else
    # Append security section if missing
    echo -e "\nsecurity:\n  authorization: disabled" >> /etc/mongod.conf
fi
systemctl restart mongod
sleep 3

# 2. Drop the 'socioboard' mongo user if it exists (fresh start)
log "Cleaning up existing MongoDB users..."
mongosh socioboard --eval "db.dropUser('socioboard')" --quiet 2>/dev/null || true

# 3. Ensure microservice config files have empty credentials
log "Resetting microservice database configurations..."
python3 << 'PYEOF'
import json, glob, sys

for f in glob.glob('/opt/socioboard/socioboard-api/*/config/development.json'):
    try:
        with open(f, 'r') as fp: 
            data = json.load(fp)
        
        modified = False
        for k, v in data.items():
            if isinstance(v, dict) and 'mongo' in k.lower():
                v['username'] = ""
                v['password'] = ""
                modified = True
                
        if modified:
            with open(f, 'w') as fp: 
                json.dump(data, fp, indent=2)
            print(f"Reset credentials in {f}")
    except Exception as e:
        print(f"Failed to reset {f}: {e}", file=sys.stderr)
PYEOF

# 4. Restart PM2 services and flush logs to remove old errors
log "Restarting PM2 services and flushing logs..."
su - ga -c "pm2 restart all > /dev/null" || pm2 restart all > /dev/null
su - ga -c "pm2 flush > /dev/null" || pm2 flush > /dev/null
sleep 2

# Take initial screenshot of terminal/desktop
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="