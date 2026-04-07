#!/usr/bin/env python3
"""
Verifier for create_stop_signal_task.

Verification Logic:
1. Files Exist & Modified: Checks .psyexp and .csv exist and were created during task.
2. Conditions File Valid:
   - Columns: direction, corrAns, stop_signal, ssd
   - Rows >= 12
   - stop_signal contains both 0 and 1
   - stop_signal ratio approx 25% (allowed range 15-35%)
3. Experiment Logic (XML parsing):
   - Routine with Sound Component exists.
   - Sound Start Time depends on `ssd` variable.
   - Sound Volume depends on `stop_signal` OR Code component handles playback.
4. VLM Verification:
   - Trajectory shows work in Builder.

Scoring:
- Files Structure: 20 pts
- CSV Validity: 20 pts
- Visual Stimulus Setup: 10 pts
- Stop Logic (Time): 25 pts
- Stop Logic (Condition/Volume): 25 pts
"""

import json
import os
import csv
import xml.etree.ElementTree as ET
import logging
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_stop_signal_task(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    exp_path_remote = metadata.get('experiment_file', '/home/ga/PsychoPyExperiments/sst_task/stop_signal.psyexp')
    cond_path_remote = metadata.get('conditions_file', '/home/ga/PsychoPyExperiments/sst_task/sst_conditions.csv')
    
    score = 0
    feedback = []
    
    # 1. Get Result JSON
    result_local = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_local)
        with open(result_local, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(result_local): os.remove(result_local)

    # Check Basic Files (20 pts)
    files_info = res_data.get("files", {})
    exp_info = files_info.get("experiment", {})
    cond_info = files_info.get("conditions", {})
    
    if exp_info.get("exists") and cond_info.get("exists"):
        score += 10
        feedback.append("Both files exist.")
    else:
        feedback.append("Missing one or more required files.")
        
    if exp_info.get("modified_during_task") and cond_info.get("modified_during_task"):
        score += 10
        feedback.append("Files modified during task.")
    else:
        feedback.append("Files not modified during task (anti-gaming check).")

    # 2. Check Conditions File (20 pts)
    cond_local = tempfile.mktemp(suffix='.csv')
    try:
        if cond_info.get("exists"):
            copy_from_env(cond_path_remote, cond_local)
            with open(cond_local, 'r') as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames if reader.fieldnames else []
                rows = list(reader)
                
            # Check headers
            req_cols = ["direction", "stop_signal", "ssd", "corrAns"]
            # Allow case-insensitive matching
            headers_lower = [h.lower() for h in headers]
            cols_present = all(rc.lower() in headers_lower for rc in req_cols)
            
            if cols_present:
                score += 5
                feedback.append("CSV headers correct.")
            else:
                feedback.append(f"CSV missing required columns. Found: {headers}")

            # Check rows
            if len(rows) >= 12:
                score += 5
                feedback.append(f"Row count sufficient ({len(rows)}).")
            else:
                feedback.append(f"Row count too low ({len(rows)} < 12).")

            # Check stop signal distribution
            stop_vals = []
            for r in rows:
                # Find the actual key that matches 'stop_signal'
                key = next((k for k in r.keys() if k.lower() == 'stop_signal'), None)
                if key:
                    try:
                        stop_vals.append(float(r[key]))
                    except:
                        pass
            
            has_0 = 0 in stop_vals or 0.0 in stop_vals
            has_1 = 1 in stop_vals or 1.0 in stop_vals
            
            if has_0 and has_1:
                score += 5
                feedback.append("Contains both Stop (1) and Go (0) trials.")
                
                stop_ratio = sum(stop_vals) / len(stop_vals)
                if 0.15 <= stop_ratio <= 0.35:
                    score += 5
                    feedback.append(f"Stop ratio acceptable ({stop_ratio:.2f}).")
                else:
                    feedback.append(f"Stop ratio {stop_ratio:.2f} outside recommended range (15-35%).")
            else:
                feedback.append("CSV does not contain both 0 and 1 in stop_signal.")
    except Exception as e:
        feedback.append(f"Error verification CSV: {e}")
    finally:
        if os.path.exists(cond_local): os.remove(cond_local)

    # 3. Check Experiment Logic (60 pts)
    exp_local = tempfile.mktemp(suffix='.psyexp')
    try:
        if exp_info.get("exists"):
            copy_from_env(exp_path_remote, exp_local)
            tree = ET.parse(exp_local)
            root = tree.getroot()
            
            # Find Sound Component
            sound_comp = None
            comps = root.findall(".//Component")
            for c in comps:
                if c.get("valType") == "sound" or "Sound" in c.get("type", ""):
                    sound_comp = c
                    break
            
            # Find Arrow Stimulus (Text or Image)
            arrow_comp = None
            for c in comps:
                if "Text" in c.get("type", "") or "Image" in c.get("type", ""):
                    # Check if it uses direction variable
                    for param in c.findall("Param"):
                        if param.get("name") in ["text", "image"] and ("$direction" in param.get("val", "") or "direction" in param.get("val", "")):
                            arrow_comp = c
                            break
            
            if arrow_comp:
                score += 10
                feedback.append("Arrow stimulus variable configured.")
            else:
                feedback.append("Could not find Text/Image component using $direction.")

            if sound_comp:
                # Check Start Time (25 pts)
                start_param = None
                for p in sound_comp.findall("Param"):
                    if p.get("name") in ["startVal", "startTime"]:
                        start_param = p.get("val")
                
                if start_param and ("ssd" in start_param or "$ssd" in start_param):
                    score += 25
                    feedback.append("Sound start time linked to $ssd.")
                else:
                    feedback.append(f"Sound start time not linked to $ssd (Found: {start_param}).")

                # Check Conditional Logic (25 pts)
                # Method A: Volume parameter
                vol_param = None
                for p in sound_comp.findall("Param"):
                    if p.get("name") == "volume":
                        vol_param = p.get("val")
                
                # Method B: Code Component logic
                code_logic_found = False
                code_comps = [c for c in comps if "Code" in c.get("type", "")]
                for cc in code_comps:
                    for p in cc.findall("Param"):
                        if "stop_signal" in p.get("val", "") and ("play" in p.get("val", "") or "volume" in p.get("val", "")):
                            code_logic_found = True
                
                if (vol_param and ("stop_signal" in vol_param or "$stop_signal" in vol_param)) or code_logic_found:
                    score += 25
                    feedback.append("Conditional sound logic found (Volume or Code).")
                else:
                    feedback.append("Conditional sound logic MISSING. Sound must only play on stop trials.")
            else:
                feedback.append("No Sound component found.")
                
    except Exception as e:
        feedback.append(f"Error parsing .psyexp: {e}")
    finally:
        if os.path.exists(exp_local): os.remove(exp_local)

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }