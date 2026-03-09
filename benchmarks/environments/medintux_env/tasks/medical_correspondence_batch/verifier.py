"""
Verifier for medical_correspondence_batch task.

Three patients each require a different type of medical correspondence:
- ROUX Celine: referral letter (courrier) to endocrinologist for poorly controlled diabetes
- FOURNIER Jacques: consolidation certificate (certificat medical) for work accident
- GAUTHIER Helene: referral letter (courrier) to cardiologist for palpitations

Scoring (100 pts total):

ROUX Celine (35 pts):
  - New letter/courrier document created: 20 pts
  - Document references endocrinology: 10 pts
  - Document mentions diabetes/HbA1c context: 5 pts

FOURNIER Jacques (30 pts):
  - New certificate document created: 20 pts
  - Document mentions consolidation: 10 pts

GAUTHIER Helene (35 pts):
  - New letter/courrier document created: 20 pts
  - Document references cardiology: 10 pts
  - Document mentions palpitations/Holter: 5 pts

Pass threshold: 55/100 (need at least 2 out of 3 documents correct)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_medical_correspondence_batch(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available in env_info."}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/correspondence_result.json", tmp.name)
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

    # ---- ROUX Celine: Endocrinology referral letter (35 pts) ----
    roux = data.get("roux", {})
    if roux.get("has_new_letter"):
        score += 20
        criteria.append("PASS: ROUX Celine — referral letter/courrier document created (+20)")
        if roux.get("has_endocrinology_keyword"):
            score += 10
            criteria.append("PASS: ROUX Celine — letter references endocrinology (+10)")
        else:
            criteria.append("FAIL: ROUX Celine — letter does not mention endocrinology (0/10)")
        kw = roux.get("letter_keywords_found", [])
        if "diabet" in kw or "hba1c" in kw or "9.2" in kw:
            score += 5
            criteria.append("PASS: ROUX Celine — letter mentions diabetes/HbA1c context (+5)")
        else:
            criteria.append("FAIL: ROUX Celine — letter lacks diabetes/HbA1c context (0/5)")
    else:
        criteria.append("FAIL: ROUX Celine — no referral letter/courrier created (0/35)")

    # ---- FOURNIER Jacques: Consolidation certificate (30 pts) ----
    fournier = data.get("fournier", {})
    if fournier.get("has_new_certificate"):
        score += 20
        criteria.append("PASS: FOURNIER Jacques — medical certificate document created (+20)")
        if fournier.get("has_consolidation_keyword"):
            score += 10
            criteria.append("PASS: FOURNIER Jacques — certificate mentions consolidation (+10)")
        else:
            criteria.append("FAIL: FOURNIER Jacques — certificate lacks consolidation mention (0/10)")
    else:
        criteria.append("FAIL: FOURNIER Jacques — no medical certificate created (0/30)")

    # ---- GAUTHIER Helene: Cardiology referral letter (35 pts) ----
    gauthier = data.get("gauthier", {})
    if gauthier.get("has_new_letter"):
        score += 20
        criteria.append("PASS: GAUTHIER Helene — referral letter/courrier document created (+20)")
        if gauthier.get("has_cardiology_keyword"):
            score += 10
            criteria.append("PASS: GAUTHIER Helene — letter references cardiology (+10)")
        else:
            criteria.append("FAIL: GAUTHIER Helene — letter does not mention cardiology (0/10)")
        kw = gauthier.get("letter_keywords_found", [])
        if "palpitation" in kw or "holter" in kw or "arythmie" in kw:
            score += 5
            criteria.append("PASS: GAUTHIER Helene — letter mentions palpitations/Holter (+5)")
        else:
            criteria.append("FAIL: GAUTHIER Helene — letter lacks palpitations/Holter mention (0/5)")
    else:
        criteria.append("FAIL: GAUTHIER Helene — no referral letter/courrier created (0/35)")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 55)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(criteria),
    }
