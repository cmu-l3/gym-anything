#!/usr/bin/env python3
"""
Verifier for emergency_planning_compliance_update task.

Scoring (100 pts total, pass threshold: 60):
  30 pts — subjectToEmergencyPlanning = true
           (Chlorine is EHS with TPQ=100 lbs; facility has 20,000 lbs)
  30 pts — Certification updated: certifier name contains "Sarah Chen"
  20 pts — dateSigned is 2025 (updated from 2020)
  20 pts — maxNumOccupants = 22 (updated from 18)

Do-nothing baseline:
  subjectToEmergencyPlanning=false, certifier="Debra Monaco, President",
  dateSigned="2020-01-13", maxNumOccupants=18 → score=0, passed=False.
"""
import json
import os
import tempfile


RESULT_PATH = "C:\\Users\\Docker\\Desktop\\emergency_planning_compliance_update_result.json"


def verify_emergency_planning_compliance_update(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 60)

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found: {e}"}

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found (do-nothing)."}

    fac = result.get("facility", {})
    if not fac:
        return {"passed": False, "score": 0, "feedback": "No facility data in export."}

    score = 0
    fb = []

    # 1. Emergency planning status (30 pts)
    ep_val = str(fac.get("subjectToEmergencyPlanning", "false")).lower().strip()
    if ep_val == "true":
        score += 30
        fb.append("PASS: subjectToEmergencyPlanning=true (+30)")
    else:
        fb.append(f"FAIL: subjectToEmergencyPlanning={ep_val} (expected true)")

    # 2. Certifier name (30 pts)
    certifier = str(fac.get("nameAndTitleOfCertifier", "")).strip()
    if "sarah chen" in certifier.lower():
        score += 30
        fb.append(f"PASS: Certifier updated to '{certifier}' (+30)")
    else:
        fb.append(f"FAIL: Certifier not updated (got '{certifier}', expected 'Sarah Chen...')")

    # 3. Date signed (20 pts)
    date_signed = str(fac.get("dateSigned", "")).strip()
    if "2025" in date_signed:
        score += 20
        fb.append(f"PASS: dateSigned={date_signed} (2025 reporting year) (+20)")
    else:
        fb.append(f"FAIL: dateSigned={date_signed} (expected 2025 date)")

    # 4. Max occupants (20 pts)
    try:
        occ = int(fac.get("maxNumOccupants", 0))
        if occ == 22:
            score += 20
            fb.append(f"PASS: maxNumOccupants={occ} (+20)")
        else:
            fb.append(f"FAIL: maxNumOccupants={occ} (expected 22)")
    except (ValueError, TypeError):
        fb.append(f"FAIL: maxNumOccupants not parseable: {fac.get('maxNumOccupants')}")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb),
    }
