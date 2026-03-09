#!/usr/bin/env python3
"""
Verifier for lab_investigation_workflow task.

Scoring (100 points):
- Clinical encounter with note/complaint created (>=50 chars): 20 pts
- Lab orders placed (CBC + malaria test): 25 pts
- Lab results entered (CBC results + positive malaria result): 30 pts
- Antimalarial treatment prescribed: 25 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_lab_investigation_workflow(traj, env_info, task_info):
    """
    Verify the full clinical-lab-pharmacy cycle was completed for Kofi Asante (BAH000024).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_identifier = metadata.get('patient_identifier', 'BAH000024')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env('/tmp/lab_investigation_workflow_result.json', temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL CHECK: Wrong patient = immediate score 0
        actual_identifier = result.get('patient_identifier', '')
        if actual_identifier != expected_identifier:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Wrong patient! Expected {expected_identifier}, got {actual_identifier}",
                "subscores": {}
            }

        # Criterion 1: Clinical encounter with note (20 pts)
        if result.get('has_encounter') and result.get('has_clinical_note'):
            score += 20
            subscores['clinical_encounter'] = 20
            feedback_parts.append(f"Clinical encounter with note ({result.get('note_length', 0)} chars)")
        elif result.get('has_encounter'):
            score += 10
            subscores['clinical_encounter'] = 10
            feedback_parts.append("Encounter created but no clinical note found (need >=50 chars)")
        else:
            subscores['clinical_encounter'] = 0
            feedback_parts.append("No clinical encounter created")

        # Criterion 2: Lab orders placed (25 pts)
        lab_orders = result.get('lab_orders', {})
        has_cbc = lab_orders.get('has_cbc_order', False)
        has_malaria = lab_orders.get('has_malaria_order', False)

        if has_cbc and has_malaria:
            score += 25
            subscores['lab_orders'] = 25
            feedback_parts.append("Both lab orders placed (CBC + malaria test)")
        elif has_cbc or has_malaria:
            score += 12
            subscores['lab_orders'] = 12
            found = []
            if has_cbc:
                found.append('CBC')
            if has_malaria:
                found.append('malaria test')
            feedback_parts.append(f"Only partial lab orders placed: {', '.join(found)}")
        else:
            subscores['lab_orders'] = 0
            orders_found = lab_orders.get('order_names', [])
            if orders_found:
                feedback_parts.append(f"Orders found but not CBC/malaria: {orders_found[:3]}")
            else:
                feedback_parts.append("No lab orders found in system")

        # Criterion 3: Lab results entered (30 pts)
        lab_results = result.get('lab_results', {})
        has_cbc_results = lab_results.get('has_cbc_results', False)
        has_malaria_pos = lab_results.get('has_malaria_positive', False)

        if has_cbc_results and has_malaria_pos:
            score += 30
            subscores['lab_results'] = 30
            feedback_parts.append("Lab results entered (CBC results + positive malaria)")
        elif has_cbc_results:
            score += 15
            subscores['lab_results'] = 15
            feedback_parts.append("CBC results entered but malaria result missing/not positive")
        elif has_malaria_pos:
            score += 15
            subscores['lab_results'] = 15
            feedback_parts.append("Positive malaria result recorded but CBC results not entered")
        else:
            subscores['lab_results'] = 0
            obs_found = lab_results.get('obs_names', [])
            if obs_found:
                feedback_parts.append(f"Lab results not found. Obs present: {obs_found[:3]}")
            else:
                feedback_parts.append("No lab results found in system")

        # Criterion 4: Antimalarial treatment (25 pts)
        treatment = result.get('treatment', {})
        if treatment.get('has_antimalarial'):
            score += 25
            subscores['antimalarial_treatment'] = 25
            drugs = treatment.get('drug_names', [])
            feedback_parts.append(f"Antimalarial treatment prescribed: {drugs[:2]}")
        else:
            subscores['antimalarial_treatment'] = 0
            drugs = treatment.get('drug_names', [])
            if treatment.get('malaria_diagnosed'):
                feedback_parts.append(f"Malaria diagnosed but no antimalarial prescribed. Drugs found: {drugs[:3]}")
            else:
                feedback_parts.append(f"No antimalarial treatment prescribed. Drugs found: {drugs[:3]}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {str(e)}"
        }
    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verifier error: {str(e)}"
        }
