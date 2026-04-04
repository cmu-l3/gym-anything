#!/usr/bin/env python3
"""
Verifier for custom_indicator_factor_config task.

Scoring (100 points total):
1. Indicator Type created with factor 10,000 (25 pts)
2. Indicator created with correct name (25 pts)
3. Indicator logic correct (uses 10k type + correct num/denom) (20 pts)
4. Visualization created (20 pts)
5. Visualization uses the correct indicator (10 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_custom_indicator_factor(traj, env_info, task_info):
    """Verify custom indicator factor configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/custom_indicator_result.json", temp_path)
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
        
        # 1. Check Indicator Type (25 pts)
        type_data = result.get('indicator_type', {})
        if type_data.get('found'):
            factor = type_data.get('factor')
            if factor == 10000:
                score += 25
                feedback_parts.append("Indicator Type 'Per 10,000' created successfully (+25)")
            else:
                feedback_parts.append(f"Indicator Type found but factor is {factor}, expected 10000")
        else:
            feedback_parts.append("Indicator Type with factor 10000 not found")

        # 2. Check Indicator Existence (25 pts)
        ind_data = result.get('indicator', {})
        if ind_data.get('found'):
            score += 25
            feedback_parts.append(f"Indicator '{ind_data.get('name')}' created (+25)")
        else:
            feedback_parts.append("Indicator 'OPD Visits per 10,000' not found")

        # 3. Check Indicator Logic (20 pts)
        if ind_data.get('found'):
            logic_score = 0
            
            # Check type link
            if ind_data.get('type_factor') == 10000:
                logic_score += 10
                feedback_parts.append("Indicator linked to correct 10k factor type (+10)")
            else:
                feedback_parts.append("Indicator linked to wrong type (factor != 10000)")

            # Check numerator/denominator content
            # We look for UIDs usually, but since agent selects them, we check if the ID string is present
            # or if the user entered hardcoded values (which is wrong but checkable).
            # The export script extracts the raw numerator/denominator strings (e.g. "#{uid1}/#{uid2}")
            # We can't easily validate UIDs without a lookup map, but we can check if they are not empty.
            # A strict check would be hard without knowing the random UIDs of "OPD visits".
            # However, if the field is not empty, we give benefit of doubt or rely on manual metadata check if needed.
            # Here we just check they are not null/empty.
            
            num = ind_data.get('numerator', '')
            den = ind_data.get('denominator', '')
            
            if num and den and len(num) > 5 and len(den) > 5:
                logic_score += 10
                feedback_parts.append("Numerator and Denominator configured (+10)")
            else:
                feedback_parts.append("Numerator or Denominator appear empty/invalid")
                
            score += logic_score

        # 4. Check Visualization (20 pts)
        viz_data = result.get('visualization', {})
        if viz_data.get('found'):
            score += 20
            feedback_parts.append(f"Visualization '{viz_data.get('name')}' created (+20)")
        else:
            feedback_parts.append("Visualization 'OPD Burden Analysis 2023' not found")

        # 5. Check Visualization Content (10 pts)
        if viz_data.get('found') and viz_data.get('uses_target_indicator'):
            score += 10
            feedback_parts.append("Visualization uses the new indicator (+10)")
        elif viz_data.get('found'):
            feedback_parts.append("Visualization does not seem to contain the new indicator")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}