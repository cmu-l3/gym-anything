#!/usr/bin/env python3
"""
Verifier for dataset_governance_config task.

Scoring (100 points total):
- Target Malaria dataset modified during task (20 pts)
- Timely days set to 15 (20 pts)
- Expiry days set to 60 (20 pts)
- Compulsory data element containing 'treated' set (30 pts)
- Correct dataset identified (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_dataset_governance_config(traj, env_info, task_info):
    """Verify dataset governance configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/dataset_governance_result.json", temp_path)
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
        
        api_data = result.get('api_result', {})
        datasets = api_data.get('datasets', [])
        
        # Find the best matching dataset (most likely the one the agent modified)
        # We look for one where criteria are met, or at least modified
        target_ds = None
        
        # Priority 1: Find a dataset that matches everything
        for ds in datasets:
            timely = ds.get('timelyDays')
            expiry = ds.get('expiryDays')
            compulsory = ds.get('compulsoryDataElements', [])
            has_treated = any('treated' in el.lower() or 'confirmed' in el.lower() for el in compulsory)
            
            if timely == 15 and expiry == 60 and has_treated:
                target_ds = ds
                break
        
        # Priority 2: Find a dataset that was modified during task
        if not target_ds:
            for ds in datasets:
                if ds.get('modified_during_task'):
                    target_ds = ds
                    break
                    
        # Priority 3: Just take the first one if it looks like the main malaria report
        if not target_ds and datasets:
             target_ds = datasets[0]

        if not target_ds:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No Malaria datasets found in the system."
            }

        ds_name = target_ds.get('displayName', 'Unknown')
        feedback_parts.append(f"Checked dataset: '{ds_name}'")
        
        # Criterion 1: Dataset Modified (20 pts)
        if target_ds.get('modified_during_task'):
            score += 20
            feedback_parts.append("Dataset modified during task (+20)")
        else:
            feedback_parts.append("Dataset NOT modified during task (check timestamp)")

        # Criterion 2: Timely Days (20 pts)
        timely_days = target_ds.get('timelyDays')
        if timely_days == 15:
            score += 20
            feedback_parts.append("Timely days set to 15 (+20)")
        else:
            feedback_parts.append(f"Timely days is {timely_days} (expected 15)")

        # Criterion 3: Expiry Days (20 pts)
        expiry_days = target_ds.get('expiryDays')
        if expiry_days == 60:
            score += 20
            feedback_parts.append("Expiry days set to 60 (+20)")
        else:
            feedback_parts.append(f"Expiry days is {expiry_days} (expected 60)")

        # Criterion 4: Compulsory Data Elements (30 pts)
        compulsory_list = target_ds.get('compulsoryDataElements', [])
        has_treated = False
        matching_elements = []
        for el in compulsory_list:
            if 'treated' in el.lower() or 'confirmed' in el.lower():
                has_treated = True
                matching_elements.append(el)
        
        if has_treated:
            score += 30
            feedback_parts.append(f"Compulsory element found: {', '.join(matching_elements[:1])} (+30)")
        else:
            feedback_parts.append("No 'treated' or 'confirmed' data element found in compulsory list")

        # Criterion 5: Correct Dataset (10 pts)
        # Assuming if we found one with matching criteria, it's the right one. 
        # Or if the name contains "Facility" or "Monthly" it's likely the main reporting form.
        if "facility" in ds_name.lower() or "monthly" in ds_name.lower() or "report" in ds_name.lower():
            score += 10
            feedback_parts.append("Target dataset appears correct (+10)")
        else:
            feedback_parts.append("Dataset name might not be the main facility report (0)")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}