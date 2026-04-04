#!/usr/bin/env python3
"""
Verifier for hardware_datasheet_create task.

Checks:
1. File Existence: ODT file must exist.
2. Technical Accuracy: Critical spec values must be present.
3. Formatting:
   - Two-column layout (via ODT XML parsing for style:column-count="2").
   - Table presence (via <table:table>).
   - Footer presence.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hardware_datasheet(traj, env_info, task_info):
    """
    Verify the hardware datasheet creation task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Result JSON
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

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Exists & Created (Gate) - 10 pts
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if result.get("file_size", 0) < 1000:
        return {"passed": False, "score": 0, "feedback": "File is empty or too small."}
        
    score += 10
    feedback.append("File created successfully.")

    # Criterion 2: Column Layout (Critical) - 25 pts
    if result.get("columns_detected"):
        score += 25
        feedback.append("Two-column layout detected.")
    else:
        feedback.append("Failed: Two-column layout not detected (required for datasheets).")

    # Criterion 3: Table Presence - 20 pts
    if result.get("table_detected"):
        score += 20
        feedback.append("Table detected.")
    else:
        feedback.append("Failed: Electrical Characteristics table missing.")

    # Criterion 4: Content Accuracy - 30 pts
    found_content = result.get("content_found", [])
    required_samples = ["SE-9042", "-148 dBm", "4.6 mA"]
    
    hits = sum(1 for item in required_samples if item in found_content)
    if hits == len(required_samples):
        score += 30
        feedback.append(f"Technical specs verified ({hits}/{len(required_samples)}).")
    elif hits > 0:
        partial = hits * 10
        score += partial
        feedback.append(f"Partial specs found ({hits}/{len(required_samples)}).")
    else:
        feedback.append("Failed: Critical technical values (part number, specs) missing.")

    # Criterion 5: Footer - 15 pts
    if result.get("footer_detected"):
        score += 15
        feedback.append("Confidential footer detected.")
    else:
        feedback.append("Failed: Confidential footer missing.")

    # 4. Final Verdict
    # Pass threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }