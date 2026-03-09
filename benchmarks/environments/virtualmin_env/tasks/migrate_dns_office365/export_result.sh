#!/bin/bash
echo "=== Exporting migrate_dns_office365 result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOMAIN="acmecorp.test"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract DNS Records to JSON
# We use a python script to parse 'virtualmin get-dns' output into JSON for the verifier
# virtualmin get-dns output format example:
# name type ttl value
# acmecorp.test. IN A 127.0.0.1
echo "Parsing DNS records..."

# Dump raw output first for debugging
virtualmin get-dns --domain "$DOMAIN" > /tmp/raw_dns_output.txt

# Python script to parse and export JSON
python3 -c "
import subprocess
import json
import sys
import re

domain = '$DOMAIN'
records = []

try:
    # Run virtualmin get-dns
    # Using --multiline might be safer if values are long, but default usually works for these records
    cmd = ['virtualmin', 'get-dns', '--domain', domain]
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    # Parse lines. Typical output:
    # name    ttl   IN    type    value
    # acmecorp.test.    38400 IN    A       127.0.0.1
    
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        
        # Heuristic parsing - Virtualmin output can be tricky
        # Usually: Name TTL IN Type Value...
        # But TTL and IN might be swapped or missing in some versions/views
        
        # Let's try to identify the TYPE (A, MX, CNAME, TXT, SRV)
        # It's usually the 4th column (index 3) if standard bind format
        
        # Simple extraction for verifier convenience:
        record = {
            'raw': line,
            'name': parts[0],
            'type': 'UNKNOWN',
            'value': ''
        }
        
        # Find type index
        type_idx = -1
        for i, part in enumerate(parts):
            if part in ['A', 'AAAA', 'MX', 'CNAME', 'TXT', 'SRV', 'NS', 'SOA']:
                type_idx = i
                record['type'] = part
                break
        
        if type_idx != -1 and len(parts) > type_idx + 1:
            # Value is everything after type
            # For MX, priority is first part of value
            val_parts = parts[type_idx+1:]
            record['value'] = ' '.join(val_parts)
            
            # Special handling for SRV to normalize
            if record['type'] == 'SRV':
                # SRV format: priority weight port target
                # capture specific fields
                if len(val_parts) >= 4:
                    record['priority'] = val_parts[0]
                    record['weight'] = val_parts[1]
                    record['port'] = val_parts[2]
                    record['target'] = val_parts[3]

            # Special handling for MX
            if record['type'] == 'MX':
                if len(val_parts) >= 2:
                    record['priority'] = val_parts[0]
                    record['target'] = val_parts[1]
        
        records.append(record)

except Exception as e:
    print(f'Error parsing DNS: {e}', file=sys.stderr)

output = {
    'task_start': $TASK_START,
    'dns_records': records,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json