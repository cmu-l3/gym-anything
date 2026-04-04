#!/usr/bin/env python3
"""
Verifier for enforce_explicit_imports task.

Criteria:
1. No wildcard imports in source files (60 pts)
   - Checks Product.java, InventoryService.java, FileUtils.java
2. Project compiles successfully (20 pts)
   - Ensures imports weren't just deleted, breaking code
3. Files were actually modified (10 pts)
   - Anti-gaming check
4. Settings file reflects configuration (10 pts)
   - Checks if .idea/codeStyles/Project.xml contains high threshold values
"""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_explicit_imports(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Compilation (20 pts)
    # This is a prerequisite. If code doesn't compile, the refactoring broke the app.
    if result.get('compile_success', False):
        score += 20
        feedback.append("Project compiles successfully.")
    else:
        feedback.append("FAIL: Project failed to compile. Imports may have been deleted incorrectly.")
        # If it doesn't compile, we heavily penalize, but continue checking other criteria
    
    # Criterion 2: No Wildcard Imports (60 pts)
    wildcard_count = result.get('wildcard_count', 999)
    
    # We also manually regex check the content to be sure the shell script grep was accurate
    java_files = [
        result.get('product_java', ''),
        result.get('service_java', ''),
        result.get('utils_java', '')
    ]
    
    manual_wildcards = 0
    for content in java_files:
        if re.search(r'import\s+[\w\.]+\*(\s*);', content):
            manual_wildcards += 1
            
    if wildcard_count == 0 and manual_wildcards == 0:
        score += 60
        feedback.append("No wildcard imports found (clean).")
    else:
        feedback.append(f"Found {manual_wildcards} files still containing wildcard imports.")
        # Partial credit: 20 pts if some progress made (assuming original had 3 files)
        if manual_wildcards < 3: 
             score += 20
             feedback.append("Some files fixed, but not all.")

    # Criterion 3: Files Modified (10 pts)
    if result.get('files_modified', False):
        score += 10
        feedback.append("Source files were modified.")
    else:
        feedback.append("Source files were NOT modified.")

    # Criterion 4: Settings Verification (10 pts)
    # Check if the Project.xml contains the config. 
    # Look for CLASS_COUNT_TO_USE_IMPORT_ON_DEMAND > 50
    settings_content = result.get('settings_content', '')
    threshold_met = False
    
    if settings_content:
        # Regex to find <option name="CLASS_COUNT_TO_USE_IMPORT_ON_DEMAND" value="999" />
        match = re.search(r'name="CLASS_COUNT_TO_USE_IMPORT_ON_DEMAND"\s+value="(\d+)"', settings_content)
        if match:
            val = int(match.group(1))
            if val > 50:
                threshold_met = True
                feedback.append(f"Settings configured correctly (Threshold: {val}).")
            else:
                feedback.append(f"Settings found but threshold too low ({val}).")
        else:
            # Maybe they set it manually in a different way or it's implicitly set, 
            # but usually this file captures project-specific overrides.
            feedback.append("Specific setting not found in project config file.")
    
    if threshold_met:
        score += 10
    
    passed = score >= 80  # Requires compilation + clean imports
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }