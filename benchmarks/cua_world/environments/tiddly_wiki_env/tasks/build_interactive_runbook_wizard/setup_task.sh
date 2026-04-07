#!/bin/bash
echo "=== Setting up build_interactive_runbook_wizard task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the 4 Runbook tiddlers directly in the tiddlers directory
TDIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TDIR"

cat > "$TDIR/Runbook_ 1. Pre-Upgrade Checks.tid" << 'EOF'
title: Runbook: 1. Pre-Upgrade Checks
tags: Runbook PostgreSQL
type: text/vnd.tiddlywiki

!! Pre-Upgrade Checks
1. Verify disk space on data partition: `df -h /var/lib/postgresql`
2. Check for active connections preventing lock: `SELECT * FROM pg_stat_activity WHERE datname='production';`
3. Verify cluster status: `pg_lsclusters`
EOF

cat > "$TDIR/Runbook_ 2. Stop Application Services.tid" << 'EOF'
title: Runbook: 2. Stop Application Services
tags: Runbook PostgreSQL
type: text/vnd.tiddlywiki

!! Stop Application Services
1. Drain traffic from load balancer.
2. Stop the primary web service: `sudo systemctl stop gunicorn-prod`
3. Stop the Celery workers: `sudo systemctl stop celery-prod`
4. Confirm no connections remain in PostgreSQL.
EOF

cat > "$TDIR/Runbook_ 3. Run pg_upgrade.tid" << 'EOF'
title: Runbook: 3. Run pg_upgrade
tags: Runbook PostgreSQL
type: text/vnd.tiddlywiki

!! Run pg_upgrade
1. Switch to postgres user: `sudo -i -u postgres`
2. Run the upgrade check: `/usr/lib/postgresql/15/bin/pg_upgrade -b /usr/lib/postgresql/14/bin -B /usr/lib/postgresql/15/bin -d /var/lib/postgresql/14/main -D /var/lib/postgresql/15/main -c`
3. Execute the actual upgrade (remove `-c`).
EOF

cat > "$TDIR/Runbook_ 4. Verification and Restart.tid" << 'EOF'
title: Runbook: 4. Verification and Restart
tags: Runbook PostgreSQL
type: text/vnd.tiddlywiki

!! Verification and Restart
1. Start the new cluster: `sudo systemctl start postgresql@15-main`
2. Run vacuum to update optimizer statistics: `/usr/lib/postgresql/15/bin/vacuumdb --all --analyze-in-stages`
3. Start application services: `sudo systemctl start gunicorn-prod celery-prod`
EOF

# Ensure correct permissions
chown -R ga:ga "$TDIR"

# Ensure TiddlyWiki is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "WARNING: TiddlyWiki server not accessible, it should be running."
fi

# Wait for Node.js to pick up the new files, then force a browser refresh
sleep 3
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

# Close any open tiddlers to ensure a clean slate
DISPLAY=:1 xdotool key Alt+w 2>/dev/null || true

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Take initial screenshot
take_screenshot /tmp/wizard_initial.png

echo "=== Task setup complete ==="