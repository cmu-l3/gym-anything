#!/bin/bash
echo "=== Setting up create_dynamic_az_glossary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create pre-populated GlossaryTerm tiddlers
echo "Creating terminology tiddlers..."
TERMS_DIR="/home/ga/mywiki/tiddlers"
mkdir -p "$TERMS_DIR"

declare -A TERMS=(
    ["Algorithm"]="A step-by-step procedure for solving a problem or accomplishing some end."
    ["API"]="Application Programming Interface, a set of functions and procedures allowing the creation of applications."
    ["Bandwidth"]="The maximum rate of data transfer across a given path."
    ["Boolean"]="A binary variable, having two possible values called 'true' and 'false'."
    ["Cache"]="A hardware or software component that stores data so that future requests for that data can be served faster."
    ["Compiler"]="A program that converts instructions into a machine-code or lower-level form so that they can be read and executed by a computer."
    ["Database"]="An organized collection of data, generally stored and accessed electronically from a computer system."
    ["Encryption"]="The process of encoding information."
    ["Firewall"]="A network security system that monitors and controls incoming and outgoing network traffic."
    ["Framework"]="An abstraction in which software providing generic functionality can be selectively changed by additional user-written code."
)

for term in "${!TERMS[@]}"; do
    cat > "$TERMS_DIR/$term.tid" << EOF
created: $(date -u +"%Y%m%d%H%M%S000")
modified: $(date -u +"%Y%m%d%H%M%S000")
tags: GlossaryTerm
title: $term
type: text/vnd.tiddlywiki

${TERMS[$term]}
EOF
    chown ga:ga "$TERMS_DIR/$term.tid"
done

# Wait for TiddlyWiki to detect the new files
sleep 3

# Record initial state
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Ensure TiddlyWiki is running and focused
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is responding"
fi

# Focus Firefox
DISPLAY=:1 wmctrl -a "TiddlyWiki" 2>/dev/null || DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot showing clean state
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="