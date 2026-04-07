#!/bin/bash
echo "=== Setting up create_interactive_troubleshoot_guide task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Seed the knowledge base with network admin reference tiddlers
echo "Creating seed tiddlers for network admin knowledge base..."

cat > "$TIDDLER_DIR/TCP_IP Model.tid" << 'EOF'
title: TCP/IP Model
tags: Networking Reference
type: text/vnd.tiddlywiki

The TCP/IP model consists of four layers:
* Application Layer (HTTP, FTP, DNS)
* Transport Layer (TCP, UDP)
* Internet Layer (IP, ICMP)
* Network Access Layer (Ethernet, Wi-Fi)
EOF

cat > "$TIDDLER_DIR/Common Network Ports.tid" << 'EOF'
title: Common Network Ports
tags: Networking Reference
type: text/vnd.tiddlywiki

|!Service |!Port |!Protocol |
|FTP |21 |TCP |
|SSH |22 |TCP |
|DNS |53 |TCP/UDP |
|HTTP |80 |TCP |
|HTTPS |443 |TCP |
EOF

cat > "$TIDDLER_DIR/DNS Overview.tid" << 'EOF'
title: DNS Overview
tags: Networking Reference
type: text/vnd.tiddlywiki

Domain Name System (DNS) resolves human-readable hostnames into machine-readable IP addresses.
Common public DNS resolvers:
* Google: 8.8.8.8, 8.8.4.4
* Cloudflare: 1.1.1.1
EOF

chown ga:ga "$TIDDLER_DIR"/*.tid

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/troubleshoot_guide_initial.png

echo "=== Task setup complete ==="