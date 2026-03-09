"""
Verifier for new_patient_complex_entry task.

Scoring (100 pts total):
- Patient created in IndexNomPrenom: 10 pts
- Demographics correct (DOB 1958-04-12, sex F, Grenoble/38000): 10 pts
- Terrain rubric (TypeRub=20060000) created: 15 pts
  + Aspirin allergy documented: 5 pts
- Consultation/antecedent rubric (TypeRub=20030000) created: 10 pts
  + Hypertension documented: 5 pts
  + Hypothyroïdie documented: 5 pts
- Prescription rubric (TypeRub=20020100) created: 10 pts
  + Ramipril present: 5 pts
  + Levothyroxine present: 5 pts
  + Amlodipine present: 5 pts
- Agenda entry created: 10 pts
  + Appointment on 2026-04-02: 5 pts

Pass threshold: 60/100
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_new_patient_complex_entry(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available in env_info."}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/new_patient_result.json", tmp.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy result from VM: {e}"}
        try:
            with open(tmp.name, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    criteria = []

    # 1. Patient created (10 pts)
    if data.get("patient_created"):
        score += 10
        criteria.append("PASS: Patient BONNET Elise created in database (+10)")
    else:
        criteria.append("FAIL: Patient BONNET Elise NOT found in database (0/10)")
        # Without the patient, nothing else can pass
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(criteria),
        }

    # 2. Demographics correct (10 pts)
    if data.get("demographics_ok"):
        score += 10
        criteria.append("PASS: Demographics correct (DOB 1958-04-12, female, Grenoble) (+10)")
    else:
        criteria.append("FAIL: Demographics incomplete or incorrect (0/10)")

    # 3. Terrain rubric (20 pts total: 15 + 5)
    if data.get("has_terrain_rubric"):
        score += 15
        criteria.append("PASS: Terrain rubric (allergies/antecedents) created (+15)")
        if data.get("terrain_has_aspirine_allergy"):
            score += 5
            criteria.append("PASS: Aspirin allergy documented in terrain (+5)")
        else:
            criteria.append("FAIL: Aspirin allergy NOT found in terrain (0/5)")
    else:
        criteria.append("FAIL: No terrain rubric found (0/20)")

    # 4. Consultation/antecedent rubric (20 pts total: 10 + 5 + 5)
    if data.get("has_consultation_rubric"):
        score += 10
        criteria.append("PASS: Consultation/antecedent rubric created (+10)")
        if data.get("consultation_has_hypertension"):
            score += 5
            criteria.append("PASS: Hypertension documented (+5)")
        else:
            criteria.append("FAIL: Hypertension NOT documented (0/5)")
        if data.get("consultation_has_hypothyroidie"):
            score += 5
            criteria.append("PASS: Hypothyroïdie documented (+5)")
        else:
            criteria.append("FAIL: Hypothyroïdie NOT documented (0/5)")
    else:
        criteria.append("FAIL: No consultation/antecedent rubric found (0/20)")

    # 5. Prescription rubric (25 pts total: 10 + 5 + 5 + 5)
    if data.get("has_prescription_rubric"):
        score += 10
        criteria.append("PASS: Prescription (ordonnance) rubric created (+10)")
        if data.get("prescription_has_ramipril"):
            score += 5
            criteria.append("PASS: Ramipril in prescription (+5)")
        else:
            criteria.append("FAIL: Ramipril NOT in prescription (0/5)")
        if data.get("prescription_has_levothyroxine"):
            score += 5
            criteria.append("PASS: Levothyroxine in prescription (+5)")
        else:
            criteria.append("FAIL: Levothyroxine NOT in prescription (0/5)")
        if data.get("prescription_has_amlodipine"):
            score += 5
            criteria.append("PASS: Amlodipine in prescription (+5)")
        else:
            criteria.append("FAIL: Amlodipine NOT in prescription (0/5)")
    else:
        criteria.append("FAIL: No prescription rubric found (0/25)")

    # 6. Agenda entry (15 pts total: 10 + 5)
    if data.get("has_agenda_entry"):
        score += 10
        criteria.append("PASS: Follow-up appointment created in agenda (+10)")
        if data.get("agenda_date_correct"):
            score += 5
            criteria.append("PASS: Appointment correctly scheduled for 2026-04-02 (+5)")
        else:
            criteria.append("FAIL: Appointment date is NOT 2026-04-02 (0/5)")
    else:
        criteria.append("FAIL: No agenda entry found for BONNET Elise (0/15)")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(criteria),
    }
