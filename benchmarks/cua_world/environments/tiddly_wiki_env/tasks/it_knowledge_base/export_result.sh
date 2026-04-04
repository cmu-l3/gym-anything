#!/bin/bash
echo "=== Exporting it_knowledge_base result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/it_knowledge_base_final.png

GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*[Ii][Tt].*[Ss]upport\|Dispatching 'save' task:.*[Nn]etwork\|Dispatching 'save' task:.*[Pp]rinter\|Dispatching 'save' task:.*[Ee]mail\|Dispatching 'save' task:.*[Pp]erformance\|Dispatching 'save' task:.*[Qq]uick.*[Rr]eference" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

export GUI_SAVE_DETECTED

python3 << 'PYEOF'
import os, json, re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"

try:
    INITIAL_COUNT = int(open('/tmp/it_knowledge_base_initial_count').read().strip())
except Exception:
    INITIAL_COUNT = 0

GUI_SAVE = os.environ.get('GUI_SAVE_DETECTED', 'false').lower() == 'true'

REQUIRED = [
    "IT Support - Master Index",
    "IT Support - Network Connectivity",
    "IT Support - Slow Performance",
    "IT Support - Printer Problems",
    "IT Support - Email Configuration",
    "IT Support - Quick Reference Commands",
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


CURRENT_COUNT = count_user_tiddlers()

tiddlers_result = {}
found_count = 0
it_support_tagged = 0
table_count = 0
link_count = 0
heading_count = 0
adequate_words = 0
# Track structured content markers
symptoms_sections = 0
solutions_sections = 0

for title in REQUIRED:
    key = re.sub(r'\W+', '_', title).lower().strip('_')
    path = find_tiddler_file(title)
    if path:
        found_count += 1
        fields, text = parse_tiddler(path)
        tags = fields.get('tags', '')
        words = len(text.split())

        has_it_support = 'it-support' in tags.lower() or 'it support' in tags.lower() or 'itsupport' in tags.lower()
        has_heading = bool(re.search(r'^!!', text, re.MULTILINE))
        has_table = bool(re.search(r'^\|', text, re.MULTILINE))
        has_link = '[[' in text
        has_symptoms = bool(re.search(r'symptom', text, re.IGNORECASE))
        has_solutions = bool(re.search(r'solution|fix|resol', text, re.IGNORECASE))

        if has_it_support:
            it_support_tagged += 1
        if has_table:
            table_count += 1
        if has_link:
            link_count += 1
        if has_heading:
            heading_count += 1
        if words >= 100:
            adequate_words += 1
        if has_symptoms:
            symptoms_sections += 1
        if has_solutions:
            solutions_sections += 1

        tiddlers_result[key] = {
            "found": True,
            "words": words,
            "has_it_support_tag": has_it_support,
            "has_heading": has_heading,
            "has_table": has_table,
            "has_link": has_link,
            "has_symptoms": has_symptoms,
            "has_solutions": has_solutions,
        }
    else:
        tiddlers_result[key] = {
            "found": False, "words": 0,
            "has_it_support_tag": False, "has_heading": False,
            "has_table": False, "has_link": False,
            "has_symptoms": False, "has_solutions": False,
        }

output = {
    "initial_count": INITIAL_COUNT,
    "current_count": CURRENT_COUNT,
    "new_count": CURRENT_COUNT - INITIAL_COUNT,
    "gui_save_detected": GUI_SAVE,
    "found_count": found_count,
    "it_support_tagged_count": it_support_tagged,
    "table_count": table_count,
    "link_count": link_count,
    "heading_count": heading_count,
    "adequate_words_count": adequate_words,
    "symptoms_sections_count": symptoms_sections,
    "solutions_sections_count": solutions_sections,
    "tiddlers": tiddlers_result,
}

with open('/tmp/it_knowledge_base_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "Result saved to /tmp/it_knowledge_base_result.json"
echo "=== Export complete ==="
