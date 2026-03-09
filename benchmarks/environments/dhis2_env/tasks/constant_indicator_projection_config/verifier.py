#!/usr/bin/env python3
"""
Verifier for constant_indicator_projection_config task.

Scoring (100 points total):
- Constant created with correct value (1.8) (20 pts)
- Indicator created (20 pts)
- Indicator uses the created Constant in denominator (30 pts) [Anti-gaming check]
- Indicator uses Population in numerator (10 pts)
- Visualization created using the indicator (20 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
import re

logger = logging.getLogger(__name__)


def verify_constant_indicator_projection(traj, env_info, task_info):
    """Verify that constant, indicator, and visualization were configured correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/constant_task_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        if 'error' in result:
             return {"passed": False, "score": 0, "feedback": f"Error in export script: {result['error']}"}

        score = 0
        feedback_parts = []
        
        constants = result.get('constants', [])
        indicators = result.get('indicators', [])
        visualizations = result.get('visualizations', [])
        population_des = result.get('population_data_elements', [])
        
        # Build set of population IDs for checking
        pop_ids = {de['id'] for de in population_des}

        # 1. Verify Constant (20 pts)
        target_constant = None
        for c in constants:
            try:
                val = float(c.get('value', 0))
                if abs(val - 1.8) < 0.01:
                    target_constant = c
                    break
            except:
                continue
        
        if target_constant:
            score += 20
            feedback_parts.append(f"Constant '{target_constant.get('name')}' created with value 1.8 (+20)")
        else:
            feedback_parts.append("No Constant found with value 1.8")

        # 2. Verify Indicator Existence (20 pts)
        target_indicator = None
        if indicators:
            target_indicator = indicators[0] # Take the first one matching 'ITN'
            score += 20
            feedback_parts.append(f"Indicator '{target_indicator.get('name')}' created (+20)")
        else:
            feedback_parts.append("No Indicator found with 'ITN' in name")

        # 3. Verify Formula Logic (30 pts + 10 pts)
        if target_indicator:
            numerator = target_indicator.get('numerator', '')
            denominator = target_indicator.get('denominator', '')
            
            # Check Denominator uses Constant (30 pts)
            # Formula format for constant is C{constant_uid}
            uses_constant = False
            if target_constant:
                const_uid = target_constant.get('id')
                if const_uid and f"C{{{const_uid}}}" in denominator:
                    uses_constant = True
            
            # Fallback: check if ANY constant ID is used if we couldn't match the specific one above
            if not uses_constant and "C{" in denominator:
                # Regex to extract C{...}
                match = re.search(r'C\{([a-zA-Z0-9]+)\}', denominator)
                if match:
                    # Check if this ID is in our constants list
                    found_id = match.group(1)
                    for c in constants:
                        if c.get('id') == found_id and abs(float(c.get('value',0)) - 1.8) < 0.01:
                            uses_constant = True
                            break
            
            if uses_constant:
                score += 30
                feedback_parts.append("Indicator denominator correctly uses the Constant (+30)")
            elif "1.8" in denominator:
                feedback_parts.append("Indicator denominator hardcodes 1.8 instead of using Constant (0 pts)")
            else:
                feedback_parts.append("Indicator denominator incorrect")

            # Check Numerator uses Population (10 pts)
            # Numerator format #{de_uid}
            uses_pop = False
            for pid in pop_ids:
                if pid in numerator:
                    uses_pop = True
                    break
            
            if uses_pop:
                score += 10
                feedback_parts.append("Indicator numerator uses Population data element (+10)")
            else:
                feedback_parts.append("Indicator numerator does not appear to use a Population data element")

        # 4. Verify Visualization (20 pts)
        viz_valid = False
        if visualizations:
            for v in visualizations:
                # Check if this visualization uses our target indicator
                data_items = v.get('dataDimensionItems', [])
                for item in data_items:
                    ind = item.get('indicator', {})
                    if target_indicator and ind.get('id') == target_indicator.get('id'):
                        viz_valid = True
                        break
                if viz_valid:
                    break
        
        if viz_valid:
            score += 20
            feedback_parts.append("Visualization created using the indicator (+20)")
        elif visualizations:
            feedback_parts.append("Visualization found but does not use the correct indicator")
        else:
            feedback_parts.append("No ITN visualization found")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}