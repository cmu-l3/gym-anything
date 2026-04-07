#!/bin/bash
echo "=== Exporting create_code_template_library task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Fetch current libraries via API (Primary verification method)
# We fetch the libraries to get the ID of "HL7 Processing Utilities"
LIBRARIES_JSON=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/json" \
    "https://localhost:8443/api/codeTemplateLibraries" 2>/dev/null)

# Save raw API output for debugging
echo "$LIBRARIES_JSON" > /tmp/api_libraries.json

# 2. Fetch all code templates via API
TEMPLATES_JSON=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/json" \
    "https://localhost:8443/api/codeTemplates" 2>/dev/null)

echo "$TEMPLATES_JSON" > /tmp/api_templates.json

# 3. Database Fallback / Confirmation
# Get raw counts
FINAL_LIB_COUNT=$(query_postgres "SELECT COUNT(*) FROM code_template_library;" 2>/dev/null || echo "0")
FINAL_TEMPLATE_COUNT=$(query_postgres "SELECT COUNT(*) FROM code_template;" 2>/dev/null || echo "0")

# 4. Construct Result JSON using Python for robust parsing
# We use Python to parse the JSON responses and extract exactly what the verifier needs
# avoiding fragile bash string manipulation
python3 -c "
import json
import sys
import os

try:
    # Load API responses
    try:
        with open('/tmp/api_libraries.json', 'r') as f:
            libs_data = json.load(f)
            # Handle case where API returns list or wrapped object
            if isinstance(libs_data, dict) and 'list' in libs_data:
                libs = libs_data['list']
            else:
                libs = libs_data if isinstance(libs_data, list) else []
    except:
        libs = []

    try:
        with open('/tmp/api_templates.json', 'r') as f:
            tmpl_data = json.load(f)
            if isinstance(tmpl_data, dict) and 'list' in tmpl_data:
                tmpls = tmpl_data['list']
            else:
                tmpls = tmpl_data if isinstance(tmpl_data, list) else []
    except:
        tmpls = []
    
    # Analyze Libraries
    target_lib = None
    for lib in libs:
        if lib.get('name') == 'HL7 Processing Utilities':
            target_lib = lib
            break
            
    # Analyze Templates
    found_templates = {}
    target_names = ['formatHL7Date', 'extractPatientName', 'generateACK']
    
    for t in tmpls:
        t_name = t.get('name')
        if t_name in target_names:
            found_templates[t_name] = {
                'id': t.get('id'),
                'type': t.get('type'),
                'code': t.get('code'),
                'contextSet': t.get('contextSet')
            }

    # Create result object
    result = {
        'task_start': int(os.environ.get('TASK_START', 0)),
        'task_end': int(os.environ.get('TASK_END', 0)),
        'initial_lib_count': int(os.environ.get('INITIAL_LIB_COUNT', 0)),
        'final_lib_count': int(os.environ.get('FINAL_LIB_COUNT', 0)),
        'library_found': target_lib is not None,
        'library_details': target_lib if target_lib else {},
        'templates_found': found_templates
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# Environment variables for the python script above
export TASK_START
export TASK_END
export INITIAL_LIB_COUNT=$(cat /tmp/initial_lib_count.txt 2>/dev/null || echo "0")
export FINAL_LIB_COUNT
export FINAL_TEMPLATE_COUNT

# Re-run python command to ensure variables are picked up (cleaner way)
# (The previous run was just to define the heredoc, now we execute)
# Actually, the python code was inside the heredoc passed to python3 -c, so it ran immediately.
# Let's fix the variable passing mechanism.
python3 -c "
import json
import os

task_start = $TASK_START
task_end = $TASK_END
init_lib = $(cat /tmp/initial_lib_count.txt 2>/dev/null || echo "0")
final_lib = $FINAL_LIB_COUNT

try:
    with open('/tmp/api_libraries.json', 'r') as f:
        raw_libs = json.load(f)
        # NextGen Connect API often returns list wrapped in 'list' key for collections
        libs = raw_libs.get('list', raw_libs) if isinstance(raw_libs, dict) else raw_libs
except:
    libs = []

try:
    with open('/tmp/api_templates.json', 'r') as f:
        raw_tmpls = json.load(f)
        tmpls = raw_tmpls.get('list', raw_tmpls) if isinstance(raw_tmpls, dict) else raw_tmpls
except:
    tmpls = []

target_lib = next((l for l in libs if l.get('name') == 'HL7 Processing Utilities'), None)

found_tmpls = {}
target_names = ['formatHL7Date', 'extractPatientName', 'generateACK']

for t in tmpls:
    name = t.get('name')
    # Check if this template is roughly what we want (case insensitive match for safety)
    if name and any(target.lower() == name.lower() for target in target_names):
        found_tmpls[name] = {
            'type': t.get('type'),
            'code': t.get('code', ''),
            'revision': t.get('revision')
        }

result = {
    'timestamp': '$(date -Iseconds)',
    'library_found': bool(target_lib),
    'library_include_new_channels': target_lib.get('includeNewChannels', False) if target_lib else False,
    'templates': found_tmpls,
    'counts': {
        'lib_initial': int(init_lib),
        'lib_final': int(final_lib)
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="