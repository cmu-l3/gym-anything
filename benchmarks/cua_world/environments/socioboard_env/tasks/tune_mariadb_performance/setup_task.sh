#!/bin/bash
echo "=== Setting up tune_mariadb_performance task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running normally
echo "Ensuring MariaDB is started and healthy..."
systemctl start mariadb || true
sleep 3

# Wait for MariaDB readiness
for i in $(seq 1 15); do
  if mysqladmin ping -h localhost --silent 2>/dev/null; then
    echo "MariaDB is ready."
    break
  fi
  sleep 2
done

# Clear any previously modified configs to ensure a clean state
# (Just in case a previous run left dirty state)
if grep -qi "max_connections" /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null; then
  sudo sed -i '/max_connections/d' /etc/mysql/mariadb.conf.d/50-server.cnf
fi
if grep -qi "innodb_buffer_pool_size" /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null; then
  sudo sed -i '/innodb_buffer_pool_size/d' /etc/mysql/mariadb.conf.d/50-server.cnf
fi
if grep -qi "slow_query_log" /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null; then
  sudo sed -i '/slow_query_log/d' /etc/mysql/mariadb.conf.d/50-server.cnf
fi
if grep -qi "long_query_time" /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null; then
  sudo sed -i '/long_query_time/d' /etc/mysql/mariadb.conf.d/50-server.cnf
fi

# Restart to clear runtime variables back to defaults
systemctl restart mariadb

# Open a terminal for the user to work in
su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=/home/ga &" 2>/dev/null || \
su - ga -c "DISPLAY=:1 x-terminal-emulator &" 2>/dev/null || true

sleep 3

# Take initial screenshot showing terminal ready
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="