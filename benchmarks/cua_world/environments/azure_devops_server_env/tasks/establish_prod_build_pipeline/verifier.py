#!/usr/bin/env python3
"""
Verifier for establish_prod_build_pipeline task.

Checks:
1. 'TailwindTraders-Prod' pipeline exists.
2. 'TailwindTraders-Dev-CI' pipeline still exists.
3. Prod pipeline variable 'buildConfiguration' == 'release'.
4. Prod pipeline CI trigger is disabled.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_establish_prod_build_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    remote_path = r"C:\Users\Docker\task_results\task_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env(remote_path, temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or read result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not retrieve task results. Ensure export script ran successfully."
        }
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # Analyze Data
    definitions = result_data.get("definitions", [])
    
    prod_def = None
    dev_def = None
    
    for d in definitions:
        name = d.get("name", "")
        if name == "TailwindTraders-Prod":
            prod_def = d
        elif name == "TailwindTraders-Dev-CI":
            dev_def = d

    # Criterion 1: Prod Pipeline Exists (30 pts)
    if not prod_def:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Pipeline 'TailwindTraders-Prod' was not found."
        }
    
    score = 30
    feedback = ["Pipeline 'TailwindTraders-Prod' created."]

    # Criterion 2: Dev Pipeline Preserved (10 pts)
    if dev_def and dev_def.get("id") != prod_def.get("id"):
        score += 10
        feedback.append("Original pipeline preserved.")
    else:
        feedback.append("Warning: Original pipeline missing or renamed.")

    # Criterion 3: Variable 'buildConfiguration' == 'release' (30 pts)
    variables = prod_def.get("variables", {})
    build_config_var = variables.get("buildConfiguration", {})
    val = build_config_var.get("value", "").lower()
    
    if val == "release":
        score += 30
        feedback.append("Variable 'buildConfiguration' set to 'release'.")
    else:
        feedback.append(f"Variable 'buildConfiguration' incorrect. Expected 'release', found '{val}'.")

    # Criterion 4: CI Trigger Disabled (30 pts)
    # Check 1: triggers array
    triggers = prod_def.get("triggers", [])
    
    ci_enabled = False
    for t in triggers:
        if t.get("triggerType") == "continuousIntegration":
            # If batchChanges is false and not explicitly disabled, it might be active
            # However, usually there's no 'enabled' flag in the JSON for CI triggers explicitly
            # The presence of the trigger object implies it's enabled UNLESS specific settings say otherwise.
            # BUT, usually 'Disable CI' removes the trigger object or sets settingsSourceType to 2 (if yaml) 
            # and yaml has triggers: none.
            # If UI override is used to disable, the triggers array might be empty or missing CI type.
            
            # If the user strictly "Disables" it in UI overrides for YAML pipelines, ADO adds a trigger 
            # definition with settingsSourceType = 1 (UI) and batchChanges=False? No.
            
            # Robust check: If 'continuousIntegration' trigger is PRESENT, it is ENABLED.
            # So we want it to be ABSENT or strictly filtered to nothing.
            ci_enabled = True

            # Check for explicit disablement properties if they exist in this ADO version
            # (ADO Server 2022 might behave differently, but generally presence = on)
            break
            
    # NOTE: If the pipeline is YAML-based, ADO returns triggers from YAML. 
    # If the user checks "Override YAML triggers", it uses the UI triggers.
    # If they uncheck "Enable continuous integration" in UI override, the API response 
    # typically reflects the effective triggers or the overridden config.
    
    # We give points if NO continuousIntegration trigger is found, 
    # OR if queueStatus is 'disabled' (though that disables manual too).
    
    if not ci_enabled:
        score += 30
        feedback.append("CI trigger disabled.")
    else:
        # Check if settingsSourceType indicates overriding to 'None' effectively?
        # If the agent simply didn't do it, ci_enabled will be True (inherited from clone).
        feedback.append("CI trigger appears to be enabled.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }