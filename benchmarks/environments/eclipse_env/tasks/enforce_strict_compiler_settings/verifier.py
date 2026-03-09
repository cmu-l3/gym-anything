#!/usr/bin/env python3
"""Verifier for enforce_strict_compiler_settings task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_strict_compiler_settings(traj, env_info, task_info):
    """Verify that Eclipse compiler settings were updated correctly.

    Criteria:
    1. Project settings file exists (10 pts)
    2. Settings file was modified during task (20 pts)
    3. Resource leak is set to 'error' (35 pts)
    4. Potential null pointer access is set to 'error' (35 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/RadiationPlanningCore')
    prefs_rel_path = metadata.get('prefs_file', '.settings/org.eclipse.jdt.core.prefs')
    prefs_remote_path = f"{project_dir}/{prefs_rel_path}"

    score = 0
    feedback_parts = []

    # Helper to copy file
    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # Helper to load properties
    def parse_properties(content):
        props = {}
        if not content:
            return props
        for line in content.splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                key, value = line.split('=', 1)
                props[key.strip()] = value.strip()
        return props

    # Load export result for timing info
    task_result_json = copy_and_read("/tmp/task_result.json")
    task_result = {}
    if task_result_json:
        try:
            task_result = json.loads(task_result_json)
        except json.JSONDecodeError:
            pass

    # Read the actual preferences file
    prefs_content = copy_and_read(prefs_remote_path)
    
    # Check 1: File Existence (10 pts)
    if prefs_content:
        score += 10
        feedback_parts.append("Preferences file exists")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Preferences file not found. Did you enable 'Project specific settings'?"
        }

    # Check 2: Modification during task (20 pts)
    # We rely on the export script's check or could compare timestamps if we had them here.
    # The export script populates 'prefs_modified'
    if task_result.get('prefs_modified', False):
        score += 20
        feedback_parts.append("Settings modified during task")
    else:
        feedback_parts.append("WARNING: Settings file timestamp indicates no change during task")

    # Parse properties
    props = parse_properties(prefs_content)
    
    # Check 3: Resource Leak (35 pts)
    resource_leak_key = "org.eclipse.jdt.core.compiler.problem.resourceLeak"
    val_leak = props.get(resource_leak_key, "").lower()
    
    if val_leak == "error":
        score += 35
        feedback_parts.append("Resource leak set to ERROR")
    elif val_leak:
        feedback_parts.append(f"Resource leak set to '{val_leak}' (expected 'error')")
    else:
        feedback_parts.append("Resource leak setting not found")

    # Check 4: Potential Null Pointer (35 pts)
    null_key = "org.eclipse.jdt.core.compiler.problem.potentialNullReference"
    val_null = props.get(null_key, "").lower()
    
    if val_null == "error":
        score += 35
        feedback_parts.append("Null pointer access set to ERROR")
    elif val_null:
        feedback_parts.append(f"Null pointer access set to '{val_null}' (expected 'error')")
    else:
        feedback_parts.append("Null pointer setting not found")

    # VLM Verification (Bonus/Confirmation)
    # If the file checks fail or are ambiguous, VLM can help, 
    # but for this config task, file state is the ground truth.
    # We'll use VLM just to ensure the UI was interacted with if score is borderline.
    
    final_passed = score >= 100
    
    return {
        "passed": final_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }