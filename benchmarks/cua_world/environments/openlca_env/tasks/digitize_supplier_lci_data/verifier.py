#!/usr/bin/env python3
"""
Verifier for Digitizing Supplier LCI Data task.

Criteria:
1. Process Created (20 pts): A process named "Supplier Injection Molding" exists.
2. Material Input (15 pts): Polypropylene input ~1.05.
3. Energy Input (15 pts): Electricity input ~2.4.
4. Transport Calculation (25 pts): Transport input ~0.525 (t*km) or 525 (kg*km).
5. Emission Output (15 pts): VOC output ~0.003.
6. Flow Direction (10 pts): Inputs are inputs, Emissions are outputs.

Pass Threshold: 70/100
"""

import json
import os
import tempfile
import logging
import math

logger = logging.getLogger(__name__)

def verify_digitize_supplier_lci_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Process Existence
    if not result.get('process_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Process 'Supplier Injection Molding' was not found in the database."
        }
    
    score += 20
    feedback.append("Process created.")

    exchanges = result.get('exchanges', [])
    
    # Flags
    pp_found = False
    elec_found = False
    transport_found = False
    voc_found = False
    directions_correct = True
    
    # Analyze Exchanges
    for ex in exchanges:
        try:
            flow_name = ex.get('flow', '').lower()
            amount = float(ex.get('amount', 0))
            is_input = str(ex.get('is_input', '')).strip() == '1' # Derby usually returns 1 for boolean true
            
            # Check Polypropylene (Input 1.05)
            if 'polypropylene' in flow_name and not pp_found:
                if 1.0 <= amount <= 1.1:
                    pp_found = True
                    if not is_input: directions_correct = False

            # Check Electricity (Input 2.4)
            if 'electricity' in flow_name and not elec_found:
                if 2.3 <= amount <= 2.5:
                    elec_found = True
                    if not is_input: directions_correct = False

            # Check Transport (Input 0.525 t*km OR 525 kg*km)
            # Transport flows usually contain "transport" or "truck"
            if ('transport' in flow_name or 'truck' in flow_name) and not transport_found:
                # Case A: t*km (0.525)
                if 0.5 <= amount <= 0.55:
                    transport_found = True
                    if not is_input: directions_correct = False
                # Case B: kg*km (525) - less likely in USLCI but possible unit mistake
                elif 500 <= amount <= 550:
                    transport_found = True
                    feedback.append("(Transport unit appears to be kg*km, accepted)")
                    if not is_input: directions_correct = False

            # Check VOC Emission (Output 0.003)
            if ('voc' in flow_name or 'volatile' in flow_name or 'organic' in flow_name) and not voc_found:
                if 0.0025 <= amount <= 0.0035:
                    voc_found = True
                    # Emission is OUTPUT, so is_input should be False (0)
                    if is_input: directions_correct = False

        except ValueError:
            continue

    # Scoring
    if pp_found:
        score += 15
        feedback.append("Polypropylene input correct.")
    else:
        feedback.append("Polypropylene input missing/incorrect.")

    if elec_found:
        score += 15
        feedback.append("Electricity input correct.")
    else:
        feedback.append("Electricity input missing/incorrect.")

    if transport_found:
        score += 25
        feedback.append("Transport calculation correct.")
    else:
        feedback.append("Transport calculation incorrect (Expected ~0.525 for t*km).")

    if voc_found:
        score += 15
        feedback.append("VOC emission correct.")
    else:
        feedback.append("VOC emission missing/incorrect.")

    if directions_correct and (pp_found or elec_found or voc_found):
        score += 10
    elif not directions_correct:
        feedback.append("Some flow directions (Input/Output) were wrong.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }