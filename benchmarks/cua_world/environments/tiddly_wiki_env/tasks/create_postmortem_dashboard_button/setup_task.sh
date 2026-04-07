#!/bin/bash
echo "=== Setting up create_postmortem_dashboard_button task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure tiddlers directory exists
mkdir -p "$TIDDLER_DIR"

# Seed 5 real-world incident post-mortems
cat > "$TIDDLER_DIR/Cloudflare 1.1.1.1 Outage.tid" << 'EOF'
title: Cloudflare 1.1.1.1 Outage
tags: PostMortem Network
incident_date: 2020-07-17
severity: SEV-1

!! Summary
A configuration error in our backbone network caused a 50% drop in global traffic across the Cloudflare network, heavily impacting the 1.1.1.1 DNS resolver service for 27 minutes.

!! Root Cause
An engineer updating a router configuration in Atlanta accidentally deployed a BGP policy that advertised a local route globally, causing traffic to be blackholed.

!! Resolution
The global policy change was rolled back. We have implemented peer-review requirements for backbone routing policies and added automated maximum-prefix limits.
EOF

cat > "$TIDDLER_DIR/AWS Kinesis Outage.tid" << 'EOF'
title: AWS Kinesis Outage
tags: PostMortem Cloud AWS
incident_date: 2020-11-25
severity: SEV-1

!! Summary
Amazon Kinesis Data Streams API experienced increased error rates in the US-EAST-1 Region, causing cascading failures across multiple AWS services including Cognito, CloudWatch, and EventBridge.

!! Root Cause
A minor capacity addition triggered an obscure operating system limit on the number of threads per process. The front-end fleet exceeded the thread limit, causing nodes to fail health checks and aggressively churn.

!! Resolution
Fleet size was reduced to clear the thread limit, then carefully scaled up with increased OS thread limits.
EOF

cat > "$TIDDLER_DIR/Fastly Global Outage.tid" << 'EOF'
title: Fastly Global Outage
tags: PostMortem CDN
incident_date: 2021-06-08
severity: SEV-1

!! Summary
A widespread disruption occurred across the Fastly CDN, bringing down major websites including Reddit, Twitch, and the New York Times for approximately 49 minutes.

!! Root Cause
An undiscovered software bug was triggered by a valid customer configuration change. The bug caused 85% of our network to return errors.

!! Resolution
The specific customer configuration was identified and disabled, immediately restoring service. A software patch fixing the underlying bug was deployed network-wide within 48 hours.
EOF

cat > "$TIDDLER_DIR/GitHub Database Partition.tid" << 'EOF'
title: GitHub Database Partition
tags: PostMortem Database
incident_date: 2018-10-21
severity: SEV-1

!! Summary
GitHub experienced a 24-hour degradation of service. Services relying on MySQL databases were unavailable or serving stale data.

!! Root Cause
A brief network partition between our US East coast data centers compromised the orchestrator nodes responsible for MySQL cluster topology. This resulted in the promotion of a database replica that was not fully synchronized.

!! Resolution
Data was carefully reconciled from backups and the original primary. Topology management has been refactored to require cross-region consensus.
EOF

cat > "$TIDDLER_DIR/Facebook BGP Routing Incident.tid" << 'EOF'
title: Facebook BGP Routing Incident
tags: PostMortem Backbone
incident_date: 2021-10-04
severity: SEV-1

!! Summary
Facebook, Instagram, and WhatsApp were globally unavailable for 6 hours due to a total DNS resolution failure caused by a routing issue.

!! Root Cause
A command issued during routine maintenance accidentally took down all the connections in our backbone network, effectively disconnecting Facebook data centers globally. This caused our DNS servers to withdraw their BGP routes.

!! Resolution
Engineers physically accessed the data center routers to override the configuration and manually restore BGP peering. 
EOF

# Fix permissions
chown -R ga:ga "$TIDDLER_DIR"

# Wait for TiddlyWiki to pick up the files
sleep 3

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused on TiddlyWiki
DISPLAY=:1 wmctrl -a "TiddlyWiki" 2>/dev/null || DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="