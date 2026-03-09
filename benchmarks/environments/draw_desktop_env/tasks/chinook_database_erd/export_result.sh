#!/bin/bash
# Do NOT use set -e

echo "=== Exporting chinook_database_erd result ==="

DISPLAY=:1 import -window root /tmp/chinook_erd_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/chinook_erd.drawio"
PNG_FILE="/home/ga/Desktop/chinook_erd.png"

FILE_EXISTS="false"
FILE_SIZE=0
PNG_EXISTS="false"
PNG_SIZE=0
NUM_SHAPES=0
NUM_EDGES=0
NUM_PAGES=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_MODIFIED_AFTER_START="false"

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
    echo "Found ERD file: $DRAWIO_FILE ($FILE_SIZE bytes, mtime=$FILE_MTIME, start=$TASK_START)"
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    echo "Found PNG: $PNG_FILE ($PNG_SIZE bytes)"
fi

# Deep XML analysis with Python (handles both compressed and uncompressed draw.io)
python3 << 'PYEOF' > /tmp/chinook_erd_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/chinook_erd.drawio"
result = {
    "num_shapes": 0,
    "num_edges": 0,
    "num_pages": 0,
    "has_group_or_swimlane": False,
    "tables_found": [],
    "fk_keywords_found": [],
    "has_crowfoot_style": False,
    "text_content": "",
    "error": None
}

REQUIRED_TABLES = ["artist", "album", "track", "mediatype", "genre",
                   "playlist", "playlisttrack", "invoice", "invoiceline",
                   "customer", "employee"]

FK_KEYWORDS = ["pk", "fk", "primary", "foreign", "artificialprimarykey",
               "albumid", "artistid", "genreid", "mediatypeid", "trackid",
               "playlistid", "customerid", "invoiceid", "employeeid",
               "supportrepid", "reportsto"]

def decompress_diagram(content):
    """Try to decompress draw.io diagram content (base64+raw-deflate or URL-encoded)."""
    if not content or not content.strip():
        return None
    try:
        decoded = base64.b64decode(content.strip())
        decompressed = zlib.decompress(decoded, -15)
        return ET.fromstring(decompressed)
    except Exception:
        pass
    try:
        from urllib.parse import unquote
        decoded_str = unquote(content.strip())
        if decoded_str.startswith('<'):
            return ET.fromstring(decoded_str)
    except Exception:
        pass
    return None

try:
    if not os.path.exists(filepath):
        result["error"] = "File not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()

        # Count pages
        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)

        all_cells = []
        # Process each page
        for page in pages:
            # Try to get inline cells first
            inline_cells = list(page.iter('mxCell'))
            if inline_cells:
                all_cells.extend(inline_cells)
            else:
                # Try compressed content
                inner_root = decompress_diagram(page.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))

        # Also get cells directly from root (uncompressed fallback)
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        # Count shapes and edges; collect text
        all_text_parts = []
        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            if cell.get('vertex') == '1' and cell.get('id') not in ('0', '1'):
                result["num_shapes"] += 1
                if val:
                    all_text_parts.append(val)
                # Check for group/swimlane styles
                if 'swimlane' in style or 'group' in style or 'container' in style:
                    result["has_group_or_swimlane"] = True
                # Check for crowfoot styles
                if 'errelation' in style or 'crowfoot' in style or 'endArrow=ERmany' in style or 'erd' in style.lower():
                    result["has_crowfoot_style"] = True
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val:
                    all_text_parts.append(val)
                # Check edge styles for crow's foot notation
                style_raw = (cell.get('style') or '').lower()
                if 'ermany' in style_raw or 'ercurveone' in style_raw or 'errelation' in style_raw or 'crowfoot' in style_raw:
                    result["has_crowfoot_style"] = True

        combined_text = ' '.join(all_text_parts).lower()
        # Also check HTML-stripped text
        import html as html_mod
        plain_text = re.sub(r'<[^>]+>', ' ', combined_text)
        plain_text = html_mod.unescape(plain_text).lower()
        search_text = combined_text + ' ' + plain_text

        result["text_content"] = search_text[:2000]

        # Check for required table names
        for tbl in REQUIRED_TABLES:
            if re.search(r'\b' + re.escape(tbl) + r'\b', search_text):
                result["tables_found"].append(tbl)

        # Check for FK/PK keywords and relationship column names
        for kw in FK_KEYWORDS:
            if kw in search_text:
                result["fk_keywords_found"].append(kw)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Parse analysis results
if [ -f /tmp/chinook_erd_analysis.json ]; then
    NUM_SHAPES=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(d.get('num_shapes',0))" 2>/dev/null || echo "0")
    NUM_EDGES=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(d.get('num_edges',0))" 2>/dev/null || echo "0")
    NUM_PAGES=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(d.get('num_pages',0))" 2>/dev/null || echo "0")
    TABLES_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(len(d.get('tables_found',[])))" 2>/dev/null || echo "0")
    FK_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(len(d.get('fk_keywords_found',[])))" 2>/dev/null || echo "0")
    HAS_GROUPS=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(str(d.get('has_group_or_swimlane',False)).lower())" 2>/dev/null || echo "false")
    HAS_CROWFOOT=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(str(d.get('has_crowfoot_style',False)).lower())" 2>/dev/null || echo "false")
    TABLES_FOUND_LIST=$(python3 -c "import json; d=json.load(open('/tmp/chinook_erd_analysis.json')); print(','.join(d.get('tables_found',[])))" 2>/dev/null || echo "")
fi

NUM_SHAPES=${NUM_SHAPES:-0}
NUM_EDGES=${NUM_EDGES:-0}
NUM_PAGES=${NUM_PAGES:-0}
TABLES_FOUND=${TABLES_FOUND:-0}
FK_COUNT=${FK_COUNT:-0}
HAS_GROUPS=${HAS_GROUPS:-"false"}
HAS_CROWFOOT=${HAS_CROWFOOT:-"false"}

echo "Analysis: shapes=$NUM_SHAPES edges=$NUM_EDGES pages=$NUM_PAGES tables=$TABLES_FOUND fk_kws=$FK_COUNT groups=$HAS_GROUPS crowfoot=$HAS_CROWFOOT"
echo "Tables: $TABLES_FOUND_LIST"

# Validate PNG
PNG_VALID="false"
PNG_DIMS="0x0"
if [ -f "$PNG_FILE" ]; then
    if file "$PNG_FILE" 2>/dev/null | grep -qi "png"; then
        PNG_VALID="true"
    fi
    if command -v identify &>/dev/null; then
        PNG_DIMS=$(identify -format "%wx%h" "$PNG_FILE" 2>/dev/null || echo "0x0")
    fi
fi

# Build result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_valid": $PNG_VALID,
    "png_dimensions": "$PNG_DIMS",
    "num_shapes": $NUM_SHAPES,
    "num_edges": $NUM_EDGES,
    "num_pages": $NUM_PAGES,
    "tables_found": $TABLES_FOUND,
    "fk_keywords_count": $FK_COUNT,
    "has_groups": $HAS_GROUPS,
    "has_crowfoot_style": $HAS_CROWFOOT,
    "tables_list": "$TABLES_FOUND_LIST",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export complete ==="
