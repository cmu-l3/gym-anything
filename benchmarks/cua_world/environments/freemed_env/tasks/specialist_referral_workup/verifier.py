#!/usr/bin/env python3
"""
Verifier for specialist_referral_workup task.

Patient: Kelle Crist (ID 9, DOB 2002-10-18, F)
Scoring (100 points):
  - Migraine diagnosis (ICD 346.00) in problem list: 20 pts
  - Aspirin allergy documented (angioedema, severe): 20 pts
  - Sumatriptan 50mg prescription (qty 9, 0 refills): 20 pts
  - Clinical note with neurological content: 20 pts
  - Neurology referral to Dr. Patricia Nguyen: 20 pts
Pass threshold: >= 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_PATIENT_ID = 9

EXPECTED_MIGRAINE_ICD_PREFIX = "346"
EXPECTED_MIGRAINE_TERMS = ["migrain", "346"]

EXPECTED_ALLERGEN = "aspirin"
EXPECTED_REACTION_TERMS = ["angioedema", "angio", "swelling", "hives", "urticaria"]
EXPECTED_SEVERITY_TERMS = ["severe", "sev"]

EXPECTED_DRUG = "sumatriptan"
EXPECTED_DOSE = "50"
EXPECTED_QTY = 9
EXPECTED_REFILLS = 0

NOTE_NEURO_TERMS = [
    "migrain", "headache", "neurolog", "neurology", "neuro",
    "sumatriptan", "prophyla", "aura", "346"
]

EXPECTED_REFERRAL_SPECIALTY_TERMS = ["neurolog", "neuro"]
EXPECTED_REFERRAL_PROVIDER_TERMS = ["nguyen", "patricia"]


def _icd_match(code: str, prefix: str) -> bool:
    c = code.strip().lower().replace(" ", "")
    p = prefix.strip().lower().replace(" ", "")
    return c == p or c.startswith(p) or p.startswith(c.rstrip(".0"))


def _in_str(value: str, terms: list) -> bool:
    vl = value.lower()
    return any(t in vl for t in terms)


def verify_specialist_referral_workup(traj, env_info, task_info):
    """Verify migraine workup for Kelle Crist: dx + allergy + Rx + note + neurology referral."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env("/tmp/specialist_referral_workup_result.json", tmp_path)
            with open(tmp_path, "r", encoding="utf-8") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — agent did not complete the task"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- Criterion 1: Migraine diagnosis (20 pts) ----
    try:
        problem_codes = result.get("problem_codes", [])
        problems = result.get("problems", [])

        migraine_found = any(_icd_match(c, EXPECTED_MIGRAINE_ICD_PREFIX) for c in problem_codes)
        # Also accept if migraine appears in problem name even without perfect ICD
        if not migraine_found:
            migraine_found = any(
                _in_str(p.get("name", ""), EXPECTED_MIGRAINE_TERMS) for p in problems
            )

        if migraine_found:
            score += 20
            subscores["migraine_dx"] = True
            feedback_parts.append(f"Migraine diagnosis (ICD 346.xx) added to problem list (20/20)")
        else:
            subscores["migraine_dx"] = False
            feedback_parts.append(f"Migraine diagnosis NOT found in problem list (0/20) [codes found: {problem_codes}]")
    except Exception as e:
        subscores["migraine_dx"] = False
        feedback_parts.append(f"Migraine diagnosis check error: {e}")

    # ---- Criterion 2: Aspirin allergy (20 pts) ----
    try:
        allergies = result.get("allergies", [])
        aspirin_allergy = None
        for alg in allergies:
            if EXPECTED_ALLERGEN in alg.get("allergy", "").lower():
                aspirin_allergy = alg
                break

        if aspirin_allergy is None:
            subscores["aspirin_allergy"] = False
            feedback_parts.append("Aspirin allergy NOT documented (0/20)")
        else:
            reaction_ok = _in_str(aspirin_allergy.get("reaction", ""), EXPECTED_REACTION_TERMS)
            severity_ok = _in_str(aspirin_allergy.get("severity", ""), EXPECTED_SEVERITY_TERMS)

            allergy_checks = sum([reaction_ok, severity_ok])
            if allergy_checks >= 1:
                score += 20
                subscores["aspirin_allergy"] = True
                feedback_parts.append(
                    f"Aspirin allergy documented (reaction={aspirin_allergy.get('reaction')}, "
                    f"severity={aspirin_allergy.get('severity')}) (20/20)"
                )
            else:
                score += 10
                subscores["aspirin_allergy"] = "partial"
                feedback_parts.append(
                    f"Aspirin allergy found but details incomplete "
                    f"(reaction={aspirin_allergy.get('reaction')}, severity={aspirin_allergy.get('severity')}) (10/20)"
                )
    except Exception as e:
        subscores["aspirin_allergy"] = False
        feedback_parts.append(f"Allergy check error: {e}")

    # ---- Criterion 3: Sumatriptan prescription (20 pts) ----
    try:
        medications = result.get("medications", [])
        sumatriptan_med = None
        for med in medications:
            if EXPECTED_DRUG in med.get("drug", "").lower():
                sumatriptan_med = med
                break

        if sumatriptan_med is None:
            subscores["sumatriptan_rx"] = False
            feedback_parts.append("Sumatriptan prescription NOT found (0/20)")
        else:
            dose_ok = EXPECTED_DOSE in sumatriptan_med.get("dose", "").replace(" ", "")
            qty_ok = str(EXPECTED_QTY) in str(sumatriptan_med.get("quantity", ""))
            refills_ok = str(EXPECTED_REFILLS) in str(sumatriptan_med.get("refills", ""))

            rx_checks = sum([dose_ok, qty_ok, refills_ok])
            if rx_checks >= 2:
                score += 20
                subscores["sumatriptan_rx"] = True
                feedback_parts.append(
                    f"Sumatriptan prescription correct (dose={sumatriptan_med.get('dose')}, "
                    f"qty={sumatriptan_med.get('quantity')}, refills={sumatriptan_med.get('refills')}) (20/20)"
                )
            else:
                score += 10
                subscores["sumatriptan_rx"] = "partial"
                feedback_parts.append(
                    f"Sumatriptan found but details wrong (dose={sumatriptan_med.get('dose')}, "
                    f"qty={sumatriptan_med.get('quantity')}, refills={sumatriptan_med.get('refills')}) (10/20)"
                )
    except Exception as e:
        subscores["sumatriptan_rx"] = False
        feedback_parts.append(f"Prescription check error: {e}")

    # ---- Criterion 4: Clinical note with neurological content (20 pts) ----
    try:
        note_text = result.get("note_text", "").lower()
        notes_count = result.get("notes_count", 0)
        initial_notes = result.get("initial_notes", 0)
        new_note = notes_count > initial_notes

        has_neuro_content = _in_str(note_text, NOTE_NEURO_TERMS)

        if not new_note or not note_text:
            subscores["clinical_note"] = False
            feedback_parts.append("No clinical note written (0/20)")
        elif has_neuro_content:
            score += 20
            subscores["clinical_note"] = True
            feedback_parts.append("Clinical note documents neurological workup (20/20)")
        else:
            score += 10
            subscores["clinical_note"] = "partial"
            feedback_parts.append("Clinical note exists but lacks migraine/neurological content (10/20)")
    except Exception as e:
        subscores["clinical_note"] = False
        feedback_parts.append(f"Clinical note check error: {e}")

    # ---- Criterion 5: Neurology referral (20 pts) ----
    try:
        referrals = result.get("referrals", [])
        ref_count = result.get("ref_count", 0)
        initial_referrals = result.get("initial_referrals", 0)
        new_referral = ref_count > initial_referrals

        neuro_referral = None
        for ref in referrals:
            if _in_str(ref.get("specialty", ""), EXPECTED_REFERRAL_SPECIALTY_TERMS):
                neuro_referral = ref
                break
            # Also match by provider name if specialty not explicitly set
            if _in_str(ref.get("referral_to", ""), EXPECTED_REFERRAL_PROVIDER_TERMS):
                neuro_referral = ref
                break

        if not new_referral or neuro_referral is None:
            subscores["neuro_referral"] = False
            feedback_parts.append("Neurology referral NOT found (0/20)")
        else:
            provider_ok = _in_str(
                neuro_referral.get("referral_to", ""), EXPECTED_REFERRAL_PROVIDER_TERMS
            )
            reason_ok = _in_str(
                neuro_referral.get("reason", ""),
                ["migrain", "headache", "neurolog", "workup"]
            )

            ref_checks = sum([provider_ok, reason_ok])
            if ref_checks >= 1:
                score += 20
                subscores["neuro_referral"] = True
                feedback_parts.append(
                    f"Neurology referral documented (to={neuro_referral.get('referral_to')}, "
                    f"specialty={neuro_referral.get('specialty')}) (20/20)"
                )
            else:
                score += 10
                subscores["neuro_referral"] = "partial"
                feedback_parts.append(
                    f"Referral found but details incomplete (to={neuro_referral.get('referral_to')}, "
                    f"specialty={neuro_referral.get('specialty')}) (10/20)"
                )
    except Exception as e:
        subscores["neuro_referral"] = False
        feedback_parts.append(f"Referral check error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria evaluated",
        "subscores": subscores
    }
