#!/usr/bin/env python3
"""
Verifier for add_exception_handling task.
Checks:
1. Compilation success (0 errors).
2. No empty catch blocks.
3. Usage of try-with-resources.
4. Usage of exception chaining.
5. VLM verification of trajectory.
"""

import json
import re
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exception_handling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy access failed"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Compilation (30 pts) ---
    compilation_success = result.get("compilation_success", False)
    if compilation_success:
        score += 30
        feedback.append("Compilation successful (+30)")
    else:
        errors = result.get("compilation_output", "")[:200]
        feedback.append(f"Compilation failed: {errors}...")

    # Files data
    files = result.get("files", {})
    fp_content = files.get("FileProcessor.java", {}).get("content", "")
    db_content = files.get("DatabaseConnector.java", {}).get("content", "")
    cp_content = files.get("ConfigParser.java", {}).get("content", "")
    app_content = files.get("App.java", {}).get("content", "")
    
    all_content = fp_content + db_content + cp_content + app_content

    # --- Criterion 2: No Empty Catch Blocks (15 pts) ---
    # Pattern looks for catch(...) { } with only whitespace or comments
    # Regex explanations:
    # catch\s*\(.*?\)\s*\{  -> matches 'catch (...){'
    # [^\}]*?               -> non-greedy match of body
    # \}                    -> closing brace
    # We strip comments before check or use sophisticated regex. 
    # Simplified check: Look for "catch (...) {}" literal or with whitespace
    empty_catch_pattern = re.compile(r'catch\s*\([^)]+\)\s*\{\s*\}')
    
    if empty_catch_pattern.search(all_content):
        feedback.append("Found empty catch blocks (FAIL)")
    else:
        score += 15
        feedback.append("No empty catch blocks found (+15)")

    # --- Criterion 3: Try-with-resources (15 pts) ---
    # Look for try (Type var = ...) in FileProcessor or ConfigParser
    twr_pattern = re.compile(r'try\s*\([^\)]+=\s*new\s+')
    
    twr_count = 0
    if twr_pattern.search(fp_content): twr_count += 1
    if twr_pattern.search(cp_content): twr_count += 1
    
    if twr_count >= 1:
        score += 15
        feedback.append("Try-with-resources usage detected (+15)")
    else:
        feedback.append("Try-with-resources not found in FileProcessor/ConfigParser")

    # --- Criterion 4: Exception Chaining (15 pts) ---
    # Look for: new ProcessingException(..., e) or new ProcessingException(e)
    # where 'e' is a variable name (usually from catch)
    chaining_pattern = re.compile(r'new\s+ProcessingException\s*\([^\)]*,\s*[a-zA-Z0-9_]+\s*\)')
    cause_pattern = re.compile(r'new\s+ProcessingException\s*\(\s*[a-zA-Z0-9_]+\s*\)')
    
    chaining_found = 0
    for content in [fp_content, db_content, cp_content]:
        if chaining_pattern.search(content) or cause_pattern.search(content):
            chaining_found += 1
            
    if chaining_found >= 2:
        score += 15
        feedback.append(f"Exception chaining found in {chaining_found} files (+15)")
    elif chaining_found == 1:
        score += 7
        feedback.append("Exception chaining found in 1 file (+7)")
    else:
        feedback.append("Exception chaining not found")

    # --- Criterion 5: App.java Top-level Handler (10 pts) ---
    if "catch" in app_content and "ProcessingException" in app_content:
        # Simple check if main captures it
        if re.search(r'catch\s*\(\s*ProcessingException', app_content):
            score += 10
            feedback.append("Top-level handler found in App.java (+10)")
    
    # --- Criterion 6: Modification Check (5 pts) ---
    files_modified = sum(1 for f in files.values() if f.get("modified", False))
    if files_modified >= 4:
        score += 5
        feedback.append("All files modified (+5)")
    
    # --- Criterion 7: VLM Verification (10 pts) ---
    if query_vlm:
        frames = sample_trajectory_frames(traj, num_samples=5)
        
        prompt = """
        You are verifying an Eclipse IDE task. 
        Goal: The user should be writing Java code to fix exception handling.
        
        Look at the screenshots. 
        1. Do you see the Eclipse IDE?
        2. Do you see Java code being edited (look for 'try', 'catch', 'throw')?
        3. Do you see the 'Problems' view (list of errors) decreasing or being empty at the end?
        
        Answer JSON: {"ide_visible": bool, "code_edited": bool, "problems_resolved": bool}
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("ide_visible") and parsed.get("code_edited"):
                score += 10
                feedback.append("VLM confirmed coding activity (+10)")
            else:
                feedback.append("VLM did not see coding activity")
    
    # Final Pass logic
    passed = (compilation_success and score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }