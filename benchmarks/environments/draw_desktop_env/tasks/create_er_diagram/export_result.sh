#!/bin/bash
# Do NOT use set -e: grep -c returns exit 1 on 0 matches, causing premature exit

echo "=== Exporting create_er_diagram task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/er_task_end.png 2>/dev/null || true

DIAGRAM_FILE="/home/ga/Desktop/library_er_diagram.drawio"
FOUND="false"
FILE_EXISTS="false"
FILE_SIZE=0
NUM_SHAPES=0
NUM_CONNECTIONS=0
VALID_CONNECTIONS=0
HAS_BOOK="false"
HAS_AUTHOR="false"
HAS_MEMBER="false"
HAS_LOAN="false"
HAS_BOOK_ID="false"
HAS_TITLE="false"
HAS_ISBN="false"
HAS_AUTHOR_ID="false"
HAS_AUTHOR_NAME="false"
HAS_MEMBER_ID="false"
HAS_MEMBER_NAME="false"
HAS_EMAIL="false"
HAS_LOAN_ID="false"
HAS_LOAN_DATE="false"
TOTAL_ATTRIBUTES=0

if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS="true"
    FOUND="true"
    FILE_SIZE=$(stat --format=%s "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    echo "Found diagram: $DIAGRAM_FILE ($FILE_SIZE bytes)"

    # Count shapes and connections
    NUM_SHAPES=$(grep -c 'vertex="1"' "$DIAGRAM_FILE" 2>/dev/null || true)
    NUM_SHAPES=${NUM_SHAPES:-0}
    NUM_CONNECTIONS=$(grep -c 'edge="1"' "$DIAGRAM_FILE" 2>/dev/null || true)
    NUM_CONNECTIONS=${NUM_CONNECTIONS:-0}

    # Count valid connections (edges with both source and target)
    VALID_CONNECTIONS=$(awk '
        BEGIN { count = 0; in_edge = 0; has_source = 0; has_target = 0 }
        /edge="1"/ { in_edge = 1; has_source = 0; has_target = 0 }
        in_edge && /source="[^"]+"/ { has_source = 1 }
        in_edge && /target="[^"]+"/ { has_target = 1 }
        in_edge && (/\/>/ || /<\/mxCell>/) {
            if (has_source && has_target) count++
            in_edge = 0
        }
        END { print count }
    ' "$DIAGRAM_FILE" 2>/dev/null || true)
    VALID_CONNECTIONS=${VALID_CONNECTIONS:-0}
    VALID_CONNECTIONS=$(printf '%d' "$VALID_CONNECTIONS" 2>/dev/null || echo "0")

    # Use Python with XML parsing for structural content analysis
    # Key: verify entity names appear inside vertex shapes (not edge labels or random text)
    python3 << 'PYEOF' > /tmp/er_analysis.json 2>/dev/null || true
import json
import re
import xml.etree.ElementTree as ET

diagram_file = "/home/ga/Desktop/library_er_diagram.drawio"
result = {
    "has_book": False,
    "has_author": False,
    "has_member": False,
    "has_loan": False,
    "has_book_id": False,
    "has_title": False,
    "has_isbn": False,
    "has_author_id": False,
    "has_author_name": False,
    "has_member_id": False,
    "has_member_name": False,
    "has_email": False,
    "has_loan_id": False,
    "has_loan_date": False,
    "total_attributes": 0,
    "entity_count": 0,
    "entities_in_shapes": 0
}

try:
    tree = ET.parse(diagram_file)
    root = tree.getroot()

    # Collect text from vertex shapes only (not edges)
    vertex_values = []
    edge_values = []
    for cell in root.iter('mxCell'):
        value = (cell.get('value') or '').strip()
        if not value:
            continue
        if cell.get('vertex') == '1':
            vertex_values.append(value)
        elif cell.get('edge') == '1':
            edge_values.append(value)

    # Also check UserObject elements (draw.io sometimes wraps cells in these)
    for obj in root.iter('UserObject'):
        value = (obj.get('label') or obj.get('value') or '').strip()
        if not value:
            continue
        # Check if parent or child mxCell is a vertex
        child_cell = obj.find('mxCell')
        if child_cell is not None and child_cell.get('vertex') == '1':
            vertex_values.append(value)

    # Build text from vertex shapes only (for entity detection)
    vertex_text = ' '.join(v.lower() for v in vertex_values)
    # Build text from all elements (for attribute detection - attributes may be
    # in child shapes or HTML content within entity shapes)
    all_values = vertex_values + edge_values
    all_text = ' '.join(v.lower() for v in all_values)

    # Also extract text from HTML content within value attributes
    # draw.io often stores rich text as HTML: value="<b>Book</b><hr>book_id<br>title"
    import html
    def extract_plain_text(html_str):
        """Strip HTML tags to get plain text."""
        clean = re.sub(r'<[^>]+>', ' ', html_str)
        return html.unescape(clean).strip()

    vertex_plain = ' '.join(extract_plain_text(v).lower() for v in vertex_values)

    # Check entity names in vertex shapes using word boundaries
    # Entity names must appear in shapes (vertex="1"), NOT just edge labels
    entity_checks = {
        "has_book": r'\bbook\b',
        "has_author": r'\bauthor\b',
        "has_member": r'\bmember\b',
        "has_loan": r'\bloan\b',
    }

    entities_in_shapes = 0
    for key, pattern in entity_checks.items():
        # Primary: check in vertex shape values (including HTML-stripped text)
        if re.search(pattern, vertex_text) or re.search(pattern, vertex_plain):
            result[key] = True
            entities_in_shapes += 1

    result["entities_in_shapes"] = entities_in_shapes
    result["entity_count"] = sum([
        result["has_book"], result["has_author"],
        result["has_member"], result["has_loan"]
    ])

    # Check attributes - these can be in any text (vertex shapes, sub-shapes, HTML content)
    # Use both raw values and HTML-stripped text for matching
    search_text = vertex_plain + ' ' + all_text
    attr_keywords = {
        "has_book_id": [r'\bbook_id\b', r'\bbookid\b', r'\bbook id\b'],
        "has_title": [r'\btitle\b'],
        "has_isbn": [r'\bisbn\b'],
        "has_author_id": [r'\bauthor_id\b', r'\bauthorid\b', r'\bauthor id\b'],
        "has_author_name": [r'\bname\b'],
        "has_member_id": [r'\bmember_id\b', r'\bmemberid\b', r'\bmember id\b'],
        "has_member_name": [r'\bname\b'],
        "has_email": [r'\bemail\b'],
        "has_loan_id": [r'\bloan_id\b', r'\bloanid\b', r'\bloan id\b'],
        "has_loan_date": [r'\bloan_date\b', r'\bloandate\b', r'\bloan date\b', r'\bdate\b'],
    }

    for key, patterns in attr_keywords.items():
        for pat in patterns:
            if re.search(pat, search_text):
                result[key] = True
                break

    # Count total unique attributes found
    attr_keys = ["has_book_id", "has_title", "has_isbn",
                 "has_author_id", "has_member_id", "has_email",
                 "has_loan_id", "has_loan_date"]
    result["total_attributes"] = sum(result.get(k, False) for k in attr_keys)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    if [ -f /tmp/er_analysis.json ]; then
        HAS_BOOK=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_book', False)).lower())" 2>/dev/null || echo "false")
        HAS_AUTHOR=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_author', False)).lower())" 2>/dev/null || echo "false")
        HAS_MEMBER=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_member', False)).lower())" 2>/dev/null || echo "false")
        HAS_LOAN=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_loan', False)).lower())" 2>/dev/null || echo "false")
        TOTAL_ATTRIBUTES=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(d.get('total_attributes', 0))" 2>/dev/null || echo "0")
        HAS_BOOK_ID=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_book_id', False)).lower())" 2>/dev/null || echo "false")
        HAS_TITLE=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_title', False)).lower())" 2>/dev/null || echo "false")
        HAS_ISBN=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_isbn', False)).lower())" 2>/dev/null || echo "false")
        HAS_EMAIL=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_email', False)).lower())" 2>/dev/null || echo "false")
        HAS_LOAN_DATE=$(python3 -c "import json; d=json.load(open('/tmp/er_analysis.json')); print(str(d.get('has_loan_date', False)).lower())" 2>/dev/null || echo "false")
    fi

    echo "Analysis results:"
    echo "  - Shapes: $NUM_SHAPES"
    echo "  - Connections: $NUM_CONNECTIONS (valid: $VALID_CONNECTIONS)"
    echo "  - Entities: book=$HAS_BOOK author=$HAS_AUTHOR member=$HAS_MEMBER loan=$HAS_LOAN"
    echo "  - Total attributes found: $TOTAL_ATTRIBUTES"
else
    echo "ERROR: Diagram file not found: $DIAGRAM_FILE"
fi

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_drawio_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "file_exists": $FILE_EXISTS,
    "file_path": "$DIAGRAM_FILE",
    "file_size": $FILE_SIZE,
    "num_shapes": $NUM_SHAPES,
    "num_connections": $VALID_CONNECTIONS,
    "raw_edge_count": $NUM_CONNECTIONS,
    "has_book": $HAS_BOOK,
    "has_author": $HAS_AUTHOR,
    "has_member": $HAS_MEMBER,
    "has_loan": $HAS_LOAN,
    "has_book_id": $HAS_BOOK_ID,
    "has_title": $HAS_TITLE,
    "has_isbn": $HAS_ISBN,
    "has_email": $HAS_EMAIL,
    "has_loan_date": $HAS_LOAN_DATE,
    "total_attributes": $TOTAL_ATTRIBUTES,
    "initial_file_count": $INITIAL_COUNT,
    "current_file_count": $CURRENT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
