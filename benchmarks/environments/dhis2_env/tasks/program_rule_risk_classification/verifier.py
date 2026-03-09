#!/usr/bin/env python3
"""
Verifier for program_rule_risk_classification task.

Scoring (100 points total):
- Data Element "Neonatal Risk Status" created (10 pts)
- Data Element assigned to "Birth" stage (20 pts)
- Program Rule Variable created for Weight (20 pts)
- Program Rule created with correct condition (20 pts)
- Program Rule Action assigns "High Risk" to the data element (30 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)

def verify_program_rule_risk_classification(traj, env_info, task_info):
    """Verify the Program Rule configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/program_rule_risk_result.json", temp_path)
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
        
        # 1. Data Element Created (10 pts)
        de = result.get("data_element")
        if de:
            score += 10
            feedback_parts.append(f"Data Element '{de['name']}' created (+10)")
            # Bonus check: is it TEXT?
            if de.get("valueType") == "TEXT":
                feedback_parts.append("Correct ValueType (TEXT)")
            else:
                feedback_parts.append(f"Warning: ValueType is {de.get('valueType')}, expected TEXT")
        else:
            feedback_parts.append("Data Element 'Neonatal Risk Status' not found")

        # 2. Stage Assignment (20 pts)
        stage_entry = result.get("program_stage_entry")
        if stage_entry and stage_entry.get("is_assigned"):
            score += 20
            feedback_parts.append(f"Data Element assigned to '{stage_entry['stage_name']}' stage (+20)")
        else:
            feedback_parts.append("Data Element NOT assigned to Birth stage")

        # 3. Rule Variable (20 pts)
        prv = result.get("rule_variable")
        if prv:
            score += 20
            feedback_parts.append(f"Rule Variable '{prv['name']}' found linked to '{prv['source_data_element']}' (+20)")
        else:
            feedback_parts.append("Program Rule Variable for Weight not found")

        # 4. Program Rule Condition (20 pts)
        pr = result.get("program_rule")
        if pr:
            cond = pr.get("condition", "")
            # Check for < and 2500
            if "<" in cond and "2500" in cond:
                score += 20
                feedback_parts.append(f"Rule Condition '{cond}' looks correct (+20)")
            else:
                score += 5 # Partial credit for creating rule
                feedback_parts.append(f"Rule created but condition '{cond}' seems incorrect (expected < 2500) (+5)")
        else:
            feedback_parts.append("Program Rule not found")

        # 5. Program Rule Action (30 pts)
        if pr and pr.get("has_assign_action"):
            val = pr.get("action_value", "")
            action_type = pr.get("action_type", "")
            
            # Check for "High Risk" (quotes might vary in API response or user input)
            if "High Risk" in val or "'High Risk'" in val:
                score += 30
                feedback_parts.append("Rule Action assigns 'High Risk' correctly (+30)")
            else:
                score += 10 # Partial for correct action type but wrong value
                feedback_parts.append(f"Rule Action found but assigns '{val}' instead of 'High Risk' (+10)")
                
            if action_type != "ASSIGN":
                feedback_parts.append(f"Warning: Action type is {action_type}, expected ASSIGN")
        else:
            feedback_parts.append("Program Rule Action to assign value not found")

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}