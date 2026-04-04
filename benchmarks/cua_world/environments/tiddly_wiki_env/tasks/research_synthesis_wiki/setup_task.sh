#!/bin/bash
echo "=== Setting up research_synthesis_wiki task ==="

source /workspace/scripts/task_utils.sh

INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/research_synthesis_wiki_initial_count
echo "Initial tiddler count: $INITIAL_COUNT"

date +%s > /tmp/research_synthesis_wiki_start_ts

# Verify the pre-existing Quantum Entanglement tiddler is present
if [ "$(tiddler_exists 'Quantum Entanglement Explained')" = "true" ]; then
    echo "Pre-existing tiddler 'Quantum Entanglement Explained' is present"
else
    echo "WARNING: Pre-existing tiddler 'Quantum Entanglement Explained' not found"
fi

if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

take_screenshot /tmp/research_synthesis_wiki_initial.png

echo "=== Task setup complete ==="
