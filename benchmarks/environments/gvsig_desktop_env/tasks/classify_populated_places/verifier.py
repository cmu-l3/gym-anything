#!/usr/bin/env python3
"""
Verifier for classify_populated_places task.

Verifies that:
1. The agent modified the shapefile (DBF).
2. A new field URBAN_CAT exists.
3. The values in URBAN_CAT are correctly classified based on POP_MAX >= 10,000,000.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_classify_populated_places(traj, env_info, task_info):
    """
    Verify the classification task using the JSON result exported from the container.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Verification Data
    dbf_data = result.get("dbf_analysis", {})
    file_modified = result.get("file_modified", False)
    
    score = 0
    feedback = []
    
    # 3. Criterion: File Modified (10 pts)
    if file_modified:
        score += 10
        feedback.append("File modification detected.")
    else:
        feedback.append("File was NOT modified (did you save edits?).")

    # 4. Criterion: Field Exists (20 pts)
    if dbf_data.get("field_exists"):
        score += 20
        feedback.append("Field 'URBAN_CAT' created successfully.")
    else:
        feedback.append("Field 'URBAN_CAT' NOT found in attribute table.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 5. Criterion: Megacities Classification (30 pts)
    # Allow some tolerance if they missed one or two, but generally should be 100%
    megacity_total = dbf_data.get("megacity_count", 0)
    megacity_correct = dbf_data.get("megacity_correct", 0)
    
    if megacity_total > 0:
        megacity_accuracy = megacity_correct / megacity_total
        if megacity_accuracy == 1.0:
            score += 30
            feedback.append(f"All {megacity_total} Megacities correctly labeled.")
        elif megacity_accuracy > 0.8:
            score += 20
            feedback.append(f"Most Megacities labeled correctly ({megacity_correct}/{megacity_total}).")
        else:
            feedback.append(f"Megacity labeling failed ({megacity_correct}/{megacity_total}).")
    else:
        feedback.append("No Megacities found in dataset (unexpected data).")

    # 6. Criterion: Standard Cities Classification (30 pts)
    city_total = dbf_data.get("city_count", 0)
    city_correct = dbf_data.get("city_correct", 0)
    
    if city_total > 0:
        city_accuracy = city_correct / city_total
        if city_accuracy == 1.0:
            score += 30
            feedback.append(f"All {city_total} Cities correctly labeled.")
        elif city_accuracy > 0.9:
            score += 25
            feedback.append(f"Most Cities labeled correctly ({city_correct}/{city_total}).")
        elif city_accuracy > 0.5:
            score += 10
            feedback.append(f"Some Cities labeled correctly ({city_correct}/{city_total}).")
        else:
            feedback.append(f"City labeling failed ({city_correct}/{city_total}).")
    
    # 7. Criterion: Completeness (10 pts)
    # Check if there are any records that weren't counted (i.e. logic errors or nulls)
    # In our python script, we iterated all records, so correct+incorrect = total.
    # The script checks if cat == "Megacity" or "City". If empty/null, it wouldn't match.
    # So strictly, we check if (megacity_correct + city_correct) == total_records
    
    total_records = dbf_data.get("total_records", 0)
    total_correct = megacity_correct + city_correct
    
    if total_records > 0 and total_correct == total_records:
        score += 10
        feedback.append("All records populated.")
    elif total_records > 0 and total_correct > (total_records * 0.9):
         score += 5
         feedback.append("Some records missing values or incorrect.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }