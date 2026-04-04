#!/bin/bash
echo "=== Exporting research_synthesis_wiki result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/research_synthesis_wiki_final.png

GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*[Qq]uantum.*[Cc]omputing\|Dispatching 'save' task:.*[Rr]esearch.*[Hh]ub\|Dispatching 'save' task:.*[Kk]ey.*[Cc]oncepts\|Dispatching 'save' task:.*[Hh]ardware\|Dispatching 'save' task:.*[Aa]pplication\|Dispatching 'save' task:.*[Cc]hallenge" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

export GUI_SAVE_DETECTED

python3 << 'PYEOF'
import os, json, re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"

try:
    INITIAL_COUNT = int(open('/tmp/research_synthesis_wiki_initial_count').read().strip())
except Exception:
    INITIAL_COUNT = 0

GUI_SAVE = os.environ.get('GUI_SAVE_DETECTED', 'false').lower() == 'true'

REQUIRED = [
    "Quantum Computing - Research Hub",
    "Quantum Computing - Key Concepts",
    "Quantum Computing - Current Hardware",
    "Quantum Computing - Real-World Applications",
    "Quantum Computing - Challenges and Roadmap",
]

EXISTING_TIDDLER = "Quantum Entanglement Explained"


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


CURRENT_COUNT = count_user_tiddlers()

tiddlers_result = {}
found_count = 0
research_tagged = 0
qc_tagged = 0
table_count = 0
link_count = 0
heading_count = 0
adequate_words = 0
hub_links_to_existing = False

for title in REQUIRED:
    key = re.sub(r'\W+', '_', title).lower().strip('_')
    path = find_tiddler_file(title)
    if path:
        found_count += 1
        fields, text = parse_tiddler(path)
        tags = fields.get('tags', '')
        words = len(text.split())

        has_research = 'research' in tags.lower()
        norm_tags = re.sub(r'[\s\-]', '', tags.lower())
        has_qc = 'quantumcomputing' in norm_tags

        has_heading = bool(re.search(r'^!!', text, re.MULTILINE))
        has_table = bool(re.search(r'^\|', text, re.MULTILINE))
        has_link = '[[' in text

        # Check if hub links to the existing Quantum Entanglement tiddler
        if title == "Quantum Computing - Research Hub":
            hub_links_to_existing = EXISTING_TIDDLER.lower() in text.lower() or \
                                    'quantum entanglement' in text.lower()

        if has_research:
            research_tagged += 1
        if has_qc:
            qc_tagged += 1
        if has_table:
            table_count += 1
        if has_link:
            link_count += 1
        if has_heading:
            heading_count += 1
        if words >= 120:
            adequate_words += 1

        tiddlers_result[key] = {
            "found": True,
            "words": words,
            "has_research_tag": has_research,
            "has_qc_tag": has_qc,
            "has_heading": has_heading,
            "has_table": has_table,
            "has_link": has_link,
        }
    else:
        tiddlers_result[key] = {
            "found": False, "words": 0,
            "has_research_tag": False, "has_qc_tag": False,
            "has_heading": False, "has_table": False, "has_link": False,
        }

output = {
    "initial_count": INITIAL_COUNT,
    "current_count": CURRENT_COUNT,
    "new_count": CURRENT_COUNT - INITIAL_COUNT,
    "gui_save_detected": GUI_SAVE,
    "found_count": found_count,
    "research_tagged_count": research_tagged,
    "qc_tagged_count": qc_tagged,
    "table_count": table_count,
    "link_count": link_count,
    "heading_count": heading_count,
    "adequate_words_count": adequate_words,
    "hub_links_to_existing_tiddler": hub_links_to_existing,
    "tiddlers": tiddlers_result,
}

with open('/tmp/research_synthesis_wiki_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "Result saved to /tmp/research_synthesis_wiki_result.json"
echo "=== Export complete ==="
