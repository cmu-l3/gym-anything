#!/bin/bash
echo "=== Exporting gdd_wiki_setup result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/gdd_wiki_setup_final.png

# Check GUI save via server log (before Python to pass as env var)
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*[Ee]choes\|Dispatching 'save' task:.*GDD\|Dispatching 'save' task:.*[Cc]ore.*[Mm]echanics\|Dispatching 'save' task:.*[Cc]haracter\|Dispatching 'save' task:.*[Ww]orld\|Dispatching 'save' task:.*[Nn]arrative\|Dispatching 'save' task:.*[Tt]echnical" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

export GUI_SAVE_DETECTED

# Use Python to check all required tiddlers and build result JSON
python3 << 'PYEOF'
import os, json, re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"

try:
    INITIAL_COUNT = int(open('/tmp/gdd_wiki_setup_initial_count').read().strip())
except Exception:
    INITIAL_COUNT = 0

GUI_SAVE = os.environ.get('GUI_SAVE_DETECTED', 'false').lower() == 'true'

REQUIRED = [
    "Echoes of the Void - GDD Hub",
    "Echoes of the Void - Core Mechanics",
    "Echoes of the Void - Character Roster",
    "Echoes of the Void - World Design",
    "Echoes of the Void - Story and Narrative",
    "Echoes of the Void - Technical Requirements",
]


def count_user_tiddlers():
    try:
        return sum(1 for f in os.listdir(TIDDLER_DIR)
                   if f.endswith('.tid') and not f.startswith('$__'))
    except Exception:
        return 0


def find_tiddler_file(title):
    """Find .tid file for a tiddler by exact title match, then by title field search."""
    fname = title + ".tid"
    path = os.path.join(TIDDLER_DIR, fname)
    if os.path.exists(path):
        return path
    # Case-insensitive filename match
    try:
        for f in os.listdir(TIDDLER_DIR):
            if f.lower() == fname.lower() and f.endswith('.tid'):
                return os.path.join(TIDDLER_DIR, f)
    except Exception:
        pass
    # Search by title field inside .tid files (handles sanitized filenames)
    try:
        for f in os.listdir(TIDDLER_DIR):
            if not f.endswith('.tid') or f.startswith('$__'):
                continue
            fpath = os.path.join(TIDDLER_DIR, f)
            try:
                with open(fpath, encoding='utf-8', errors='replace') as fp:
                    for line in fp:
                        line = line.rstrip('\n\r')
                        if not line:
                            break
                        if line.lower().startswith('title:'):
                            file_title = line[6:].strip()
                            if file_title.lower() == title.lower():
                                return fpath
            except Exception:
                pass
    except Exception:
        pass
    return None


def parse_tiddler(path):
    """Return (fields_dict, body_text) for a .tid file."""
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception:
        return {}, ""
    parts = content.split('\n\n', 1)
    fields = {}
    for line in parts[0].split('\n'):
        if ':' in line:
            key, _, val = line.partition(':')
            fields[key.strip().lower()] = val.strip()
    text = parts[1] if len(parts) > 1 else ""
    return fields, text


CURRENT_COUNT = count_user_tiddlers()

tiddlers_result = {}
found_count = 0
gdd_tagged = 0
echoes_tagged = 0
table_count = 0
link_count = 0
heading_count = 0
adequate_words = 0

for title in REQUIRED:
    key = re.sub(r'\W+', '_', title).lower().strip('_')
    path = find_tiddler_file(title)
    if path:
        found_count += 1
        fields, text = parse_tiddler(path)
        tags = fields.get('tags', '')
        words = len(text.split())

        has_gdd = 'gdd' in tags.lower()
        # Match EchoesOfTheVoid ignoring spaces/hyphens
        norm_tags = re.sub(r'[\s\-]', '', tags.lower())
        has_echoes = 'echoesofthevoid' in norm_tags

        has_heading = bool(re.search(r'^!!', text, re.MULTILINE))
        has_table = bool(re.search(r'^\|', text, re.MULTILINE))
        has_link = '[[' in text

        if has_gdd:
            gdd_tagged += 1
        if has_echoes:
            echoes_tagged += 1
        if has_table:
            table_count += 1
        if has_link:
            link_count += 1
        if has_heading:
            heading_count += 1
        if words >= 80:
            adequate_words += 1

        tiddlers_result[key] = {
            "found": True,
            "words": words,
            "has_gdd_tag": has_gdd,
            "has_echoes_tag": has_echoes,
            "has_heading": has_heading,
            "has_table": has_table,
            "has_link": has_link,
        }
    else:
        key = re.sub(r'\W+', '_', title).lower().strip('_')
        tiddlers_result[key] = {
            "found": False, "words": 0,
            "has_gdd_tag": False, "has_echoes_tag": False,
            "has_heading": False, "has_table": False, "has_link": False,
        }

output = {
    "initial_count": INITIAL_COUNT,
    "current_count": CURRENT_COUNT,
    "new_count": CURRENT_COUNT - INITIAL_COUNT,
    "gui_save_detected": GUI_SAVE,
    "found_count": found_count,
    "gdd_tagged_count": gdd_tagged,
    "echoes_tagged_count": echoes_tagged,
    "table_count": table_count,
    "link_count": link_count,
    "heading_count": heading_count,
    "adequate_words_count": adequate_words,
    "tiddlers": tiddlers_result,
}

with open('/tmp/gdd_wiki_setup_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "Result saved to /tmp/gdd_wiki_setup_result.json"
echo "=== Export complete ==="
