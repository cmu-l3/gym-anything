#!/bin/bash
# Do NOT use set -e

echo "=== Exporting microservices_dependency_audit result ==="

DISPLAY=:1 import -window root /tmp/ms_end.png 2>/dev/null || true

OUTPUT_DRAWIO="/home/ga/Desktop/microservices_architecture.drawio"
OUTPUT_SVG="/home/ga/Desktop/microservices_architecture.svg"
PARTIAL_FILE="/home/ga/Diagrams/microservices_partial.drawio"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_AFTER_START="false"
SVG_EXISTS="false"
SVG_SIZE=0
IS_COPY_OF_PARTIAL="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$OUTPUT_DRAWIO" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$OUTPUT_DRAWIO" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$OUTPUT_DRAWIO" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi

    # Check if output is identical to partial (agent just renamed it)
    if [ -f "$PARTIAL_FILE" ]; then
        PARTIAL_HASH=$(md5sum "$PARTIAL_FILE" | cut -d' ' -f1)
        OUTPUT_HASH=$(md5sum "$OUTPUT_DRAWIO" | cut -d' ' -f1)
        if [ "$PARTIAL_HASH" = "$OUTPUT_HASH" ]; then
            IS_COPY_OF_PARTIAL="true"
            echo "WARNING: Output is identical to partial diagram — not a valid submission"
        fi
    fi
fi

if [ -f "$OUTPUT_SVG" ]; then
    SVG_EXISTS="true"
    SVG_SIZE=$(stat --format=%s "$OUTPUT_SVG" 2>/dev/null || echo "0")
fi

# Deep analysis
python3 << 'PYEOF' > /tmp/ms_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib, html as html_mod
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/microservices_architecture.drawio"
partial_path = "/home/ga/Diagrams/microservices_partial.drawio"

result = {
    "num_shapes": 0, "num_edges": 0, "num_pages": 0,
    "services_found": [],
    "domains_found": [],
    "has_grouping": False,
    "protocol_labels": [],
    "tech_stacks_found": [],
    "has_dependency_matrix": False,
    "errors_fixed": False,
    "wrong_edges_removed": False,
    "text_content": "",
    "error": None
}

ALL_SERVICES = ["api-gateway", "customer-service", "notification-service",
                "payment-service", "fraud-detection-service", "ledger-service",
                "checkout-service", "order-service", "reporting-service"]
# Friendly aliases
SERVICE_ALIASES = {
    "api-gateway": ["api.gateway", "apigateway", "api gateway"],
    "customer-service": ["customer.service", "customerservice", "customer service"],
    "notification-service": ["notification.service", "notificationservice", "notification service", "notification"],
    "payment-service": ["payment.service", "paymentservice", "payment service"],
    "fraud-detection-service": ["fraud", "frauddetection", "fraud detection", "fraud.detection"],
    "ledger-service": ["ledger.service", "ledgerservice", "ledger service", "ledger"],
    "checkout-service": ["checkout.service", "checkoutservice", "checkout service", "checkout"],
    "order-service": ["order.service", "orderservice", "order service"],
    "reporting-service": ["reporting.service", "reportingservice", "reporting service", "reporting"],
}

DOMAIN_TERMS = ["customer domain", "payment domain", "operations domain",
                "customer", "payment", "operations"]

PROTOCOL_TERMS = ["rest", "grpc", "amqp", "http", "https", "rabbitmq", "protobuf"]

TECH_STACKS = ["node.js", "nodejs", "python", "fastapi", "go", "java", "spring",
               "celery", "pandas", "spark", "scikit"]

MATRIX_TERMS = ["dependency matrix", "matrix", "table", "depends"]

WRONG_EDGE_INDICATORS = ["wrong", "incorrect", "error"]

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
        result["error"] = "Output file not found"
    else:
        tree = ET.parse(filepath)
        root = tree.getroot()

        pages = root.findall('.//diagram')
        result["num_pages"] = len(pages)
        page_names = [p.get('name', '').lower() for p in pages]

        for pname in page_names:
            if any(m in pname for m in MATRIX_TERMS):
                result["has_dependency_matrix"] = True

        all_cells = []
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
        edge_labels = []

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
                if 'swimlane' in style or 'group' in style or 'container' in style:
                    result["has_grouping"] = True

            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val:
                    all_text_parts.append(val)
                    edge_labels.append(val.lower())

        combined = ' '.join(all_text_parts).lower()
        plain = re.sub(r'<[^>]+>', ' ', combined)
        plain = html_mod.unescape(plain).lower()
        search_text = combined + ' ' + plain
        result["text_content"] = search_text[:4000]

        # Check services
        for svc in ALL_SERVICES:
            svc_lower = svc.replace('-', ' ').lower()
            if svc_lower in search_text or svc.lower() in search_text:
                result["services_found"].append(svc)
                continue
            # Check aliases
            for alias in SERVICE_ALIASES.get(svc, []):
                if alias in search_text:
                    result["services_found"].append(svc)
                    break

        # Deduplicate services found
        result["services_found"] = list(set(result["services_found"]))

        # Check domains
        for dt in DOMAIN_TERMS:
            if dt in search_text and dt not in result["domains_found"]:
                result["domains_found"].append(dt)

        # Check protocols on edges
        for proto in PROTOCOL_TERMS:
            for label in edge_labels:
                if proto in label:
                    if proto not in result["protocol_labels"]:
                        result["protocol_labels"].append(proto)
                    break

        # Check tech stacks
        for ts in TECH_STACKS:
            if ts in search_text:
                result["tech_stacks_found"].append(ts)

        # Check if wrong edges were removed (look for "wrong" annotation removal)
        # If the "WRONG" labels from partial diagram are absent in output, errors were fixed
        wrong_found = any(w in search_text for w in WRONG_EDGE_INDICATORS)
        result["wrong_edges_removed"] = not wrong_found

        # Check for MATRIX content in text
        for mt in MATRIX_TERMS:
            if mt in search_text:
                result["has_dependency_matrix"] = True
                break

        # Check errors_fixed: correct tech stacks present and wrong connections absent
        has_python_fastapi = "python/fastapi" in search_text or ("python" in search_text and "fastapi" in search_text)
        has_go_grpc = "go/grpc" in search_text or ("go" in search_text and "grpc" in search_text) or "grpc" in search_text
        result["errors_fixed"] = has_python_fastapi and has_go_grpc and result["wrong_edges_removed"]

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

if [ -f /tmp/ms_analysis.json ]; then
    NUM_SHAPES=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(d.get('num_shapes',0))" 2>/dev/null || echo "0")
    NUM_EDGES=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(d.get('num_edges',0))" 2>/dev/null || echo "0")
    NUM_PAGES=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(d.get('num_pages',0))" 2>/dev/null || echo "0")
    SERVICES_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(len(d.get('services_found',[])))" 2>/dev/null || echo "0")
    SERVICES_LIST=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(','.join(d.get('services_found',[])))" 2>/dev/null || echo "")
    DOMAINS_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(len(d.get('domains_found',[])))" 2>/dev/null || echo "0")
    HAS_GROUPS=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(str(d.get('has_grouping',False)).lower())" 2>/dev/null || echo "false")
    PROTOCOLS=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(len(d.get('protocol_labels',[])))" 2>/dev/null || echo "0")
    TECH_STACKS=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(len(d.get('tech_stacks_found',[])))" 2>/dev/null || echo "0")
    ERRORS_FIXED=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(str(d.get('errors_fixed',False)).lower())" 2>/dev/null || echo "false")
    HAS_MATRIX=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(str(d.get('has_dependency_matrix',False)).lower())" 2>/dev/null || echo "false")
    WRONG_REMOVED=$(python3 -c "import json; d=json.load(open('/tmp/ms_analysis.json')); print(str(d.get('wrong_edges_removed',False)).lower())" 2>/dev/null || echo "false")
fi

NUM_SHAPES=${NUM_SHAPES:-0}; NUM_EDGES=${NUM_EDGES:-0}; NUM_PAGES=${NUM_PAGES:-0}
SERVICES_FOUND=${SERVICES_FOUND:-0}; DOMAINS_FOUND=${DOMAINS_FOUND:-0}
HAS_GROUPS=${HAS_GROUPS:-"false"}; PROTOCOLS=${PROTOCOLS:-0}; TECH_STACKS=${TECH_STACKS:-0}
ERRORS_FIXED=${ERRORS_FIXED:-"false"}; HAS_MATRIX=${HAS_MATRIX:-"false"}
WRONG_REMOVED=${WRONG_REMOVED:-"false"}

echo "Analysis: shapes=$NUM_SHAPES edges=$NUM_EDGES pages=$NUM_PAGES services=$SERVICES_FOUND domains=$DOMAINS_FOUND"
echo "groups=$HAS_GROUPS protocols=$PROTOCOLS stacks=$TECH_STACKS errors_fixed=$ERRORS_FIXED matrix=$HAS_MATRIX"
echo "Services: $SERVICES_LIST"

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "is_copy_of_partial": $IS_COPY_OF_PARTIAL,
    "svg_exists": $SVG_EXISTS,
    "svg_size": $SVG_SIZE,
    "num_shapes": $NUM_SHAPES,
    "num_edges": $NUM_EDGES,
    "num_pages": $NUM_PAGES,
    "services_found": $SERVICES_FOUND,
    "domains_found": $DOMAINS_FOUND,
    "has_grouping": $HAS_GROUPS,
    "protocol_labels_count": $PROTOCOLS,
    "tech_stacks_count": $TECH_STACKS,
    "errors_fixed": $ERRORS_FIXED,
    "has_dependency_matrix": $HAS_MATRIX,
    "wrong_edges_removed": $WRONG_REMOVED,
    "services_list": "$SERVICES_LIST",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export complete ==="
