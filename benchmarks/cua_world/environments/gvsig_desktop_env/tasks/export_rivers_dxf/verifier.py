#!/usr/bin/env python3
"""
Verifier for export_rivers_dxf task.

Checks:
1. Output file exists and was created during task.
2. Output file is a valid DXF (header checks).
3. Output file has non-trivial content (size & entities) indicating spatial selection was likely performed.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_rivers_dxf(traj, env_info, task_info):
    """
    Verify the agent exported the selected rivers to DXF.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/gvsig_data/exports/brazil_rivers.dxf')
    min_size = metadata.get('min_size_bytes', 10000)
    expected_strings = metadata.get('expected_strings', ["SECTION", "ENTITIES"])

    # Load result JSON
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    score = 0
    feedback = []
    
    # 1. Check existence and creation time (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Output file created during task.")
    elif result.get('output_exists'):
        score += 5
        feedback.append("Output file exists but timestamp is old (reused?).")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Check basic validity from shell script check (20 pts)
    if result.get('is_valid_dxf'):
        score += 20
        feedback.append("File has valid DXF structure.")
    else:
        feedback.append("File does not appear to be a valid DXF.")

    # 3. Deep content inspection (60 pts)
    # We copy the actual DXF file out to inspect it
    dxf_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    try:
        copy_from_env(expected_path, dxf_temp.name)
        
        with open(dxf_temp.name, 'r', errors='ignore') as f:
            content = f.read()
            
        # Check size again here to be safe
        size_bytes = len(content)
        
        # Check for specific entities (lines/polylines)
        # Brazil rivers should result in many entities
        entity_count = content.count("AcDbLine") + content.count("AcDbPolyline") + content.count("lwpolyline")
        
        if size_bytes > min_size:
            score += 20
            feedback.append(f"File size ({size_bytes} bytes) is reasonable.")
        else:
            feedback.append(f"File size ({size_bytes} bytes) is too small - likely empty.")

        # Check entity count
        # An empty export might have headers but 0 entities
        if entity_count > 50:
            score += 40
            feedback.append(f"Found {entity_count} vector entities (Rivers).")
        elif entity_count > 0:
            score += 20
            feedback.append(f"Found {entity_count} vector entities (Low count - partial selection?).")
        else:
            feedback.append("No vector entities found in DXF.")

    except Exception as e:
        feedback.append(f"Could not inspect DXF content: {e}")
    finally:
        if os.path.exists(dxf_temp.name):
            os.unlink(dxf_temp.name)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }