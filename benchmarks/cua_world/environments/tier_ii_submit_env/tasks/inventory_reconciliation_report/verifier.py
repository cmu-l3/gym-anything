#!/usr/bin/env python3
"""
Verifier for inventory_reconciliation_report task.

Scoring (100 pts total, pass threshold: 60):
  Chemical quantities (50 pts):
    15 pts — Chlorine max amount = 35000 (±2000 tolerance)
    10 pts — Chlorine ave amount = 22000 (±2000 tolerance)
    15 pts — Fluorosilic Acid max amount = 30000 (±2000 tolerance)
    10 pts — Fluorosilic Acid ave amount = 18000 (±2000 tolerance)
  New storage location (15 pts):
    15 pts — Chlorine has 2 storage locations (new outdoor cylinder bank)
  Facility updates (15 pts):
    15 pts — maxNumOccupants = 25
  Certification (20 pts):
    10 pts — Certifier contains "James Okafor"
    10 pts — dateSigned contains "2025"

Do-nothing baseline:
  Chlorine max=20000, ave=15000; Fluorosilic max=45000, ave=20000;
  1 storage location each; occupants=18; old certifier → score=0.
"""
import json
import os
import tempfile


RESULT_PATH = "C:\\Users\\Docker\\Desktop\\inventory_reconciliation_report_result.json"


def _find_chemical_by_cas(chemicals, cas):
    for chem in chemicals:
        if chem.get("cas", "").strip() == cas:
            return chem
    return None


def verify_inventory_reconciliation_report(traj, env_info, task_info):
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
    fac = result.get("facility", {})
    score = 0
    fb = []

    # --- Chlorine quantities ---
    cl = _find_chemical_by_cas(chemicals, "7782-50-5")
    if cl:
        try:
            cl_max = int(float(cl.get("maxAmount", 0)))
            if abs(cl_max - 35000) <= 2000:
                score += 15
                fb.append(f"PASS: Chlorine max={cl_max} (+15)")
            else:
                fb.append(f"FAIL: Chlorine max={cl_max} (expected ~35000)")
        except (ValueError, TypeError):
            fb.append("FAIL: Chlorine max amount not parseable")

        try:
            cl_ave = int(float(cl.get("aveAmount", 0)))
            if abs(cl_ave - 22000) <= 2000:
                score += 10
                fb.append(f"PASS: Chlorine ave={cl_ave} (+10)")
            else:
                fb.append(f"FAIL: Chlorine ave={cl_ave} (expected ~22000)")
        except (ValueError, TypeError):
            fb.append("FAIL: Chlorine ave amount not parseable")

        # Chlorine storage count
        sl_count = cl.get("storage_count", 0)
        if isinstance(sl_count, str):
            try:
                sl_count = int(sl_count)
            except ValueError:
                sl_count = 0
        if sl_count >= 2:
            score += 15
            fb.append(f"PASS: Chlorine has {sl_count} storage locations (+15)")
        else:
            fb.append(f"FAIL: Chlorine has {sl_count} storage location(s) (expected 2)")
    else:
        fb.append("FAIL: Chlorine (7782-50-5) not found")

    # --- Fluorosilic Acid quantities ---
    fa = _find_chemical_by_cas(chemicals, "16961-83-4")
    if fa:
        try:
            fa_max = int(float(fa.get("maxAmount", 0)))
            if abs(fa_max - 30000) <= 2000:
                score += 15
                fb.append(f"PASS: Fluorosilic Acid max={fa_max} (+15)")
            else:
                fb.append(f"FAIL: Fluorosilic Acid max={fa_max} (expected ~30000)")
        except (ValueError, TypeError):
            fb.append("FAIL: Fluorosilic Acid max amount not parseable")

        try:
            fa_ave = int(float(fa.get("aveAmount", 0)))
            if abs(fa_ave - 18000) <= 1500:
                score += 10
                fb.append(f"PASS: Fluorosilic Acid ave={fa_ave} (+10)")
            else:
                fb.append(f"FAIL: Fluorosilic Acid ave={fa_ave} (expected ~18000)")
        except (ValueError, TypeError):
            fb.append("FAIL: Fluorosilic Acid ave amount not parseable")
    else:
        fb.append("FAIL: Fluorosilic Acid (16961-83-4) not found")

    # --- Facility: max occupants ---
    try:
        occ = int(fac.get("maxNumOccupants", 0))
        if occ == 25:
            score += 15
            fb.append(f"PASS: maxNumOccupants={occ} (+15)")
        else:
            fb.append(f"FAIL: maxNumOccupants={occ} (expected 25)")
    except (ValueError, TypeError):
        fb.append("FAIL: maxNumOccupants not parseable")

    # --- Certification ---
    certifier = str(fac.get("nameAndTitleOfCertifier", "")).strip()
    if "james okafor" in certifier.lower():
        score += 10
        fb.append(f"PASS: Certifier = '{certifier}' (+10)")
    else:
        fb.append(f"FAIL: Certifier = '{certifier}' (expected 'James Okafor...')")

    date_signed = str(fac.get("dateSigned", "")).strip()
    if "2025" in date_signed:
        score += 10
        fb.append(f"PASS: dateSigned={date_signed} (+10)")
    else:
        fb.append(f"FAIL: dateSigned={date_signed} (expected 2025 date)")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb),
    }
