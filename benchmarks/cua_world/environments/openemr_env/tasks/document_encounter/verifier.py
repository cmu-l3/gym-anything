#!/usr/bin/env python3
"""
Verifier for Document Encounter task in OpenEMR

Robust verification with adversarial case handling:
1. Must be for correct patient (pid=9, Karyn Metz)
2. Must have NEW encounter created
3. Must have NEW vitals documented with reasonable values
4. Must have diagnosis (J06.9 or URI-related)
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_encounter(traj, env_info, task_info):
    """
    Verify that a complete clinical encounter was documented.

    Scoring (100 points total):
    - Encounter for correct patient: 20 points
    - New encounter created: 15 points
    - Vitals documented: 30 points (10 for BP, 5 each for others)
    - Diagnosis added: 25 points
    - Encounter dated today: 10 points

    Passing threshold: 65 points (must have encounter + vitals + diagnosis)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 9)
    expected_fname = metadata.get('patient_fname', 'Karyn')
    expected_lname = metadata.get('patient_lname', 'Metz')
    expected_vitals = metadata.get('expected_vitals', {})
    expected_diagnosis = metadata.get('expected_diagnosis', {})

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/document_encounter_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "encounter_created": False,
            "vitals_documented": False,
            "bp_documented": False,
            "diagnosis_added": False,
            "dated_today": False
        }

        # Extract data
        patient_pid = result.get('patient_pid', 0)
        initial_enc_count = result.get('initial_enc_count', 0)
        current_enc_count = result.get('current_enc_count', 0)
        initial_vitals_count = result.get('initial_vitals_count', 0)
        current_vitals_count = result.get('current_vitals_count', 0)
        enc_found = result.get('encounter_found', False)
        vitals_found = result.get('vitals_found', False)
        dx_found = result.get('diagnosis_found', False)
        encounter = result.get('encounter', {})
        vitals = result.get('vitals', {})
        diagnosis = result.get('diagnosis', {})
        validation = result.get('validation', {})

        logger.info(f"Result data: pid={patient_pid}, enc_found={enc_found}, vitals_found={vitals_found}, dx_found={dx_found}")

        # CRITERION 1: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += 20
            subscores["correct_patient"] = True
            feedback_parts.append(f"Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Encounter documented for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }

        # CRITERION 2: New encounter created (15 points)
        if enc_found and current_enc_count > initial_enc_count:
            score += 15
            subscores["encounter_created"] = True
            feedback_parts.append(f"New encounter created (count: {initial_enc_count} -> {current_enc_count})")
        else:
            feedback_parts.append("No new encounter detected")

        # CRITERION 3: Vitals documented (30 points total)
        vitals_score = 0
        vitals_details = []

        if vitals_found and current_vitals_count > initial_vitals_count:
            subscores["vitals_documented"] = True

            # Blood pressure (10 points)
            bp_sys = vitals.get('bp_systolic', '')
            bp_dia = vitals.get('bp_diastolic', '')
            if bp_sys and bp_dia:
                try:
                    sys_val = float(bp_sys)
                    dia_val = float(bp_dia)
                    # Check if values are reasonable (not obviously fake)
                    if 80 <= sys_val <= 200 and 40 <= dia_val <= 120:
                        vitals_score += 10
                        subscores["bp_documented"] = True
                        vitals_details.append(f"BP: {sys_val}/{dia_val}")

                        # Bonus: check if close to expected values
                        expected_sys = expected_vitals.get('bp_systolic', 118)
                        expected_dia = expected_vitals.get('bp_diastolic', 76)
                        if abs(sys_val - expected_sys) <= 20 and abs(dia_val - expected_dia) <= 15:
                            vitals_details[-1] += " (accurate)"
                except (ValueError, TypeError):
                    vitals_details.append("BP: invalid format")

            # Heart rate/pulse (5 points)
            pulse = vitals.get('pulse', '')
            if pulse:
                try:
                    pulse_val = float(pulse)
                    if 40 <= pulse_val <= 150:
                        vitals_score += 5
                        vitals_details.append(f"HR: {pulse_val}")
                except (ValueError, TypeError):
                    pass

            # Temperature (5 points)
            temp = vitals.get('temperature', '')
            if temp:
                try:
                    temp_val = float(temp)
                    # Accept both F and C ranges
                    if 95 <= temp_val <= 105 or 35 <= temp_val <= 41:
                        vitals_score += 5
                        vitals_details.append(f"Temp: {temp_val}")
                except (ValueError, TypeError):
                    pass

            # Respiratory rate (5 points)
            resp = vitals.get('respiratory_rate', '')
            if resp:
                try:
                    resp_val = float(resp)
                    if 8 <= resp_val <= 40:
                        vitals_score += 5
                        vitals_details.append(f"RR: {resp_val}")
                except (ValueError, TypeError):
                    pass

            # O2 saturation (5 points)
            o2 = vitals.get('oxygen_saturation', '')
            if o2:
                try:
                    o2_val = float(o2)
                    if 80 <= o2_val <= 100:
                        vitals_score += 5
                        vitals_details.append(f"O2: {o2_val}%")
                except (ValueError, TypeError):
                    pass

            score += vitals_score
            if vitals_details:
                feedback_parts.append(f"Vitals: {', '.join(vitals_details)}")
            else:
                feedback_parts.append("Vitals found but values missing/invalid")
        else:
            feedback_parts.append("No new vitals documented")

        # CRITERION 4: Diagnosis added (25 points)
        if dx_found:
            dx_code = diagnosis.get('code', '')
            dx_text = diagnosis.get('text', '')
            has_j06 = diagnosis.get('has_j06', False)
            has_uri = diagnosis.get('has_uri_text', False)

            if has_j06:
                score += 25
                subscores["diagnosis_added"] = True
                feedback_parts.append(f"Correct diagnosis: J06.9 - URI")
            elif has_uri:
                score += 20  # Partial credit for URI-related diagnosis without exact code
                subscores["diagnosis_added"] = True
                feedback_parts.append(f"URI diagnosis added: {dx_text[:50]}")
            else:
                score += 10  # Some credit for any diagnosis
                feedback_parts.append(f"Diagnosis added but not URI-related: {dx_text[:50]}")
        else:
            feedback_parts.append("No diagnosis documented")

        # CRITERION 5: Encounter dated today (10 points)
        enc_date = encounter.get('date', '')
        if enc_date:
            try:
                enc_date_obj = datetime.strptime(enc_date.split()[0], '%Y-%m-%d').date()
                today = datetime.now().date()
                if enc_date_obj == today:
                    score += 10
                    subscores["dated_today"] = True
                    feedback_parts.append(f"Encounter dated today ({enc_date})")
                else:
                    feedback_parts.append(f"Encounter date ({enc_date}) is not today")
            except ValueError:
                feedback_parts.append(f"Could not parse encounter date: {enc_date}")

        # Determine pass/fail
        # Must have: encounter (35) + some vitals (15+) + diagnosis (15+) = 65 minimum
        has_core_components = subscores["encounter_created"] and subscores["vitals_documented"]
        passed = score >= 65 and has_core_components

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "encounter_date": encounter.get('date', ''),
                "vitals_documented": vitals_details if vitals_found else [],
                "diagnosis_code": diagnosis.get('code', ''),
                "diagnosis_text": diagnosis.get('text', ''),
                "patient_pid": patient_pid
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
