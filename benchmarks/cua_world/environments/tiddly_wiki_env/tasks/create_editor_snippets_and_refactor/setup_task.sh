#!/bin/bash
echo "=== Setting up create_editor_snippets_and_refactor task ==="

source /workspace/scripts/task_utils.sh

TIDDLER_DIR="/home/ga/mywiki/tiddlers"

# 1. Create the draft runbooks
cat > "$TIDDLER_DIR/PostgreSQL_16_Minor_Upgrade.tid" << 'EOF'
created: 20260101000000000
modified: 20260101000000000
tags: [[Draft Runbook]] Database
title: PostgreSQL 16 Minor Upgrade
type: text/vnd.tiddlywiki

[INSERT CRITICAL WARNING]

1. Run `sudo apt-get update`
2. Verify clusters: `pg_lsclusters`
EOF

cat > "$TIDDLER_DIR/Nginx_SSL_Certificate_Rotation.tid" << 'EOF'
created: 20260101000000000
modified: 20260101000000000
tags: [[Draft Runbook]] Web
title: Nginx SSL Certificate Rotation
type: text/vnd.tiddlywiki

Steps for renewing Certbot:
`certbot renew`

[INSERT INFO BOX]

Verify with `nginx -t`
EOF

cat > "$TIDDLER_DIR/Kubernetes_Node_Draining.tid" << 'EOF'
created: 20260101000000000
modified: 20260101000000000
tags: [[Draft Runbook]] Orchestration
title: Kubernetes Node Draining
type: text/vnd.tiddlywiki

[INSERT CRITICAL WARNING]

Start node drain:
`kubectl drain <node> --ignore-daemonsets`

[INSERT INFO BOX]

Verify pods have migrated.
EOF

chown ga:ga "$TIDDLER_DIR"/*.tid

# 2. Restart TiddlyWiki to ensure it picks up the new files immediately
echo "Restarting TiddlyWiki to load new tiddlers..."
pkill -f "tiddlywiki" 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 >> /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to come back up
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# 3. Refresh Firefox to reflect changes
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key "F5"
sleep 3

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="