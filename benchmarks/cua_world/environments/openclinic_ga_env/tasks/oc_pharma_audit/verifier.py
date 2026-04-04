#!/usr/bin/env python3
"""
Verifier: oc_pharma_audit — Pharmacy Medication Safety Audit

Reads /tmp/oc_pharma_audit_result.json written by export_result.sh.

Scoring (100 pts total):
  C1 (20 pts): Amoxicillin (9001) removed from Fatima Al-Rashid (10003)
               [antibiotic — inappropriate as a chronic medication]
  C2 (20 pts): Duplicate Amlodipine (9004) resolved for Priya Sharma (10007)
               [exactly 1 entry must remain; not 0, not 2+]
  C3 (20 pts): Metformin (9002) removed from Mohammed Hassan (10008)
               [contraindicated in renal failure — CREAT=4.5 mg/dL]
  C4 (40 pts): Li Wei (10009) Atorvastatin (9005) still present (correct decoy)
               [must NOT be removed; penalizes indiscriminate deletion]

Pass threshold: 75 / 100
  Requires at least 2 of 3 errors corrected AND the decoy intact.

Do-nothing state: C4 passes (Li Wei seeded = 40 pts), others fail -> 40/100 < 75 -> passed=False
"""

import json
import os
import tempfile


RESULT_FILE_IN_VM = "/tmp/oc_pharma_audit_result.json"


def verify_oc_pharma_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

    # Copy result JSON from VM
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        copy_from_env(RESULT_FILE_IN_VM, tmp_path)
        with open(tmp_path, "r") as f:
            result = json.load(f)
    except (FileNotFoundError, OSError):
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON is malformed: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    criteria = {}

    # ------------------------------------------------------------------
    # C1: Amoxicillin (9001) removed from Fatima Al-Rashid (10003)
    # ------------------------------------------------------------------
    fatima_amox = result.get("fatima_amox_count", -1)
    c1_pass = (fatima_amox == 0)
    if c1_pass:
        score += 20
        criteria["C1_amoxicillin_removed_fatima"] = {
            "passed": True, "points": 20,
            "detail": "Amoxicillin correctly removed from Fatima Al-Rashid's chronic med list"
        }
    else:
        criteria["C1_amoxicillin_removed_fatima"] = {
            "passed": False, "points": 0,
            "detail": (f"Amoxicillin still in Fatima's chronic meds ({fatima_amox} entries). "
                       "Antibiotics should not be listed as chronic medications.")
        }

    # ------------------------------------------------------------------
    # C2: Duplicate Amlodipine resolved for Priya Sharma (10007)
    # Pass: exactly 1 entry remains
    # ------------------------------------------------------------------
    priya_aml = result.get("priya_aml_count", -1)
    c2_pass = (priya_aml == 1)
    if c2_pass:
        score += 20
        criteria["C2_duplicate_amlodipine_resolved_priya"] = {
            "passed": True, "points": 20,
            "detail": "Duplicate Amlodipine resolved — exactly 1 entry remains for Priya Sharma"
        }
    elif priya_aml == 0:
        criteria["C2_duplicate_amlodipine_resolved_priya"] = {
            "passed": False, "points": 0,
            "detail": "All Amlodipine entries removed from Priya — 1 active prescription should remain"
        }
    else:
        criteria["C2_duplicate_amlodipine_resolved_priya"] = {
            "passed": False, "points": 0,
            "detail": f"Priya still has {priya_aml} Amlodipine entries (duplicate not resolved)"
        }

    # ------------------------------------------------------------------
    # C3: Metformin (9002) removed from Mohammed Hassan (10008)
    # ------------------------------------------------------------------
    moham_met = result.get("moham_met_count", -1)
    c3_pass = (moham_met == 0)
    if c3_pass:
        score += 20
        criteria["C3_metformin_removed_mohammed"] = {
            "passed": True, "points": 20,
            "detail": "Metformin correctly removed from Mohammed Hassan (CREAT=4.5 contraindication)"
        }
    else:
        criteria["C3_metformin_removed_mohammed"] = {
            "passed": False, "points": 0,
            "detail": (f"Metformin still present for Mohammed ({moham_met} entries). "
                       "CREAT=4.5 mg/dL indicates severe renal failure — Metformin is contraindicated.")
        }

    # ------------------------------------------------------------------
    # C4: Atorvastatin (9005) still present for Li Wei (10009) [decoy]
    # ------------------------------------------------------------------
    liwei_sta = result.get("liwei_sta_count", -1)
    c4_pass = (liwei_sta >= 1)
    if c4_pass:
        score += 40
        criteria["C4_atorvastatin_intact_liwei"] = {
            "passed": True, "points": 40,
            "detail": "Li Wei's Atorvastatin correctly preserved (appropriate chronic therapy)"
        }
    else:
        criteria["C4_atorvastatin_intact_liwei"] = {
            "passed": False, "points": 0,
            "detail": ("Li Wei's Atorvastatin was incorrectly removed — this is a clinically "
                       "appropriate chronic medication with no contraindications.")
        }

    passed = score >= 75
    errors_fixed = sum([c1_pass, c2_pass, c3_pass])

    return {
        "passed": passed,
        "score": score,
        "feedback": {
            "total_score": score,
            "pass_threshold": 75,
            "errors_fixed": f"{errors_fixed}/3",
            "decoy_intact": c4_pass,
            "criteria": criteria,
            "raw_counts": {
                "fatima_amox": fatima_amox,
                "priya_aml": priya_aml,
                "moham_met": moham_met,
                "liwei_sta": liwei_sta,
            }
        }
    }
