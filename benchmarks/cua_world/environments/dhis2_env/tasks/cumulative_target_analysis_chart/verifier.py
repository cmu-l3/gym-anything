#!/usr/bin/env python3
"""
Verifier for cumulative_target_analysis_chart task.

Scoring (100 points total):
1. Visualization created with correct name (20 pts)
2. Cumulative values enabled (30 pts) [Critical]
3. Target line configured correctly (20 pts)
4. Base line configured correctly (15 pts)
5. Correct data context (Malaria data + Bo district) (15 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_cumulative_chart(traj, env_info, task_info):
    """Verify the cumulative chart configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
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
        
        viz_data = result.get('visualization_data', {})
        found = viz_data.get('found', False)
        
        # Criterion 1: Visualization Created (20 pts)
        if not found:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No visualization named 'Bo Malaria Cumulative Analysis 2023' was found."
            }
        
        score += 20
        feedback_parts.append("Visualization created (+20)")
        
        # Criterion 2: Cumulative Values (30 pts)
        cumulative = viz_data.get('cumulative_values', False)
        if cumulative:
            score += 30
            feedback_parts.append("Cumulative values enabled (+30)")
        else:
            feedback_parts.append("Cumulative values NOT enabled (0)")
            
        # Criterion 3: Target Line (20 pts)
        # Expected: 25000
        target_val = viz_data.get('target_line_value')
        if target_val is not None and 24900 <= float(target_val) <= 25100:
            score += 20
            feedback_parts.append(f"Target line correct ({target_val}) (+20)")
        else:
            feedback_parts.append(f"Target line missing or incorrect (Found: {target_val}, Expected: 25000)")
            
        # Criterion 4: Base Line (15 pts)
        # Expected: 5000
        base_val = viz_data.get('base_line_value')
        if base_val is not None and 4900 <= float(base_val) <= 5100:
            score += 15
            feedback_parts.append(f"Base line correct ({base_val}) (+15)")
        else:
            feedback_parts.append(f"Base line missing or incorrect (Found: {base_val}, Expected: 5000)")
            
        # Criterion 5: Data Context (15 pts)
        # Check for Malaria data and Bo district
        data_elements = [d.lower() for d in viz_data.get('data_elements', [])]
        org_units = [o.lower() for o in viz_data.get('org_units', [])]
        
        has_malaria = any('malaria' in d for d in data_elements)
        has_bo = any('bo' in o for o in org_units)
        
        if has_malaria and has_bo:
            score += 15
            feedback_parts.append("Correct data (Malaria) and org unit (Bo) selected (+15)")
        elif has_malaria:
            score += 7
            feedback_parts.append("Correct data selected, but wrong org unit (+7)")
        elif has_bo:
            score += 7
            feedback_parts.append("Correct org unit selected, but wrong data (+7)")
        else:
            feedback_parts.append("Incorrect data and org unit")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}