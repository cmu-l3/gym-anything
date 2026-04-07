#!/usr/bin/env python3
"""
Verifier for configure_actuated_tsp task.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import re
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_actuated_tsp(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    score = 0
    feedback_parts = []
    
    # 1. Fetch Task Results JSON
    result_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)
            
    tls_modified = result.get('tls_modified', False)
    tripinfo_exists = result.get('tripinfo_exists', False)
    report_exists = result.get('report_exists', False)
    
    # Check Anti-Gaming constraint
    if not tls_modified:
        feedback_parts.append("TLS file was not modified after task started (score=0).")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # 2. Fetch and parse the original/modified TLS configuration
    bak_path = tempfile.mktemp(suffix=".xml")
    mod_path = tempfile.mktemp(suffix=".xml")
    
    tls_type_actuated = False
    min_dur_correct = False
    max_dur_correct = False
    states_preserved = False
    
    try:
        copy_from_env("/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_tls.add.xml.bak", bak_path)
        copy_from_env("/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_tls.add.xml", mod_path)
        
        tree_orig = ET.parse(bak_path)
        root_orig = tree_orig.getroot()
        
        tree_mod = ET.parse(mod_path)
        root_mod = tree_mod.getroot()
        
        tls_type_actuated = True
        min_dur_correct = True
        max_dur_correct = True
        states_preserved = True
        has_tl = False
        
        for orig_tl in root_orig.findall('tlLogic'):
            has_tl = True
            tl_id = orig_tl.get('id')
            
            # Find corresponding modified tlLogic
            mod_tl = None
            for tl in root_mod.findall('tlLogic'):
                if tl.get('id') == tl_id:
                    mod_tl = tl
                    break
                    
            if mod_tl is None:
                tls_type_actuated = False
                continue
                
            if mod_tl.get('type') != 'actuated':
                tls_type_actuated = False
                
            orig_phases = list(orig_tl.findall('phase'))
            mod_phases = list(mod_tl.findall('phase'))
            
            if len(orig_phases) != len(mod_phases):
                states_preserved = False
                min_dur_correct = False
                max_dur_correct = False
                continue
                
            for op, mp in zip(orig_phases, mod_phases):
                orig_dur = float(op.get('duration', 0))
                exp_min = max(5, round(orig_dur * 0.5))
                exp_max = round(orig_dur * 1.5)
                
                try:
                    mod_min = float(mp.get('minDur', -999))
                    mod_max = float(mp.get('maxDur', -999))
                except ValueError:
                    mod_min, mod_max = -999, -999
                    
                if abs(mod_min - exp_min) > 2:
                    min_dur_correct = False
                if abs(mod_max - exp_max) > 2:
                    max_dur_correct = False
                if mp.get('state') != op.get('state'):
                    states_preserved = False
                    
        if not has_tl:
            tls_type_actuated = False
            
    except Exception as e:
        logger.error(f"Error parsing XML files: {e}")
        feedback_parts.append("Failed to parse modified TLS XML")
        tls_type_actuated = False
    finally:
        if os.path.exists(bak_path): os.remove(bak_path)
        if os.path.exists(mod_path): os.remove(mod_path)

    # Scoring XML properties
    if tls_type_actuated:
        score += 25
        feedback_parts.append("TLS type='actuated' correct (25 pts)")
    else:
        feedback_parts.append("Missing or incorrect TLS type")
        
    if min_dur_correct:
        score += 15
        feedback_parts.append("Phase minDur values correct (15 pts)")
        
    if max_dur_correct:
        score += 15
        feedback_parts.append("Phase maxDur values correct (15 pts)")
        
    if states_preserved:
        score += 10
        feedback_parts.append("Phase states preserved (10 pts)")
    else:
        feedback_parts.append("Phase state strings were altered or missing")

    # 3. Analyze Trip Info output and Report contents
    tripinfo_path = tempfile.mktemp(suffix=".xml")
    report_path = tempfile.mktemp(suffix=".txt")
    
    bus_count = 0
    avg_dur = 0.0
    avg_wait = 0.0
    
    simulation_completed = False
    
    if tripinfo_exists:
        try:
            copy_from_env("/home/ga/SUMO_Scenarios/bologna_pasubio/tripinfos.xml", tripinfo_path)
            trip_tree = ET.parse(tripinfo_path)
            trip_root = trip_tree.getroot()
            
            trips = trip_root.findall('tripinfo')
            if len(trips) > 0:
                simulation_completed = True
                score += 15
                feedback_parts.append("Simulation executed successfully (15 pts)")
                
                total_dur = 0
                total_wait = 0
                for trip in trips:
                    if 'bus' in trip.get('id', '').lower():
                        bus_count += 1
                        total_dur += float(trip.get('duration', 0))
                        total_wait += float(trip.get('waitingTime', 0))
                        
                if bus_count > 0:
                    avg_dur = total_dur / bus_count
                    avg_wait = total_wait / bus_count
        except Exception as e:
            logger.error(f"Error parsing tripinfos: {e}")
            feedback_parts.append("Invalid tripinfos.xml generated")
    else:
        feedback_parts.append("Simulation output tripinfos.xml not found")
        
    # Check the actual extracted text summary report
    if report_exists:
        try:
            copy_from_env("/home/ga/SUMO_Output/bus_travel_times.txt", report_path)
            with open(report_path, 'r') as f:
                report_text = f.read()
                
            match_trips = re.search(r'bus_trips_completed:\s*(\d+)', report_text, re.IGNORECASE)
            match_dur = re.search(r'avg_duration_s:\s*([\d\.]+)', report_text, re.IGNORECASE)
            match_wait = re.search(r'avg_waitingTime_s:\s*([\d\.]+)', report_text, re.IGNORECASE)
            
            bus_trips_ok = match_trips and int(match_trips.group(1)) == bus_count and bus_count > 0
            bus_dur_ok = match_dur and abs(float(match_dur.group(1)) - avg_dur) < 5.0
            bus_wait_ok = match_wait and abs(float(match_wait.group(1)) - avg_wait) < 5.0
            
            if bus_trips_ok and bus_dur_ok and bus_wait_ok:
                score += 15
                feedback_parts.append("Bus summary perfectly extracted (15 pts)")
            elif bus_trips_ok or bus_dur_ok or bus_wait_ok:
                score += 7
                feedback_parts.append("Bus summary partially extracted (7 pts)")
            else:
                feedback_parts.append("Bus summary missing or incorrect values")
        except Exception as e:
            logger.error(f"Error reading report: {e}")
            feedback_parts.append("Could not process report text file")
    else:
        feedback_parts.append("Report bus_travel_times.txt not created")

    # 4. VLM Verification (Trajectory checking)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "Review these trajectory screenshots showing a traffic simulation workflow. "
                "Did the user use a text editor to modify XML configuration files, "
                "then run 'sumo' (a traffic simulator) in a terminal window, and examine/process data?"
                "\nRespond in JSON format: {\"workflow_detected\": true/false, \"observations\": \"what you see\"}"
            )
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('workflow_detected', False):
                    score += 5
                    feedback_parts.append("VLM confirms workflow execution (5 pts)")
                else:
                    feedback_parts.append(f"VLM observation: {parsed.get('observations', 'No workflow detected')}")
            else:
                logger.warning("VLM call failed")
    
    # Cleanup Temp files
    if os.path.exists(tripinfo_path): os.remove(tripinfo_path)
    if os.path.exists(report_path): os.remove(report_path)

    # Calculate final pass boolean
    # Pass requires >= 60 AND TLS type changed AND simulation ran.
    passed = (score >= 60) and tls_type_actuated and simulation_completed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }