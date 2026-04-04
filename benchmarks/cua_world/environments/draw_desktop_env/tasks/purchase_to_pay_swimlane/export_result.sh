#!/bin/bash
# Do NOT use set -e

echo "=== Exporting purchase_to_pay_swimlane result ==="

DISPLAY=:1 import -window root /tmp/p2p_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/p2p_process.drawio"
PDF_FILE="/home/ga/Desktop/p2p_process.pdf"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_AFTER_START="false"
PDF_EXISTS="false"
PDF_SIZE=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat --format=%s "$PDF_FILE" 2>/dev/null || echo "0")
fi

# Deep XML analysis
python3 << 'PYEOF' > /tmp/p2p_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib, html as html_mod
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/p2p_process.drawio"
result = {
    "num_shapes": 0, "num_edges": 0, "num_pages": 0,
    "has_swimlanes": False, "num_lanes": 0,
    "has_decision_diamond": False, "num_decisions": 0,
    "has_data_objects": False,
    "has_start_end": False,
    "lane_names_found": [],
    "process_keywords": [],
    "has_kpi_page": False,
    "text_content": "",
    "error": None
}

LANE_NAMES = ["requester", "procurement", "accounts payable", "ap", "supplier", "finance", "treasury"]
PROCESS_KEYWORDS = ["purchase requisition", "pr", "purchase order", "po",
                    "goods receipt", "invoice", "payment", "approve", "match",
                    "budget", "vendor", "supplier", "remittance"]
KPI_TERMS = ["kpi", "cycle time", "match rate", "compliance", "on-time", "cost per invoice", "dashboard"]

def decompress_diagram(content):
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

        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)

        all_cells = []
        page_names = [p.get('name', '').lower() for p in pages]

        # Check if any page name suggests KPI
        for pname in page_names:
            if any(k in pname for k in ['kpi', 'dashboard', 'metric', 'summary']):
                result["has_kpi_page"] = True

        for page in pages:
            inline_cells = list(page.iter('mxCell'))
            if inline_cells:
                all_cells.extend(inline_cells)
            else:
                inner_root = decompress_diagram(page.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))

        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        all_text_parts = []
        decision_count = 0
        lane_count = 0

        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            cid = cell.get('id', '')
            if cid in ('0', '1'):
                continue

            if cell.get('vertex') == '1':
                result["num_shapes"] += 1
                if val:
                    all_text_parts.append(val)

                # Detect swim lane
                if 'swimlane' in style:
                    result["has_swimlanes"] = True
                    lane_count += 1
                    val_lower = re.sub(r'<[^>]+>', '', val.lower())
                    for ln in LANE_NAMES:
                        if ln in val_lower:
                            if ln not in result["lane_names_found"]:
                                result["lane_names_found"].append(ln)

                # Detect decision diamond
                if 'rhombus' in style or 'shape=mxgraph' in style and 'diamond' in style:
                    result["has_decision_diamond"] = True
                    decision_count += 1
                # Also check for explicit shape=rhombus
                if 'shape=rhombus' in style or ';rhombus' in style:
                    result["has_decision_diamond"] = True
                    decision_count += 1

                # Detect data objects (folded page)
                if 'foldedpage' in style or 'note' in style or 'document' in style or 'shape=mxgraph.flowchart.document' in style:
                    result["has_data_objects"] = True

                # Detect start/end events
                if 'ellipse' in style or 'terminal' in style or 'event' in style:
                    val_lower = val.lower()
                    if 'start' in val_lower or 'end' in val_lower or 'begin' in val_lower:
                        result["has_start_end"] = True

            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val:
                    all_text_parts.append(val)

        result["num_decisions"] = decision_count
        result["num_lanes"] = lane_count

        combined = ' '.join(all_text_parts).lower()
        plain = re.sub(r'<[^>]+>', ' ', combined)
        plain = html_mod.unescape(plain).lower()
        search_text = combined + ' ' + plain
        result["text_content"] = search_text[:3000]

        # Check process keywords
        for kw in PROCESS_KEYWORDS:
            if kw in search_text:
                result["process_keywords"].append(kw)

        # Check for KPI content in any page text
        for k in KPI_TERMS:
            if k in search_text:
                result["has_kpi_page"] = True
                break

        # Check data objects in text
        doc_terms = ['purchase requisition', 'purchase order', 'goods receipt', 'invoice', 'remittance', 'packing slip']
        if any(t in search_text for t in doc_terms):
            result["has_data_objects"] = True

        # Cross-check lane detection: look for lane names in all text
        for ln in LANE_NAMES:
            if ln in search_text and ln not in result["lane_names_found"]:
                result["lane_names_found"].append(ln)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

if [ -f /tmp/p2p_analysis.json ]; then
    NUM_SHAPES=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(d.get('num_shapes',0))" 2>/dev/null || echo "0")
    NUM_EDGES=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(d.get('num_edges',0))" 2>/dev/null || echo "0")
    NUM_PAGES=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(d.get('num_pages',0))" 2>/dev/null || echo "0")
    NUM_LANES=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(d.get('num_lanes',0))" 2>/dev/null || echo "0")
    HAS_SWIMLANES=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(str(d.get('has_swimlanes',False)).lower())" 2>/dev/null || echo "false")
    HAS_DECISIONS=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(str(d.get('has_decision_diamond',False)).lower())" 2>/dev/null || echo "false")
    NUM_DECISIONS=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(d.get('num_decisions',0))" 2>/dev/null || echo "0")
    HAS_DATA_OBJS=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(str(d.get('has_data_objects',False)).lower())" 2>/dev/null || echo "false")
    HAS_START_END=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(str(d.get('has_start_end',False)).lower())" 2>/dev/null || echo "false")
    HAS_KPI=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(str(d.get('has_kpi_page',False)).lower())" 2>/dev/null || echo "false")
    LANE_NAMES=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(','.join(d.get('lane_names_found',[])))" 2>/dev/null || echo "")
    PROC_KWS=$(python3 -c "import json; d=json.load(open('/tmp/p2p_analysis.json')); print(len(d.get('process_keywords',[])))" 2>/dev/null || echo "0")
fi

NUM_SHAPES=${NUM_SHAPES:-0}; NUM_EDGES=${NUM_EDGES:-0}; NUM_PAGES=${NUM_PAGES:-0}
NUM_LANES=${NUM_LANES:-0}; HAS_SWIMLANES=${HAS_SWIMLANES:-"false"}
HAS_DECISIONS=${HAS_DECISIONS:-"false"}; NUM_DECISIONS=${NUM_DECISIONS:-0}
HAS_DATA_OBJS=${HAS_DATA_OBJS:-"false"}; HAS_START_END=${HAS_START_END:-"false"}
HAS_KPI=${HAS_KPI:-"false"}; PROC_KWS=${PROC_KWS:-0}

echo "Analysis: shapes=$NUM_SHAPES edges=$NUM_EDGES pages=$NUM_PAGES lanes=$NUM_LANES"
echo "swimlanes=$HAS_SWIMLANES decisions=$NUM_DECISIONS data_objs=$HAS_DATA_OBJS kpi=$HAS_KPI"
echo "Lanes: $LANE_NAMES"

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "pdf_exists": $PDF_EXISTS,
    "pdf_size": $PDF_SIZE,
    "num_shapes": $NUM_SHAPES,
    "num_edges": $NUM_EDGES,
    "num_pages": $NUM_PAGES,
    "num_lanes": $NUM_LANES,
    "has_swimlanes": $HAS_SWIMLANES,
    "has_decision_diamond": $HAS_DECISIONS,
    "num_decisions": $NUM_DECISIONS,
    "has_data_objects": $HAS_DATA_OBJS,
    "has_start_end": $HAS_START_END,
    "has_kpi_page": $HAS_KPI,
    "process_keywords_count": $PROC_KWS,
    "lane_names": "$LANE_NAMES",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export complete ==="
