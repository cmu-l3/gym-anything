#!/bin/bash
# Do NOT use set -e

echo "=== Exporting oauth2_flow_sequence result ==="

DISPLAY=:1 import -window root /tmp/oauth2_end.png 2>/dev/null || true

DRAWIO_FILE="/home/ga/Desktop/oauth2_sequence.drawio"
PNG_FILE="/home/ga/Desktop/oauth2_sequence.png"

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

python3 << 'PYEOF' > /tmp/oauth2_analysis.json 2>/dev/null || true
import json, re, os, base64, zlib, html as html_mod
import xml.etree.ElementTree as ET

filepath = "/home/ga/Desktop/oauth2_sequence.drawio"
result = {
    "num_shapes": 0, "num_edges": 0, "num_pages": 0,
    "has_sequence_lifelines": False, "num_lifelines": 0,
    "has_fragments": False,
    "participants_found": [],
    "oauth_keywords": [],
    "has_threat_page": False,
    "has_activation_boxes": False,
    "text_content": "",
    "error": None
}

PARTICIPANT_TERMS = {
    "user": [r'\buser\b', r'end.?user', r'actor'],
    "browser": [r'\bbrowser\b', r'\bspa\b', r'client.?app', r'javascript'],
    "authorization_server": [r'auth.?server', r'authorization.?server', r'oauth', r'okta', r'auth0'],
    "token": [r'token.?endpoint', r'\btoken\b'],
    "resource": [r'resource.?server', r'fhir', r'api.?server', r'protected'],
    "jwks": [r'\bjwks\b', r'public.?key', r'json.?web.?key'],
    "session": [r'session.?store', r'\bredis\b', r'localstorage', r'session'],
}

OAUTH_KEYWORDS = ["access_token", "refresh_token", "authorization_code", "code_verifier",
                  "code_challenge", "pkce", "bearer", "jwt", "openid", "scope",
                  "grant_type", "redirect_uri", "client_id", "state"]

THREAT_TERMS = ["threat", "csrf", "injection", "interception", "leakage",
                "stolen", "attack", "mitigation", "risk"]

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
        page_names = [p.get('name', '').lower() for p in pages]

        for pname in page_names:
            if any(t in pname for t in THREAT_TERMS + ['threat', 'security', 'model']):
                result["has_threat_page"] = True

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
        lifeline_count = 0

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

                # Detect sequence diagram lifelines
                if 'lifeline' in style or 'uml.lifeline' in style or 'participant' in style:
                    result["has_sequence_lifelines"] = True
                    lifeline_count += 1
                # Detect activation boxes
                if 'activation' in style or ('fillcolor' in style and 'white' not in style and cell.get('vertex') == '1'):
                    if val == '' or val is None:  # Activation boxes often have no label
                        result["has_activation_boxes"] = True
                # Detect alt/opt/loop fragments
                if 'combine' in style or 'swimlane' in style:
                    val_lower = val.lower() if val else ''
                    if any(frag in val_lower for frag in ['alt', 'opt', 'loop', 'ref', 'par']):
                        result["has_fragments"] = True

            elif cell.get('edge') == '1':
                result["num_edges"] += 1
                if val:
                    all_text_parts.append(val)
                # Check for dashed arrows (return messages)
                if 'dashed=1' in style or 'dash' in style:
                    pass  # return messages present

        result["num_lifelines"] = lifeline_count

        combined = ' '.join(all_text_parts).lower()
        plain = re.sub(r'<[^>]+>', ' ', combined)
        plain = html_mod.unescape(plain).lower()
        search_text = combined + ' ' + plain
        result["text_content"] = search_text[:4000]

        # Check participants
        for p, patterns in PARTICIPANT_TERMS.items():
            for pat in patterns:
                if re.search(pat, search_text, re.IGNORECASE):
                    result["participants_found"].append(p)
                    break

        # Check OAuth keywords
        for kw in OAUTH_KEYWORDS:
            if kw in search_text:
                result["oauth_keywords"].append(kw)

        # Check threat content
        if any(t in search_text for t in THREAT_TERMS):
            result["has_threat_page"] = True

        # Lifelines: also look for box shapes labeled with participant names
        if lifeline_count == 0 and result["num_shapes"] >= 5:
            for p in PARTICIPANT_TERMS:
                if p in result["participants_found"]:
                    lifeline_count += 1
            result["num_lifelines"] = lifeline_count
            if lifeline_count >= 3:
                result["has_sequence_lifelines"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

if [ -f /tmp/oauth2_analysis.json ]; then
    NUM_SHAPES=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(d.get('num_shapes',0))" 2>/dev/null || echo "0")
    NUM_EDGES=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(d.get('num_edges',0))" 2>/dev/null || echo "0")
    NUM_PAGES=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(d.get('num_pages',0))" 2>/dev/null || echo "0")
    NUM_LIFELINES=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(d.get('num_lifelines',0))" 2>/dev/null || echo "0")
    HAS_LIFELINES=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(str(d.get('has_sequence_lifelines',False)).lower())" 2>/dev/null || echo "false")
    HAS_FRAGMENTS=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(str(d.get('has_fragments',False)).lower())" 2>/dev/null || echo "false")
    PARTICIPANTS=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(len(d.get('participants_found',[])))" 2>/dev/null || echo "0")
    OAUTH_KWS=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(len(d.get('oauth_keywords',[])))" 2>/dev/null || echo "0")
    HAS_THREAT=$(python3 -c "import json; d=json.load(open('/tmp/oauth2_analysis.json')); print(str(d.get('has_threat_page',False)).lower())" 2>/dev/null || echo "false")
fi

NUM_SHAPES=${NUM_SHAPES:-0}; NUM_EDGES=${NUM_EDGES:-0}; NUM_PAGES=${NUM_PAGES:-0}
NUM_LIFELINES=${NUM_LIFELINES:-0}; HAS_LIFELINES=${HAS_LIFELINES:-"false"}
HAS_FRAGMENTS=${HAS_FRAGMENTS:-"false"}; PARTICIPANTS=${PARTICIPANTS:-0}
OAUTH_KWS=${OAUTH_KWS:-0}; HAS_THREAT=${HAS_THREAT:-"false"}

echo "Analysis: shapes=$NUM_SHAPES edges=$NUM_EDGES pages=$NUM_PAGES lifelines=$NUM_LIFELINES"
echo "lifelines_present=$HAS_LIFELINES fragments=$HAS_FRAGMENTS participants=$PARTICIPANTS oauth_kws=$OAUTH_KWS"

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
    "num_lifelines": $NUM_LIFELINES,
    "has_sequence_lifelines": $HAS_LIFELINES,
    "has_fragments": $HAS_FRAGMENTS,
    "participants_found": $PARTICIPANTS,
    "oauth_keywords_count": $OAUTH_KWS,
    "has_threat_page": $HAS_THREAT,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result: $(cat /tmp/task_result.json)"
echo "=== Export complete ==="
