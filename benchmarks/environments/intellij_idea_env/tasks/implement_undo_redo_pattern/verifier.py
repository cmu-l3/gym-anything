#!/usr/bin/env python3
"""
Verifier for Implement Undo/Redo Pattern task.
Verifies file structure, compilation, logic (via output), and VLM trajectory.
"""

import json
import tempfile
import os
import re
import logging
import sys

# Import shared VLM utils
sys.path.append("/workspace/utils")
try:
    from intellij_verification_utils import vlm_verify_intellij_task
except ImportError:
    vlm_verify_intellij_task = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_undo_redo(traj, env_info, task_info):
    """
    Verifies the undo/redo task implementation.
    
    Scoring:
    1. File Creation & Structure (25 pts): All 5 required command classes exist.
    2. Compilation (25 pts): Project compiles successfully.
    3. Output Verification (25 pts): output.txt demonstrates undo/redo logic.
    4. Code Quality/Logic (10 pts): Interfaces implemented correctly (via regex check).
    5. VLM Verification (15 pts): Trajectory shows active development.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    score = 0
    feedback = []
    
    # Load result JSON
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. File Creation (25 pts)
    files = result.get('files', {})
    required_files = [
        'Command.java', 'InsertCommand.java', 'DeleteCommand.java', 
        'ReplaceCommand.java', 'CommandHistory.java'
    ]
    
    files_found = 0
    for fname in required_files:
        status = files.get(fname, 'false')
        if status == 'true':
            files_found += 1
        elif status == 'old':
            feedback.append(f"⚠️ {fname} was not modified from initial state")
        else:
            feedback.append(f"❌ {fname} is missing")

    if files_found == len(required_files):
        score += 25
        feedback.append("✅ All required files created")
    else:
        file_score = int(25 * (files_found / len(required_files)))
        score += file_score
        feedback.append(f"⚠️ Created {files_found}/{len(required_files)} required files")

    # 2. Compilation (25 pts)
    if result.get('compilation_success', False):
        score += 25
        feedback.append("✅ Project compiles successfully")
    else:
        feedback.append("❌ Project compilation failed")

    # 3. Output Verification (25 pts)
    # Expected: "After operations", "After undo", "After redo" logic check
    output_content = result.get('output_content', '')
    if output_content and result.get('output_created_during_task'):
        logic_score = 0
        
        # Check for non-empty output
        if len(output_content.strip()) > 50:
            logic_score += 5
        
        # Check for keywords indicating success
        lower_content = output_content.lower()
        if "undo" in lower_content:
            logic_score += 10
            feedback.append("✅ Output shows undo operations")
        if "redo" in lower_content:
            logic_score += 10
            feedback.append("✅ Output shows redo operations")
            
        score += logic_score
    else:
        feedback.append("❌ output.txt missing or empty")

    # 4. Code Logic Check (10 pts)
    # We verify Command.java is an interface and implementation classes use 'implements'
    try:
        project_dir = task_info['metadata']['project_dir']
        cmd_path = f"{project_dir}/src/main/java/com/editor/command"
        
        # Helper to read remote file
        def read_remote(path):
            t = tempfile.NamedTemporaryFile(delete=False)
            copy_from_env(path, t.name)
            with open(t.name, 'r') as f: c = f.read()
            os.unlink(t.name)
            return c

        command_code = read_remote(f"{cmd_path}/Command.java")
        insert_code = read_remote(f"{cmd_path}/InsertCommand.java")
        
        if "interface Command" in command_code:
            score += 5
        if "implements Command" in insert_code:
            score += 5
            
    except Exception:
        # Fail silently if files don't exist (points already lost in step 1)
        pass

    # 5. VLM Verification (15 pts)
    if vlm_verify_intellij_task:
        vlm_out = vlm_verify_intellij_task(
            traj, env_info, 
            task_description=task_info['description'],
            checklist_items=[
                "Project explorer shows 'command' package with multiple files",
                "Editor shows Java code with 'Command' interface or implementation",
                "Console output shows successful build or execution",
                "No visible red syntax error squiggles in the final state"
            ]
        )
        if vlm_out:
            vlm_score = vlm_out.get('vlm_score', 0)
            score += int(vlm_score * 0.15) # Scale 0-100 to 0-15
            feedback.append(f"VLM Analysis: {vlm_out.get('vlm_feedback')}")
    else:
        # Fallback if VLM not available: give full points if compilation passed
        if result.get('compilation_success', False):
            score += 15
            feedback.append("VLM unavailable, assumed pass due to successful compile")

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": "\n".join(feedback)
    }