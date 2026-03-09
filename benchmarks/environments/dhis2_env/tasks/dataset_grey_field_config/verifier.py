#!/usr/bin/env python3
"""
Verifier for dataset_grey_field_config task.

Criteria:
1. Data Element "Prostate Screening [Task]" created (20 pts)
2. Data Element uses "Gender" Category Combo (20 pts)
3. Data Element assigned to "PHU Monthly 1" Dataset (20 pts)
4. Section "NCD Screening [Task]" created (15 pts)
5. "Female" option for the Data Element is greyed out in the section (25 pts)

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_dataset_grey_field_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/dataset_grey_field_config_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        if result.get('error'):
            return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

        score = 0
        feedback_parts = []
        
        # Data Element Check
        de = result.get('data_element')
        if de:
            score += 20
            feedback_parts.append("Data Element created (+20)")
            
            # Category Combo Check
            cat_combo = de.get('categoryCombo', {})
            if cat_combo.get('name') == 'Gender':
                score += 20
                feedback_parts.append("Correct Category Combo (Gender) (+20)")
            else:
                feedback_parts.append(f"Wrong Category Combo: {cat_combo.get('name')}")
        else:
            return {"passed": False, "score": 0, "feedback": "Data Element 'Prostate Screening [Task]' not found"}

        # Dataset Assignment Check
        ds = result.get('dataset')
        if ds and de:
            if de['id'] in ds.get('element_ids', []):
                score += 20
                feedback_parts.append("Assigned to Dataset (+20)")
            else:
                feedback_parts.append("Data Element NOT assigned to Dataset")
        else:
            feedback_parts.append("Dataset 'PHU Monthly 1' not found or DE missing")

        # Section Check
        section = result.get('section')
        if section:
            score += 15
            feedback_parts.append("Section created (+15)")
            
            # Grey Field Check
            greyed_fields = section.get('greyedFields', [])
            gender_options = result.get('gender_options', {})
            
            # Find the ID for "Female" option
            # The name might be "(Female)" or "Female" depending on how DHIS2 formats C_OCs
            female_coc_id = None
            for coc_id, coc_name in gender_options.items():
                if "Female" in coc_name:
                    female_coc_id = coc_id
                    break
            
            if not female_coc_id:
                # Fallback: try to find it in the DE's cat combo list if available
                # But usually the export script gets it from the cat combo endpoint
                feedback_parts.append("Could not identify Female option ID for verification")
            else:
                # Check if {DE_ID, FEMALE_COC_ID} is in greyedFields
                is_greyed = False
                for gf in greyed_fields:
                    gf_de = gf.get('dataElement', {}).get('id')
                    gf_coc = gf.get('categoryOptionCombo', {}).get('id')
                    if gf_de == de['id'] and gf_coc == female_coc_id:
                        is_greyed = True
                        break
                
                if is_greyed:
                    score += 25
                    feedback_parts.append("Female field correctly greyed out (+25)")
                else:
                    feedback_parts.append("Female field NOT greyed out")
                    
        else:
            feedback_parts.append("Section 'NCD Screening [Task]' not found")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier exception: {str(e)}"}