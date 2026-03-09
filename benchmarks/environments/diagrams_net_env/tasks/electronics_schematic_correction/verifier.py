#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_electronics_schematic_correction(traj, env_info, task_info):
    """
    Verifies the electronics schematic correction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    xml_data = result.get('xml_analysis', {})
    
    score = 0
    feedback = []

    # 1. File Modification (10 pts)
    if result.get('file_modified', False):
        score += 10
        feedback.append("File was modified.")
    else:
        feedback.append("File was NOT modified.")

    # 2. Resistor Corrections (15 pts)
    # We look for 1k and 10k. 
    # Note: 10k implies 1k exists as substring, so we check specific logic if needed, 
    # but usually if they type "10k" they get points for 10k.
    if xml_data.get('has_1k') and xml_data.get('has_10k'):
        score += 15
        feedback.append("Resistor values R1/R2 corrected (1k, 10k found).")
    elif xml_data.get('has_10k'): 
        # If they only have 10k, they likely missed the 1k change or it's ambiguous
        score += 10
        feedback.append("Found 10k label, but 1k might be missing or ambiguous.")
    else:
        feedback.append("Missing correct resistor values (1k, 10k).")

    # 3. Output Stage (20 pts)
    if xml_data.get('has_LED') and xml_data.get('has_470'):
        score += 20
        feedback.append("Output stage added (LED + 470 ohm).")
    elif xml_data.get('has_LED'):
        score += 10
        feedback.append("LED added, but missing 470 ohm resistor.")
    else:
        feedback.append("Output stage missing.")

    # 4. Timing Capacitor (15 pts)
    if xml_data.get('has_10uF'):
        score += 15
        feedback.append("Timing capacitor (10uF) added.")
    else:
        feedback.append("Missing timing capacitor (10uF).")

    # 5. Noise Capacitor (10 pts)
    if xml_data.get('has_10nF'):
        score += 10
        feedback.append("Control capacitor (10nF) added.")
    else:
        feedback.append("Missing control capacitor (10nF).")

    # 6. Wiring/Connectivity (10 pts)
    # Using edge count as a proxy for "did they add wires"
    total_edges = xml_data.get('total_edges', 0)
    # Initial draft has ~2 edges. 
    # Adding components (C1, C2, LED, R3) and wires should increase this significantly.
    if total_edges >= 8:
        score += 10
        feedback.append(f"Connectivity looks substantial ({total_edges} edges).")
    else:
        feedback.append(f"Low connectivity detected ({total_edges} edges). Did you wire everything?")

    # 7. Export (20 pts)
    if result.get('export_exists', False):
        score += 20
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }