#!/usr/bin/env python3
"""
Verifier: oc_critical_lab_followup — Critical Lab Value Response Protocol

Reads /tmp/oc_critical_lab_followup_result.json written by export_result.sh.

3 patients with critical lab values requiring immediate action:
  - Fatima Al-Rashid (10003): GLUC=450 -> schedule appt + add Insulin Regular (9012)
  - David Okonkwo    (10004): CBC Hgb=6.1 -> schedule appt + add Folic Acid 5mg (9011)
                              TRAP: David has Metformin but normal CREAT — do NOT remove
  - Li Wei           (10009): CREAT=4.8 -> schedule appt + REMOVE Metformin (9002)

Scoring (100 pts):
  C1 (15 pts): Fatima — follow-up appointment scheduled
  C2 (15 pts): Fatima — Insulin Regular added (9012)
  C3 (15 pts): David  — follow-up appointment scheduled
  C4 (15 pts): David  — Folic Acid 5mg added (9011)
  C5 (10 pts): David  — Metformin NOT removed (trap check — must stay)
  C6 (15 pts): Li Wei — follow-up appointment scheduled
  C7 (15 pts): Li Wei — Metformin removed (9002 gone)

Pass threshold: 70 / 100
Do-nothing: ~10/100 (C5 passes if Metformin untouched), passed=False
"""

import json
import os
import tempfile


RESULT_FILE_IN_VM = "/tmp/oc_critical_lab_followup_result.json"


def verify_oc_critical_lab_followup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available"}

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
    # C1: Fatima — urgent follow-up appointment scheduled
    # ------------------------------------------------------------------
    fatima_appt = result.get("fatima_appt", 0)
    c1_pass = fatima_appt >= 1
    if c1_pass:
        score += 15
    criteria["C1_fatima_appointment"] = {
        "passed": c1_pass,
        "points": 15 if c1_pass else 0,
        "detail": (
            "Follow-up appointment scheduled for Fatima Al-Rashid"
            if c1_pass
            else f"No follow-up appointment for Fatima Al-Rashid (appt_count={fatima_appt})"
        )
    }

    # ------------------------------------------------------------------
    # C2: Fatima — Insulin Regular added (9012)
    # ------------------------------------------------------------------
    fatima_insulin = result.get("fatima_insulin", 0)
    c2_pass = fatima_insulin >= 1
    if c2_pass:
        score += 15
    criteria["C2_fatima_insulin_added"] = {
        "passed": c2_pass,
        "points": 15 if c2_pass else 0,
        "detail": (
            "Insulin Regular (9012) added for Fatima — critical hyperglycemia treated"
            if c2_pass
            else f"Insulin Regular NOT added for Fatima (count={fatima_insulin})"
        )
    }

    # ------------------------------------------------------------------
    # C3: David — urgent follow-up appointment scheduled
    # ------------------------------------------------------------------
    david_appt = result.get("david_appt", 0)
    c3_pass = david_appt >= 1
    if c3_pass:
        score += 15
    criteria["C3_david_appointment"] = {
        "passed": c3_pass,
        "points": 15 if c3_pass else 0,
        "detail": (
            "Follow-up appointment scheduled for David Okonkwo"
            if c3_pass
            else f"No follow-up appointment for David Okonkwo (appt_count={david_appt})"
        )
    }

    # ------------------------------------------------------------------
    # C4: David — Folic Acid 5mg added (9011)
    # ------------------------------------------------------------------
    david_folic = result.get("david_folic_acid", 0)
    c4_pass = david_folic >= 1
    if c4_pass:
        score += 15
    criteria["C4_david_folic_acid_added"] = {
        "passed": c4_pass,
        "points": 15 if c4_pass else 0,
        "detail": (
            "Folic Acid 5mg (9011) added for David — critical anemia treated"
            if c4_pass
            else f"Folic Acid NOT added for David (count={david_folic})"
        )
    }

    # ------------------------------------------------------------------
    # C5: David — Metformin NOT removed (trap: normal CREAT, keep it)
    #     Points awarded if Metformin still present (agent did NOT remove it)
    # ------------------------------------------------------------------
    david_metformin = result.get("david_metformin", 0)
    c5_pass = david_metformin >= 1
    if c5_pass:
        score += 10
    criteria["C5_david_metformin_kept"] = {
        "passed": c5_pass,
        "points": 10 if c5_pass else 0,
        "detail": (
            "Metformin correctly kept for David — normal CREAT, no contraindication"
            if c5_pass
            else "Metformin incorrectly REMOVED from David — trap triggered (normal CREAT does not warrant removal)"
        )
    }

    # ------------------------------------------------------------------
    # C6: Li Wei — urgent follow-up appointment scheduled
    # ------------------------------------------------------------------
    liwei_appt = result.get("liwei_appt", 0)
    c6_pass = liwei_appt >= 1
    if c6_pass:
        score += 15
    criteria["C6_liwei_appointment"] = {
        "passed": c6_pass,
        "points": 15 if c6_pass else 0,
        "detail": (
            "Follow-up appointment scheduled for Li Wei"
            if c6_pass
            else f"No follow-up appointment for Li Wei (appt_count={liwei_appt})"
        )
    }

    # ------------------------------------------------------------------
    # C7: Li Wei — Metformin removed (CREAT=4.8 contraindication)
    # ------------------------------------------------------------------
    liwei_metformin = result.get("liwei_metformin", 0)
    c7_pass = liwei_metformin == 0
    if c7_pass:
        score += 15
    criteria["C7_liwei_metformin_removed"] = {
        "passed": c7_pass,
        "points": 15 if c7_pass else 0,
        "detail": (
            "Metformin correctly removed for Li Wei — critical renal failure (CREAT=4.8)"
            if c7_pass
            else f"Metformin still present for Li Wei — must be removed due to critical CREAT=4.8 (count={liwei_metformin})"
        )
    }

    passed = score >= 70
    steps_done = sum(1 for v in criteria.values() if v["passed"])

    return {
        "passed": passed,
        "score": score,
        "feedback": {
            "total_score": score,
            "pass_threshold": 70,
            "criteria_passed": f"{steps_done}/7",
            "criteria": criteria
        }
    }
