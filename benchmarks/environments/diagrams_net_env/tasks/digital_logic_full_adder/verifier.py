#!/usr/bin/env python3
import json
import os
import tempfile

def verify_digital_logic_full_adder(traj, env_info, task_info):
    """
    Verifies the 1-bit Full Adder task.
    
    Criteria:
    1. File Creation & Modification (10 pts)
    2. Logic Gate Counts (2 XOR, 2 AND, 1 OR) (40 pts total)
    3. Input/Output Labels (15 pts)
    4. Connectivity (Wires exist) (15 pts)
    5. PNG Export (10 pts)
    6. VLM Check (Visual Confirmation) (10 pts)
    """
    
    # 1. Boilerplate: Get result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Results
    parsed = result.get('parsed_data', {})
    counts = parsed.get('counts', {})
    labels = [l.lower() for l in parsed.get('labels', [])]
    conn_count = parsed.get('connection_count', 0)
    
    score = 0
    feedback = []

    # Criterion 1: File Existence (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file saved and modified.")
    else:
        feedback.append("Draw.io file not found or not modified.")

    # Criterion 2: Logic Gates (40 pts)
    # Expect: 2 XOR, 2 AND, 1 OR
    xor_c = counts.get('xor', 0)
    and_c = counts.get('and', 0)
    or_c  = counts.get('or', 0)
    
    # XOR Check (15 pts)
    if xor_c >= 2:
        score += 15
        feedback.append(f"Correct XOR gate count ({xor_c}).")
    elif xor_c > 0:
        score += 7
        feedback.append(f"Partial XOR gate count ({xor_c}/2).")
    else:
        feedback.append("Missing XOR gates.")

    # AND Check (15 pts)
    if and_c >= 2:
        score += 15
        feedback.append(f"Correct AND gate count ({and_c}).")
    elif and_c > 0:
        score += 7
        feedback.append(f"Partial AND gate count ({and_c}/2).")
    else:
        feedback.append("Missing AND gates.")

    # OR Check (10 pts)
    if or_c >= 1:
        score += 10
        feedback.append(f"Correct OR gate count ({or_c}).")
    else:
        feedback.append("Missing OR gate.")

    # Criterion 3: Labels (15 pts)
    # Expect: A, B, Cin, Sum, Cout
    required = ['a', 'b', 'cin', 'sum', 'cout']
    found = [r for r in required if any(r in l for l in labels)] # fuzzy match
    
    if len(found) == 5:
        score += 15
        feedback.append("All labels found.")
    elif len(found) >= 3:
        score += 7
        feedback.append(f"Some labels found ({len(found)}/5). missing: {set(required)-set(found)}")
    else:
        feedback.append("Most labels missing.")

    # Criterion 4: Connectivity (15 pts)
    # Simple check: are there enough wires? A full adder needs at least ~6-8 wires.
    if conn_count >= 6:
        score += 15
        feedback.append(f"Circuit connectivity looks good ({conn_count} wires).")
    elif conn_count >= 3:
        score += 7
        feedback.append(f"Circuit partially wired ({conn_count} wires).")
    else:
        feedback.append("Circuit appears disconnected.")

    # Criterion 5: PNG Export (10 pts)
    if result.get('png_exists'):
        score += 10
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    # Criterion 6: Basic VLM Sanity Check (Visual confirmation) (10 pts)
    # Since we don't have VLM here in python code, we grant this if connectivity and gates are high
    # assuming the programmatic check is a proxy for visual structure.
    # In a real pipeline, we would call the VLM here.
    if score >= 60: 
        score += 10
        feedback.append("Structure implies valid visual diagram.")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }