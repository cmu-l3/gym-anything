#!/bin/bash
# Export script for Tracker Program Stage Config task

echo "=== Exporting Tracker Config Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# We need to extract:
# 1. The created Data Element (to check properties)
# 2. The Child Programme -> Birth Stage (to check assignment and config)

echo "Querying DHIS2 metadata..."

python3 << 'PYEOF' > /tmp/tracker_config_result.json
import json
import sys
import subprocess

def api_get(endpoint):
    cmd = f"curl -s -u admin:district 'http://localhost:8080/api/{endpoint}'"
    try:
        result = subprocess.check_output(cmd, shell=True)
        return json.loads(result)
    except:
        return {}

result = {
    "de_exists": False,
    "de_correct_type": False,
    "program_found": False,
    "stage_found": False,
    "de_in_stage": False,
    "compulsory": False,
    "display_in_reports": False,
    "debug_info": {}
}

try:
    # 1. Check Data Element
    de_resp = api_get("dataElements?filter=name:eq:Chlorhexidine+Gel+Applied&fields=id,name,shortName,valueType,domainType")
    data_elements = de_resp.get("dataElements", [])
    
    if data_elements:
        de = data_elements[0]
        result["de_exists"] = True
        result["de_id"] = de.get("id")
        result["de_value_type"] = de.get("valueType")
        result["de_domain_type"] = de.get("domainType")
        
        # YES_NO is stored as BOOLEAN or TRUE_ONLY in some versions, or explicitly YES_NO
        vt = de.get("valueType", "")
        if vt in ["BOOLEAN", "TRUE_ONLY", "YES_NO"]:
            result["de_correct_type"] = True
            
        target_de_id = de.get("id")

        # 2. Find Child Programme
        # Search for programs containing "Child"
        prog_resp = api_get("programs?filter=name:ilike:Child&fields=id,name,programStages[id,name]")
        programs = prog_resp.get("programs", [])
        
        # Logic to find the main child programme (usually has 'Child Programme' or similar)
        child_prog = None
        for p in programs:
            if "child" in p.get("name", "").lower():
                child_prog = p
                break
        
        if child_prog:
            result["program_found"] = True
            result["program_name"] = child_prog.get("name")
            
            # 3. Find Birth Stage
            birth_stage = None
            for stage in child_prog.get("programStages", []):
                if "birth" in stage.get("name", "").lower():
                    birth_stage = stage
                    break
            
            if birth_stage:
                result["stage_found"] = True
                stage_id = birth_stage.get("id")
                
                # 4. Check Stage Configuration
                # Need to fetch specific stage details to see data elements
                stage_details = api_get(f"programStages/{stage_id}?fields=id,name,programStageDataElements[compulsory,displayInReports,dataElement[id]]")
                
                psdes = stage_details.get("programStageDataElements", [])
                
                for psde in psdes:
                    if psde.get("dataElement", {}).get("id") == target_de_id:
                        result["de_in_stage"] = True
                        result["compulsory"] = psde.get("compulsory", False)
                        result["display_in_reports"] = psde.get("displayInReports", False)
                        break
            else:
                result["debug_info"]["stages_found"] = [s.get("name") for s in child_prog.get("programStages", [])]

    else:
        result["debug_info"]["error"] = "Data element not found"

except Exception as e:
    result["debug_info"]["exception"] = str(e)

print(json.dumps(result, indent=2))
PYEOF

echo "Result generated:"
cat /tmp/tracker_config_result.json

chmod 666 /tmp/tracker_config_result.json 2>/dev/null || true
echo "=== Export Complete ==="