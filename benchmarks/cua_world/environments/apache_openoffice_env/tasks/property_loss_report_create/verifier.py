#!/usr/bin/env python3
"""
Verifier for Property Loss Report Task.

Checks:
1. File existence and creation time.
2. Structure analysis from exported JSON (images, tables, text).
3. formatting compliance (styles).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_property_loss_report(traj, env_info, task_info):
    """
    Verify the Property Loss Report creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    max_score = 100

    # 1. File Existence and Validity (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File created successfully.")
        
        # Anti-gaming: Check if created during task
        if result.get("created_during_task"):
            feedback.append("File created during task session.")
        else:
            feedback.append("WARNING: File timestamp check failed (possibly pre-existing).")
            # We don't deduct heavily here as FS sync can vary, but good to note
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found. Task failed."}

    # 2. Content Checks (30 pts)
    struct = result.get("structure", {})
    
    if struct.get("has_claim_number"):
        score += 10
        feedback.append("Claim number found.")
    else:
        feedback.append("Missing Claim Number (778492).")

    if struct.get("has_insured_name"):
        score += 10
        feedback.append("Insured name found.")
    else:
        feedback.append("Missing Insured Name.")
    
    if struct.get("has_grand_total"):
        score += 10
        feedback.append("Table calculation (Grand Total) found.")
    else:
        feedback.append("Missing Grand Total (1,443.90) or table content.")

    # 3. Image Verification (30 pts) - CRITICAL
    # We expect 3 images
    img_count = struct.get("image_count", 0)
    if img_count >= 3:
        score += 30
        feedback.append(f"Images inserted successfully ({img_count} found).")
    elif img_count > 0:
        score += 15
        feedback.append(f"Partial images found ({img_count}/3).")
    else:
        feedback.append("No images found in document.")

    # 4. Captions (15 pts)
    if struct.get("has_captions"):
        score += 15
        feedback.append("Photo captions found.")
    else:
        feedback.append("Missing specific photo captions.")

    # 5. Formatting / Styles (15 pts)
    h1_count = struct.get("heading1_count", 0)
    if h1_count >= 4:
        score += 15
        feedback.append("Section headings formatted correctly.")
    elif h1_count > 0:
        score += 5
        feedback.append("Some headings found, but not all sections formatted.")
    else:
        feedback.append("No 'Heading 1' styles detected.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }