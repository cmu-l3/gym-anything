#!/usr/bin/env python3
"""
Verifier: oc_complex_intake — Complex Patient Transfer Intake

Reads /tmp/oc_complex_intake_result.json written by export_result.sh.

5-step chain for new patient Amara Nwosu (female, DOB 1972-04-19, Nigeria).

Scoring (100 pts):
  C1 (20 pts): Patient registered — Amara Nwosu found, DOB 1972-04-19, gender F
  C2 (20 pts): Clinical encounter created — health record exists for her
  C3 (20 pts): Both chronic meds added (Metformin 9002 AND Amlodipine 9004)
  C4 (20 pts): Both labs ordered after task start (HBA1C AND CREAT)
  C5 (20 pts): Follow-up appointment scheduled

Pass threshold: 60 / 100 (at least 3 steps completed)
Do-nothing: 0/100 (Amara not registered -> all criteria fail) -> passed=False
"""

import json
import os
import tempfile


RESULT_FILE_IN_VM = "/tmp/oc_complex_intake_result.json"


def verify_oc_complex_intake(traj, env_info, task_info):
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
    pid = result.get("amara_pid")

    # ------------------------------------------------------------------
    # C1: Patient registered with correct demographics
    # ------------------------------------------------------------------
    if pid is not None:
        dob = result.get("amara_dob", "")
        gender = result.get("amara_gender", "")
        dob_ok = dob and "1972-04-19" in dob
        gender_ok = gender in ("F", "FEMALE")
        if dob_ok and gender_ok:
            score += 20
            criteria["C1_patient_registered"] = {
                "passed": True, "points": 20,
                "detail": f"Amara Nwosu registered (ID={pid}, DOB=1972-04-19, F)"
            }
        else:
            score += 10  # Partial: registered but wrong details
            criteria["C1_patient_registered"] = {
                "passed": False, "points": 10,
                "detail": f"Amara Nwosu found (ID={pid}) but DOB={dob} or gender={gender} may be incorrect"
            }
    else:
        criteria["C1_patient_registered"] = {
            "passed": False, "points": 0,
            "detail": "Amara Nwosu not found in patient registry (firstname=AMARA, lastname=NWOSU)"
        }

    # ------------------------------------------------------------------
    # C2: Clinical encounter / health record created
    # ------------------------------------------------------------------
    hr = result.get("amara_hr_count", 0)
    c2_pass = (hr >= 1) and pid is not None
    if c2_pass:
        score += 20
        criteria["C2_encounter_created"] = {
            "passed": True, "points": 20,
            "detail": "Clinical health record created for Amara Nwosu"
        }
    else:
        criteria["C2_encounter_created"] = {
            "passed": False, "points": 0,
            "detail": "No health record found for Amara Nwosu" if pid else "Cannot check — patient not registered"
        }

    # ------------------------------------------------------------------
    # C3: Both chronic medications added (Metformin 9002 + Amlodipine 9004)
    # ------------------------------------------------------------------
    met = result.get("amara_metformin", 0)
    aml = result.get("amara_amlodipine", 0)
    met_ok = met >= 1
    aml_ok = aml >= 1
    if met_ok and aml_ok:
        score += 20
        criteria["C3_chronic_meds_added"] = {
            "passed": True, "points": 20,
            "detail": "Both chronic medications added: Metformin 500mg + Amlodipine 5mg"
        }
    elif met_ok or aml_ok:
        score += 10
        missing = "Amlodipine 5mg" if met_ok else "Metformin 500mg"
        criteria["C3_chronic_meds_added"] = {
            "passed": False, "points": 10,
            "detail": f"Only one medication added — {missing} is missing"
        }
    else:
        criteria["C3_chronic_meds_added"] = {
            "passed": False, "points": 0,
            "detail": "Neither Metformin nor Amlodipine added to chronic medications"
        }

    # ------------------------------------------------------------------
    # C4: Both lab tests ordered after task start (HbA1c + CREAT)
    # ------------------------------------------------------------------
    hba1c = result.get("amara_hba1c_new", 0)
    creat = result.get("amara_creat_new", 0)
    hba1c_ok = hba1c >= 1
    creat_ok = creat >= 1
    if hba1c_ok and creat_ok:
        score += 20
        criteria["C4_labs_ordered"] = {
            "passed": True, "points": 20,
            "detail": "Both lab tests ordered: HbA1c (HBA1C) + Creatinine (CREAT)"
        }
    elif hba1c_ok or creat_ok:
        score += 10
        missing = "CREAT" if hba1c_ok else "HBA1C"
        criteria["C4_labs_ordered"] = {
            "passed": False, "points": 10,
            "detail": f"Only one lab test ordered — {missing} is missing"
        }
    else:
        criteria["C4_labs_ordered"] = {
            "passed": False, "points": 0,
            "detail": "No HbA1c or Creatinine lab tests ordered"
        }

    # ------------------------------------------------------------------
    # C5: Follow-up appointment scheduled
    # ------------------------------------------------------------------
    appt = result.get("amara_appt_count", 0)
    c5_pass = (appt >= 1) and pid is not None
    if c5_pass:
        score += 20
        criteria["C5_followup_scheduled"] = {
            "passed": True, "points": 20,
            "detail": "Follow-up appointment scheduled for Amara Nwosu"
        }
    else:
        criteria["C5_followup_scheduled"] = {
            "passed": False, "points": 0,
            "detail": "No follow-up appointment found" if pid else "Cannot check — patient not registered"
        }

    passed = score >= 60
    steps_done = sum(1 for v in criteria.values() if v["passed"])

    return {
        "passed": passed,
        "score": score,
        "feedback": {
            "total_score": score,
            "pass_threshold": 60,
            "patient_id_found": pid,
            "steps_completed": f"{steps_done}/5",
            "criteria": criteria
        }
    }
