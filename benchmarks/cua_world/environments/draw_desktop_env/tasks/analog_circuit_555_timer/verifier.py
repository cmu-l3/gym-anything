#!/usr/bin/env python3
import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analog_circuit_555_timer(traj, env_info, task_info):
    """
    Verifies the 555 timer schematic task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get('drawio_exists') and result.get('drawio_size', 0) > 100:
        score += 10
        feedback.append("Drawio file created.")
    else:
        feedback.append("Drawio file missing or empty.")

    # 2. PNG Check (5 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 100:
        score += 5
        feedback.append("PNG export created.")

    # 3. XML Analysis (Components) (40 pts)
    analysis = result.get('analysis', {})
    
    resistors = analysis.get('num_resistors', 0)
    capacitors = analysis.get('num_capacitors', 0)
    leds = analysis.get('num_leds', 0)
    ics = analysis.get('num_ics', 0)
    
    # Resistors: need 3 (R1, R2, R3)
    if resistors >= 3:
        score += 15
        feedback.append(f"Found {resistors} resistors (Goal: 3).")
    elif resistors > 0:
        score += 5
        feedback.append(f"Found {resistors} resistors (Goal: 3).")
        
    # Capacitor: need 1 (C1)
    if capacitors >= 1:
        score += 10
        feedback.append(f"Found {capacitors} capacitors.")
    
    # LED: need 1
    if leds >= 1:
        score += 5
        feedback.append(f"Found {leds} LED.")
        
    # IC: need 1 (555)
    if ics >= 1:
        score += 10
        feedback.append(f"Found {ics} IC.")

    # 4. Connectivity (20 pts)
    conns = analysis.get('num_connections', 0)
    if conns >= 8:
        score += 20
        feedback.append(f"Connectivity looks good ({conns} wires).")
    elif conns >= 4:
        score += 10
        feedback.append(f"Some connectivity ({conns} wires).")
    else:
        feedback.append(f"Low connectivity ({conns} wires).")

    # 5. Labels (10 pts)
    labels = analysis.get('labels_found', [])
    # We look for key values: "555", "1k", "1uf", "470k"
    key_labels = [l for l in labels if l in ["555", "1k", "1uf", "470k", "220"]]
    if len(key_labels) >= 3:
        score += 10
        feedback.append(f"Found key labels: {key_labels}")
    elif len(key_labels) > 0:
        score += 5
        feedback.append(f"Found some labels: {key_labels}")

    # 6. VLM Verification (15 pts)
    # Use VLM to confirm it looks like a schematic and not random boxes
    final_screenshot = get_final_screenshot(traj)
    vlm_passed = False
    
    if final_screenshot:
        prompt = "Is this an electronic circuit schematic diagram? Does it contain component symbols like resistors (zigzag lines) and an IC box?"
        try:
            vlm_res = query_vlm([final_screenshot], prompt)
            if vlm_res and 'yes' in vlm_res.lower():
                score += 15
                vlm_passed = True
                feedback.append("VLM confirmed schematic appearance.")
            else:
                feedback.append("VLM did not recognize a schematic.")
        except Exception:
            feedback.append("VLM verification failed to run.")

    passed = score >= 60 and result.get('drawio_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }