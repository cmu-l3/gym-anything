#!/usr/bin/env python3
"""
Verifier for configure_save_actions task.

Verification Strategy:
1. Configuration Check (40 pts):
   - Verify .settings/org.eclipse.jdt.ui.prefs contains the correct keys to enable
     Save Actions, Formatting, Organize Imports, and Trailing Whitespace removal.
2. Functional Check (40 pts):
   - Verify MessyService.java was actually modified.
   - Verify 'java.util.Vector' (unused import) is removed.
   - Verify indentation is corrected (no weird 1-space indentation).
   - Verify trailing whitespace is removed.
3. VLM Check (20 pts):
   - Visual confirmation that Eclipse was used and the file looks clean.
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_save_actions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    result = {}
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
    
    # Extract data
    prefs_content = result.get('prefs_content', '')
    source_content = result.get('source_content', '')
    file_modified = result.get('file_modified', False)

    # --- Criterion 1: Configuration Check (40 pts) ---
    # We look for specific Eclipse preference keys. 
    # Note: Exact keys can vary slightly by Eclipse version, so we look for substrings.
    
    config_score = 0
    
    # 1. Save actions enabled
    if 'sp_cleanup.on_save=true' in prefs_content or 'editor_save_participant' in prefs_content:
        config_score += 10
        feedback_parts.append("Save actions enabled")
    else:
        feedback_parts.append("Save actions NOT enabled in prefs")

    # 2. Format source code
    if 'sp_cleanup.format_source_code=true' in prefs_content:
        config_score += 10
        feedback_parts.append("Auto-format enabled")
    else:
        feedback_parts.append("Auto-format NOT enabled")

    # 3. Organize imports
    if 'sp_cleanup.organize_imports=true' in prefs_content:
        config_score += 10
        feedback_parts.append("Organize imports enabled")
    else:
        feedback_parts.append("Organize imports NOT enabled")

    # 4. Remove trailing whitespace
    # Key usually involves 'remove_trailing_whitespaces'
    if 'remove_trailing_whitespaces=true' in prefs_content:
        config_score += 10
        feedback_parts.append("Remove trailing whitespace enabled")
    else:
        feedback_parts.append("Remove trailing whitespace NOT enabled")

    score += config_score

    # --- Criterion 2: Functional Check (40 pts) ---
    func_score = 0
    
    if not file_modified:
        feedback_parts.append("FAIL: File was not modified (did you save?)")
    else:
        # 1. Check Unused Import (Vector)
        if 'java.util.Vector' not in source_content:
            func_score += 10
            feedback_parts.append("Unused import removed")
        else:
            feedback_parts.append("Unused import (Vector) still present")

        # 2. Check Indentation
        # The messy file had lines like "     System.out.println" (5 spaces) and "    System.out.println" (4 spaces, but weirdly placed)
        # A formatted file should typically have consistent 4-space or tab indentation.
        # We check that the specific messy patterns are gone.
        if '     if(data==null){' not in source_content and '   private String' not in source_content:
            func_score += 15
            feedback_parts.append("Indentation corrected")
        else:
            feedback_parts.append("Indentation still looks messy")

        # 3. Check Trailing Whitespace
        # We look for lines ending in space
        has_trailing = False
        for line in source_content.splitlines():
            if len(line) > 0 and line[-1].isspace():
                # Be careful not to count empty lines that are just a newline char (splitlines handles \n)
                # But line ending in space ' ' or tab '\t' is bad.
                if line.endswith(' ') or line.endswith('\t'):
                    has_trailing = True
                    break
        
        if not has_trailing:
            func_score += 15
            feedback_parts.append("Trailing whitespace removed")
        else:
            feedback_parts.append("Trailing whitespace detected")

    score += func_score

    # --- Criterion 3: VLM Verification (20 pts) ---
    # If the functional check passed, we have high confidence. 
    # We use VLM to ensure the agent didn't just run a script but used the GUI.
    try:
        from utils.eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Configure Eclipse Save Actions to format code and organize imports on save",
            checklist_items=[
                "Eclipse Project Properties dialog is visible",
                "Save Actions page is selected",
                "Enable project specific settings is checked",
                "Perform the following actions on save is checked",
                "MessyService.java is open in the editor"
            ]
        )
        
        if vlm_result:
            vlm_score = vlm_result.get('vlm_score', 0)
            score += (vlm_score * 0.2)  # Max 20 points
            feedback_parts.append(f"VLM: {vlm_result.get('vlm_feedback', '')}")
        else:
            # Fallback if VLM unavailable but functional passed
            if func_score >= 30:
                score += 20
                feedback_parts.append("VLM skipped, awarded points based on functional success")

    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # If functional checks passed, give benefit of doubt
        if func_score >= 30:
            score += 20
            feedback_parts.append("VLM error, points awarded based on functional success")

    return {
        "passed": score >= 75,
        "score": min(int(score), 100),
        "feedback": " | ".join(feedback_parts)
    }