#!/usr/bin/env python3
"""
Verifier for Pre-Operative Medication Review task in OpenEMR.

Patient Margaret Chen has 8 active medications before elective hip arthroplasty.
The agent must: create encounter, record vitals, discontinue perioperatively unsafe
medications, order pre-op labs, and write a clearance note.

Scoring (100 points total, pass threshold: 70):
  10 pts - Correct patient identified
  10 pts - New encounter created, dated today
  15 pts - Vitals recorded (BP 6, HR 2, Temp 2, RR 2, SpO2 2, Wt/Ht 1)
  15 pts - Warfarin discontinued (anticoagulant - surgical bleeding risk)
  10 pts - Clopidogrel discontinued (antiplatelet - surgical bleeding risk)
  10 pts - Ibuprofen discontinued (NSAID - bleeding + nephrotoxicity)
  10 pts - Safe medications preserved (anti-gaming: >=3 of 4 safe meds still active)
   5 pts - Metformin held (bonus - perioperative lactic acidosis risk)
  10 pts - Pre-operative labs ordered
   5 pts - Clinical note documented

Hard gate: safe_medications_preserved must be True to pass (>=3 of 4 safe meds active).

Anti-gaming analysis:
  Do nothing:          20 pts (patient + safe meds trivially)                 -> FAIL (score<70)
  Discontinue ALL 8:   90 pts but safe gate HARD FAIL (0/4 safe)             -> FAIL
  Stop only 2 of 3:    ~75 pts with safe gate OK                             -> borderline PASS
  Correct 3 + safe:    ~80-95 pts with safe gate OK                          -> PASS
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_preoperative_medication_review(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/preop_review_result.json')
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
            "feedback": f"Export file not found: {e}",
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

    if result.get('error'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Setup error: {result['error']}",
            "subscores": {},
        }

    # ===== CRITERION 1: Correct patient (10 pts) =====
    patient_pid = result.get('patient_pid', 0)
    expected_pid_raw = open('/tmp/task_patient_pid_local', 'w') if False else None  # noqa
    # We trust the PID from the export — it was set by setup_task.sh
    # The patient is correct if the export ran against the right PID
    if patient_pid and isinstance(patient_pid, int) and patient_pid > 0:
        score += 10
        subscores['correct_patient'] = True
        feedback_parts.append(f"Correct patient (pid={patient_pid})")
    else:
        subscores['correct_patient'] = False
        feedback_parts.append("Patient PID not found in result")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # ===== CRITERION 2: New encounter created today (10 pts) =====
    enc_found = result.get('encounter_found', False)
    enc_date_today = result.get('encounter_date_today', False)
    initial_enc = result.get('initial_enc_count', 0)
    current_enc = result.get('current_enc_count', 0)

    if enc_found and current_enc > initial_enc:
        score += 10
        subscores['encounter_created'] = True
        if enc_date_today:
            feedback_parts.append("New encounter created, dated today")
        else:
            feedback_parts.append("New encounter created (date may not be today)")
    else:
        subscores['encounter_created'] = False
        feedback_parts.append("No new encounter detected")

    # ===== CRITERION 3: Vitals recorded (15 pts) =====
    vitals_found = result.get('vitals_found', False)
    initial_vitals = result.get('initial_vitals_count', 0)
    current_vitals = result.get('current_vitals_count', 0)
    vitals_score = 0

    if vitals_found and current_vitals > initial_vitals:
        subscores['vitals_documented'] = True

        # BP (6 pts)
        bps = result.get('vitals_bps', '')
        bpd = result.get('vitals_bpd', '')
        if bps and bpd:
            try:
                sys_val = float(bps)
                dia_val = float(bpd)
                if 80 <= sys_val <= 200 and 40 <= dia_val <= 120:
                    vitals_score += 6
                    subscores['bp_documented'] = True
            except (ValueError, TypeError):
                pass

        # HR (2 pts)
        pulse = result.get('vitals_pulse', '')
        if pulse:
            try:
                if 40 <= float(pulse) <= 150:
                    vitals_score += 2
            except (ValueError, TypeError):
                pass

        # Temp (2 pts)
        temp = result.get('vitals_temperature', '')
        if temp:
            try:
                t = float(temp)
                if (95 <= t <= 105) or (35 <= t <= 41):
                    vitals_score += 2
            except (ValueError, TypeError):
                pass

        # RR (2 pts)
        resp = result.get('vitals_respiration', '')
        if resp:
            try:
                if 8 <= float(resp) <= 40:
                    vitals_score += 2
            except (ValueError, TypeError):
                pass

        # SpO2 (2 pts)
        o2 = result.get('vitals_oxygen_saturation', '')
        if o2:
            try:
                if 80 <= float(o2) <= 100:
                    vitals_score += 2
            except (ValueError, TypeError):
                pass

        # Weight or Height (1 pt)
        wt = result.get('vitals_weight', '')
        ht = result.get('vitals_height', '')
        if wt or ht:
            try:
                if (wt and float(wt) > 0) or (ht and float(ht) > 0):
                    vitals_score += 1
            except (ValueError, TypeError):
                pass

        score += vitals_score
        feedback_parts.append(f"Vitals recorded ({vitals_score}/15 pts)")
    else:
        subscores['vitals_documented'] = False
        feedback_parts.append("No new vitals documented")

    # ===== CRITERION 4: Warfarin discontinued (15 pts) =====
    warfarin_active = result.get('warfarin_still_active', True)
    if not warfarin_active:
        score += 15
        subscores['warfarin_discontinued'] = True
        feedback_parts.append("PASS: Warfarin discontinued — anticoagulant, surgical bleeding risk")
    else:
        subscores['warfarin_discontinued'] = False
        feedback_parts.append("FAIL: Warfarin still active — must discontinue before surgery")

    # ===== CRITERION 5: Clopidogrel discontinued (10 pts) =====
    clopidogrel_active = result.get('clopidogrel_still_active', True)
    if not clopidogrel_active:
        score += 10
        subscores['clopidogrel_discontinued'] = True
        feedback_parts.append("PASS: Clopidogrel discontinued — antiplatelet, surgical bleeding risk")
    else:
        subscores['clopidogrel_discontinued'] = False
        feedback_parts.append("FAIL: Clopidogrel still active — antiplatelet must be stopped pre-op")

    # ===== CRITERION 6: Ibuprofen discontinued (10 pts) =====
    ibuprofen_active = result.get('ibuprofen_still_active', True)
    if not ibuprofen_active:
        score += 10
        subscores['ibuprofen_discontinued'] = True
        feedback_parts.append("PASS: Ibuprofen/NSAID discontinued — bleeding and renal risk")
    else:
        subscores['ibuprofen_discontinued'] = False
        feedback_parts.append("FAIL: Ibuprofen still active — NSAID poses bleeding and renal risk")

    # ===== CRITERION 7: Safe medications preserved - anti-gaming gate (10 pts) =====
    lisinopril_ok = result.get('lisinopril_still_active', False)
    amlodipine_ok = result.get('amlodipine_still_active', False)
    atorvastatin_ok = result.get('atorvastatin_still_active', False)
    omeprazole_ok = result.get('omeprazole_still_active', False)

    safe_count = sum([lisinopril_ok, amlodipine_ok, atorvastatin_ok, omeprazole_ok])

    if safe_count >= 3:
        score += 10
        subscores['safe_medications_preserved'] = True
        feedback_parts.append(f"PASS: Safe medications preserved ({safe_count}/4 still active)")
    else:
        subscores['safe_medications_preserved'] = False
        removed = []
        if not lisinopril_ok:
            removed.append("Lisinopril")
        if not amlodipine_ok:
            removed.append("Amlodipine")
        if not atorvastatin_ok:
            removed.append("Atorvastatin")
        if not omeprazole_ok:
            removed.append("Omeprazole")
        feedback_parts.append(
            f"FAIL: Too many safe medications removed ({', '.join(removed)}) — these are safe perioperatively"
        )

    # ===== CRITERION 8: Metformin held - bonus (5 pts) =====
    metformin_active = result.get('metformin_still_active', True)
    if not metformin_active:
        score += 5
        subscores['metformin_held'] = True
        feedback_parts.append("BONUS: Metformin held — perioperative lactic acidosis risk (+5)")
    else:
        subscores['metformin_held'] = False
        # Not penalized — holding Metformin is best practice but not strictly required

    # ===== CRITERION 9: Pre-operative labs ordered (10 pts) =====
    lab_ordered = result.get('lab_ordered', False)
    initial_labs = result.get('initial_lab_count', 0)
    lab_count_after = result.get('lab_count_after', 0)
    new_orders = result.get('new_orders_after_start', 0)

    labs_found = (
        lab_ordered is True
        or (isinstance(lab_count_after, int) and isinstance(initial_labs, int) and lab_count_after > initial_labs)
        or (isinstance(new_orders, int) and new_orders > 0)
    )

    if labs_found:
        score += 10
        subscores['labs_ordered'] = True
        feedback_parts.append("PASS: Pre-operative labs ordered")
    else:
        subscores['labs_ordered'] = False
        feedback_parts.append("FAIL: No pre-operative labs ordered")

    # ===== CRITERION 10: Clinical note documented (5 pts) =====
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
        score += 5
        subscores['clinical_note'] = True
        feedback_parts.append("PASS: Clinical clearance note documented")
    else:
        subscores['clinical_note'] = False
        feedback_parts.append("FAIL: No clinical note documenting the pre-op assessment")

    # === HARD GATES ===
    # Anti-gaming: discontinuing all medications (including safe ones) is a critical
    # patient safety failure — must fail regardless of numeric score.
    safe_meds_ok = subscores.get('safe_medications_preserved', False)
    passed = score >= pass_threshold and safe_meds_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "pass_threshold": pass_threshold,
            "medication_status": {
                "warfarin_discontinued": not result.get('warfarin_still_active', True),
                "clopidogrel_discontinued": not result.get('clopidogrel_still_active', True),
                "ibuprofen_discontinued": not result.get('ibuprofen_still_active', True),
                "metformin_held": not result.get('metformin_still_active', True),
                "lisinopril_active": lisinopril_ok,
                "amlodipine_active": amlodipine_ok,
                "atorvastatin_active": atorvastatin_ok,
                "omeprazole_active": omeprazole_ok,
            },
            "encounter_found": enc_found,
            "vitals_found": vitals_found,
            "labs_ordered": labs_found,
            "note_created": note_created,
        },
    }
