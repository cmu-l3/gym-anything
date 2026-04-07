#!/bin/bash
echo "=== Setting up build_dynamic_grouping_index task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

echo "Waiting for TiddlyWiki API..."
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null; then
        break
    fi
    sleep 1
done

# Safe HTTP API injection function for pre-seeding complex data
create_tiddler() {
    local title="$1"
    local tags="$2"
    local director="$3"
    local year="$4"
    local text="$5"
    
    local encoded_title=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$title")
    
    local json_payload=$(python3 -c "
import json, sys
print(json.dumps({
    'title': sys.argv[1],
    'tags': sys.argv[2],
    'director': sys.argv[3],
    'release_year': sys.argv[4],
    'text': sys.argv[5]
}))
" "$title" "$tags" "$director" "$year" "$text")
    
    curl -s -X PUT -H "Content-Type: application/json" -d "$json_payload" "http://localhost:8080/recipes/default/tiddlers/$encoded_title" > /dev/null
}

echo "Injecting media tiddlers..."
create_tiddler "The Godfather" "Film" "Francis Ford Coppola" "1972" "Mafia epic."
create_tiddler "The Conversation" "Film" "Francis Ford Coppola" "1974" "Surveillance thriller."
create_tiddler "Apocalypse Now" "Film" "Francis Ford Coppola" "1979" "Vietnam war epic."

create_tiddler "Taxi Driver" "Film" "Martin Scorsese" "1976" "Psychological thriller."
create_tiddler "Raging Bull" "Film" "Martin Scorsese" "1980" "Boxing drama."
create_tiddler "Goodfellas" "Film" "Martin Scorsese" "1990" "Mobster film."

create_tiddler "Reservoir Dogs" "Film" "Quentin Tarantino" "1992" "Heist film."
create_tiddler "Pulp Fiction" "Film" "Quentin Tarantino" "1994" "Crime film."

create_tiddler "Death of a Salesman" "Play" "Elia Kazan" "1949" "Arthur Miller play."
create_tiddler "A Streetcar Named Desire" "Play" "Elia Kazan" "1947" "Tennessee Williams play."

# Refresh Firefox to show new contents seamlessly
echo "Refreshing Firefox..."
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    sleep 0.5
    DISPLAY=:1 xdotool key F5
    sleep 3
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="