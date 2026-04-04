#!/usr/bin/env python3
"""
Verifier for nutrition_program_stage_design task.

Scoring (100 points total):
- Program Stage "Nutrition Screening" exists in Child Programme (30 pts)
- Stage is set to Repeatable (20 pts)
- Correct Data Elements assigned (Weight, Height, MUAC/Temp) (20 pts)
- Section "Anthropometry" created (15 pts)
- Data Elements correctly placed inside the Section (15 pts)

Pass threshold: 60 points
Mandatory: Stage must exist
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_nutrition_program_stage(traj, env_info, task_info):
    """Verify the Nutrition Screening program stage configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/nutrition_stage_result.json", temp_path)
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
        subscores = {}

        # 1. Check Program Found
        if not result.get('program_found'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not locate 'Child Programme' or similar tracker program.",
                "subscores": {}
            }

        # 2. Check Stage Found (MANDATORY)
        stage_found = result.get('target_stage_found', False)
        if not stage_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Program Stage 'Nutrition Screening' was not found in the Child Programme.",
                "subscores": {}
            }
        
        score += 30
        subscores["stage_created"] = True
        feedback_parts.append("Program Stage 'Nutrition Screening' created (+30)")

        # Get details
        details = result.get('stage_details', {})
        
        # 3. Check Repeatable
        is_repeatable = details.get('repeatable', False)
        if is_repeatable:
            score += 20
            subscores["repeatable"] = True
            feedback_parts.append("Stage is set to Repeatable (+20)")
        else:
            subscores["repeatable"] = False
            feedback_parts.append("Stage is NOT set to Repeatable (0)")

        # 4. Check Data Elements
        # Expected keywords: Weight, Height, MUAC (or Arm/Circumference/Temperature)
        assigned_des = [d.lower() for d in details.get('data_elements', [])]
        
        has_weight = any('weight' in d for d in assigned_des)
        has_height = any('height' in d for d in assigned_des)
        has_muac = any(k in d for d in assigned_des for k in ['muac', 'arm', 'circumference', 'temperature'])
        
        de_score = 0
        if has_weight: de_score += 7
        if has_height: de_score += 7
        if has_muac: de_score += 6
        
        score += de_score
        subscores["data_elements"] = de_score
        feedback_parts.append(f"Data Elements assigned: {de_score}/20 pts (Weight={has_weight}, Height={has_height}, Other={has_muac})")

        # 5. Check Section Created
        section_found = details.get('section_found', False)
        section_name = details.get('section_name', 'None')
        
        if section_found and 'anthropometry' in section_name.lower():
            score += 15
            subscores["section_created"] = True
            feedback_parts.append("Section 'Anthropometry' created (+15)")
        elif section_found:
            score += 5 # Partial credit for creating a section with wrong name
            subscores["section_created"] = False
            feedback_parts.append(f"Section created but named '{section_name}' (+5)")
        else:
            subscores["section_created"] = False
            feedback_parts.append("No Form Section created (0)")

        # 6. Check Elements inside Section
        if section_found:
            section_des = [d.lower() for d in details.get('section_data_elements', [])]
            # Check if at least 2 of the required elements are IN the section
            count_in_section = 0
            if any('weight' in d for d in section_des): count_in_section += 1
            if any('height' in d for d in section_des): count_in_section += 1
            if any(k in d for d in section_des for k in ['muac', 'arm', 'circumference', 'temperature']): count_in_section += 1
            
            if count_in_section >= 2:
                score += 15
                subscores["elements_in_section"] = True
                feedback_parts.append("Data elements correctly placed in Section (+15)")
            elif count_in_section == 1:
                score += 5
                subscores["elements_in_section"] = False
                feedback_parts.append("Only 1 data element found in Section (+5)")
            else:
                subscores["elements_in_section"] = False
                feedback_parts.append("Section exists but is empty or missing required elements (0)")
        else:
            subscores["elements_in_section"] = False

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}