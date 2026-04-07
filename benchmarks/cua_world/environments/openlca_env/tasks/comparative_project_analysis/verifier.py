#!/usr/bin/env python3
"""
Verifier for Comparative Project Analysis task.

Task Requirements:
1. Create Global Parameter 'transport_tkm'.
2. Create Process using this parameter for transport input.
3. Create Project 'Sand_Sourcing_Comparison'.
4. Define 3 Variants (Local=20, Regional=200, National=800).
5. Run & Export Report.

Scoring (100 pts):
- Project Entity Created (25 pts)
- Variants Defined (25 pts) - check count >= 3
- Parameter Usage (20 pts) - check parameter exists and is used in formula
- Variant Values Verified (10 pts) - check DB for 20/200/800
- Report Exported (10 pts) - file check
- VLM Trajectory (10 pts) - visual confirmation of Project/Variant tab usage
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# VLM Prompts
TRAJECTORY_PROMPT = """You are verifying an openLCA task where an agent must create a Project with Variants.

Look for these key screens in the screenshot sequence:
1. **Parameters Tab**: Creating a global parameter named 'transport_tkm'.
2. **Process Editor**: Adding a transport flow and typing 'transport_tkm' into the Amount/Formula field.
3. **Project Tab**: A tab labeled 'Project: Sand_Sourcing_Comparison'.
4. **Variants Section**: A table in the Project tab showing 'Local', 'Regional', 'National' with values 20, 200, 800.
5. **Report/Export**: A report generation dialog or the resulting report.

Assess:
- PARAMETER_CREATED: Did you see the parameter creation?
- PROJECT_CREATED: Is the Project tab visible?
- VARIANTS_DEFINED: Are distinct variants visible in the project table?
- REPORT_GENERATED: Is there evidence of report export?

Return JSON:
{
  "parameter_created": true/false,
  "project_created": true/false,
  "variants_defined": true/false,
  "report_generated": true/false,
  "confidence": "low"/"medium"/"high"
}"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_comparative_project_analysis(traj, env_info, task_info):
    """Verify Comparative Project Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Project Entity Created (25 pts)
    if result.get("project_found", False):
        score += 25
        feedback.append("Project 'Sand_Sourcing_Comparison' found in database.")
    else:
        feedback.append("Project entity not found in database.")

    # 2. Variants Defined (25 pts)
    variant_count = result.get("variant_count", 0)
    try:
        variant_count = int(variant_count)
    except:
        variant_count = 0
        
    if variant_count >= 3:
        score += 25
        feedback.append(f"Found {variant_count} variants (>=3 required).")
    elif variant_count > 0:
        score += 10
        feedback.append(f"Found only {variant_count} variants (3 required).")
    else:
        feedback.append("No variants found in project.")

    # 3. Parameter Usage (20 pts)
    param_found = result.get("parameter_found", False)
    param_used = result.get("parameter_usage_count", 0)
    try:
        param_used = int(param_used)
    except:
        param_used = 0

    if param_found:
        score += 10
        feedback.append("Global parameter 'transport_tkm' found.")
        if param_used > 0:
            score += 10
            feedback.append("Parameter is correctly used in a process formula.")
        else:
            feedback.append("Parameter exists but not used in any process formulas.")
    else:
        feedback.append("Global parameter 'transport_tkm' not found.")

    # 4. Variant Values Verified (10 pts)
    if result.get("variants_values_verified", False):
        score += 10
        feedback.append("Variant values (20, 200, 800) verified in database.")
    else:
        feedback.append("Could not verify exact variant values in database.")

    # 5. Report Exported (10 pts)
    if result.get("report_created_during_task", False) and result.get("report_size", 0) > 1000:
        score += 10
        feedback.append("Report file exported successfully.")
    else:
        feedback.append("No valid report file exported.")

    # 6. VLM Verification (10 pts)
    # Check trajectory for visual confirmation
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Sample frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, 5)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get("project_created") and vlm_res.get("variants_defined"):
                score += 10
                feedback.append("VLM confirmed project and variant creation workflow.")
            elif vlm_res.get("project_created"):
                score += 5
                feedback.append("VLM confirmed project creation.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }