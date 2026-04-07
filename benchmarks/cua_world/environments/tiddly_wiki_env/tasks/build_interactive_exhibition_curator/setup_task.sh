#!/bin/bash
echo "=== Setting up Exhibition Curator task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time

# Create museum artifact tiddlers directly in the file system
echo "Seeding artifact tiddlers..."
ARTIFACTS=(
    "Senet Board from KV62|A board game found in the tomb of Tutankhamun."
    "Faience Hippopotamus (William)|A blue faience statuette demonstrating wildlife representation."
    "Wooden Model of a Bakery|Middle Kingdom wooden tomb model showing daily food preparation."
    "Kohl Tube of Amenhotep III|Cosmetic container used for eye makeup."
    "Gold Mask of Tutankhamun|The iconic death mask of the boy king."
    "Narmer Palette|Early dynastic cosmetic palette showing the unification of Egypt."
    "Bust of Nefertiti|Stucco-coated limestone bust of the Great Royal Wife."
    "Statue of Khafre|Diorite statue of the Fourth Dynasty pharaoh."
    "Canopic Jar of Qebehsenuef|Limestone jar used to store mummified intestines."
    "Mummy of Hatshepsut|The mummified remains of the female pharaoh."
    "Book of the Dead of Ani|Papyrus scroll with spells to assist the deceased."
    "Sarcophagus of Seti I|Alabaster sarcophagus with intricate carvings."
)

for artifact in "${ARTIFACTS[@]}"; do
    TITLE="${artifact%%|*}"
    DESC="${artifact##*|}"
    FILENAME=$(echo "$TITLE" | sed 's/[\/\\:*?"<>|]/_/g')
    
    cat > "/home/ga/mywiki/tiddlers/${FILENAME}.tid" << EOF
title: $TITLE
tags: Artifact
type: text/vnd.tiddlywiki

$DESC
EOF
done
chown -R ga:ga /home/ga/mywiki/tiddlers/

# Restart TiddlyWiki to ensure it picks up the new files immediately
echo "Restarting TiddlyWiki server..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server
for i in {1..15}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki is up."
        break
    fi
    sleep 1
done

# Focus Firefox and reload
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    # Force reload to see new tiddlers
    DISPLAY=:1 xdotool key ctrl+r
    sleep 3
fi

take_screenshot /tmp/curator_initial.png

echo "=== Task setup complete ==="