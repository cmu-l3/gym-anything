#!/usr/bin/env python3
"""
Verifier for photosynthesis_process_diagram task.

Scoring (100 points total):
1. File Validity (20 pts): Exists, valid format, created during task.
2. Structure (15 pts): Exactly 3 pages.
3. Content - Intro (10 pts): Title "Photosynthesis" present.
4. Content - Inputs (15 pts): "Carbon Dioxide", "Water", "Sunlight".
5. Content - Outputs (15 pts): "Oxygen", "Glucose".
6. Visuals (25 pts): 
   - Sun shape detected (10 pts)
   - Arrows/Flow detected (15 pts)

VLM Verification:
- Used to confirm the visual diagram structure if programmatic checks are ambiguous,
  but primary scoring relies on file analysis for reliability.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_photosynthesis_diagram(traj, env_info, task_info):
    """
    Verify the photosynthesis flipchart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result load failed: {e}"}

    score = 0
    feedback = []
    
    # 1. File Validity (20 pts)
    if result.get("file_found") and result.get("file_valid"):
        if result.get("created_during_task"):
            score += 20
            feedback.append("File created successfully (20/20)")
        else:
            score += 10
            feedback.append("File exists but timestamp verification failed (10/20)")
    else:
        return {"passed": False, "score": 0, "feedback": "File not found or invalid"}

    # 2. Structure (15 pts)
    pages = result.get("page_count", 0)
    if pages == 3:
        score += 15
        feedback.append("Correct page count (15/15)")
    elif pages > 0:
        score += 5
        feedback.append(f"Incorrect page count: {pages} (5/15)")
    else:
        feedback.append("No pages found (0/15)")

    # Content Checks
    content = result.get("content", {})
    
    # 3. Intro (10 pts)
    if content.get("has_title"):
        score += 10
        feedback.append("Title found (10/10)")
    else:
        feedback.append("Title 'Photosynthesis' missing")

    # 4. Inputs (15 pts)
    inputs = 0
    if content.get("has_co2"): inputs += 1
    if content.get("has_water"): inputs += 1
    if content.get("has_sunlight"): inputs += 1
    
    input_score = inputs * 5
    score += input_score
    feedback.append(f"Inputs found: {inputs}/3 ({input_score}/15)")

    # 5. Outputs (15 pts)
    outputs = 0
    if content.get("has_oxygen"): outputs += 1
    if content.get("has_glucose"): outputs += 1
    
    # Weight outputs slightly higher per item to reach 15 total (7.5 each)
    output_score = 0
    if outputs == 1: output_score = 7
    if outputs == 2: output_score = 15
    score += output_score
    feedback.append(f"Outputs found: {outputs}/2 ({output_score}/15)")

    # 6. Visuals (25 pts)
    if content.get("has_sun_shape"):
        score += 10
        feedback.append("Sun shape detected (10/10)")
    else:
        feedback.append("Sun shape missing")

    if content.get("has_arrows"):
        score += 15
        feedback.append("Flow arrows detected (15/15)")
    else:
        feedback.append("Arrows missing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }