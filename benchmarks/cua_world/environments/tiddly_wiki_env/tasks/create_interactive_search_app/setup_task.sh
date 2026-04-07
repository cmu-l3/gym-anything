#!/bin/bash
echo "=== Setting up create_interactive_search_app task ==="

source /workspace/scripts/task_utils.sh

WIKI_DIR="/home/ga/mywiki"
TIDDLER_DIR="$WIKI_DIR/tiddlers"

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Seed the 5 DrugPaper tiddlers with real interaction data
echo "Seeding pharmacology paper tiddlers..."

cat > "$TIDDLER_DIR/CYP3A4 Inhibition by Ketoconazole.tid" << 'EOF'
title: CYP3A4 Inhibition by Ketoconazole
tags: DrugPaper
type: text/vnd.tiddlywiki

Ketoconazole is a strong inhibitor of cytochrome P450 3A4 (CYP3A4). Co-administration with drugs metabolized by CYP3A4 can lead to significant increases in their plasma concentrations, causing severe toxicity.
EOF

cat > "$TIDDLER_DIR/Warfarin and Aspirin Bleeding Risk.tid" << 'EOF'
title: Warfarin and Aspirin Bleeding Risk
tags: DrugPaper
type: text/vnd.tiddlywiki

The combination of warfarin (an anticoagulant) and aspirin (an antiplatelet agent) significantly increases the risk of major gastrointestinal bleeding due to synergistic impairment of hemostasis.
EOF

cat > "$TIDDLER_DIR/Grapefruit Juice Effect on Statins.tid" << 'EOF'
title: Grapefruit Juice Effect on Statins
tags: DrugPaper
type: text/vnd.tiddlywiki

Compounds in grapefruit juice, particularly furanocoumarins, inhibit intestinal CYP3A4. This drastically increases the bioavailability of certain statins like simvastatin and atorvastatin, raising the risk of rhabdomyolysis.
EOF

cat > "$TIDDLER_DIR/Omeprazole and Clopidogrel Interaction.tid" << 'EOF'
title: Omeprazole and Clopidogrel Interaction
tags: DrugPaper
type: text/vnd.tiddlywiki

Omeprazole inhibits CYP2C19, the enzyme responsible for converting the prodrug clopidogrel to its active metabolite, potentially reducing its antiplatelet efficacy and increasing cardiovascular event risks.
EOF

cat > "$TIDDLER_DIR/Serotonin Syndrome from SSRI and MAOI.tid" << 'EOF'
title: Serotonin Syndrome from SSRI and MAOI
tags: DrugPaper
type: text/vnd.tiddlywiki

Combining Selective Serotonin Reuptake Inhibitors (SSRIs) with Monoamine Oxidase Inhibitors (MAOIs) can precipitate serotonin syndrome, a potentially life-threatening condition characterized by hyperthermia, clonus, and altered mental status.
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Restart TiddlyWiki to ensure it picks up the new files immediately
echo "Restarting TiddlyWiki server..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2
su - ga -c "cd $WIKI_DIR && nohup tiddlywiki . --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to come back up
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running."
        break
    fi
    sleep 1
done

# Ensure Firefox is open and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080/ &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# Refresh the page to ensure fresh state
DISPLAY=:1 xdotool key ctrl+r
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="