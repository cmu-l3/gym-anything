#!/bin/bash
echo "=== Exporting fiction_worldbuilding_wiki result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/fiction_worldbuilding_wiki_final.png

GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*[Cc]elestial\|Dispatching 'save' task:.*[Ff]action\|Dispatching 'save' task:.*[Cc]haracter\|Dispatching 'save' task:.*[Mm]agic\|Dispatching 'save' task:.*[Tt]imeline\|Dispatching 'save' task:.*[Gg]lossary\|Dispatching 'save' task:.*[Ww]orld.*[Oo]verview" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

export GUI_SAVE_DETECTED

python3 << 'PYEOF'
import os, json, re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"

try:
    INITIAL_COUNT = int(open('/tmp/fiction_worldbuilding_wiki_initial_count').read().strip())
except Exception:
    INITIAL_COUNT = 0

GUI_SAVE = os.environ.get('GUI_SAVE_DETECTED', 'false').lower() == 'true'

REQUIRED = [
    "Celestial War - World Overview",
    "Celestial War - Factions and Politics",
    "Celestial War - Characters",
    "Celestial War - Magic System",
    "Celestial War - Timeline",
    "Celestial War - Glossary",
]


def count_user_tiddlers():
    try:
        return sum(1 for f in os.listdir(TIDDLER_DIR)
                   if f.endswith('.tid') and not f.startswith('$__'))
    except Exception:
        return 0


def find_tiddler_file(title):
    fname = title + ".tid"
    path = os.path.join(TIDDLER_DIR, fname)
    if os.path.exists(path):
        return path
    try:
        for f in os.listdir(TIDDLER_DIR):
            if f.lower() == fname.lower() and f.endswith('.tid'):
                return os.path.join(TIDDLER_DIR, f)
    except Exception:
        pass
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
                            if line[6:].strip().lower() == title.lower():
                                return fpath
            except Exception:
                pass
    except Exception:
        pass
    return None


def parse_tiddler(path):
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


def count_table_rows(text):
    """Count non-header table rows (lines starting with | but not |!)."""
    rows = [line for line in text.split('\n')
            if line.strip().startswith('|') and not line.strip().startswith('|!')]
    return len(rows)


CURRENT_COUNT = count_user_tiddlers()

tiddlers_result = {}
found_count = 0
fiction_tagged = 0
cw_tagged = 0
table_count = 0
link_count = 0
heading_count = 0
adequate_words = 0
characters_table_rows = 0

for title in REQUIRED:
    key = re.sub(r'\W+', '_', title).lower().strip('_')
    path = find_tiddler_file(title)
    if path:
        found_count += 1
        fields, text = parse_tiddler(path)
        tags = fields.get('tags', '')
        words = len(text.split())

        has_fiction = 'fiction' in tags.lower()
        norm_tags = re.sub(r'[\s\-]', '', tags.lower())
        has_cw = 'celestialwar' in norm_tags

        has_heading = bool(re.search(r'^!!', text, re.MULTILINE))
        has_table = bool(re.search(r'^\|', text, re.MULTILINE))
        has_link = '[[' in text

        if has_fiction:
            fiction_tagged += 1
        if has_cw:
            cw_tagged += 1
        if has_table:
            table_count += 1
        if has_link:
            link_count += 1
        if has_heading:
            heading_count += 1
        if words >= 100:
            adequate_words += 1

        # For Characters tiddler, count table rows to verify 5+ characters
        if title == "Celestial War - Characters":
            characters_table_rows = count_table_rows(text)

        tiddlers_result[key] = {
            "found": True,
            "words": words,
            "has_fiction_tag": has_fiction,
            "has_cw_tag": has_cw,
            "has_heading": has_heading,
            "has_table": has_table,
            "has_link": has_link,
        }
    else:
        tiddlers_result[key] = {
            "found": False, "words": 0,
            "has_fiction_tag": False, "has_cw_tag": False,
            "has_heading": False, "has_table": False, "has_link": False,
        }

output = {
    "initial_count": INITIAL_COUNT,
    "current_count": CURRENT_COUNT,
    "new_count": CURRENT_COUNT - INITIAL_COUNT,
    "gui_save_detected": GUI_SAVE,
    "found_count": found_count,
    "fiction_tagged_count": fiction_tagged,
    "cw_tagged_count": cw_tagged,
    "table_count": table_count,
    "link_count": link_count,
    "heading_count": heading_count,
    "adequate_words_count": adequate_words,
    "characters_table_rows": characters_table_rows,
    "tiddlers": tiddlers_result,
}

with open('/tmp/fiction_worldbuilding_wiki_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "Result saved to /tmp/fiction_worldbuilding_wiki_result.json"
echo "=== Export complete ==="
