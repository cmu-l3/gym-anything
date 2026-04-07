#!/usr/bin/env python3
"""
Verifier for emergency_contact_config task.

Multi-Criteria Verification:
1. File exists and was created/modified during the task window (anti-gaming).
2. T2S file (ZIP/XML) correctly parses and contains Emergency Contact 1.
3. T2S file correctly parses and contains Emergency Contact 2.
4. T2S file correctly parses and contains Information Contact.
5. VLM trajectory verification (optional backup) to ensure Contacts tab was visibly engaged.
"""

import json
import os
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_emergency_contacts(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    expected_output_path = metadata.get("expected_output_path", "C:\\Tier2Submit\\LoneStar_Contacts.t2s")
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch metadata result file
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\tmp\\task_result.json", tmp_json.name)
        with open(tmp_json.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export JSON: {e}"}
    finally:
        os.unlink(tmp_json.name)

    # 2. Base Anti-Gaming Checks
    file_exists = result.get("file_exists", False)
    file_mtime = result.get("file_mtime", 0)
    task_start = result.get("task_start", 0)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": f"Output file not found at {expected_output_path}."}
        
    if file_mtime < task_start:
        feedback_parts.append("Warning: File timestamp is older than task start time (possible stale file)")
    else:
        score += 15
        feedback_parts.append("File created/modified during task (+15)")

    # 3. Fetch and Parse the target .t2s file
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    t2s_content = ""
    try:
        copy_from_env(expected_output_path, tmp_t2s.name)
        
        # Tier2 Submit files are usually ZIP archives containing XML, but we handle flat XML too.
        if zipfile.is_zipfile(tmp_t2s.name):
            with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
                for filename in z.namelist():
                    if filename.endswith('.xml') or filename.endswith('.t2s'):
                        t2s_content += z.read(filename).decode('utf-8', errors='ignore')
        else:
            with open(tmp_t2s.name, 'r', encoding='utf-8', errors='ignore') as f:
                t2s_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to copy/read .t2s file: {e}"}
    finally:
        os.unlink(tmp_t2s.name)

    if not t2s_content.strip():
        return {"passed": False, "score": score, "feedback": "Saved file is empty."}
    
    score += 10
    feedback_parts.append("File parsed successfully (+10)")
    
    # Lowercase content for robust case-insensitive matching
    content_lower = t2s_content.lower()

    # 4. Check Emergency Contact 1 (25 points)
    ec1 = metadata["contacts"]["emergency_1"]
    ec1_found = 0
    if ec1["name"].lower() in content_lower: ec1_found += 10
    if ec1["title"].lower() in content_lower: ec1_found += 5
    if ec1["phone"] in content_lower: ec1_found += 5
    if ec1["phone24"] in content_lower: ec1_found += 5
    score += ec1_found
    if ec1_found == 25:
        feedback_parts.append("Primary Emergency Contact completely correct (+25)")
    else:
        feedback_parts.append(f"Primary Emergency Contact partially correct (+{ec1_found})")

    # 5. Check Emergency Contact 2 (25 points)
    ec2 = metadata["contacts"]["emergency_2"]
    ec2_found = 0
    if ec2["name"].lower() in content_lower: ec2_found += 10
    if ec2["title"].lower() in content_lower: ec2_found += 5
    if ec2["phone"] in content_lower: ec2_found += 5
    if ec2["phone24"] in content_lower: ec2_found += 5
    score += ec2_found
    if ec2_found == 25:
        feedback_parts.append("Secondary Emergency Contact completely correct (+25)")
    else:
        feedback_parts.append(f"Secondary Emergency Contact partially correct (+{ec2_found})")

    # 6. Check Information Contact (25 points)
    ic = metadata["contacts"]["info"]
    ic_found = 0
    if ic["name"].lower() in content_lower: ic_found += 10
    if ic["title"].lower() in content_lower: ic_found += 5
    if ic["phone"] in content_lower: ic_found += 10
    score += ic_found
    if ic_found == 25:
        feedback_parts.append("Information Contact completely correct (+25)")
    else:
        feedback_parts.append(f"Information Contact partially correct (+{ic_found})")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }