import json
import os
import tempfile


def verify_medication_interaction_audit(traj, env_info, task_info):
    """
    Verify medication safety audit for CKD3b patient James Kowalski.

    Scoring breakdown (100 pts total, pass threshold: 70):
      20 pts — Metformin discontinued      (lactic acidosis risk in CKD3b eGFR<45)
      20 pts — Ibuprofen/NSAID discontinued (nephrotoxic, contraindicated in CKD)
      20 pts — Nitrofurantoin discontinued  (ineffective + toxic in CKD3b eGFR<45)
      20 pts — All 3 safe meds still active (Amlodipine, Atorvastatin, Lisinopril) — anti-gaming gate
      10 pts — Monitoring lab ordered       (BMP/CMP/Creatinine/Urinalysis)
      10 pts — Clinical documentation note  (any new note/encounter/soap)

    Strategy enumeration (anti-gaming validation):
      Do-nothing:              20 pts (safe meds preserved trivially) → FAIL
      Discontinue ALL 6:       60 pts (anti-gaming 0, 60 < 70)        → FAIL
      Correct (3 bad + keep 3): 80-100 pts                            → PASS
      2 of 3 bad + keep all safe + labs: 70 pts                       → borderline PASS
      Touch any safe med:      ≤40 pts                                → FAIL
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/medication_audit_result.json')
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    subscores = {}
    feedback_parts = []

    # --- Copy and parse result file ---
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found — task may not have been attempted or export script failed: {e}",
            "subscores": {},
        }

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse export result JSON: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    # Sanity check — confirm patient data exists
    if result.get('error'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Setup error: {result['error']}",
            "subscores": {},
        }

    # --- Criterion 1: Metformin discontinued ---
    metformin_active = result.get('metformin_still_active', True)
    if not metformin_active:
        score += 20
        subscores['metformin_discontinued'] = True
        feedback_parts.append("PASS: Metformin discontinued (+20) — correct, risk of lactic acidosis in CKD3b")
    else:
        subscores['metformin_discontinued'] = False
        feedback_parts.append("FAIL: Metformin still active — contraindicated in CKD3b (eGFR<45, lactic acidosis risk)")

    # --- Criterion 2: NSAID (Ibuprofen) discontinued ---
    ibuprofen_active = result.get('ibuprofen_still_active', True)
    if not ibuprofen_active:
        score += 20
        subscores['ibuprofen_discontinued'] = True
        feedback_parts.append("PASS: NSAID (Ibuprofen) discontinued (+20) — correct, nephrotoxic in CKD")
    else:
        subscores['ibuprofen_discontinued'] = False
        feedback_parts.append("FAIL: Ibuprofen still active — NSAIDs are nephrotoxic and contraindicated in CKD")

    # --- Criterion 3: Nitrofurantoin discontinued ---
    nitrofurantoin_active = result.get('nitrofurantoin_still_active', True)
    if not nitrofurantoin_active:
        score += 20
        subscores['nitrofurantoin_discontinued'] = True
        feedback_parts.append("PASS: Nitrofurantoin discontinued (+20) — correct, contraindicated at eGFR<45")
    else:
        subscores['nitrofurantoin_discontinued'] = False
        feedback_parts.append("FAIL: Nitrofurantoin still active — contraindicated in CKD3b (eGFR<45)")

    # --- Criterion 4: Anti-gaming — safe medications preserved ---
    amlodipine_ok = result.get('amlodipine_still_active', False)
    atorvastatin_ok = result.get('atorvastatin_still_active', False)
    lisinopril_ok = result.get('lisinopril_still_active', False)
    all_safe_preserved = amlodipine_ok and atorvastatin_ok and lisinopril_ok

    if all_safe_preserved:
        score += 20
        subscores['safe_medications_preserved'] = True
        feedback_parts.append("PASS: Safe medications preserved (Amlodipine, Atorvastatin, Lisinopril) (+20)")
    else:
        subscores['safe_medications_preserved'] = False
        removed = []
        if not amlodipine_ok:
            removed.append("Amlodipine")
        if not atorvastatin_ok:
            removed.append("Atorvastatin")
        if not lisinopril_ok:
            removed.append("Lisinopril")
        feedback_parts.append(
            f"FAIL: Inappropriate discontinuation of: {', '.join(removed)} — these are safe/beneficial in CKD"
        )

    # --- Criterion 5: Monitoring labs ordered ---
    lab_monitoring = result.get('lab_monitoring_ordered', False)
    initial_labs = result.get('initial_lab_count', 0)
    lab_count_after = result.get('lab_count_after', 0)
    new_orders = result.get('new_orders_after_start', 0)

    labs_ordered = (
        lab_monitoring is True
        or (isinstance(lab_count_after, int) and isinstance(initial_labs, int) and lab_count_after > initial_labs)
        or (isinstance(new_orders, int) and new_orders > 0)
    )

    if labs_ordered:
        score += 10
        subscores['monitoring_labs_ordered'] = True
        feedback_parts.append("PASS: Monitoring laboratory test(s) ordered (+10)")
    else:
        subscores['monitoring_labs_ordered'] = False
        feedback_parts.append(
            "FAIL: No monitoring labs ordered — CKD3b management requires regular BMP/creatinine monitoring"
        )

    # --- Criterion 6: Clinical note ---
    new_pnotes = result.get('new_pnotes', 0)
    new_encounters = result.get('new_encounters', 0)
    new_soap = result.get('new_soap_notes', 0)
    new_clinical = result.get('new_clinical_notes', 0)

    note_created = (
        (isinstance(new_pnotes, int) and new_pnotes > 0)
        or (isinstance(new_encounters, int) and new_encounters > 0)
        or (isinstance(new_soap, int) and new_soap > 0)
        or (isinstance(new_clinical, int) and new_clinical > 0)
    )

    if note_created:
        score += 10
        subscores['documentation_note'] = True
        feedback_parts.append("PASS: Clinical documentation note created (+10)")
    else:
        subscores['documentation_note'] = False
        feedback_parts.append("FAIL: No clinical note documenting the medication review was created")

    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "pass_threshold": pass_threshold,
            "contraindicated_status": {
                "metformin_discontinued": not result.get('metformin_still_active', True),
                "ibuprofen_discontinued": not result.get('ibuprofen_still_active', True),
                "nitrofurantoin_discontinued": not result.get('nitrofurantoin_still_active', True),
            },
            "safe_meds_status": {
                "amlodipine_active": amlodipine_ok,
                "atorvastatin_active": atorvastatin_ok,
                "lisinopril_active": lisinopril_ok,
            },
        },
    }
