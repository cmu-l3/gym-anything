#!/usr/bin/env python3
"""Verifier for Configure Calculated Grade Item task in Moodle."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_calculated_grade_item(traj, env_info, task_info):
    """
    Verify that:
    1. 'Experiment 1 Total' grade item exists.
    2. 'Pre-Lab 1' has idnumber 'PreLab1'.
    3. 'Post-Lab 1' has idnumber 'PostLab1'.
    4. 'Experiment 1 Total' has correct calculation formula.
    
    Moodle stores formulas with internal IDs: =[[#101]] + ([[#102]] * 2)
    We must resolve these IDs to verify the logic matches: =[[PreLab1]] + ([[PostLab1]] * 2)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_item_name', 'Experiment 1 Total')
    expected_logic = metadata.get('expected_formula_logic', '=[[PreLab1]] + ([[PostLab1]] * 2)')
    
    # Clean up expected logic for comparison (remove spaces, lowercase)
    clean_expected = expected_logic.replace(" ", "").lower()

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_calculated_grade_item_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        grade_items = result.get('grade_items', [])
        
        # Build lookup maps
        id_to_item = {item['id']: item for item in grade_items}
        name_to_item = {item['itemname']: item for item in grade_items}
        
        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Verify Target Item Exists (20 pts)
        target_item = name_to_item.get(target_name)
        if target_item:
            score += 20
            subscores['target_created'] = True
            feedback_parts.append(f"Item '{target_name}' created")
        else:
            feedback_parts.append(f"Item '{target_name}' NOT found")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": " | ".join(feedback_parts)
            }

        # 2. Verify Pre-Lab 1 ID Number (20 pts)
        pre_lab = name_to_item.get("Pre-Lab 1")
        if pre_lab and pre_lab.get('idnumber') == 'PreLab1':
            score += 20
            subscores['prelab_id_set'] = True
            feedback_parts.append("Pre-Lab 1 ID set correctly")
        else:
            current_id = pre_lab.get('idnumber') if pre_lab else "None"
            feedback_parts.append(f"Pre-Lab 1 ID incorrect (found: '{current_id}', expected: 'PreLab1')")

        # 3. Verify Post-Lab 1 ID Number (20 pts)
        post_lab = name_to_item.get("Post-Lab 1")
        if post_lab and post_lab.get('idnumber') == 'PostLab1':
            score += 20
            subscores['postlab_id_set'] = True
            feedback_parts.append("Post-Lab 1 ID set correctly")
        else:
            current_id = post_lab.get('idnumber') if post_lab else "None"
            feedback_parts.append(f"Post-Lab 1 ID incorrect (found: '{current_id}', expected: 'PostLab1')")

        # 4. Verify Calculation Active (10 pts)
        raw_calculation = target_item.get('calculation')
        if raw_calculation and raw_calculation.strip():
            score += 10
            subscores['calculation_active'] = True
            feedback_parts.append("Calculation formula is active")
        else:
            feedback_parts.append("No calculation formula found")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # 5. Verify Formula Logic (30 pts)
        # Moodle formula: =[[#101]] + [[#102]]*2
        # We need to replace [[#ID]] with [[IDNUMBER]] using our lookup
        
        def replace_id_match(match):
            # match.group(1) is the ID number (e.g. 101)
            item_id = int(match.group(1))
            item = id_to_item.get(item_id)
            if item and item.get('idnumber'):
                return f"[[{item['idnumber']}]]"
            return f"[[UNKNOWN_ID_{item_id}]]"

        # Regex to find [[#123]] pattern
        # Moodle uses # prefix for internal IDs in formula
        resolved_formula = re.sub(r'\[\[#(\d+)\]\]', replace_id_match, raw_calculation)
        
        # Clean for comparison
        clean_resolved = resolved_formula.replace(" ", "").lower()
        
        if clean_resolved == clean_expected:
            score += 30
            subscores['formula_correct'] = True
            feedback_parts.append("Formula logic is correct")
        else:
            # Check for close matches (e.g. wrong multiplier)
            feedback_parts.append(f"Formula mismatch. Logic resolved to: {resolved_formula}")
            
        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "raw_formula": raw_calculation,
                "resolved_formula": resolved_formula,
                "expected_logic": expected_logic
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}