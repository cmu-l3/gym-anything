#!/usr/bin/env python3
"""
Verifier for create_code_template_library task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_code_template_library(traj, env_info, task_info):
    """
    Verify the creation of the Code Template Library and specific functions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # 1. Library Existence (15 pts)
    if result.get('library_found'):
        score += 15
        feedback_parts.append("Library 'HL7 Processing Utilities' found.")
    else:
        feedback_parts.append("Library 'HL7 Processing Utilities' NOT found.")

    # 2. Library Properties (10 pts)
    # includeNewChannels should be true
    if result.get('library_include_new_channels'):
        score += 10
        feedback_parts.append("Library configured to include new channels.")
    elif result.get('library_found'):
        feedback_parts.append("Library exists but 'Include New Channels' is False (expected True).")

    # 3. Templates Verification
    templates = result.get('templates', {})
    expected_templates = [
        ("formatHL7Date", ["function formathl7date", "return"]),
        ("extractPatientName", ["function extractpatientname", "^"]),
        ("generateACK", ["function generateack", "msh"])
    ]

    for name, required_snippets in expected_templates:
        # Find template key case-insensitively
        tmpl_key = next((k for k in templates.keys() if k.lower() == name.lower()), None)
        
        if tmpl_key:
            tmpl_data = templates[tmpl_key]
            
            # Existence (10 pts)
            score += 10
            feedback_parts.append(f"Template '{name}' exists.")
            
            # Type Check (5 pts)
            if tmpl_data.get('type') == 'FUNCTION':
                score += 5
                feedback_parts.append(f"Template '{name}' is type FUNCTION.")
            else:
                feedback_parts.append(f"Template '{name}' type is {tmpl_data.get('type')} (expected FUNCTION).")
                
            # Content Check (10 pts)
            code_content = tmpl_data.get('code', '').lower()
            if all(snippet in code_content for snippet in required_snippets):
                score += 10
                feedback_parts.append(f"Template '{name}' code logic looks correct.")
            else:
                feedback_parts.append(f"Template '{name}' code missing required logic/keywords.")
        else:
            feedback_parts.append(f"Template '{name}' NOT found.")

    # 4. Anti-gaming / Change Detection
    counts = result.get('counts', {})
    if counts.get('lib_final', 0) > counts.get('lib_initial', 0):
        # Good, something was actually created
        pass
    elif not result.get('library_found'):
        # If library not found and counts didn't change, confirms failure
        pass
    else:
        # Library found but counts didn't change? Might be pre-existing (unlikely in fresh env)
        feedback_parts.append("(Note: Library count did not increase, strictly speaking)")

    # Normalize Score
    # Total possible: 15 (Lib) + 10 (Props) + 3*(10+5+10) (Templates) = 100
    
    passed = score >= 60 and result.get('library_found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }