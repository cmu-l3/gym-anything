#!/usr/bin/env python3
"""
Verifier for regulatory_notification_chemical_entry task.

Scoring (100 pts total, pass threshold: 60):
  Ammonia (CAS 7664-41-7) — 50 pts:
    10 pts — Chemical present with correct CAS
    10 pts — EHS = true
    10 pts — All 4 required hazards marked true
    10 pts — Max amount 8000, Ave amount 5000
    10 pts — Storage location with correct description and type
  Propane (CAS 74-98-6) — 50 pts:
    10 pts — Chemical present with correct CAS
    10 pts — EHS = false
    10 pts — Both required hazards marked true
    10 pts — Max amount 15000, Ave amount 10000
    10 pts — Storage location with correct description and type

Do-nothing baseline: Only 2 chemicals (Chlorine, Fluorosilic Acid) → score=0.
"""
import json
import os
import tempfile


RESULT_PATH = "C:\\Users\\Docker\\Desktop\\regulatory_notification_chemical_entry_result.json"


def _find_chemical_by_cas(chemicals, cas):
    """Find a chemical entry by CAS number."""
    for chem in chemicals:
        if chem.get("cas", "").strip() == cas:
            return chem
    return None


def _check_hazards(chem, required_hazards):
    """Check if all required hazards are in the true hazards list."""
    true_hazards = [h.strip() for h in chem.get("hazards_true", [])]
    missing = []
    for h in required_hazards:
        if h not in true_hazards:
            missing.append(h)
    return len(missing) == 0, missing


def verify_regulatory_notification_chemical_entry(traj, env_info, task_info):
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

    chemicals = result.get("chemicals", [])
    score = 0
    fb = []

    # --- Ammonia (CAS 7664-41-7) ---
    ammonia = _find_chemical_by_cas(chemicals, "7664-41-7")
    if ammonia:
        score += 10
        fb.append("PASS: Ammonia (7664-41-7) present (+10)")

        # EHS
        if str(ammonia.get("ehs", "false")).lower() == "true":
            score += 10
            fb.append("PASS: Ammonia EHS=true (+10)")
        else:
            fb.append("FAIL: Ammonia EHS should be true")

        # Hazards
        req_hazards = [
            "Acute toxicity (any route of exposure)",
            "Skin corrosion or irritation",
            "Serious eye damage or eye irritation",
            "Gas under pressure (compressed gas)",
        ]
        all_ok, missing = _check_hazards(ammonia, req_hazards)
        if all_ok:
            score += 10
            fb.append("PASS: Ammonia all 4 hazards correct (+10)")
        else:
            fb.append(f"FAIL: Ammonia missing hazards: {missing}")

        # Amounts
        try:
            max_amt = int(float(ammonia.get("maxAmount", 0)))
            ave_amt = int(float(ammonia.get("aveAmount", 0)))
            if 7000 <= max_amt <= 9000 and 4000 <= ave_amt <= 6000:
                score += 10
                fb.append(f"PASS: Ammonia amounts correct (max={max_amt}, ave={ave_amt}) (+10)")
            else:
                fb.append(f"FAIL: Ammonia amounts wrong (max={max_amt}, ave={ave_amt})")
        except (ValueError, TypeError):
            fb.append("FAIL: Ammonia amounts not parseable")

        # Storage
        storage = ammonia.get("storage_locations", [])
        if storage:
            s = storage[0]
            desc = str(s.get("description", "")).lower()
            stype = str(s.get("storageType", "")).lower()
            if "refrigeration" in desc or "pressurized" in desc:
                if "tank inside" in stype or "building" in stype:
                    score += 10
                    fb.append("PASS: Ammonia storage location correct (+10)")
                else:
                    fb.append(f"FAIL: Ammonia storage type wrong: {stype}")
            else:
                fb.append(f"FAIL: Ammonia storage description wrong: {desc}")
        else:
            fb.append("FAIL: Ammonia has no storage locations")
    else:
        fb.append("FAIL: Ammonia (CAS 7664-41-7) not found in submission")

    # --- Propane (CAS 74-98-6) ---
    propane = _find_chemical_by_cas(chemicals, "74-98-6")
    if propane:
        score += 10
        fb.append("PASS: Propane (74-98-6) present (+10)")

        # EHS
        if str(propane.get("ehs", "true")).lower() == "false":
            score += 10
            fb.append("PASS: Propane EHS=false (+10)")
        else:
            fb.append("FAIL: Propane EHS should be false")

        # Hazards
        req_hazards = [
            "Flammable (gases, aerosols, liquids, or solids)",
            "Gas under pressure (compressed gas)",
        ]
        all_ok, missing = _check_hazards(propane, req_hazards)
        if all_ok:
            score += 10
            fb.append("PASS: Propane both hazards correct (+10)")
        else:
            fb.append(f"FAIL: Propane missing hazards: {missing}")

        # Amounts
        try:
            max_amt = int(float(propane.get("maxAmount", 0)))
            ave_amt = int(float(propane.get("aveAmount", 0)))
            if 14000 <= max_amt <= 16000 and 9000 <= ave_amt <= 11000:
                score += 10
                fb.append(f"PASS: Propane amounts correct (max={max_amt}, ave={ave_amt}) (+10)")
            else:
                fb.append(f"FAIL: Propane amounts wrong (max={max_amt}, ave={ave_amt})")
        except (ValueError, TypeError):
            fb.append("FAIL: Propane amounts not parseable")

        # Storage
        storage = propane.get("storage_locations", [])
        if storage:
            s = storage[0]
            desc = str(s.get("description", "")).lower()
            stype = str(s.get("storageType", "")).lower()
            if "outdoor" in desc or "tank farm" in desc or "propane" in desc:
                if "above ground" in stype:
                    score += 10
                    fb.append("PASS: Propane storage location correct (+10)")
                else:
                    fb.append(f"FAIL: Propane storage type wrong: {stype}")
            else:
                fb.append(f"FAIL: Propane storage description wrong: {desc}")
        else:
            fb.append("FAIL: Propane has no storage locations")
    else:
        fb.append("FAIL: Propane (CAS 74-98-6) not found in submission")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb),
    }
