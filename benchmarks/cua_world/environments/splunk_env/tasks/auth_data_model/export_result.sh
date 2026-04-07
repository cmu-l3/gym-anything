#!/bin/bash
echo "=== Exporting auth_data_model result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch all datamodels
echo "Fetching datamodels..."
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/datamodel/model?output_mode=json&count=0" \
    > /tmp/all_datamodels.json 2>/dev/null

# Parse results using Python
python3 << 'PYEOF'
import json

result = {
    "model_found": False,
    "model_name_actual": "",
    "acceleration_enabled": False,
    "objects_count": 0,
    "child_objects_count": 0,
    "fields_count": 0,
    "root_search": "",
    "is_newly_created": True,
    "parse_error": None
}

try:
    # Check if it existed initially (anti-gaming)
    try:
        with open('/tmp/initial_datamodels.json', 'r') as f:
            init_data = json.load(f)
            for e in init_data.get('entry', []):
                if e.get('name', '').lower() == 'authentication_events':
                    result["is_newly_created"] = False
                    break
    except Exception as e:
        pass

    with open('/tmp/all_datamodels.json', 'r') as f:
        data = json.load(f)
    
    entries = data.get('entry', [])
    for entry in entries:
        name = entry.get('name', '')
        if name.lower() == 'authentication_events':
            result["model_found"] = True
            result["model_name_actual"] = name
            content = entry.get('content', {})
            
            # Check acceleration flag
            accel = content.get('acceleration', 0)
            result["acceleration_enabled"] = str(accel).lower() in ['1', 'true']
            
            # Parse description string for schema layout
            desc_str = content.get('description', '{}')
            try:
                schema = json.loads(desc_str)
                objects = schema.get('objects', [])
                result["objects_count"] = len(objects)
                
                child_count = 0
                field_count = 0
                root_search = ""
                
                for obj in objects:
                    # Child objects have a parentName defined
                    if obj.get('parentName'):
                        child_count += 1
                    else:
                        # Root object constraints
                        constraints = obj.get('constraints', [])
                        if constraints:
                            root_search += " ".join([c.get('search', '') for c in constraints])
                            
                    fields = obj.get('fields', [])
                    field_count += len(fields)
                    
                result["child_objects_count"] = child_count
                result["fields_count"] = field_count
                result["root_search"] = root_search
                
            except Exception as e:
                result["parse_error"] = str(e)
            
            break

    # Save payload to json file
    with open('/tmp/auth_data_model_result.json', 'w') as f:
        json.dump(result, f)
except Exception as e:
    with open('/tmp/auth_data_model_result.json', 'w') as f:
        json.dump({"error": str(e)}, f)
PYEOF

chmod 666 /tmp/auth_data_model_result.json
cat /tmp/auth_data_model_result.json
echo -e "\n=== Export complete ==="