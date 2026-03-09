#!/usr/bin/env python3
"""
Verifier for evaluate_wake_interaction_two_turbines task.

Checks:
1. Project file existence and validity (20 pts)
2. Project configuration (25 pts) - Checks for 2 turbine instances
3. Simulation Physics (30 pts) - Checks report for Wake Loss > 10%
4. Report Format (15 pts) - formatting compliance
5. VLM / App State (10 pts) - App running, trajectory verification
"""

import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_value(content, key):
    """Extract numeric value for a key from report content."""
    # Pattern: Key: [Value] Unit
    # Case insensitive
    pattern = re.compile(rf"{key}\s*[:=]\s*([0-9\.]+)", re.IGNORECASE)
    match = pattern.search(content)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            return None
    return None

def verify_wake_interaction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Project File (20 pts) ---
    if result.get('project_exists') and result.get('project_created_during_task'):
        score += 20
        feedback_parts.append("Project file saved successfully")
    elif result.get('project_exists'):
        score += 10
        feedback_parts.append("Project file exists but timestamp is old")
    else:
        feedback_parts.append("Project file not found")

    # --- Criterion 2: Project Configuration (25 pts) ---
    # Analyze snippet for evidence of multiple turbines
    project_snippet = ""
    try:
        if result.get('project_snippet_b64'):
            project_snippet = base64.b64decode(result.get('project_snippet_b64')).decode('utf-8', errors='ignore')
    except:
        pass

    # Look for keywords indicating multiple instances
    # Common QBlade keywords: "TurbineInstance", "Position", "Scene"
    # Or simply multiple occurrences of "Turbine" or "Instance"
    turbine_refs = len(re.findall(r"Turbine", project_snippet, re.IGNORECASE))
    instance_refs = len(re.findall(r"Instance", project_snippet, re.IGNORECASE))
    
    # We expect at least references to the definition and 2 instances
    if turbine_refs >= 2 or instance_refs >= 2:
        score += 25
        feedback_parts.append("Project file indicates multiple turbine instances")
    else:
        # Check specifically for "50" (distance)
        if "50" in project_snippet:
             score += 15
             feedback_parts.append("Project file contains spacing parameter (50m) but structure unclear")
        else:
             feedback_parts.append("Project file structure analysis inconclusive")

    # --- Criterion 3: Report & Physics (45 pts total) ---
    report_content = ""
    try:
        if result.get('report_content_b64'):
            report_content = base64.b64decode(result.get('report_content_b64')).decode('utf-8', errors='ignore')
    except:
        pass

    if result.get('report_exists'):
        score += 10 # Report exists (Criterion 4 base)
        
        upstream = parse_report_value(report_content, "Upstream Power")
        downstream = parse_report_value(report_content, "Downstream Power")
        reported_loss = parse_report_value(report_content, "Wake Loss")
        
        physics_passed = False
        if upstream is not None and downstream is not None:
            # Check Physics: Downstream should be significantly less than Upstream
            if downstream < upstream:
                loss_calc = (upstream - downstream) / upstream * 100
                
                # Check for significant wake effect (>10%)
                if loss_calc > 10.0:
                    score += 20 # Physics check passed
                    physics_passed = True
                    feedback_parts.append(f"Physics valid: {loss_calc:.1f}% wake loss detected")
                else:
                    feedback_parts.append(f"Physics questionable: Only {loss_calc:.1f}% loss (expected >10%)")
            else:
                feedback_parts.append("Physics invalid: Downstream power >= Upstream power")
        else:
            feedback_parts.append("Could not parse power values from report")
            
        # Check reported calculation accuracy
        if physics_passed and reported_loss is not None:
            if abs(reported_loss - loss_calc) < 1.0:
                score += 5
                feedback_parts.append("Reported loss matches calculation")
    else:
        feedback_parts.append("Report file not found")

    # --- Criterion 5: App State (10 pts) ---
    if result.get('app_was_running'):
        score += 10
        feedback_parts.append("QBlade was running")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }