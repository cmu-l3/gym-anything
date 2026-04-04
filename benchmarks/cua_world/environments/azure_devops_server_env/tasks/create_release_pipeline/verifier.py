#!/usr/bin/env python3
"""
Verifier for create_release_pipeline task.
Validates the structure of the created Release Pipeline in Azure DevOps.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_release_pipeline(traj, env_info, task_info):
    """
    Verify the Azure DevOps release pipeline configuration.
    
    Criteria:
    1. Pipeline 'Tailwind-CD' exists (10 pts)
    2. Linked to 'Tailwind-CI' build artifact (10 pts)
    3. Continuous Deployment trigger enabled (20 pts)
    4. Two stages 'Staging' and 'Production' exist in correct order (20 pts)
    5. 'Production' has pre-deployment approval configured (25 pts)
    6. All stages have valid tasks defined (15 pts)
    
    Bonus: Pipeline created during task session (checked via timestamp).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_path = r"C:\Users\Docker\task_results\release_pipeline_result.json"
    
    # Temp file for extraction
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env(remote_path, temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not generated. Task execution failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

    score = 0
    feedback = []
    
    # 1. Pipeline Exists
    if result.get("pipeline_exists") and result.get("pipeline_name_match"):
        score += 10
        feedback.append("Pipeline 'Tailwind-CD' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Pipeline 'Tailwind-CD' not found."}

    # 2. Artifact Linked
    if result.get("artifact_linked"):
        score += 10
        feedback.append("Artifact 'Tailwind-CI' linked correctly.")
    else:
        feedback.append("Artifact not linked or incorrect source.")

    # 3. CD Trigger
    if result.get("cd_trigger_enabled"):
        score += 20
        feedback.append("Continuous Deployment trigger enabled.")
    else:
        feedback.append("CD trigger NOT enabled.")

    # 4. Stages (Environments)
    stages = result.get("stages_found", [])
    stage_names = [s.get("name") for s in stages]
    
    has_staging = "Staging" in stage_names
    has_prod = "Production" in stage_names
    
    # Check order (Rank)
    order_correct = False
    if has_staging and has_prod:
        staging_rank = next(s["rank"] for s in stages if s["name"] == "Staging")
        prod_rank = next(s["rank"] for s in stages if s["name"] == "Production")
        if prod_rank > staging_rank:
            order_correct = True
    
    if has_staging and has_prod and order_correct:
        score += 20
        feedback.append("Stages 'Staging' -> 'Production' configured correctly.")
    elif has_staging and has_prod:
        score += 10
        feedback.append("Stages exist but order might be wrong.")
    else:
        feedback.append(f"Missing required stages. Found: {stage_names}")

    # 5. Approvals
    if result.get("approvals_configured"):
        score += 25
        feedback.append("Pre-deployment approval configured on Production.")
    else:
        feedback.append("Pre-deployment approval MISSING on Production.")

    # 6. Tasks Defined
    if result.get("tasks_defined") and len(stages) >= 2:
        score += 15
        feedback.append("Deployment tasks added to stages.")
    else:
        feedback.append("One or more stages have no tasks defined.")

    # Anti-gaming check (Soft check, doesn't zero score but notes it)
    if not result.get("created_during_task"):
        feedback.append("(Warning: Pipeline creation timestamp predates task start)")

    final_feedback = " | ".join(feedback)
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": final_feedback
    }