#!/bin/bash
echo "=== Setting up build_interactive_inventory_dashboard task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
TIDDLER_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TIDDLER_DIR"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create the 6 initial reagent tiddlers using realistic laboratory data
echo "Seeding lab reagent data..."

cat > "$TIDDLER_DIR/Taq DNA Polymerase.tid" << 'EOF'
title: Taq DNA Polymerase
tags: Reagent
stock_level: 5
unit: tubes
type: text/vnd.tiddlywiki

Standard Taq polymerase for routine PCR applications. Stored in -20C freezer.
EOF

cat > "$TIDDLER_DIR/10x TBE Buffer.tid" << 'EOF'
title: 10x TBE Buffer
tags: Reagent
stock_level: 12
unit: bottles
type: text/vnd.tiddlywiki

Tris-borate-EDTA buffer for polyacrylamide and agarose gel electrophoresis.
EOF

cat > "$TIDDLER_DIR/Agarose Powder, LE.tid" << 'EOF'
title: Agarose Powder, LE
tags: Reagent
stock_level: 3
unit: bottles
type: text/vnd.tiddlywiki

Low electroendosmosis (LE) agarose, multi-purpose, 500g bottle.
EOF

cat > "$TIDDLER_DIR/1000uL Pipette Tips.tid" << 'EOF'
title: 1000uL Pipette Tips
tags: Reagent
stock_level: 25
unit: boxes
type: text/vnd.tiddlywiki

Blue, un-filtered, non-sterile pipette tips. Autoclave before use.
EOF

cat > "$TIDDLER_DIR/Ethidium Bromide (10mg_mL).tid" << 'EOF'
title: Ethidium Bromide (10mg/mL)
tags: Reagent
stock_level: 2
unit: vials
type: text/vnd.tiddlywiki

Fluorescent tag for nucleic acid visualization. **CAUTION: Mutagenic.**
EOF

cat > "$TIDDLER_DIR/Nuclease-Free Water.tid" << 'EOF'
title: Nuclease-Free Water
tags: Reagent
stock_level: 50
unit: aliquots
type: text/vnd.tiddlywiki

DEPC-treated, nuclease-free water for RNA work. 50mL conical tubes.
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Wait for TiddlyWiki to pick up the new files via its internal watcher
sleep 3

# Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running and accessible."
else
    echo "WARNING: TiddlyWiki server not responding at localhost:8080."
fi

# Ensure Firefox is focused on the application
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1

# Take an initial screenshot proving the starting state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="