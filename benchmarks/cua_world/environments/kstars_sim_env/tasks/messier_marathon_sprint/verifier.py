#!/usr/bin/env python3
"""
Verifier for messier_marathon_sprint task.

Occupation: Amateur Astronomer / Observational Astronomer
Context: Observing 6 Messier objects in sequence, storing in correct directories.

Criteria (100 pts total, pass >= 60):
1. M1 images (≥2 valid in marathon/M1/)       - 12 pts
2. M13 images (≥3 valid in marathon/M13/)     - 12 pts
3. M27 images (≥2 valid in marathon/M27/)     - 12 pts
4. M51 images (≥2 valid in marathon/M51/)     - 12 pts
5. M57 images (≥2 valid in marathon/M57/)     - 12 pts
6. M101 images (≥2 valid in marathon/M101/)   - 12 pts
7. Log file exists & created during task      - 10 pts
8. Log content mentions all 6 targets         - 8 pts
9. Sky view created & >50KB                   - 10 pts

Anti-gaming: files must have mtime > task_start and size > 2048 to count.
This excludes the pre-seeded stale files in M13 which have mtime from 2024 and 0 bytes.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_REQS = {
    "M1": 2,
    "M13": 3,
    "M27": 2,
    "M51": 2,
    "M57": 2,
    "M101": 2
}

def verify_messier_marathon_sprint(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = result.get('task_start', 0)
    fits_files = result.get('fits_files', [])

    # Filter out empty/stale files (anti-gaming)
    valid_fits = [f for f in fits_files
                  if f.get('mtime', 0) > task_start and f.get('size', 0) > 2048]

    def count_target(target_name):
        return sum(1 for f in valid_fits if f.get('dir', '').upper() == target_name.upper())

    # Check the 6 FITS targets (12 pts each = 72 pts total)
    for target, required in TARGET_REQS.items():
        count = count_target(target)
        if count >= required:
            score += 12
            feedback.append(f"{target}: {count} valid frames")
        elif count >= 1:
            score += 6
            feedback.append(f"{target}: {count}/{required} valid frames")
        else:
            feedback.append(f"{target}: NO valid frames")

    # Check Log Exists (10 pts)
    log_exists = result.get('log_exists', False)
    log_mtime = result.get('log_mtime', 0)
    log_b64 = result.get('log_b64', '')
    
    if log_exists and log_mtime > task_start:
        score += 10
        feedback.append("Observation log created")
        
        # Check Log Content (8 pts)
        try:
            log_text = base64.b64decode(log_b64).decode('utf-8', errors='ignore').upper()
            mentions = [t for t in TARGET_REQS.keys() if t in log_text]
            if len(mentions) == 6:
                score += 8
                feedback.append("Log contains all 6 target designations")
            elif len(mentions) > 0:
                score += len(mentions) * 1  # Partial credit
                feedback.append(f"Log mentions {len(mentions)} targets")
            else:
                feedback.append("Log does not mention target designations")
        except Exception:
            feedback.append("Failed to decode observation log")
    else:
        feedback.append("Observation log not found or pre-dates task")

    # Check Sky View (10 pts)
    sky_exists = result.get('sky_exists', False)
    sky_mtime = result.get('sky_mtime', 0)
    sky_size = result.get('sky_size', 0)

    if sky_exists and sky_mtime > task_start and sky_size > 50000:
        score += 10
        feedback.append("Sky view generated successfully")
    elif sky_exists and sky_mtime > task_start:
        feedback.append(f"Sky view file found but size is too small ({sky_size} bytes)")
    else:
        feedback.append("Sky view not generated")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }