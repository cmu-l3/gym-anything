#!/usr/bin/env python3
"""
Verifier for forensic_evidence_extraction task.

Score Breakdown (Total 100):
- Evidence Directory Exists: 5 pts
- All Files Extracted (Count): 20 pts
- File Integrity (Hashes match GT): 15 pts
- Manifest Exists: 5 pts
- Manifest Format Valid: 10 pts
- Manifest Hashes Correct: 20 pts
- Report Exists: 5 pts
- Report Content (4 keywords): 10 pts (2.5 each)
- Volume Dismounted: 10 pts

Anti-Gaming:
- Timestamp check failures reduce score by 50%
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []

    # 1. Extraction (Max 40)
    if result.get("evidence_dir_exists"):
        score += 5
        feedback.append("Evidence dir created")
    else:
        feedback.append("Evidence dir missing")

    extracted = result.get("extracted_count", 0)
    expected = result.get("expected_count", 3)
    
    if extracted >= expected and expected > 0:
        score += 20
        feedback.append(f"All files extracted ({extracted}/{expected})")
    elif extracted > 0:
        partial = int(20 * (extracted / expected))
        score += partial
        feedback.append(f"Partial extraction ({extracted}/{expected})")
    
    if result.get("files_integrity"):
        score += 15
        feedback.append("File integrity verified")
    elif extracted > 0:
        feedback.append("File integrity check failed (hashes mismatch)")

    # 2. Manifest (Max 35)
    if result.get("manifest_exists"):
        score += 5
        feedback.append("Manifest exists")
        
        if result.get("manifest_format_valid"):
            score += 10
            feedback.append("Manifest format valid")
        else:
            feedback.append("Manifest format invalid")
            
        if result.get("manifest_hashes_correct"):
            score += 20
            feedback.append("Manifest hashes correct")
        else:
            feedback.append("Manifest hashes incorrect")
    else:
        feedback.append("Manifest missing")

    # 3. Report (Max 15)
    if result.get("report_exists"):
        score += 5
        content_score = result.get("report_content_score", 0)
        # 10 points distributed over 4 items = 2.5 per item
        report_pts = int(content_score * 2.5)
        score += report_pts
        feedback.append(f"Report contains {content_score}/4 fields")
    else:
        feedback.append("Report missing")

    # 4. Dismount (Max 10)
    if result.get("volume_dismounted"):
        score += 10
        feedback.append("Volume dismounted safely")
    else:
        feedback.append("Volume left mounted")

    # Anti-gaming
    if not result.get("timestamp_valid", True):
        score = int(score / 2)
        feedback.append("⚠️ ANTIGAMING: Files predate task start")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }