#!/usr/bin/env python3
"""
Verifier for waste_management_config_entry task.

Scoring (100 points total):
- Data Elements Created (20 pts): 'Waste Generated' and 'Waste Incinerated' exist and are new.
- Dataset Created (10 pts): 'Hospital Waste Management' exists and is new.
- Configuration (20 pts): Elements assigned to dataset, Dataset assigned to OU.
- Data Entry (40 pts): Correct values (150, 120) entered for correct period/OU.
- Completion (10 pts): Dataset marked complete.

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_waste_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/waste_management_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        # 1. Verify Data Elements (20 pts)
        # We need to find elements that match the names loosely
        created_des = result.get('created_data_elements', [])
        target_ids = result.get('target_ids', {})
        
        gen_de = next((de for de in created_des if 'Generated' in de['name']), None)
        inc_de = next((de for de in created_des if 'Incinerated' in de['name']), None)
        
        if gen_de:
            score += 10
            feedback_parts.append(f"DE 'Waste Generated' created (+10)")
            # Strict check on type?
            if gen_de.get('valueType') != 'NUMBER' and gen_de.get('valueType') != 'INTEGER':
                 feedback_parts.append(f"(Warning: {gen_de['name']} type is {gen_de.get('valueType')}, expected NUMBER)")
        else:
            feedback_parts.append("DE 'Waste Generated' NOT found")

        if inc_de:
            score += 10
            feedback_parts.append(f"DE 'Waste Incinerated' created (+10)")
        else:
            feedback_parts.append("DE 'Waste Incinerated' NOT found")

        # 2. Verify Dataset (10 pts)
        datasets = result.get('created_datasets', [])
        # Find the one that looks right
        target_ds = next((ds for ds in datasets if 'Hospital Waste' in ds['name']), None)
        
        if target_ds:
            score += 10
            feedback_parts.append(f"Dataset '{target_ds['name']}' created (+10)")
            
            # 3. Verify Configuration (20 pts)
            config_score = 0
            if target_ds.get('contains_gen') and target_ds.get('contains_inc'):
                config_score += 10
                feedback_parts.append("Elements assigned to dataset (+10)")
            else:
                feedback_parts.append("Elements missing from dataset")
            
            if target_ds.get('assigned_to_target_ou'):
                config_score += 10
                feedback_parts.append("Dataset assigned to Org Unit (+10)")
            else:
                feedback_parts.append("Dataset NOT assigned to Bo Government Hospital")
            
            score += config_score
        else:
            feedback_parts.append("Dataset 'Hospital Waste Management' NOT found")

        # 4. Verify Data Values (40 pts)
        data_values = result.get('data_values', [])
        val_gen_found = False
        val_inc_found = False
        
        # ID-based lookup if we found the elements
        id_gen = target_ids.get('gen')
        id_inc = target_ids.get('inc')
        
        for val in data_values:
            v = val.get('value', '')
            de = val.get('de', '')
            
            if id_gen and de == id_gen and v == '150':
                val_gen_found = True
            elif id_inc and de == id_inc and v == '120':
                val_inc_found = True
        
        if val_gen_found:
            score += 20
            feedback_parts.append("Value 150 entered correctly (+20)")
        else:
            feedback_parts.append("Value 150 for Generated waste NOT found")
            
        if val_inc_found:
            score += 20
            feedback_parts.append("Value 120 for Incinerated waste entered correctly (+20)")
        else:
            feedback_parts.append("Value 120 for Incinerated waste NOT found")

        # 5. Verify Completion (10 pts)
        if result.get('dataset_complete'):
            score += 10
            feedback_parts.append("Dataset marked complete (+10)")
        else:
            feedback_parts.append("Dataset NOT marked complete")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}