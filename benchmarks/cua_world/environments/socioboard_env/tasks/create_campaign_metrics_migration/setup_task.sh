#!/bin/bash
echo "=== Setting up create_campaign_metrics_migration task ==="

# Source utilities if available
[ -f /workspace/scripts/task_utils.sh ] && source /workspace/scripts/task_utils.sh
set -e

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
systemctl is-active --quiet mariadb || systemctl start mariadb
sleep 2

# Wait for MariaDB readiness
for i in $(seq 1 30); do
  if mysqladmin ping -h localhost --silent 2>/dev/null; then
    echo "MariaDB ready"
    break
  fi
  sleep 2
done

# Clean state: drop table if it exists from a previous attempt
mysql -u root socioboard -e "DROP TABLE IF EXISTS campaign_metrics;" 2>/dev/null || true
echo "Ensured campaign_metrics table does not exist"

# Clean state: remove any existing campaign_metrics migration files
find /opt/socioboard/socioboard-api/library/sequelize-cli/migrations/ -iname "*campaign*metric*" -delete 2>/dev/null || true
echo "Cleaned any pre-existing campaign metrics migration files"

# Record initial table count
INITIAL_TABLES=$(mysql -u root socioboard -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='socioboard';" 2>/dev/null || echo "0")
echo "$INITIAL_TABLES" > /tmp/initial_table_count.txt
echo "Initial table count: $INITIAL_TABLES"

# Ensure sequelize-cli works (install mysql2 driver if needed)
cd /opt/socioboard/socioboard-api/library/sequelize-cli
npm install mysql2 --save 2>/dev/null || true

# Verify sequelize-cli is operational
NODE_ENV=development npx sequelize-cli db:migrate:status 2>/dev/null | tail -5 || \
  echo "WARNING: sequelize-cli status check had issues (may still work)"

# Ensure proper permissions
chown -R ga:ga /opt/socioboard 2>/dev/null || true

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/opt/socioboard/socioboard-api/library/sequelize-cli --maximize" 2>/dev/null || \
su - ga -c "DISPLAY=:1 xterm -maximized -e 'cd /opt/socioboard/socioboard-api/library/sequelize-cli && bash'" 2>/dev/null &
sleep 4

# Maximize terminal window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="