#!/bin/bash
echo "=== Exporting AWS HA Architecture Results ==="

# Record end time and paths
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DIAGRAM_PATH="/home/ga/Diagrams/startup_aws_arch.drawio"
PDF_PATH="/home/ga/Diagrams/startup_aws_arch.pdf"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Files
FILE_EXISTS="false"
PDF_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DIAGRAM_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DIAGRAM_PATH")
    FILE_MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PDF_PATH" ]; then
    PDF_SIZE=$(stat -c %s "$PDF_PATH")
    # PDF must be non-empty and created/modified after start
    if [ "$PDF_SIZE" -gt 100 ]; then
        PDF_MTIME=$(stat -c %Y "$PDF_PATH")
        if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
            PDF_EXISTS="true"
        fi
    fi
fi

# 2. Parse Diagram Content (Python embedded)
# We need to extract shapes and text to verify the architecture changes.
# draw.io files can be plain XML or compressed (deflate+base64).

echo "Parsing diagram content..."
python3 -c "
import sys
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import json
import re

file_path = '$DIAGRAM_PATH'
output_file = '/tmp/diagram_analysis.json'

result = {
    'total_shapes': 0,
    'total_edges': 0,
    'text_content': [],
    'has_az_b': False,
    'has_alb': False,
    'has_asg': False,
    'has_cloudfront': False,
    'has_nat': False,
    'has_redis': False,
    'has_multiaz_rds': False
}

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # Handle compressed content
    xml_content = ''
    if root.tag == 'mxfile':
        diagrams = root.findall('diagram')
        for d in diagrams:
            if d.text:
                try:
                    # Try decompressing
                    data = base64.b64decode(d.text)
                    xml_content += zlib.decompress(data, -15).decode('utf-8')
                except:
                    # Maybe just urlencoded?
                    try:
                        data = urllib.parse.unquote(d.text)
                        # Check if it looks like XML
                        if '<mxGraphModel' in data:
                            xml_content += data
                    except:
                        pass
    
    # If we couldn't decompress or it wasn't compressed, use raw file
    if not xml_content:
        with open(file_path, 'r') as f:
            xml_content = f.read()

    # Naive XML parsing of the combined content (or original file)
    # We look for value attributes and specific styles
    
    # Count shapes (vertex='1') and edges (edge='1')
    result['total_shapes'] = len(re.findall(r'vertex=\"1\"', xml_content))
    result['total_edges'] = len(re.findall(r'edge=\"1\"', xml_content))
    
    # Extract all text values
    values = re.findall(r'value=\"([^\"]*)\"', xml_content)
    result['text_content'] = [v.lower() for v in values]
    full_text = ' '.join(result['text_content'])
    
    # Check for specific requirements in text or styles
    
    # AZ-B: Look for 'availability zone b', 'az-b', 'az b'
    if any(x in full_text for x in ['availability zone b', 'az-b', 'az b', 'us-east-1b']):
        result['has_az_b'] = True
        
    # ALB: Look for 'application load balancer', 'alb'
    if any(x in full_text for x in ['application load balancer', 'alb', 'load balancer']):
        result['has_alb'] = True
        
    # ASG: Look for 'auto scaling', 'asg', 'autoscaling'
    if any(x in full_text for x in ['auto scaling', 'asg', 'autoscaling']):
        result['has_asg'] = True
        
    # CloudFront
    if any(x in full_text for x in ['cloudfront', 'cdn', 'distribution']):
        result['has_cloudfront'] = True
        
    # NAT
    if 'nat' in full_text:
        result['has_nat'] = True
        
    # Redis/ElastiCache
    if any(x in full_text for x in ['redis', 'elasticache']):
        result['has_redis'] = True
        
    # Multi-AZ RDS
    if 'multi-az' in full_text:
        result['has_multiaz_rds'] = True

except Exception as e:
    result['error'] = str(e)

with open(output_file, 'w') as f:
    json.dump(result, f)
"

# 3. Create Final Result JSON
# Merge shell variables and python analysis
TEMP_JSON=$(mktemp)
ANALYSIS_JSON=$(cat /tmp/diagram_analysis.json || echo "{}")

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pdf_exists": $PDF_EXISTS,
    "analysis": $ANALYSIS_JSON
}
EOF

# Move to safe location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="