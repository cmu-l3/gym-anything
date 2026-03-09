#!/usr/bin/env python3
"""Verifier for configure_task_tags_workflow task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_task_tags_workflow(traj, env_info, task_info):
    """
    Verify that the agent:
    1. Configured custom task tags (SECURITY=High, PERF=Low).
    2. Removed the specific backdoor code block from UserDAO.java.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    backdoor_sig = metadata.get('backdoor_signature', 'if ("superuser".equals(username))')

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Task Tags Configuration (40 points) ---
    prefs_content = result.get('prefs_content', '')
    prefs_dict = {}
    
    # Parse prefs line by line manually
    for line in prefs_content.splitlines():
        if '=' in line:
            key, val = line.split('=', 1)
            prefs_dict[key.strip()] = val.strip()

    task_tags = prefs_dict.get('org.eclipse.jdt.core.compiler.taskTags', '')
    task_priorities = prefs_dict.get('org.eclipse.jdt.core.compiler.taskPriorities', '')
    
    tags_list = [t.strip() for t in task_tags.split(',') if t.strip()]
    priorities_list = [p.strip() for p in task_priorities.split(',') if p.strip()]
    
    # Check if lists align
    if len(tags_list) != len(priorities_list):
        feedback_parts.append("WARNING: Tags and Priorities count mismatch in prefs")
    
    # Map tags to priorities
    tag_map = {}
    for i, tag in enumerate(tags_list):
        if i < len(priorities_list):
            tag_map[tag] = priorities_list[i]
            
    # Verify SECURITY -> HIGH
    if 'SECURITY' in tag_map:
        if tag_map['SECURITY'] == 'HIGH':
            score += 25
            feedback_parts.append("Tag 'SECURITY' configured as HIGH")
        else:
            score += 10
            feedback_parts.append(f"Tag 'SECURITY' found but priority is {tag_map['SECURITY']} (expected HIGH)")
    else:
        feedback_parts.append("Tag 'SECURITY' not found")
        
    # Verify PERF -> LOW
    if 'PERF' in tag_map:
        if tag_map['PERF'] == 'LOW':
            score += 15
            feedback_parts.append("Tag 'PERF' configured as LOW")
        else:
            score += 5
            feedback_parts.append(f"Tag 'PERF' found but priority is {tag_map['PERF']} (expected LOW)")
    else:
        feedback_parts.append("Tag 'PERF' not found")

    # --- Criterion 2: Backdoor Removal (40 points) ---
    userdao_content = result.get('userdao_content', '')
    
    if userdao_content:
        # Check if backdoor signature is GONE
        if backdoor_sig not in userdao_content:
            # Check if main logic is still there (don't delete whole file)
            if "checkCredentialsInDb" in userdao_content and "public class UserDAO" in userdao_content:
                score += 40
                feedback_parts.append("Backdoor code block removed successfully")
            else:
                score += 5
                feedback_parts.append("Backdoor gone, but file seems corrupted/emptied")
        else:
            feedback_parts.append("Backdoor code block still present")
    else:
        feedback_parts.append("UserDAO.java not found or empty")

    # --- Criterion 3: Project Compilation (10 points) ---
    # We trust the export script's check of class file existence or compilation state
    # But strictly, if we removed code and it compiles, that's good.
    if result.get('compilation_success'):
        score += 10
        feedback_parts.append("Project compiles")
    elif userdao_content and "}" not in userdao_content: # Crude syntax check if compile check fails
         feedback_parts.append("Project compilation failed (syntax error?)")
    else:
        # If compilation failed but file looks decent, give partial points
        if score >= 40: 
            score += 5
            feedback_parts.append("Compilation check failed (partial credit)")

    # --- Criterion 4: VLM / Workflow Verification (10 points) ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Configure 'SECURITY' (High) and 'PERF' (Low) task tags, open Tasks view, and remove backdoor code.",
            checklist_items=[
                "Project Properties dialog opened",
                "Java Compiler > Task Tags settings visible",
                "Tasks view opened/visible",
                "Code editor showing UserDAO.java",
                "Backdoor code removal performed"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            score += 10
            feedback_parts.append("VLM: Workflow verification passed")
        else:
            feedback_parts.append(f"VLM: {vlm_result.get('vlm_feedback', 'Workflow not clearly verified')}")
            
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        # If VLM fails but file changes are correct, assume they did it blindly (e.g. via shortcuts) and give 5 pts
        if score >= 60:
            score += 5
            feedback_parts.append("VLM skipped, partial workflow points")

    # Final tally
    final_score = min(score, 100)
    passed = final_score >= 75
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }