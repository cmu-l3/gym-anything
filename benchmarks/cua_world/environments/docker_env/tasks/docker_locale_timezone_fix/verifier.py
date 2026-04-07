#!/usr/bin/env python3
"""
Verifier for docker_locale_timezone_fix task.

Scoring (100 points):
  - Image built and exists: 10 pts
  - Timezone correctly configured (Europe/Berlin): 20 pts
  - Locale correctly configured (UTF-8): 20 pts
  - Application runs without crashing (Exit Code 0): 20 pts
  - Output files generated with correct encoding (No Mojibake): 30 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_locale_timezone_fix(traj, env_info, task_info):
    """Verify Docker locale and timezone configuration."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve Result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/locale_fix_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Image Exists (10 pts)
    if result.get("image_exists", 0):
        score += 10
        feedback_parts.append("Image built (+10)")
    else:
        feedback_parts.append("Image 'acme-invoicer:fixed' not found (0/10)")
        return {"passed": False, "score": 0, "feedback": "Task failed: Image not built."}

    # 2. Timezone Check (20 pts)
    if result.get("tz_check_passed", 0):
        score += 20
        feedback_parts.append(f"Timezone correct ({result.get('detected_tz')}) (+20)")
    else:
        feedback_parts.append("Timezone incorrect (not Berlin/CET) (0/20)")

    # 3. Locale Check (20 pts)
    if result.get("locale_check_passed", 0):
        score += 20
        feedback_parts.append(f"Locale correct ({result.get('detected_lang')}) (+20)")
    else:
        feedback_parts.append("Locale incorrect (not UTF-8) (0/20)")

    # 4. App Execution (20 pts)
    if result.get("app_run_passed", 0):
        score += 20
        feedback_parts.append("App ran successfully (+20)")
    else:
        feedback_parts.append("App crashed/failed (0/20)")

    # 5. Output Content (30 pts)
    if result.get("file_content_passed", 0):
        score += 30
        feedback_parts.append("Output encoding correct (No Mojibake) (+30)")
    else:
        feedback_parts.append("Output encoding incorrect (Mojibake detected or files missing) (0/30)")

    # Final Verification
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }