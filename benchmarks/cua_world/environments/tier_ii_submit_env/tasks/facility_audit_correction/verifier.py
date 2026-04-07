#!/usr/bin/env python3
"""
Verifier for facility_audit_correction task.

Scoring (100 pts total, pass threshold: 60):
  25 pts — NAICS code corrected to 221310
  20 pts — County corrected to Chittenden
  25 pts — Lat/long corrected (lat ≈ 44.554, lon ≈ -73.167)
  15 pts — Mailing city corrected to Burlington
  15 pts — NAICS description corrected to "Water Supply and Irrigation Systems"

Do-nothing baseline: All 4 errors remain from injected values → score=0.
"""
import json
import os
import tempfile


RESULT_PATH = "C:\\Users\\Docker\\Desktop\\facility_audit_correction_result.json"


def verify_facility_audit_correction(traj, env_info, task_info):
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

    # 1. NAICS code (25 pts)
    naics = str(fac.get("naics_code", "")).strip()
    if naics == "221310":
        score += 25
        fb.append(f"PASS: NAICS code = {naics} (+25)")
    else:
        fb.append(f"FAIL: NAICS code = {naics} (expected 221310)")

    # 2. County (20 pts)
    county = str(fac.get("county", "")).strip()
    if county.lower() == "chittenden":
        score += 20
        fb.append(f"PASS: County = {county} (+20)")
    else:
        fb.append(f"FAIL: County = {county} (expected Chittenden)")

    # 3. Lat/Long (25 pts)
    try:
        lat = float(fac.get("latitude", 0))
        lon = float(fac.get("longitude", 0))
        # Correct: 44.554437, -73.167142. Accept within ~0.01 degree tolerance.
        lat_ok = abs(lat - 44.554437) < 0.01
        lon_ok = abs(lon - (-73.167142)) < 0.01
        if lat_ok and lon_ok:
            score += 25
            fb.append(f"PASS: Lat/Long = ({lat}, {lon}) (+25)")
        else:
            fb.append(f"FAIL: Lat/Long = ({lat}, {lon}) (expected ~44.554, ~-73.167)")
    except (ValueError, TypeError):
        fb.append(f"FAIL: Lat/Long not parseable")

    # 4. Mailing city (15 pts)
    mail_city = str(fac.get("mailing_city", "")).strip()
    if mail_city.lower() == "burlington":
        score += 15
        fb.append(f"PASS: Mailing city = {mail_city} (+15)")
    else:
        fb.append(f"FAIL: Mailing city = {mail_city} (expected Burlington)")

    # 5. NAICS description (15 pts)
    naics_desc = str(fac.get("naics_description", "")).strip().lower()
    if "water supply" in naics_desc or "irrigation" in naics_desc:
        score += 15
        fb.append(f"PASS: NAICS description contains 'Water Supply' (+15)")
    else:
        fb.append(f"FAIL: NAICS description = '{fac.get('naics_description', '')}' (expected 'Water Supply and Irrigation Systems')")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb),
    }
