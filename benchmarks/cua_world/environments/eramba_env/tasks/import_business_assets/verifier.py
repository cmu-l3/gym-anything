#!/usr/bin/env python3
"""
Verifier for import_business_assets task.

SCORING CRITERIA:
1. Assets Created (10 pts per asset, max 50): Checks if the 5 specific assets exist in DB.
2. Import Initiation (20 pts): Awarded if at least 1 asset is found (implies import tool was used).
3. Data Mapping (30 pts): Checks if 'Description' field was mapped correctly from CSV 'Function' column.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_business_assets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Specific Assets (10 pts each, max 50)
    found_assets = result.get('found_assets', [])
    target_assets = task_info.get('metadata', {}).get('expected_assets', [])
    
    found_count = len(found_assets)
    asset_score = found_count * 10
    score += asset_score
    
    if found_count == len(target_assets):
        feedback_parts.append(f"All {found_count} assets imported successfully (+50)")
    else:
        feedback_parts.append(f"Imported {found_count}/{len(target_assets)} assets (+{asset_score})")
        missing = [a for a in target_assets if a not in found_assets]
        if missing:
            feedback_parts.append(f"Missing: {', '.join(missing[:3])}...")

    # 2. Import Initiation / Usage (20 pts)
    # If they managed to import at least one valid asset from the CSV, 
    # they clearly found the import tool and started the process.
    if found_count > 0:
        score += 20
        feedback_parts.append("Import process initiated successfully (+20)")
    else:
        feedback_parts.append("No valid assets found (Import failed or not attempted)")

    # 3. Data Integrity / Mapping (30 pts)
    # Checks if 'Function' column mapped to 'Description'
    data_integrity = result.get('data_integrity_check', False)
    if data_integrity:
        score += 30
        feedback_parts.append("Column mapping correct (Description matches) (+30)")
    elif found_count > 0:
        feedback_parts.append("Column mapping incorrect - Description field empty or wrong (+0)")
        # Debug info
        retrieved = result.get('retrieved_description', '')
        if retrieved:
            feedback_parts.append(f"Got description: '{retrieved}'")

    # Anti-gaming check: Delta
    # If found_assets is high but delta is 0, something is wrong (maybe assets existed before?)
    # But setup script clears/checks this. 
    # We rely on specific names which are unique to the task.
    
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }