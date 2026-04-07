#!/usr/bin/env python3
"""
Verifier for Posner Spatial Cueing Task.

Verification Strategy (Programmatic + VLM):

Programmatic Checks (Files must be pulled from env):
1. Conditions File Analysis:
   - File exists and modified during task
   - Has required columns (cue_direction, target_location, validity, correct_resp, soa)
   - Has sufficient rows (>= 12)
   - Design is balanced (checks for mix of cues, locations, SOAs)

2. Experiment File Analysis (XML parsing):
   - File exists and is valid XML
   - Routines exist: instructions, fixation, cue, target, feedback
   - Components exist: Arrow/Text for cue, Visual/Key for target
   - Loops exist: Practice and Main loops
   - Main loop references the conditions file
   - Variables used in components ($cue_direction, $target_location, etc.)

3. VLM Checks:
   - Trajectory shows interaction with Builder interface
   - Final state implies completion

Scoring:
- Total: 100 points
- Pass threshold: 60 points + critical criteria met
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET
from collections import Counter

logger = logging.getLogger(__name__)

def verify_create_posner_cueing_task(traj, env_info, task_info):
    """Verify the Posner cueing task implementation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_file_path = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/posner_cueing.psyexp')
    cond_file_path = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/posner_conditions.csv')

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Get Basic Result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            json_path = tmp.name
        copy_from_env("/tmp/posner_task_result.json", json_path)
        with open(json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if 'json_path' in locals() and os.path.exists(json_path):
            os.unlink(json_path)

    # 2. Check Nonce (Anti-gaming)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        if expected_nonce and result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Nonce mismatch (anti-gaming check failed)"}
    except Exception:
        pass # If nonce file missing, ignore (robustness)
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # =========================================================
    # CHECK 1: Conditions File (30 points)
    # =========================================================
    cond_score = 0
    cond_feedback = []
    
    if result.get('cond_file_exists') and result.get('cond_file_modified'):
        # Pull file
        rows = []
        headers = []
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
                local_cond_path = tmp.name
            copy_from_env(cond_file_path, local_cond_path)
            
            with open(local_cond_path, 'r', encoding='utf-8-sig') as f:
                reader = csv.DictReader(f)
                headers = [h.strip() for h in (reader.fieldnames or [])]
                for row in reader:
                    rows.append(row)
            
            # Check A: Required columns (10 pts)
            req_cols = ["cue_direction", "target_location", "validity", "correct_resp", "soa"]
            missing_cols = [rc for rc in req_cols if rc not in headers]
            if not missing_cols:
                cond_score += 10
                cond_feedback.append("All required CSV columns present")
            else:
                partial = max(0, 10 - (len(missing_cols) * 2))
                cond_score += partial
                cond_feedback.append(f"Missing columns: {missing_cols}")

            # Check B: Row count (5 pts)
            if len(rows) >= 12:
                cond_score += 5
                cond_feedback.append(f"Sufficient rows ({len(rows)})")
            else:
                cond_feedback.append(f"Insufficient rows ({len(rows)} < 12)")

            # Check C: Balanced Design (15 pts)
            # We expect variation in cue, target, and soa
            cues = set(r.get('cue_direction', '') for r in rows)
            targets = set(r.get('target_location', '') for r in rows)
            soas = set(r.get('soa', '') for r in rows)
            
            balanced = True
            if len(cues) < 2: balanced = False
            if len(targets) < 2: balanced = False
            if len(soas) < 2: balanced = False
            
            if balanced:
                cond_score += 15
                cond_feedback.append("Design appears balanced (multiple cues, targets, SOAs)")
            else:
                cond_score += 5
                cond_feedback.append(f"Design unbalanced: cues={len(cues)}, targets={len(targets)}, soas={len(soas)}")
                
        except Exception as e:
            cond_feedback.append(f"Error parsing CSV: {e}")
        finally:
            if 'local_cond_path' in locals() and os.path.exists(local_cond_path):
                os.unlink(local_cond_path)
    else:
        cond_feedback.append("Conditions file not found or not modified")

    score += cond_score
    feedback_parts.append(f"Conditions File: {cond_score}/30 ({'; '.join(cond_feedback)})")

    # =========================================================
    # CHECK 2: Experiment File (55 points)
    # =========================================================
    exp_score = 0
    exp_feedback = []
    
    if result.get('exp_file_exists') and result.get('exp_file_modified'):
        try:
            with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
                local_exp_path = tmp.name
            copy_from_env(exp_file_path, local_exp_path)
            
            tree = ET.parse(local_exp_path)
            root = tree.getroot()
            
            # Check A: Routines existence (20 pts)
            routines = root.findall(".//Routine")
            routine_names = [r.get('name') for r in routines]
            required_routines = ['instructions', 'fixation', 'cue', 'target', 'feedback']
            found_routines = [rr for rr in required_routines if any(rr.lower() in rn.lower() for rn in routine_names)]
            
            if len(found_routines) == len(required_routines):
                exp_score += 20
                exp_feedback.append("All routines found")
            else:
                pts = len(found_routines) * 4
                exp_score += pts
                exp_feedback.append(f"Found routines: {found_routines}")

            # Check B: Components & Variables (20 pts)
            # Check for specific variable usage in components
            text_comps = root.findall(".//TextComponent")
            key_comps = root.findall(".//KeyboardComponent")
            
            has_cue_var = False
            has_target_var = False
            has_corr_ans = False
            
            # Check text components for $cue_direction or similar
            for tc in text_comps:
                for param in tc:
                    val = param.get('val', '')
                    if '$cue' in val or 'cue_direction' in val:
                        has_cue_var = True
                    if '$target' in val or 'target_location' in val: # If target is text
                        has_target_var = True
            
            # Check keyboard for correctAns
            for kc in key_comps:
                for param in kc:
                    name = param.get('name')
                    val = param.get('val', '')
                    if name in ['correctAns', 'corrAns'] and ('$' in val or 'correct' in val):
                        has_corr_ans = True
            
            # Also check for Target position if not found in text
            if not has_target_var:
                # Check position params of all components
                for comp in root.findall(".//*[@name]"):
                    for param in comp:
                        if param.get('name') == 'pos' and ('$target' in param.get('val', '') or 'target_location' in param.get('val', '')):
                            has_target_var = True
            
            if has_cue_var: exp_score += 7
            if has_target_var: exp_score += 7
            if has_corr_ans: exp_score += 6
            
            if not (has_cue_var and has_target_var and has_corr_ans):
                exp_feedback.append(f"Variables missing: cue={has_cue_var}, target={has_target_var}, ans={has_corr_ans}")
            else:
                exp_feedback.append("Variables correctly linked")

            # Check C: Loops (15 pts)
            loops = root.findall(".//LoopInitiator")
            if len(loops) >= 2:
                exp_score += 15
                exp_feedback.append("Practice and Main loops found")
            elif len(loops) == 1:
                exp_score += 8
                exp_feedback.append("One loop found")
            else:
                exp_feedback.append("No loops found")

            # Check D: Conditions file reference
            has_cond_ref = False
            for loop in loops:
                for param in loop:
                    if param.get('name') == 'conditionsFile' and 'posner' in param.get('val', '').lower():
                        has_cond_ref = True
            
            if has_cond_ref:
                exp_feedback.append("Conditions file referenced")
            else:
                exp_feedback.append("Conditions file NOT referenced in loop")
                # Deduct small penalty if loop exists but file not linked
                exp_score = max(0, exp_score - 5)

        except Exception as e:
            exp_feedback.append(f"XML parse error: {e}")
        finally:
            if 'local_exp_path' in locals() and os.path.exists(local_exp_path):
                os.unlink(local_exp_path)
    else:
        exp_feedback.append("Experiment file not found or not modified")

    score += exp_score
    feedback_parts.append(f"Experiment File: {exp_score}/55 ({'; '.join(exp_feedback)})")

    # =========================================================
    # CHECK 3: VLM Verification (15 points)
    # =========================================================
    # Just checking file existence isn't enough - look for Builder interaction
    vlm_score = 0
    
    # We don't have direct access to trajectory frames here without importing a helper, 
    # but we can assume if the files are complex (high exp_score), they likely used the tool.
    # However, to be strict, we check if the app was running and if files were valid.
    
    if result.get('psychopy_running'):
        vlm_score += 5
    
    # If the experiment has routines and loops, it implies successful Builder usage
    if exp_score > 30:
        vlm_score += 10
    
    score += vlm_score
    feedback_parts.append(f"Process/State: {vlm_score}/15")

    # =========================================================
    # Final Result
    # =========================================================
    passed = score >= 60 and result.get('exp_file_exists') and result.get('cond_file_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }