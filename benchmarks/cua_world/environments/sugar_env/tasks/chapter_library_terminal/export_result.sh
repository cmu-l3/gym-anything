#!/bin/bash
echo "=== Exporting chapter_library_terminal task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/terminal_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/chapter_library_terminal_start_ts 2>/dev/null || echo "0")
LIBRARY_DIR="/home/ga/Library"
CHAPTERS_DIR="$LIBRARY_DIR/chapters"

export DIR_EXISTS="false"
export CHAPTER_COUNT=0
export VALID_MTIME="true" # Set to false if any file is older than task start
export NON_TRIVIAL_FILES="true"

export CHAP1_CORRECT="false"
export CHAP7_CORRECT="false"
export CHAP12_CORRECT="false"

export INDEX_EXISTS="false"
export INDEX_COUNT=0

export STATS_EXISTS="false"
export STATS_COUNT=0

export SEARCH_EXISTS="false"
export SEARCH_EXECUTABLE="false"
export SEARCH_WORKS="false"
export SEARCH_OUTPUT=""

if [ -d "$CHAPTERS_DIR" ]; then
    DIR_EXISTS="true"
    # Find chapter files (case insensitive for extension, matches chapter_01.txt or chapter_1.txt)
    CHAPTER_FILES=$(find "$CHAPTERS_DIR" -type f -iname "chapter_*.txt" 2>/dev/null)
    CHAPTER_COUNT=$(echo "$CHAPTER_FILES" | grep -c "chapter" || echo "0")
    
    # Check mtime and sizes
    if [ -n "$CHAPTER_FILES" ]; then
        for f in $CHAPTER_FILES; do
            mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$mtime" -lt "$TASK_START" ]; then
                VALID_MTIME="false"
            fi
            size=$(stat -c %s "$f" 2>/dev/null || echo "0")
            if [ "$size" -lt 200 ]; then
                NON_TRIVIAL_FILES="false"
            fi
        done
        
        # Check specific chapters by content validating phrases
        CHAP1_FILE=$(find "$CHAPTERS_DIR" -type f -iname "chapter_*1.txt" | head -1)
        if [ -n "$CHAP1_FILE" ]; then
            if grep -qiE "rabbit-hole|down the rabbit" "$CHAP1_FILE"; then
                CHAP1_CORRECT="true"
            fi
        fi
        
        CHAP7_FILE=$(find "$CHAPTERS_DIR" -type f -iname "chapter_*7.txt" | head -1)
        if [ -n "$CHAP7_FILE" ]; then
            if grep -qiE "hatter|tea-party" "$CHAP7_FILE"; then
                CHAP7_CORRECT="true"
            fi
        fi
        
        CHAP12_FILE=$(find "$CHAPTERS_DIR" -type f -iname "chapter_*12.txt" | head -1)
        if [ -n "$CHAP12_FILE" ]; then
            if grep -qiE "verdict|evidence" "$CHAP12_FILE"; then
                CHAP12_CORRECT="true"
            fi
        fi
    fi
fi

if [ -f "$LIBRARY_DIR/index.txt" ]; then
    INDEX_EXISTS="true"
    mtime=$(stat -c %Y "$LIBRARY_DIR/index.txt" 2>/dev/null || echo "0")
    if [ "$mtime" -lt "$TASK_START" ]; then
        VALID_MTIME="false"
    fi
    # Count lines that look like chapter listings
    INDEX_COUNT=$(grep -ciE "chapter" "$LIBRARY_DIR/index.txt" || echo "0")
fi

if [ -f "$LIBRARY_DIR/stats.txt" ]; then
    STATS_EXISTS="true"
    mtime=$(stat -c %Y "$LIBRARY_DIR/stats.txt" 2>/dev/null || echo "0")
    if [ "$mtime" -lt "$TASK_START" ]; then
        VALID_MTIME="false"
    fi
    # Count lines with numbers and words
    STATS_COUNT=$(grep -ciE "[0-9]+.*words|words.*[0-9]+" "$LIBRARY_DIR/stats.txt" || echo "0")
    
    # Also just check lines with numbers if the exact word format wasn't followed
    if [ "$STATS_COUNT" -eq 0 ]; then
        STATS_COUNT=$(grep -ciE "[0-9]+" "$LIBRARY_DIR/stats.txt" || echo "0")
    fi
fi

if [ -f "$LIBRARY_DIR/search.sh" ]; then
    SEARCH_EXISTS="true"
    mtime=$(stat -c %Y "$LIBRARY_DIR/search.sh" 2>/dev/null || echo "0")
    if [ "$mtime" -lt "$TASK_START" ]; then
        VALID_MTIME="false"
    fi
    
    if [ -x "$LIBRARY_DIR/search.sh" ]; then
        SEARCH_EXECUTABLE="true"
        
        # Test the script if chapters exist
        if [ "$CHAPTER_COUNT" -gt 0 ]; then
            SEARCH_OUTPUT=$(su - ga -c "cd /home/ga/Library && ./search.sh 'rabbit'" 2>/dev/null | head -n 20 || true)
            
            # Check if output contains rabbit (case insensitive)
            if echo "$SEARCH_OUTPUT" | grep -qi "rabbit"; then
                SEARCH_WORKS="true"
            fi
        fi
    fi
fi

# Write results to JSON safely via python to prevent quote escaping errors
python3 << 'PYEOF' > /tmp/chapter_library_result.json
import json
import os

result = {
    "dir_exists": os.environ.get("DIR_EXISTS") == "true",
    "chapter_count": int(os.environ.get("CHAPTER_COUNT", 0)),
    "valid_mtime": os.environ.get("VALID_MTIME") == "true",
    "non_trivial_files": os.environ.get("NON_TRIVIAL_FILES") == "true",
    "chap1_correct": os.environ.get("CHAP1_CORRECT") == "true",
    "chap7_correct": os.environ.get("CHAP7_CORRECT") == "true",
    "chap12_correct": os.environ.get("CHAP12_CORRECT") == "true",
    "index_exists": os.environ.get("INDEX_EXISTS") == "true",
    "index_count": int(os.environ.get("INDEX_COUNT", 0)),
    "stats_exists": os.environ.get("STATS_EXISTS") == "true",
    "stats_count": int(os.environ.get("STATS_COUNT", 0)),
    "search_exists": os.environ.get("SEARCH_EXISTS") == "true",
    "search_executable": os.environ.get("SEARCH_EXECUTABLE") == "true",
    "search_works": os.environ.get("SEARCH_WORKS") == "true",
    "search_output": os.environ.get("SEARCH_OUTPUT", "")
}

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/chapter_library_result.json
echo "Result saved to /tmp/chapter_library_result.json"
cat /tmp/chapter_library_result.json
echo "=== Export complete ==="