#!/bin/bash
# Do NOT use set -e

echo "=== Exporting logic_circuit_adder result ==="

# Capture final screenshot
DISPLAY=:1 import -window root /tmp/adder_task_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/ripple_carry_adder.drawio"
PNG_FILE="/home/ga/Desktop/ripple_carry_adder.png"

# Basic File Checks
FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_AFTER_START="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
    echo "Found .drawio file: $DRAWIO_FILE ($FILE_SIZE bytes)"
fi

PNG_EXISTS="false"
PNG_SIZE=0
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    echo "Found .png file: $PNG_FILE ($PNG_SIZE bytes)"
fi

# Python Script for XML Parsing (Decompression + Analysis)
python3 << 'PYEOF' > /tmp/adder_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/ripple_carry_adder.drawio"
result = {
    "num_pages": 0,
    "num_edges": 0,
    "blocks_found": [],
    "signals_found": [],
    "gates_found": [],
    "has_equations": False,
    "text_content": "",
    "error": None
}

REQUIRED_BLOCKS = ["fa0", "fa1", "fa2", "fa3"]
REQUIRED_SIGNALS = [
    "a0", "a1", "a2", "a3", 
    "b0", "b1", "b2", "b3", 
    "s0", "s1", "s2", "s3", 
    "cout", "c4"
]
GATE_KEYWORDS = ["xor", "and", "or"]

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
        for page in pages:
            # Try inline
            inline_cells = list(page.iter('mxCell'))
            if inline_cells:
                all_cells.extend(inline_cells)
            else:
                # Try compressed
                inner_root = decompress_diagram(page.text or '')
                if inner_root is not None:
                    all_cells.extend(list(inner_root.iter('mxCell')))
        
        # Also check root for uncompressed files
        for cell in root.iter('mxCell'):
            if cell not in all_cells:
                all_cells.append(cell)

        all_text_parts = []
        for cell in all_cells:
            val = (cell.get('value') or '').strip()
            style = (cell.get('style') or '').lower()
            
            # Edges
            if cell.get('edge') == '1':
                result["num_edges"] += 1
            
            # Collect text
            if val:
                all_text_parts.append(val)
            
            # Check styles for electrical gates
            if 'electrical' in style or 'gate' in style:
                all_text_parts.append(style)

        # Normalize text for searching
        import html as html_mod
        combined = ' '.join(all_text_parts).lower()
        # Strip HTML tags
        plain = re.sub(r'<[^>]+>', ' ', combined)
        plain = html_mod.unescape(plain).lower()
        
        result["text_content"] = plain[:5000] # Cap for debug

        # Check Blocks
        found_blocks = set()
        for b in REQUIRED_BLOCKS:
            if re.search(r'\b' + b + r'\b', plain):
                found_blocks.add(b)
        result["blocks_found"] = list(found_blocks)

        # Check Signals
        found_signals = set()
        for s in REQUIRED_SIGNALS:
            if re.search(r'\b' + s + r'\b', plain):
                found_signals.add(s)
        result["signals_found"] = list(found_signals)

        # Check Gates (keywords in text or style)
        found_gates = set()
        for g in GATE_KEYWORDS:
            if g in plain:
                found_gates.add(g)
        result["gates_found"] = list(found_gates)

        # Check Equations (look for logic symbols or equation text)
        if "sum" in plain and "xor" in plain:
            result["has_equations"] = True
        if "cout" in plain and ("and" in plain or "or" in plain):
            result["has_equations"] = True
        if "⊕" in plain or "·" in plain:
            result["has_equations"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Assemble final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "analysis": $(cat /tmp/adder_analysis.json 2>/dev/null || echo "{}")
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json