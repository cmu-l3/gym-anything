#!/usr/bin/env python3
"""
Verifier for optimize_pipeline_triggers task.
Evaluates the YAML content of azure-pipelines.yml to ensure triggers are optimized.
"""

import json
import os
import tempfile
import logging
import yaml  # PyYAML is standard in these environments

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_pipeline_triggers(traj, env_info, task_info):
    """
    Verify that the pipeline triggers include specific path exclusions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path inside VM
        copy_from_env("C:/Users/Docker/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if file exists and commit was made (Anti-gaming: 10 pts)
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "azure-pipelines.yml deleted or missing"}
    
    if result.get('new_commit_made', False):
        score += 10
        feedback_parts.append("New commit created")
    else:
        feedback_parts.append("No new commit detected")

    # 2. Parse YAML (20 pts)
    yaml_content = result.get('yaml_content', '')
    try:
        pipeline_def = yaml.safe_load(yaml_content)
        if not pipeline_def:
            raise ValueError("Empty YAML")
        score += 20
        feedback_parts.append("Valid YAML syntax")
    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Invalid YAML syntax: {e} | " + " | ".join(feedback_parts)
        }

    # 3. Analyze Trigger Structure
    trigger = pipeline_def.get('trigger')
    
    # Trigger can be a simple list of branches ['main'] or a dict/complex object
    # We need to normalize it for checking
    
    if not trigger:
        feedback_parts.append("Trigger section missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    # If trigger is just a list (e.g., ['main']), it has no paths/exclude, so that's a fail
    if isinstance(trigger, list):
        feedback_parts.append("Trigger is simple list (no exclusions configured)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check for paths section (20 pts)
    paths = trigger.get('paths')
    if paths and isinstance(paths, dict) and 'exclude' in paths:
        score += 20
        feedback_parts.append("Path exclusion block found")
        
        exclusions = paths['exclude']
        if isinstance(exclusions, str): 
            exclusions = [exclusions] # Normalize to list
            
        # Check README exclusion (25 pts)
        readme_excluded = any('readme' in x.lower() for x in exclusions)
        if readme_excluded:
            score += 25
            feedback_parts.append("README.md excluded")
        else:
            feedback_parts.append("README.md NOT excluded")

        # Check docs exclusion (25 pts)
        docs_excluded = any('docs' in x.lower() for x in exclusions)
        if docs_excluded:
            score += 25
            feedback_parts.append("docs/ directory excluded")
        else:
            feedback_parts.append("docs/ directory NOT excluded")
            
    else:
        feedback_parts.append("No 'paths: exclude:' section found in trigger")

    # Final check: Ensure 'branches' or 'include' still covers main
    # Complex triggers often look like:
    # trigger:
    #   branches:
    #     include: [main]
    #   paths: ...
    branches_ok = True
    if isinstance(trigger, dict):
        branches = trigger.get('branches')
        if branches:
            # Check if it covers main
            if isinstance(branches, dict):
                includes = branches.get('include', [])
                if 'main' not in includes:
                    branches_ok = False
        # If 'branches' key is missing but trigger is a dict, it defaults to all branches usually, 
        # or it might be mixed syntax. If the agent kept 'branches' section, we give credit.
    
    if not branches_ok:
        feedback_parts.append("WARNING: Main branch trigger might be lost")
        # We don't deduct heavily unless it's clearly broken, as syntax varies.

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }