#!/usr/bin/env python3
"""Verifier for Refactor SSR Migration task."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_ssr_migration(traj, env_info, task_info):
    """
    Verify the refactoring of LegacyLogger to FluentLogger.
    
    Criteria:
    1. File Modified: The LogService.java file must have been modified during the task. (10 pts)
    2. Legacy Gone: Zero occurrences of `LegacyLogger.log` remain. (30 pts)
    3. New API Present: High count (>40) of `FluentLogger.at` calls. (30 pts)
    4. Compilation: The project must compile successfully (proves valid syntax). (30 pts)
    
    The task is designed to be difficult to do with simple find/replace due to argument reordering,
    encouraging the use of Structural Search and Replace.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_replacements = metadata.get('min_expected_replacements', 45)

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    file_modified = result.get('file_modified', False)
    legacy_count = result.get('legacy_count', -1)
    fluent_count = result.get('fluent_count', 0)
    compile_success = result.get('compile_success', False)
    file_content = result.get('file_content', "")

    # Criterion 1: Anti-gaming / Action check (10 pts)
    if file_modified:
        score += 10
        feedback_parts.append("File was modified")
    else:
        feedback_parts.append("File was NOT modified")
        return {
            "passed": False,
            "score": 0, 
            "feedback": "No changes detected in LogService.java. Did you save the file?"
        }

    # Criterion 2: Legacy code removed (30 pts)
    if legacy_count == 0:
        score += 30
        feedback_parts.append("All legacy calls removed")
    elif legacy_count > 0:
        # Partial credit if some were removed (assuming starting count ~50)
        # But this is a refactoring task, so strictness is preferred.
        feedback_parts.append(f"{legacy_count} legacy calls still remaining")
    else:
        feedback_parts.append("Could not verify legacy usage count")

    # Criterion 3: New API adopted (30 pts)
    if fluent_count >= min_replacements:
        score += 30
        feedback_parts.append(f"Fluent API adopted ({fluent_count} calls)")
    elif fluent_count > 0:
        # Partial credit
        partial = int(30 * (fluent_count / min_replacements))
        score += partial
        feedback_parts.append(f"Partial adoption of Fluent API ({fluent_count}/{min_replacements} calls)")
    else:
        feedback_parts.append("No Fluent API calls found")

    # Criterion 4: Compilation (30 pts)
    # This is critical because simple regex replace often breaks syntax (missing parens, etc.)
    if compile_success:
        score += 30
        feedback_parts.append("Project compiles successfully")
    else:
        feedback_parts.append("Project compilation FAILED (syntax errors introduced?)")
        if result.get('compile_output'):
            feedback_parts.append(f"Compile error: {result['compile_output'][:100]}...")

    # Optional: content check for correct argument ordering
    # We check if timestamp (long/System.current...) is inside .withTime(...)
    # Heuristic: Find at least one instance of .withTime(System.currentTimeMillis()) or variable
    if file_content and "withTime(" in file_content:
        if re.search(r'\.withTime\([^)]+\)', file_content):
            feedback_parts.append("Argument structure looks correct")
        else:
            feedback_parts.append("Warning: .withTime() found but structure unclear")

    # Final verdict
    passed = score >= 90  # High threshold because broken code (non-compiling) is a failed refactor
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }