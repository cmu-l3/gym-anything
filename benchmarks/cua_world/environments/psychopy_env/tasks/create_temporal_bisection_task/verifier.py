#!/usr/bin/env python3
"""
Verifier for create_temporal_bisection_task.

Verification Strategy:
1. File Existence & Timestamp (10 pts): Check .psyexp and both CSVs exist and were created during task.
2. CSV Content Validation (20 pts):
   - anchors.csv: Check for 0.4 and 1.6 durations, correct columns.
   - probes.csv: Check for full range 0.4-1.6.
3. PsychoPy XML Structure (70 pts):
   - Routines: Demo, Training, Testing exist (15 pts).
   - Loops: Check loops link to correct CSVs (15 pts).
   - Variable Duration: Check that the stimulus duration uses a variable (e.g., $stim_dur) (25 pts).
   - Feedback: Check for feedback logic in Training routine (15 pts).
"""

import json
import tempfile
import os
import csv
import logging
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

def verify_create_temporal_bisection_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path = metadata.get('exp_file', '/home/ga/PsychoPyExperiments/temporal_bisection.psyexp')
    anchors_path = metadata.get('anchors_file', '/home/ga/PsychoPyExperiments/conditions/anchors.csv')
    probes_path = metadata.get('probes_file', '/home/ga/PsychoPyExperiments/conditions/probes.csv')

    score = 0
    feedback_parts = []
    
    # 1. Load basic result stats
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_json = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_json)
        with open(tmp_json, 'r') as f:
            result_stats = json.load(f)
        os.unlink(tmp_json)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result stats: {str(e)}"}

    # Nonce check
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        os.unlink(nonce_path)
        
        if result_stats.get("result_nonce") != expected_nonce:
             return {"passed": False, "score": 0, "feedback": "Anti-gaming check failed (nonce mismatch)."}
    except:
        pass # Ignore if nonce file missing in env (e.g. legacy setup)

    # Check file existence points
    files_created = (
        result_stats['exp_file']['created_during'] and 
        result_stats['anchors_file']['created_during'] and 
        result_stats['probes_file']['created_during']
    )
    if files_created:
        score += 10
        feedback_parts.append("All files created during task.")
    elif result_stats['exp_file']['exists']:
        score += 5
        feedback_parts.append("Files exist but timestamp verification failed.")
    else:
        feedback_parts.append("Missing required files.")
        return {"passed": False, "score": 0, "feedback": "Main experiment file not found."}

    # 2. Verify CSV Content (20 pts)
    # ----------------------------
    # Verify Anchors
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            local_anchors = tmp.name
        copy_from_env(anchors_path, local_anchors)
        
        with open(local_anchors, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            headers = reader.fieldnames if reader.fieldnames else []
            
        # Check columns
        if 'stim_dur' in headers and 'corr_key' in headers:
            score += 5
            feedback_parts.append("Anchors CSV headers correct.")
        
        # Check values
        durs = [float(r.get('stim_dur', 0)) for r in rows]
        if 0.4 in durs and 1.6 in durs:
            score += 5
            feedback_parts.append("Anchors values correct.")
            
        os.unlink(local_anchors)
    except Exception as e:
        feedback_parts.append(f"Anchors CSV check failed: {str(e)}")

    # Verify Probes
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            local_probes = tmp.name
        copy_from_env(probes_path, local_probes)
        
        with open(local_probes, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
        durs = [float(r.get('stim_dur', 0)) for r in rows]
        # Check for range roughly
        if len(durs) >= 5 and 0.4 in durs and 1.0 in durs and 1.6 in durs:
            score += 10
            feedback_parts.append("Probes CSV values correct.")
        
        os.unlink(local_probes)
    except Exception as e:
        feedback_parts.append(f"Probes CSV check failed: {str(e)}")

    # 3. Verify PsychoPy XML (70 pts)
    # ------------------------------
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.psyexp') as tmp:
            local_exp = tmp.name
        copy_from_env(exp_path, local_exp)
        
        tree = ET.parse(local_exp)
        root = tree.getroot()
        
        # Check Routines
        routines = root.findall(".//Routine")
        routine_names = [r.get('name') for r in routines]
        
        has_demo = any('demo' in n.lower() for n in routine_names)
        has_train = any('train' in n.lower() for n in routine_names)
        has_test = any('test' in n.lower() for n in routine_names)
        
        if has_demo and has_train and has_test:
            score += 15
            feedback_parts.append("All 3 routines found.")
        elif has_train and has_test:
            score += 10
            feedback_parts.append("Training and Testing routines found.")
            
        # Check Loops (Flow)
        loops = root.findall(".//LoopInitiator")
        loop_valid = False
        anchors_linked = False
        probes_linked = False
        
        for loop in loops:
            params = {p.get('name'): p.get('val') for p in loop.findall(".//Param")}
            cond_file = params.get('conditionsFile', '')
            if 'anchors' in cond_file:
                anchors_linked = True
            if 'probes' in cond_file:
                probes_linked = True
        
        if anchors_linked and probes_linked:
            score += 15
            feedback_parts.append("Loops correctly linked to CSVs.")
        
        # Check Variable Duration (CRITICAL)
        # Look for Polygon/Shape components in routines
        variable_dur_found = False
        feedback_logic_found = False
        pink_color_found = False
        
        for routine in routines:
            rname = routine.get('name').lower()
            
            # Check components
            for comp in routine:
                # Check for feedback logic
                if 'code' in comp.tag.lower() or 'code' in comp.get('name', '').lower():
                    # Simple check if code mentions conditional logic or feedback
                    # This is hard to parse perfectly from XML without CDATA inspection, 
                    # but usually stored in Param name="Begin Routine Code"
                    for param in comp.findall("Param"):
                        val = param.get('val', '')
                        if ('if' in val and 'corr' in val) or ('msg' in val):
                            feedback_logic_found = True

                # Check Visual Stimuli (Polygon, Image, etc)
                # Looking for Polygon (often named 'polygon' or 'shape')
                # But could be any visual component.
                is_visual = False
                comp_type = comp.tag # e.g. "PolygonComponent"
                if "Polygon" in comp_type or "Image" in comp_type or "Text" in comp_type:
                     # Check duration parameter
                     for param in comp.findall("Param"):
                         if param.get('name') == 'stopVal': # Duration usually set here if stopType is duration
                             val = param.get('val')
                             if '$' in val or 'dur' in val: # e.g. $stim_dur
                                 variable_dur_found = True
                         if param.get('name') == 'fillColor':
                             if 'pink' in param.get('val', '').lower():
                                 pink_color_found = True

        if variable_dur_found:
            score += 25
            feedback_parts.append("Variable duration logic detected.")
        else:
            feedback_parts.append("FAIL: Stimulus duration does not appear to use a variable.")
            
        if feedback_logic_found:
            score += 15
            feedback_parts.append("Feedback logic detected.")
            
        os.unlink(local_exp)
        
    except Exception as e:
        feedback_parts.append(f"PsychoPy XML parse failed: {str(e)}")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }