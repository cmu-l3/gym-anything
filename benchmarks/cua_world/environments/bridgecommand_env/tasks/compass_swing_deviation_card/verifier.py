#!/usr/bin/env python3
import json
import math
import os
import re
import tempfile

def calculate_ground_truth_deviation(heading_deg, coeffs):
    """
    Calculate deviation using Admiralty coefficient formula:
    Dev = A + B*sin(h) + C*cos(h) + D*sin(2h) + E*cos(2h)
    """
    rad = math.radians(heading_deg)
    A = coeffs['A']
    B = coeffs['B']
    C = coeffs['C']
    D = coeffs['D']
    E = coeffs['E']
    
    dev = A + B * math.sin(rad) + C * math.cos(rad) + \
          D * math.sin(2 * rad) + E * math.cos(2 * rad)
    return dev

def parse_ini_content(content):
    """Parse flat INI key=value content."""
    data = {}
    for line in content.splitlines():
        if '=' in line:
            key, val = line.split('=', 1)
            data[key.strip().lower()] = val.strip().strip('"')
    return data

def verify_compass_swing_deviation_card(traj, env_info, task_info):
    """
    Verify the compass swing scenario and deviation card task.
    
    Criteria:
    1. Scenario creation (Dir + 3 INI files) - 20 pts
    2. Environment/Ownship configuration correctness - 20 pts
    3. Deviation Card Math Accuracy - 40 pts
    4. Instructor Guide Completeness - 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    coeffs = metadata.get('coefficients', {'A': 2.0, 'B': -3.0, 'C': 1.0, 'D': -1.5, 'E': 0.5})
    
    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result.get('files', {})

    # --- 1. Scenario Structure (20 pts) ---
    structure_score = 0
    if result.get('scenario_dir_exists'):
        structure_score += 5
    
    # Check creation status (must be "true", meaning created during task)
    if files.get('environment_ini', {}).get('status') == 'true': structure_score += 5
    if files.get('ownship_ini', {}).get('status') == 'true': structure_score += 5
    if files.get('othership_ini', {}).get('status') == 'true': structure_score += 5
    
    score += structure_score
    feedback.append(f"Structure Score: {structure_score}/20")

    # --- 2. Configuration Correctness (20 pts) ---
    config_score = 0
    
    # Environment
    env_data = parse_ini_content(files.get('environment_ini', {}).get('content', ''))
    if 'solent' in env_data.get('setting', '').lower(): config_score += 3
    if env_data.get('starttime') == '10.0': config_score += 2
    try:
        if float(env_data.get('visibilityrange', 0)) >= 15.0: config_score += 2
        if float(env_data.get('weather', 99)) <= 1.0: config_score += 1
    except: pass

    # Ownship
    own_data = parse_ini_content(files.get('ownship_ini', {}).get('content', ''))
    if 'dorado' in own_data.get('shipname', '').lower(): config_score += 3
    try:
        lat = float(own_data.get('initiallat', 0))
        lon = float(own_data.get('initiallong', 0))
        # Tolerance 0.01 degrees
        if abs(lat - 50.8050) < 0.01 and abs(lon - -1.2850) < 0.01:
            config_score += 5
        else:
            feedback.append(f"Coords mismatch: got {lat},{lon}")
    except: pass
    
    # Othership (Empty)
    other_data = parse_ini_content(files.get('othership_ini', {}).get('content', ''))
    if other_data.get('number') == '0': config_score += 4

    score += config_score
    feedback.append(f"Config Score: {config_score}/20")

    # --- 3. Deviation Card Accuracy (40 pts) ---
    math_score = 0
    card_content = files.get('deviation_card', {}).get('content', '')
    
    if files.get('deviation_card', {}).get('status') == 'true':
        # Extract numbers from lines that look like table rows
        # Expect lines with at least Heading and Deviation
        # Robust parsing: Look for lines starting with a number 0-360
        lines = card_content.splitlines()
        correct_entries = 0
        total_checked = 0
        
        ground_truth = {}
        for h in range(0, 360, 15):
            ground_truth[h] = calculate_ground_truth_deviation(h, coeffs)
            
        found_headings = []
        
        for line in lines:
            # Find all numbers in the line
            nums = re.findall(r"[-+]?\d*\.\d+|[-+]?\d+", line)
            if len(nums) >= 2:
                try:
                    # Assume first col is heading, second is deviation (or reverse if headers imply, but usually H is first)
                    # We check if first num is a valid heading in our step list
                    h_candidate = float(nums[0])
                    dev_candidate = float(nums[1])
                    
                    # Check if valid integer heading step
                    if h_candidate % 15 == 0 and 0 <= h_candidate < 360:
                        expected = ground_truth[int(h_candidate)]
                        if abs(dev_candidate - expected) <= 0.2:
                            correct_entries += 1
                        total_checked += 1
                        found_headings.append(h_candidate)
                except:
                    continue
        
        # Scoring: 24 entries needed. 
        # If we found at least 20 correct entries, full points roughly.
        if correct_entries >= 24:
            math_score = 40
        elif correct_entries >= 12:
            math_score = 20 + correct_entries
        elif correct_entries > 0:
            math_score = correct_entries
            
        feedback.append(f"Deviation Math: Found {correct_entries} correct entries out of 24 required.")
    else:
        feedback.append("Deviation card file not created.")

    score += math_score

    # --- 4. Instructor Guide (20 pts) ---
    guide_score = 0
    guide_data = files.get('instructor_guide', {})
    guide_content = guide_data.get('content', '').lower()
    
    if guide_data.get('status') == 'true':
        if guide_data.get('length', 0) > 1500: guide_score += 5
        
        # Keywords
        keywords = ["calshot", "fawley", "needles", "hurst", "solas", "variation"]
        found_kw = sum(1 for kw in keywords if kw in guide_content)
        guide_score += (found_kw * 2.5) # Max 15 pts
        
    score += min(20, guide_score)
    feedback.append(f"Guide Score: {min(20, guide_score)}/20")

    # Final check
    passed = score >= 60 and math_score >= 10 # Must have done some math
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }