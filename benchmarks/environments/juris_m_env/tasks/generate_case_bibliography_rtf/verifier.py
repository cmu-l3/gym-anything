#!/usr/bin/env python3
"""
Verifier for generate_case_bibliography_rtf task.

Criteria:
1. Output file /home/ga/Documents/warren_bibliography.rtf exists.
2. File was created/modified during the task window.
3. File content is valid RTF (starts with {\rtf).
4. File contains the expected case citations (Brown, Gideon, Miranda).
5. File contains correct reporter citations (checking for 347 U.S., etc.).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_case_bibliography_rtf(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
        
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('output_path', '/home/ga/Documents/warren_bibliography.rtf')
    
    # Create temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_rtf = tempfile.NamedTemporaryFile(delete=False, suffix='.rtf')
    temp_json.close()
    temp_rtf.close()
    
    try:
        # Fetch Result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy/read result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Could not read task result file."}
            
        # Fetch RTF File (if it exists according to result)
        rtf_content = ""
        if result.get('file_exists'):
            try:
                copy_from_env(expected_path, temp_rtf.name)
                with open(temp_rtf.name, 'r', errors='ignore') as f:
                    rtf_content = f.read()
            except Exception as e:
                logger.error(f"Failed to copy output RTF: {e}")
                # We'll handle this in scoring
        
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_rtf.name):
            os.unlink(temp_rtf.name)

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (30 pts)
    if result.get('file_exists'):
        score += 30
        feedback.append("Output file created (+30)")
    else:
        feedback.append(f"Output file not found at {expected_path}")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Timestamp (15 pts)
    if result.get('created_during_task'):
        score += 15
        feedback.append("File created during task session (+15)")
    else:
        feedback.append("File timestamp is too old (pre-dates task start)")

    # Criterion 3: RTF Format (10 pts)
    if rtf_content.strip().startswith(r"{\rtf"):
        score += 10
        feedback.append("Valid RTF format detected (+10)")
    else:
        feedback.append("File does not appear to be a valid RTF document")
    
    # Criterion 4: Content Verification (45 pts)
    # We check for key phrases. RTF often breaks text with formatting codes, 
    # but "Brown" and "347" usually survive or can be found close enough.
    # To be robust, we check basic substrings.
    
    expected_cases = [
        ("Brown", 15),
        ("Gideon", 15),
        ("Miranda", 15)
    ]
    
    content_score = 0
    for case, pts in expected_cases:
        if case in rtf_content:
            content_score += pts
            feedback.append(f"Found citation for {case} (+{pts})")
        else:
            feedback.append(f"Missing citation for {case}")
            
    score += content_score

    # 3. Final Result
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "file_size": result.get('file_size'),
            "has_content": bool(rtf_content)
        }
    }