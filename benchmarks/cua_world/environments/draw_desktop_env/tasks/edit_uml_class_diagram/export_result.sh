#!/bin/bash
# Do NOT use set -e: grep -c returns exit 1 on 0 matches, causing premature exit

echo "=== Exporting edit_uml_class_diagram task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/uml_task_end.png 2>/dev/null || true

DIAGRAM_FILE="/home/ga/Diagrams/ecommerce_uml_classes.drawio"
FOUND="false"
FILE_EXISTS="false"
FILE_SIZE=0
NUM_SHAPES=0
NUM_EDGES=0
HAS_PAYMENT_CLASS="false"
HAS_PAYMENT_ID="false"
HAS_AMOUNT="false"
HAS_PAYMENT_DATE="false"
HAS_METHOD_ATTR="false"
HAS_PROCESS_PAYMENT="false"
HAS_REFUND="false"
NEW_CONNECTIONS=0
FILE_MODIFIED="false"

# Check file exists
if [ -f "$DIAGRAM_FILE" ]; then
    FILE_EXISTS="true"
    FOUND="true"
    FILE_SIZE=$(stat --format=%s "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    echo "Found diagram: $DIAGRAM_FILE ($FILE_SIZE bytes)"

    # Check if file was modified (compare size, mtime, or md5)
    INITIAL_SIZE=$(cat /tmp/initial_file_size 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat /tmp/initial_file_mtime 2>/dev/null || echo "0")
    INITIAL_MD5=$(cat /tmp/initial_file_md5 2>/dev/null || echo "")
    CURRENT_MTIME=$(stat --format=%Y "$DIAGRAM_FILE" 2>/dev/null || echo "0")
    CURRENT_MD5=$(md5sum "$DIAGRAM_FILE" 2>/dev/null | awk '{print $1}' || echo "")
    if [ "$FILE_SIZE" -ne "$INITIAL_SIZE" ] 2>/dev/null || \
       [ "$CURRENT_MTIME" -ne "$INITIAL_MTIME" ] 2>/dev/null || \
       { [ -n "$CURRENT_MD5" ] && [ "$CURRENT_MD5" != "$INITIAL_MD5" ]; }; then
        FILE_MODIFIED="true"
    fi

    # Count shapes and edges
    NUM_SHAPES=$(grep -c 'vertex="1"' "$DIAGRAM_FILE" 2>/dev/null || true)
    NUM_SHAPES=${NUM_SHAPES:-0}
    NUM_EDGES=$(grep -c 'edge="1"' "$DIAGRAM_FILE" 2>/dev/null || true)
    NUM_EDGES=${NUM_EDGES:-0}

    # Calculate new elements added
    INITIAL_SHAPES=$(cat /tmp/initial_shape_count 2>/dev/null || echo "0")
    INITIAL_EDGES=$(cat /tmp/initial_edge_count 2>/dev/null || echo "0")
    NEW_SHAPES=$((NUM_SHAPES - INITIAL_SHAPES))
    NEW_CONNECTIONS=$((NUM_EDGES - INITIAL_EDGES))

    # Use Python for robust XML parsing of the diagram content
    python3 << 'PYEOF' > /tmp/uml_analysis.json 2>/dev/null || true
import json
import sys

diagram_file = "/home/ga/Diagrams/ecommerce_uml_classes.drawio"
result = {
    "has_payment_class": False,
    "has_payment_id": False,
    "has_amount": False,
    "has_payment_date": False,
    "has_method_attr": False,
    "has_process_payment": False,
    "has_refund": False,
    "payment_related_text": []
}

try:
    with open(diagram_file, 'r') as f:
        content = f.read().lower()

    # Check for Payment class name in value attributes
    import re
    # Find all value="..." occurrences
    values = re.findall(r'value="([^"]*)"', content)
    all_text = ' '.join(values)

    # Check for Payment class
    for v in values:
        v_lower = v.lower().strip()
        if 'payment' == v_lower or v_lower.startswith('payment'):
            result["has_payment_class"] = True
            result["payment_related_text"].append(v)

    # To avoid false positives from existing classes (e.g., "totalAmount" in Order),
    # we need to check attributes specifically within Payment-related value blocks.
    # Strategy: find all value="" blocks, identify which ones belong to a Payment class context,
    # and check attributes within those blocks.

    payment_context_text = ""
    found_payment_header = False
    for i, v in enumerate(values):
        v_lower = v.lower().strip()
        # A value that is just "payment" or "Payment" is the class header
        if v_lower in ('payment', 'payment class'):
            found_payment_header = True
        # Also check for payment appearing as a class name within other patterns
        if re.match(r'^payment$', v_lower):
            found_payment_header = True

    if found_payment_header:
        result["has_payment_class"] = True

    # Check all values for Payment-specific content
    # If we found a Payment class header, attributes in nearby value="" blocks are likely its children
    for v in values:
        v_lower = v.lower()
        # Check for Payment-specific attribute names (avoid matching totalAmount in Order)
        # Look for standalone "amount" (not "totalAmount")
        if re.search(r'(?<![a-z])amount\b', v_lower) and 'totalamount' not in v_lower:
            result["has_amount"] = True
        if 'paymentid' in v_lower or 'payment_id' in v_lower:
            result["has_payment_id"] = True
        if 'paymentdate' in v_lower or 'payment_date' in v_lower:
            result["has_payment_date"] = True
        # Check for "method" as an attribute (with type annotation), not a UML method
        if re.search(r'method\s*[:\-]', v_lower) or re.search(r'[-+]\s*method\s*:', v_lower):
            result["has_method_attr"] = True
        # Also accept "method" followed by String/string
        if 'method' in v_lower and 'string' in v_lower:
            result["has_method_attr"] = True

    # Check for methods (these are specific enough to not have false positives)
    if 'processpayment' in all_text or 'process_payment' in all_text:
        result["has_process_payment"] = True
    # For refund, check it appears as a method signature, not just the word
    for v in values:
        v_lower = v.lower()
        if 'refund' in v_lower and ('(' in v_lower or '+' in v_lower or '-' in v_lower):
            result["has_refund"] = True
    # Fallback: also check if refund appears anywhere in a method context
    if not result["has_refund"] and re.search(r'refund\s*\(', all_text):
        result["has_refund"] = True

    # If we found payment-specific attributes but not the class header,
    # the agent likely added a Payment entity with a different naming
    if not result["has_payment_class"]:
        if 'payment' in all_text:
            result["has_payment_class"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Parse Python analysis results
    if [ -f /tmp/uml_analysis.json ]; then
        HAS_PAYMENT_CLASS=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_payment_class', False)).lower())" 2>/dev/null || echo "false")
        HAS_PAYMENT_ID=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_payment_id', False)).lower())" 2>/dev/null || echo "false")
        HAS_AMOUNT=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_amount', False)).lower())" 2>/dev/null || echo "false")
        HAS_PAYMENT_DATE=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_payment_date', False)).lower())" 2>/dev/null || echo "false")
        HAS_METHOD_ATTR=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_method_attr', False)).lower())" 2>/dev/null || echo "false")
        HAS_PROCESS_PAYMENT=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_process_payment', False)).lower())" 2>/dev/null || echo "false")
        HAS_REFUND=$(python3 -c "import json; d=json.load(open('/tmp/uml_analysis.json')); print(str(d.get('has_refund', False)).lower())" 2>/dev/null || echo "false")
    fi

    echo "Analysis results:"
    echo "  - Total shapes: $NUM_SHAPES (new: $NEW_SHAPES)"
    echo "  - Total edges: $NUM_EDGES (new: $NEW_CONNECTIONS)"
    echo "  - Payment class: $HAS_PAYMENT_CLASS"
    echo "  - Attributes: paymentId=$HAS_PAYMENT_ID amount=$HAS_AMOUNT date=$HAS_PAYMENT_DATE method=$HAS_METHOD_ATTR"
    echo "  - Methods: processPayment=$HAS_PROCESS_PAYMENT refund=$HAS_REFUND"
else
    echo "ERROR: Diagram file not found: $DIAGRAM_FILE"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "found": $FOUND,
    "file_exists": $FILE_EXISTS,
    "file_path": "$DIAGRAM_FILE",
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "num_shapes": $NUM_SHAPES,
    "num_edges": $NUM_EDGES,
    "new_connections": $NEW_CONNECTIONS,
    "has_payment_class": $HAS_PAYMENT_CLASS,
    "has_payment_id": $HAS_PAYMENT_ID,
    "has_amount": $HAS_AMOUNT,
    "has_payment_date": $HAS_PAYMENT_DATE,
    "has_method_attr": $HAS_METHOD_ATTR,
    "has_process_payment": $HAS_PROCESS_PAYMENT,
    "has_refund": $HAS_REFUND,
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
