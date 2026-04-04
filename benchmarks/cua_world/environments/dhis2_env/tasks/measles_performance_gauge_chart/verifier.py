#!/usr/bin/env python3
"""
Verifier for measles_performance_gauge_chart task.

Scoring (100 points total):
- Visualization Created (20 pts)
- Correct Chart Type (GAUGE) (20 pts)
- Correct Data/OrgUnit (Measles/Bo) (15 pts)
- Target Line Configured (value 95) (25 pts)
- Axis Max Configured (value 120) (20 pts)

Pass Threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_measles_gauge(traj, env_info, task_info):
    """Verify that the measles gauge chart was created with correct options."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/measles_gauge_result.json", temp_path)
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
        
        target_found = result.get('target_found', False)
        viz_data = result.get('viz_data', {})
        
        # Criterion 1: Visualization Created (20 pts)
        if target_found:
            score += 20
            feedback_parts.append("Visualization created (+20)")
        else:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new Gauge visualization found. Please create a Gauge chart named 'Bo Measles Performance Gauge 2023'."
            }

        # Criterion 2: Correct Chart Type (20 pts)
        viz_type = viz_data.get('type', 'UNKNOWN')
        if viz_type == 'GAUGE':
            score += 20
            feedback_parts.append("Correct chart type: Gauge (+20)")
        else:
            feedback_parts.append(f"Incorrect chart type: {viz_type} (Expected GAUGE)")

        # Criterion 3: Correct Data/OrgUnit context (15 pts)
        # Check name for context
        display_name = viz_data.get('displayName', '').lower()
        indicators = viz_data.get('indicators', [])
        org_units = viz_data.get('organisationUnits', [])
        
        has_context = False
        if 'measles' in display_name and 'bo' in display_name:
            has_context = True
        elif any('measles' in ind.get('displayName', '').lower() for ind in indicators) and \
             any('bo' in ou.get('displayName', '').lower() for ou in org_units):
            has_context = True
            
        if has_context:
            score += 15
            feedback_parts.append("Correct data/org unit context (+15)")
        else:
            feedback_parts.append("Visualization does not appear to use Measles data for Bo district")

        # Criterion 4: Target Line Configured (25 pts)
        # DHIS2 stores target lines in 'axes' list or sometimes top-level fields depending on version
        axes = viz_data.get('axes', [])
        target_line_found = False
        target_value = None
        
        # Check top level (some versions)
        if viz_data.get('targetLineValue') is not None:
             target_value = viz_data.get('targetLineValue')
             if abs(float(target_value) - 95) <= 1:
                 target_line_found = True

        # Check axes list (standard)
        if not target_line_found and axes:
            for axis in axes:
                # Some versions structure: axis.targetLine.value
                t_line = axis.get('targetLine', {})
                if t_line and t_line.get('value') is not None:
                    if abs(float(t_line.get('value')) - 95) <= 1:
                        target_line_found = True
                        break
        
        if target_line_found:
            score += 25
            feedback_parts.append("Target line set to 95 (+25)")
        else:
            feedback_parts.append("Target line not found or incorrect value (expected 95)")

        # Criterion 5: Axis Max Configured (20 pts)
        axis_max_correct = False
        
        # Check top level
        if viz_data.get('rangeAxisMaxValue') is not None:
            if abs(float(viz_data.get('rangeAxisMaxValue')) - 120) <= 5:
                axis_max_correct = True
                
        # Check axes list
        if not axis_max_correct and axes:
            for axis in axes:
                max_val = axis.get('maxValue')
                if max_val is not None:
                    if abs(float(max_val) - 120) <= 5:
                        axis_max_correct = True
                        break
        
        if axis_max_correct:
            score += 20
            feedback_parts.append("Axis max set to 120 (+20)")
        else:
            feedback_parts.append("Axis maximum not set or incorrect (expected 120)")

        return {
            "passed": score >= 65,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verification failed with error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}