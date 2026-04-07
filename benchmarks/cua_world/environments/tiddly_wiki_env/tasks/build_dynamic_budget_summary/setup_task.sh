#!/bin/bash
echo "=== Setting up build_dynamic_budget_summary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Create seed data directories if they don't exist
WIKI_TIDDLERS="/home/ga/mywiki/tiddlers"
mkdir -p "$WIKI_TIDDLERS"

# Seed data creation
echo "Injecting trip itinerary tiddlers..."

cat > "$WIKI_TIDDLERS/Flight to Tokyo.tid" << 'EOF'
title: Flight to Tokyo
tags: Japan2026
category: Flight
cost: 1200

Roundtrip flight from SFO to HND.
EOF

cat > "$WIKI_TIDDLERS/Shinjuku Hotel.tid" << 'EOF'
title: Shinjuku Hotel
tags: Japan2026
category: Accommodation
cost: 800

5 nights at Shinjuku Gracery.
EOF

cat > "$WIKI_TIDDLERS/JR Pass.tid" << 'EOF'
title: JR Pass
tags: Japan2026
category: Transport
cost: 400

14-day Japan Rail Pass.
EOF

cat > "$WIKI_TIDDLERS/Robot Restaurant.tid" << 'EOF'
title: Robot Restaurant
tags: Japan2026
category: Activity
cost: 80

Evening entertainment in Shinjuku.
EOF

cat > "$WIKI_TIDDLERS/TeamLab Planets.tid" << 'EOF'
title: TeamLab Planets
tags: Japan2026
category: Activity
cost: 30

Digital art museum.
EOF

cat > "$WIKI_TIDDLERS/Sushi Zanmai.tid" << 'EOF'
title: Sushi Zanmai
tags: Japan2026
category: Food
cost: 50

Lunch in Tsukiji.
EOF

# Fix permissions
chown -R ga:ga "$WIKI_TIDDLERS"

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
fi

# Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5  # Refresh browser to ensure new files are loaded
sleep 2

take_screenshot /tmp/budget_initial.png

echo "=== Task setup complete ==="