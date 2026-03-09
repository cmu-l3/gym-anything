#!/usr/bin/env python3
"""
Verifier for Corporate Acquisition Rebranding task.

Criteria:
1. Schema: 'Brands' and 'BelongsTo' classes exist (20 pts).
2. Entity: 'The Collections' Brand vertex exists (10 pts).
3. Data Update (Type): Target hotels have Type 'Luxury Collection' (15 pts).
4. Data Update (Name): Target hotels have ' - The Collections' suffix (25 pts).
5. Graph Linkage: Target hotels are linked to 'The Collections' via 'BelongsTo' (20 pts).
6. Safety: Non-target hotels are NOT modified (10 pts).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_acquisition_rebranding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in export script: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Schema Check (20 pts)
    classes = result.get('classes_exist', {})
    if classes.get('Brands') and classes.get('BelongsTo'):
        score += 20
        feedback.append("Schema classes created.")
    else:
        feedback.append(f"Missing classes: Brands={classes.get('Brands')}, BelongsTo={classes.get('BelongsTo')}")

    # 2. Brand Entity Check (10 pts)
    brands = result.get('brands_data', [])
    brand_found = any(b.get('Name') == 'The Collections' for b in brands)
    if brand_found:
        score += 10
        feedback.append("Brand vertex created.")
    else:
        feedback.append("Brand 'The Collections' not found.")

    # Get lists for data verification
    converted_by_type = result.get('converted_hotels_by_type', [])
    converted_by_name = result.get('converted_hotels_by_name', [])
    
    # We expect some hotels to be converted. If lists are empty, agent did nothing.
    if not converted_by_type and not converted_by_name:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback + ["No hotels were updated."])}

    # 3. Data Update - Name Suffix (25 pts)
    # Check if hotels in the converted lists actually have the suffix
    valid_names = 0
    total_checked = 0
    
    # Use converted_by_name list which queried via LIKE '% - The Collections'
    if converted_by_name:
        valid_names = len(converted_by_name)
        score += 25
        feedback.append(f"{valid_names} hotels updated with correct name suffix.")
    else:
        feedback.append("No hotels found with ' - The Collections' suffix.")

    # 4. Data Update - Type (15 pts)
    # Check hotels with the new type
    if converted_by_type:
        score += 15
        feedback.append(f"{len(converted_by_type)} hotels updated to 'Luxury Collection'.")
    else:
        feedback.append("No hotels updated to Type 'Luxury Collection'.")

    # 5. Graph Linkage (20 pts)
    # Check if the hotels with new type/name are linked to the brand
    # The export query for converted_by_type includes "out('BelongsTo').Name"
    linked_count = 0
    for h in converted_by_type:
        brand_links = h.get('BrandLinks', [])
        if brand_links and 'The Collections' in brand_links:
            linked_count += 1
    
    if linked_count > 0 and linked_count == len(converted_by_type):
        score += 20
        feedback.append(f"All {linked_count} converted hotels are linked to Brand.")
    elif linked_count > 0:
        score += 10
        feedback.append(f"Only {linked_count}/{len(converted_by_type)} converted hotels linked.")
    else:
        feedback.append("No hotels are linked to 'The Collections'.")

    # 6. Safety Check (10 pts)
    # Non-target sample should NOT have changed
    non_target = result.get('non_target_sample', [])
    safety_pass = True
    for h in non_target:
        if "The Collections" in h.get('Name', '') or h.get('Type') == 'Luxury Collection':
            safety_pass = False
            break
    
    if safety_pass:
        score += 10
        feedback.append("Non-target hotels preserved.")
    else:
        feedback.append("FAIL: Non-target hotels were incorrectly modified.")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }