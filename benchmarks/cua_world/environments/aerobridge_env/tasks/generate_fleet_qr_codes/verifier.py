#!/usr/bin/env python3
"""
Verifier for generate_fleet_qr_codes task.

Verification Criteria:
1. Environment Setup (10 pts): 'qrcode' library installed.
2. Output Artifacts (10 pts): Output directory exists.
3. Quantity (30 pts): Number of generated files matches aircraft count in DB.
4. Naming Convention (20 pts): Filenames match 'tag_*.png'.
5. Quality/Content (30 pts): QR codes are valid and decode to the correct URL pattern.

Pass Threshold: 70 points (Must have correct file count and readable QR codes).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_fleet_qr_codes(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Criterion 1: Library Installation (10 pts)
    if result.get('lib_installed', False):
        score += 10
        feedback_parts.append("Library 'qrcode' installed (+10)")
    else:
        feedback_parts.append("Library 'qrcode' NOT installed")

    # Criterion 2: Directory Existence (10 pts)
    if result.get('output_dir_exists', False):
        score += 10
        feedback_parts.append("Output directory created (+10)")
    else:
        feedback_parts.append("Output directory NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: File Count (30 pts)
    expected = result.get('expected_count', 0)
    actual = result.get('file_count', 0)
    
    if expected > 0 and actual == expected:
        score += 30
        feedback_parts.append(f"Correct number of files generated ({actual}/{expected}) (+30)")
    elif actual > 0:
        # Partial credit if some files generated
        partial = int(30 * (actual / expected)) if expected > 0 else 0
        score += partial
        feedback_parts.append(f"Incorrect file count ({actual}/{expected}) (+{partial})")
    else:
        feedback_parts.append("No files generated")

    # Criterion 4: Naming Convention (20 pts)
    # Check if files match tag_*.png
    valid_names = result.get('valid_filename_count', 0)
    if valid_names == actual and actual > 0:
        score += 20
        feedback_parts.append("All filenames follow convention 'tag_*.png' (+20)")
    elif valid_names > 0:
        score += 10
        feedback_parts.append("Some filenames follow convention (+10)")
    else:
        feedback_parts.append("Filenames do NOT follow convention 'tag_*.png'")

    # Criterion 5: QR Code Content (30 pts)
    decoded_url = result.get('sample_decoded_url', '')
    url_pattern = r"http://localhost:8000/admin/registry/aircraft/.*/change/?"
    
    if decoded_url:
        if re.match(url_pattern, decoded_url):
            score += 30
            feedback_parts.append("QR code decodes to correct Admin URL (+30)")
        else:
            # It decoded, but URL is wrong (maybe just ID, or wrong path)
            score += 10
            feedback_parts.append(f"QR code decodes but URL is incorrect: {decoded_url} (+10)")
    else:
        # If we couldn't decode (zbar missing or invalid image), we can't give points
        # unless files were created and script exists, suggesting effort
        if result.get('files_created_during_task', False) and result.get('script_created', False):
             feedback_parts.append("Could not decode sample QR code (format issue?)")
        else:
             feedback_parts.append("No valid QR code content detected")

    # Anti-gaming check: Files must be new
    if not result.get('files_created_during_task', False) and actual > 0:
        score = 0
        feedback_parts = ["ANTI-GAMING: Files existed before task start"]
        
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }