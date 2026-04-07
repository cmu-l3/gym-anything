#!/usr/bin/env python3
"""
Verifier for transload_railcar_temporary_storage task.

Scoring (100 pts total, pass threshold: 75):
  20 pts — Chemical present (Chlorine / CAS 7782-50-5)
  15 pts — Hazard categories configured (Gas under pressure, Oxidizing, etc.)
  15 pts — Quantities set to 180,000 lbs
  20 pts — Days on-site is 45
  30 pts — Storage Location configured (Rail car, pressure, temperature, description)

Do-nothing baseline / Spoof prevention:
  - Validates output file creation against task start time.
  - Queries raw XML payload output of the proprietary desktop application.
"""
import json
import os
import tempfile
import re

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\transload_result.json"

def verify_transload_railcar_temporary_storage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found or invalid: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found (did agent export to correct path?)."}

    # Anti-gaming: Check if file was created/modified during task
    mtime = result.get("file_mtime", 0)
    start_time = result.get("task_start", 0)
    if start_time > 0 and mtime < start_time:
        return {"passed": False, "score": 0, "feedback": "Output file predates task start (was not modified during session)."}

    xml_content = result.get("xml_content", "")
    if not xml_content:
        return {"passed": False, "score": 0, "feedback": "Output file contains no XML data."}

    xml_lower = xml_content.lower()
    score = 0
    feedback = []

    # 1. Chemical added (20 pts)
    if "7782-50-5" in xml_content or "chlorine" in xml_lower:
        score += 20
        feedback.append("PASS: Chlorine (7782-50-5) present (+20)")
    else:
        feedback.append("FAIL: Chlorine (7782-50-5) not found in exported XML")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Hazard Categories (15 pts) - check a few key characteristics of Chlorine
    hazards_found = 0
    if "pressure" in xml_lower: hazards_found += 1
    if "oxidiz" in xml_lower: hazards_found += 1
    if "toxic" in xml_lower: hazards_found += 1
    if "corros" in xml_lower: hazards_found += 1

    if hazards_found >= 2:
        score += 15
        feedback.append("PASS: Hazard categories configured (+15)")
    else:
        feedback.append("FAIL: Hazard categories missing")

    # 3. Amounts (15 pts)
    if "180000" in xml_content or "180,000" in xml_content:
        score += 15
        feedback.append("PASS: Amounts set to 180,000 (+15)")
    else:
        feedback.append("FAIL: 180,000 lbs amount not found")

    # 4. Days On-Site (20 pts)
    days_match = re.search(r'<DaysOnSite[^>]*>\s*45\s*</DaysOnSite>', xml_content, re.IGNORECASE)
    if days_match or "45" in xml_content:
        score += 20
        feedback.append("PASS: Days on site = 45 (+20)")
    else:
        feedback.append("FAIL: Days on site is not 45")

    # 5. Storage Details (30 pts max)
    storage_score = 0
    if "rail car" in xml_lower or "railcar" in xml_lower:
        storage_score += 10
    if "greater than ambient pressure" in xml_lower or "above ambient pressure" in xml_lower:
        storage_score += 10
    if "ambient temperature" in xml_lower and "less than" not in xml_lower:
        storage_score += 5
    if "rail siding track 4" in xml_lower or "track 4" in xml_lower:
        storage_score += 5

    score += storage_score
    feedback.append(f"Storage details configured: +{storage_score}/30")

    # Final logic threshold
    passed = score >= 75
    
    # Crucial criterion: The temporary storage nuance (Days on site & Railcar) must be met
    if passed and storage_score < 10:
        passed = False
        feedback.append("FAIL: Not enough railcar storage details configured to pass.")

    return {"passed": passed, "score": min(score, 100), "feedback": " | ".join(feedback)}