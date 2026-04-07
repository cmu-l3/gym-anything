#!/bin/bash
echo "=== Exporting create_filtered_dashboard result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to reliably extract info and construct JSON without bash escaping issues
python3 -c "
import os
import json
import re
import urllib.request

TIDDLER_DIR = '/home/ga/mywiki/tiddlers'

def get_dashboard_file():
    if not os.path.exists(TIDDLER_DIR): return None
    for root, dirs, files in os.walk(TIDDLER_DIR):
        for file in files:
            if not file.endswith('.tid'): continue
            path = os.path.join(root, file)
            try:
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if re.search(r'^title:\s*Project Dashboard\s*$', content, re.MULTILINE):
                        return path
            except:
                pass
    return None

dashboard_path = get_dashboard_file()

try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = float(f.read().strip())
except Exception:
    start_time = 0

result = {
    'exists': False,
    'mtime': 0,
    'start_time': start_time,
    'body': '',
    'tags': '',
    'api_status': 404,
    'hardcoded_titles': 0
}

if dashboard_path:
    result['exists'] = True
    result['mtime'] = os.path.getmtime(dashboard_path)
    with open(dashboard_path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()
        
    parts = content.split('\n\n', 1)
    head = parts[0]
    body = parts[1] if len(parts) > 1 else ''
    
    result['body'] = body
    
    tag_match = re.search(r'^tags:\s*(.*)$', head, re.MULTILINE)
    if tag_match:
        result['tags'] = tag_match.group(1)
        
    # Check for hardcoded task titles (gaming detection)
    titles = [
        'Implement rate limiting middleware', 'Add OAuth2 authentication flow', 
        'Fix CORS configuration for staging', 'Set up API versioning strategy', 
        'Write integration tests for users endpoint', 'Migrate to React Navigation v6', 
        'Implement push notification handler', 'Fix memory leak in image carousel', 
        'Add biometric authentication support', 'Optimize bundle size for production', 
        'Configure Apache Airflow DAG for ETL', 'Add data quality checks for customer table', 
        'Migrate from Redshift to BigQuery', 'Implement incremental load for orders', 
        'Set up monitoring dashboards in Grafana'
    ]
    for t in titles:
        if t in body:
            result['hardcoded_titles'] += 1

try:
    resp = urllib.request.urlopen('http://localhost:8080/recipes/default/tiddlers/Project%20Dashboard')
    result['api_status'] = resp.getcode()
except Exception:
    pass

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

cat /tmp/task_result.json
echo "=== Export complete ==="