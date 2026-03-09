#!/usr/bin/env python3
"""Verifier for reformat_optimize_codebase task."""

import json
import tempfile
import os
import re
import logging
import sys

# Import VLM utilities (assuming environment has this available in path or parallel dir)
sys.path.insert(0, "/workspace/utils")
try:
    from intellij_verification_utils import vlm_verify_intellij_task
except ImportError:
    # Fallback if module not found
    def vlm_verify_intellij_task(*args, **kwargs):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reformat_optimize_codebase(traj, env_info, task_info):
    """Verify that code was reformatted and imports optimized.

    Criteria:
    1. Files modified (anti-gaming) (10 pts)
    2. No tab characters (15 pts)
    3. Consistent 4-space indentation (15 pts)
    4. No wildcard imports (15 pts)
    5. No unused imports (15 pts)
    6. No trailing whitespace (10 pts)
    7. No excessive blank lines (5 pts)
    8. Compilation success (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    files_to_check = metadata.get('files_to_check', [])
    forbidden_imports = metadata.get('forbidden_imports', [])

    score = 0
    feedback_parts = []
    
    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}

    files_data = result.get('files', {})
    compilation = result.get('compilation', {})

    # --- Criterion 1: Files Modified (10 pts) ---
    modified_count = 0
    for fname, data in files_data.items():
        if data.get('modified', False):
            modified_count += 1
    
    if modified_count >= 4:
        score += 10
        feedback_parts.append(f"Files modified ({modified_count}/5)")
    elif modified_count > 0:
        score += 5
        feedback_parts.append(f"Some files modified ({modified_count}/5)")
    else:
        feedback_parts.append("No files modified (do-nothing check)")

    if modified_count == 0:
         return {"passed": False, "score": 0, "feedback": "No files were modified."}

    # --- Content Verification ---
    tabs_score = 15
    indent_score = 15
    wildcard_score = 15
    unused_score = 15
    trailing_score = 10
    blank_lines_score = 5

    total_files = len(files_to_check)
    if total_files == 0: total_files = 1 # Avoid div by zero

    # Known unused imports from setup script
    known_unused = [
        "java.awt.Color", "java.io.FileNotFoundException", 
        "java.io.PrintWriter", "java.io.IOException", 
        "java.net.URL", "java.net.MalformedURLException",
        "java.io.File", "java.io.BufferedReader",
        "java.io.InputStreamReader", "java.time.LocalDate"
    ]

    failed_files_tabs = []
    failed_files_indent = []
    failed_files_wildcard = []
    failed_files_unused = []
    failed_files_trailing = []

    for fname in files_to_check:
        if fname not in files_data:
            continue
            
        content = files_data[fname].get('content', '')
        
        # Check tabs
        if '\t' in content:
            failed_files_tabs.append(fname)
            
        # Check indentation (simple heuristic: look for lines starting with odd spaces or non-multiples of 4)
        # We check lines that have at least one space indentation
        lines = content.split('\n')
        bad_indent = False
        for line in lines:
            stripped = line.lstrip()
            if stripped and line != stripped:
                indent = len(line) - len(stripped)
                if indent % 4 != 0 and indent > 1:
                    # Allow continuation indents (often +4 or +8, but some styles use +2 for continuation)
                    # We'll be lenient and just check for 2-space base indent patterns (2, 6, 10...) 
                    # OR check if the majority of the file looks wrong.
                    # Stricter: standard IntelliJ formatter uses 4 spaces.
                    if indent % 4 != 0: 
                        bad_indent = True
                        break
        if bad_indent:
            failed_files_indent.append(fname)

        # Check wildcard imports
        if re.search(r'import\s+[\w.]+\.\*\s*;', content):
            failed_files_wildcard.append(fname)
            
        # Check unused imports
        for unused in known_unused:
            if re.search(r'import\s+' + re.escape(unused) + r'\s*;', content):
                failed_files_unused.append(fname)
                break # count file as failed once
        
        # Check trailing whitespace
        if re.search(r'[ \t]+$', content, re.MULTILINE):
            failed_files_trailing.append(fname)
            
        # Check excessive blank lines (more than 2)
        if re.search(r'\n\s*\n\s*\n\s*\n', content):
            blank_lines_score = 0

    # Calculate scores based on failure counts
    tabs_score -= (len(failed_files_tabs) * 3)
    indent_score -= (len(failed_files_indent) * 3)
    wildcard_score -= (len(failed_files_wildcard) * 3)
    unused_score -= (len(failed_files_unused) * 3)
    trailing_score -= (len(failed_files_trailing) * 2)

    # Clamp scores
    tabs_score = max(0, tabs_score)
    indent_score = max(0, indent_score)
    wildcard_score = max(0, wildcard_score)
    unused_score = max(0, unused_score)
    trailing_score = max(0, trailing_score)

    score += tabs_score + indent_score + wildcard_score + unused_score + trailing_score + blank_lines_score
    
    # Feedback generation
    if tabs_score < 15: feedback_parts.append(f"Tabs found in {len(failed_files_tabs)} files")
    if indent_score < 15: feedback_parts.append(f"Bad indentation in {len(failed_files_indent)} files")
    if wildcard_score < 15: feedback_parts.append(f"Wildcard imports in {len(failed_files_wildcard)} files")
    if unused_score < 15: feedback_parts.append(f"Unused imports in {len(failed_files_unused)} files")
    if trailing_score < 10: feedback_parts.append(f"Trailing whitespace in {len(failed_files_trailing)} files")

    # --- Criterion 8: Compilation (15 pts) ---
    if compilation.get('status') == 'success':
        score += 15
        feedback_parts.append("Compilation successful")
    else:
        feedback_parts.append("Compilation failed")

    # --- VLM Verification (Bonus/Confirmation) ---
    vlm_result = vlm_verify_intellij_task(
        traj,
        env_info,
        "Reformat code and optimize imports in IntelliJ",
        ["Agent used Reformat Code action", "Agent used Optimize Imports action"]
    )
    if vlm_result and vlm_result.get('vlm_passed'):
        # Just logging, score is fully programmatic here for reliability
        logger.info(f"VLM passed: {vlm_result.get('vlm_feedback')}")

    passed = score >= 70 and compilation.get('status') == 'success'
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }