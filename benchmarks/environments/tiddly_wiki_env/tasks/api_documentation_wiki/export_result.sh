#!/bin/bash
echo "=== Exporting api_documentation_wiki result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/api_documentation_wiki_final.png

GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*[Ll]ibrary.*[Aa][Pp][Ii]\|Dispatching 'save' task:.*[Aa][Pp][Ii].*[Dd]oc\|Dispatching 'save' task:.*[Aa]uth\|Dispatching 'save' task:.*[Ee]ndpoint\|Dispatching 'save' task:.*[Ee]rror.*[Cc]ode\|Dispatching 'save' task:.*[Cc]hangelog\|Dispatching 'save' task:.*[Oo]verview" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

export GUI_SAVE_DETECTED

python3 << 'PYEOF'
import os, json, re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"

try:
    INITIAL_COUNT = int(open('/tmp/api_documentation_wiki_initial_count').read().strip())
except Exception:
    INITIAL_COUNT = 0

GUI_SAVE = os.environ.get('GUI_SAVE_DETECTED', 'false').lower() == 'true'

REQUIRED = [
    "Library API - Overview",
    "Library API - Authentication Guide",
    "Library API - Endpoints Reference",
    "Library API - Error Codes Reference",
    "Library API - Changelog",
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
    """Count non-header table rows."""
    rows = [line for line in text.split('\n')
            if line.strip().startswith('|') and not line.strip().startswith('|!')]
    return len(rows)


CURRENT_COUNT = count_user_tiddlers()

tiddlers_result = {}
found_count = 0
api_doc_tagged = 0
library_tagged = 0
table_count = 0
link_count = 0
heading_count = 0
adequate_words = 0
endpoints_row_count = 0
error_codes_row_count = 0
changelog_row_count = 0
has_code_example = False

for title in REQUIRED:
    key = re.sub(r'\W+', '_', title).lower().strip('_')
    path = find_tiddler_file(title)
    if path:
        found_count += 1
        fields, text = parse_tiddler(path)
        tags = fields.get('tags', '')
        words = len(text.split())

        norm_tags = re.sub(r'[\s\-]', '', tags.lower())
        has_api_doc = 'api-documentation' in tags.lower() or 'apidocumentation' in norm_tags or 'api' in tags.lower()
        has_library = 'librarysystem' in norm_tags or 'library' in tags.lower()

        has_heading = bool(re.search(r'^!!', text, re.MULTILINE))
        has_table = bool(re.search(r'^\|', text, re.MULTILINE))
        has_link = '[[' in text

        if has_api_doc:
            api_doc_tagged += 1
        if has_library:
            library_tagged += 1
        if has_table:
            table_count += 1
        if has_link:
            link_count += 1
        if has_heading:
            heading_count += 1
        if words >= 120:
            adequate_words += 1

        # Check specific structural requirements
        if title == "Library API - Endpoints Reference":
            endpoints_row_count = count_table_rows(text)
        elif title == "Library API - Error Codes Reference":
            error_codes_row_count = count_table_rows(text)
        elif title == "Library API - Changelog":
            changelog_row_count = count_table_rows(text)
        elif title == "Library API - Authentication Guide":
            # Check for code example (backtick or monospace)
            has_code_example = '`' in text or '{{{' in text

        tiddlers_result[key] = {
            "found": True,
            "words": words,
            "has_api_doc_tag": has_api_doc,
            "has_library_tag": has_library,
            "has_heading": has_heading,
            "has_table": has_table,
            "has_link": has_link,
        }
    else:
        tiddlers_result[key] = {
            "found": False, "words": 0,
            "has_api_doc_tag": False, "has_library_tag": False,
            "has_heading": False, "has_table": False, "has_link": False,
        }

output = {
    "initial_count": INITIAL_COUNT,
    "current_count": CURRENT_COUNT,
    "new_count": CURRENT_COUNT - INITIAL_COUNT,
    "gui_save_detected": GUI_SAVE,
    "found_count": found_count,
    "api_doc_tagged_count": api_doc_tagged,
    "library_tagged_count": library_tagged,
    "table_count": table_count,
    "link_count": link_count,
    "heading_count": heading_count,
    "adequate_words_count": adequate_words,
    "endpoints_row_count": endpoints_row_count,
    "error_codes_row_count": error_codes_row_count,
    "changelog_row_count": changelog_row_count,
    "has_code_example_in_auth": has_code_example,
    "tiddlers": tiddlers_result,
}

with open('/tmp/api_documentation_wiki_result.json', 'w') as f:
    json.dump(output, f, indent=2)

print(json.dumps(output, indent=2))
PYEOF

echo "Result saved to /tmp/api_documentation_wiki_result.json"
echo "=== Export complete ==="
