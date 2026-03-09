#!/bin/bash
# Do NOT use set -e

echo "=== Exporting aws_saas_architecture result ==="

DISPLAY=:1 import -window root /tmp/aws_arch_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/aws_architecture.drawio"
PNG_FILE="/home/ga/Desktop/aws_architecture.png"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED_AFTER_START="false"
PNG_EXISTS="false"
PNG_SIZE=0
PNG_VALID="false"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$((FILE_MTIME))" -gt "$((TASK_START))" ]; then
        FILE_MODIFIED_AFTER_START="true"
    fi
fi

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat --format=%s "$PNG_FILE" 2>/dev/null || echo "0")
    if file "$PNG_FILE" 2>/dev/null | grep -qi "png"; then
        PNG_VALID="true"
    fi
fi

# Deep analysis
python3 << 'PYEOF' > /tmp/aws_arch_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/aws_architecture.drawio"
result = {
    "num_shapes": 0, "num_edges": 0, "num_pages": 0,
    "has_security_zones": False,
    "aws_components": [],
    "text_content": "",
    "error": None
}

AWS_COMPONENTS = {
    "vpc": [r'\bvpc\b', r'virtual private cloud'],
    "subnet": [r'\bsubnet\b', r'10\.0\.\d+\.'],
    "ec2": [r'\bec2\b', r't3\.', r'instance'],
    "rds": [r'\brds\b', r'postgres', r'aurora', r'database'],
    "elasticache": [r'elasticache', r'\bredis\b', r'cache'],
    "s3": [r'\bs3\b', r'bucket', r'storage'],
    "alb": [r'\balb\b', r'load.?balancer', r'application load'],
    "cloudfront": [r'cloudfront', r'cdn', r'distribution'],
    "route53": [r'route.?53', r'dns', r'hosted.?zone'],
    "igw": [r'\bigw\b', r'internet.?gateway'],
    "nat": [r'\bnat\b', r'nat.?gateway'],
    "asg": [r'auto.?scal', r'\basg\b'],
    "waf": [r'\bwaf\b', r'web.?application.?firewall'],
    "acm": [r'\bacm\b', r'certificate'],
}

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
                # Check for security zone indicators (dashed style)
                if 'dashed=1' in style or 'dashed' in style.split(';')[0] or 'container' in style:
                    result["has_security_zones"] = True
            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val:
                    all_text_parts.append(val)
                    # Also check tooltip/style for AWS shapes
                if 'aws' in style or 'amazon' in style.lower():
                    all_text_parts.append(style)

        import html as html_mod
        combined = ' '.join(all_text_parts).lower()
        plain = re.sub(r'<[^>]+>', ' ', combined)
        plain = html_mod.unescape(plain).lower()
        search_text = combined + ' ' + plain
        result["text_content"] = search_text[:3000]

        found = []
        for comp, patterns in AWS_COMPONENTS.items():
            for pat in patterns:
                if re.search(pat, search_text, re.IGNORECASE):
                    found.append(comp)
                    break
        result["aws_components"] = found

        # Check styles for dashed containers (security groups)
        for cell in all_cells:
            style = (cell.get('style') or '').lower()
            if ('dashed=1' in style or 'strokedasharray' in style) and cell.get('vertex') == '1':
                result["has_security_zones"] = True
                break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

if [ -f /tmp/aws_arch_analysis.json ]; then
    NUM_SHAPES=$(python3 -c "import json; d=json.load(open('/tmp/aws_arch_analysis.json')); print(d.get('num_shapes',0))" 2>/dev/null || echo "0")
    NUM_EDGES=$(python3 -c "import json; d=json.load(open('/tmp/aws_arch_analysis.json')); print(d.get('num_edges',0))" 2>/dev/null || echo "0")
    NUM_PAGES=$(python3 -c "import json; d=json.load(open('/tmp/aws_arch_analysis.json')); print(d.get('num_pages',0))" 2>/dev/null || echo "0")
    AWS_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/aws_arch_analysis.json')); print(len(d.get('aws_components',[])))" 2>/dev/null || echo "0")
    AWS_LIST=$(python3 -c "import json; d=json.load(open('/tmp/aws_arch_analysis.json')); print(','.join(d.get('aws_components',[])))" 2>/dev/null || echo "")
    HAS_ZONES=$(python3 -c "import json; d=json.load(open('/tmp/aws_arch_analysis.json')); print(str(d.get('has_security_zones',False)).lower())" 2>/dev/null || echo "false")
fi

NUM_SHAPES=${NUM_SHAPES:-0}
NUM_EDGES=${NUM_EDGES:-0}
NUM_PAGES=${NUM_PAGES:-0}
AWS_COUNT=${AWS_COUNT:-0}
HAS_ZONES=${HAS_ZONES:-"false"}

echo "Analysis: shapes=$NUM_SHAPES edges=$NUM_EDGES pages=$NUM_PAGES aws_components=$AWS_COUNT zones=$HAS_ZONES"
echo "AWS: $AWS_LIST"

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified_after_start": $FILE_MODIFIED_AFTER_START,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_valid": $PNG_VALID,
    "num_shapes": $NUM_SHAPES,
    "num_edges": $NUM_EDGES,
    "num_pages": $NUM_PAGES,
    "aws_components_found": $AWS_COUNT,
    "has_security_zones": $HAS_ZONES,
    "aws_list": "$AWS_LIST",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export complete ==="
