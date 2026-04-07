#!/usr/bin/env python3
"""
Verifier for nav_light_drill_set task.

Verifies:
1. 5 Scenario directories exist with correct structure (INI files).
2. Scenario content: Nighttime, stationary ownship, single target vessel.
3. Documents: Answer key (with rules) and student sheet (without answers).
4. Config: bc5.ini settings.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nav_light_drill_set(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    scenarios = result.get('scenarios', {})
    docs = result.get('documents', {})
    config = result.get('config', {})
    
    # === 1. SCENARIO VERIFICATION (50 points total, 10 per scenario) ===
    # Expected directories defined in task metadata
    expected_scenarios = task_info['metadata']['required_scenarios']
    
    scenarios_passed = 0
    
    for name in expected_scenarios:
        s_data = scenarios.get(name, {})
        s_score = 0
        s_feedback = []
        
        if not s_data.get('exists'):
            feedback.append(f"Scenario '{name}': MISSING")
            continue
            
        # Check files (3 pts)
        files = s_data.get('files', {})
        if files.get('environment') and files.get('ownship') and files.get('othership'):
            s_score += 3
        else:
            s_feedback.append("Missing INI files")
            
        # Check Content (7 pts)
        data = s_data.get('data', {})
        
        # Nighttime check (22.0-24.0 or 0.0-4.0)
        try:
            st = float(data.get('start_time', -1))
            if (st >= 22.0) or (st <= 4.0 and st >= 0.0):
                s_score += 2
            else:
                s_feedback.append(f"Not nighttime (Start={st})")
        except:
            s_feedback.append("Invalid StartTime")
            
        # Ownship stationary (Speed 0)
        try:
            sp = float(data.get('own_speed', -1))
            if sp == 0.0:
                s_score += 2
            else:
                s_feedback.append(f"Ownship not stationary (Speed={sp})")
        except:
            s_feedback.append("Invalid Speed")
            
        # Target vessel exists (Count=1 and Type is set)
        try:
            vc = int(data.get('vessel_count', -1))
            vt = data.get('vessel_type', '').strip()
            if vc == 1 and len(vt) > 2:
                s_score += 3
            else:
                s_feedback.append(f"Target vessel issue (Count={vc}, Type='{vt}')")
        except:
            s_feedback.append("Invalid vessel count")
            
        # Accumulate score
        if s_score == 10:
            scenarios_passed += 1
            feedback.append(f"Scenario '{name}': PERFECT")
        elif s_score >= 5:
            feedback.append(f"Scenario '{name}': PARTIAL ({s_score}/10) - {', '.join(s_feedback)}")
        else:
            feedback.append(f"Scenario '{name}': FAILED ({s_score}/10) - {', '.join(s_feedback)}")
            
        score += s_score

    # === 2. DOCUMENT VERIFICATION (25 points) ===
    
    # Answer Key (15 pts)
    key_data = docs.get('answer_key', {})
    if key_data.get('exists'):
        k_content = key_data.get('content', '').lower()
        k_score = 5 # Base for existence
        
        # Check required rules
        rules_found = 0
        required_rules = ["23", "25", "26", "27", "30"]
        for r in required_rules:
            if r in k_content:
                rules_found += 1
        
        if rules_found == 5:
            k_score += 5
        elif rules_found >= 3:
            k_score += 3
            
        # Check vessel keywords
        types_found = 0
        for t in ["power", "sailing", "fishing", "aground"]:
            if t in k_content:
                types_found += 1
        
        if types_found >= 4:
            k_score += 5
            
        score += k_score
        feedback.append(f"Answer Key: {k_score}/15 pts")
    else:
        feedback.append("Answer Key: MISSING")

    # Student Sheet (10 pts)
    sheet_data = docs.get('student_sheet', {})
    if sheet_data.get('exists'):
        s_content = sheet_data.get('content', '').lower()
        sh_score = 5 # Base
        
        # Should NOT contain answers (specific rules)
        # We check if it contains the rule numbers associated with answers
        leaked_answers = 0
        for r in ["23", "25", "26", "27", "30"]:
            # Simple check, might have false positives if numbers used elsewhere, 
            # but usually student sheets are blank forms.
            # We'll be lenient and only penalize if multiple appear
            if r in s_content: 
                leaked_answers += 1
        
        if leaked_answers < 2:
            sh_score += 5
            
        score += sh_score
        feedback.append(f"Student Sheet: {sh_score}/10 pts")
    else:
        feedback.append("Student Sheet: MISSING")

    # === 3. CONFIG VERIFICATION (5 points) ===
    # Check bc5.ini
    c_hide = config.get('hide_instruments', '1')
    c_radar = config.get('full_radar', '0')
    
    c_score = 0
    if str(c_hide) == '0': c_score += 3
    if str(c_radar) == '1': c_score += 2
    
    score += c_score
    if c_score < 5:
        feedback.append(f"Config incomplete (Hide={c_hide}, Radar={c_radar})")
    else:
        feedback.append("Config correct")

    # === FINAL SCORING ===
    # Pass if >60 points AND at least 3 scenarios are fully correct
    passed = (score >= 60) and (scenarios_passed >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }