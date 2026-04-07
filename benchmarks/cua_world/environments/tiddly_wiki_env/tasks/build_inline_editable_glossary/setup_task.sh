#!/bin/bash
echo "=== Setting up build_inline_editable_glossary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the terminology tiddlers
TIDDLER_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TIDDLER_DIR"

cat > "$TIDDLER_DIR/Myocardial Infarction.tid" << 'EOF'
title: Myocardial Infarction
tags: Term
es: Infarto de miocardio
fr: Infarctus du myocarde

A heart attack.
EOF

cat > "$TIDDLER_DIR/Hypertension.tid" << 'EOF'
title: Hypertension
tags: Term
es: Hipertensión

High blood pressure.
EOF

cat > "$TIDDLER_DIR/Erythema.tid" << 'EOF'
title: Erythema
tags: Term
fr: Érythème

Redness of the skin.
EOF

cat > "$TIDDLER_DIR/Atelectasis.tid" << 'EOF'
title: Atelectasis
tags: Term
fr: Atelectasie

Partial or complete collapse of the lung.
EOF

cat > "$TIDDLER_DIR/Tachycardia.tid" << 'EOF'
title: Tachycardia
tags: Term
es: Taquicardia

A heart rate that is too fast.
EOF

cat > "$TIDDLER_DIR/Dyspnea.tid" << 'EOF'
title: Dyspnea
tags: Term
es: Disnea
fr: Dyspnée

Shortness of breath.
EOF

chown -R ga:ga "$TIDDLER_DIR"

# Delete any existing Glossary Dashboard to ensure clean state
rm -f "$TIDDLER_DIR/Glossary Dashboard.tid" 2>/dev/null || true
rm -f "$TIDDLER_DIR/Glossary_Dashboard.tid" 2>/dev/null || true

# Give TiddlyWiki server a moment to sync files
sleep 2

# Reload browser to ensure it picks up new tiddlers
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

# Record initial mod time of target tiddlers for anti-gaming
stat -c %Y "$TIDDLER_DIR/Atelectasis.tid" 2>/dev/null > /tmp/atelectasis_mtime
stat -c %Y "$TIDDLER_DIR/Tachycardia.tid" 2>/dev/null > /tmp/tachycardia_mtime

# Take initial screenshot for evidence
take_screenshot /tmp/glossary_initial.png ga

echo "=== Task setup complete ==="