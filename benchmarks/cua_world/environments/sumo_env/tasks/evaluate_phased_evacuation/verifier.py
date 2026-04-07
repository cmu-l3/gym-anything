#!/usr/bin/env python3
"""
Verifier for evaluate_phased_evacuation task.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_evaluate_phased_evacuation(traj, env_info, task_info):
    """
    Verifies the phased vs uncoordinated evacuation evaluation.
    
    Criteria:
    1. Directory & Route Generation (20 points)
    2. Configuration Setup (20 points)
    3. Simulation Execution (30 points)
    4. Analytical Accuracy (30 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read task execution metadata
    meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", meta_file.name)
        with open(meta_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read execution metadata: {e}"}
    finally:
        if os.path.exists(meta_file.name):
            os.unlink(meta_file.name)

    dir_exists = result.get('dir_exists', False)
    if not dir_exists:
        return {"passed": False, "score": 0, "feedback": "Evacuation directory not created."}

    # Helper function to fetch files from env
    def get_env_file(filename):
        tmp_f = tempfile.NamedTemporaryFile(delete=False)
        try:
            success = copy_from_env(f"/tmp/evac_{filename}", tmp_f.name)
            if success:
                return tmp_f.name
        except Exception:
            pass
        os.unlink(tmp_f.name)
        return None

    # Criterion 1: Routes generated (20 points)
    r_uncoord = get_env_file("uncoordinated.rou.xml")
    r_wave1 = get_env_file("wave1.rou.xml")
    r_wave2 = get_env_file("wave2.rou.xml")
    
    routes_present = r_uncoord and r_wave1 and r_wave2
    if routes_present:
        try:
            # Check they are valid XML files
            ET.parse(r_uncoord)
            ET.parse(r_wave1)
            ET.parse(r_wave2)
            score += 20
            feedback_parts.append("Route files successfully generated.")
        except ET.ParseError:
            feedback_parts.append("Generated route files are invalid XML.")
    else:
        feedback_parts.append("One or more route files missing.")
        
    for f in [r_uncoord, r_wave1, r_wave2]:
        if f and os.path.exists(f): os.unlink(f)

    # Criterion 2: Configurations Setup (20 points)
    cfg_uncoord = get_env_file("uncoordinated.sumocfg")
    cfg_phased = get_env_file("phased.sumocfg")
    
    cfg_score = 0
    if cfg_uncoord and cfg_phased:
        try:
            t_unc = ET.parse(cfg_uncoord).getroot()
            t_pha = ET.parse(cfg_phased).getroot()
            
            # Simple check to see if routes are referenced correctly
            unc_routes = t_unc.find('.//route-files')
            if unc_routes is not None and 'uncoordinated.rou.xml' in unc_routes.get('value', ''):
                cfg_score += 10
                
            pha_routes = t_pha.find('.//route-files')
            if pha_routes is not None and 'wave1.rou.xml' in pha_routes.get('value', '') and 'wave2.rou.xml' in pha_routes.get('value', ''):
                cfg_score += 10
                
            score += cfg_score
            if cfg_score == 20:
                feedback_parts.append("Configurations properly set up.")
            else:
                feedback_parts.append("Configurations missing correct route file references.")
        except ET.ParseError:
            feedback_parts.append("SUMO configurations are invalid XML.")
    else:
        feedback_parts.append("SUMO configurations missing.")

    for f in [cfg_uncoord, cfg_phased]:
        if f and os.path.exists(f): os.unlink(f)

    # Criterion 3: Simulation Execution (30 points)
    ti_uncoord = get_env_file("tripinfo_uncoordinated.xml")
    ti_phased = get_env_file("tripinfo_phased.xml")
    
    sim_executed = False
    ground_truth = {"uncoordinated": None, "phased": None}
    
    def parse_tripinfo(file_path):
        try:
            tree = ET.parse(file_path)
            trips = tree.findall('.//tripinfo')
            if len(trips) < 800:
                return None
            max_arrival = 0.0
            total_duration = 0.0
            for t in trips:
                max_arrival = max(max_arrival, float(t.get('arrival', 0)))
                total_duration += float(t.get('duration', 0))
            return {
                "clearance_time": round(max_arrival, 2),
                "average_duration": round(total_duration / len(trips), 2)
            }
        except Exception:
            return None

    if ti_uncoord and ti_phased:
        gt_unc = parse_tripinfo(ti_uncoord)
        gt_pha = parse_tripinfo(ti_phased)
        
        if gt_unc and gt_pha:
            score += 30
            sim_executed = True
            ground_truth["uncoordinated"] = gt_unc
            ground_truth["phased"] = gt_pha
            feedback_parts.append("Simulations executed successfully with >800 trips.")
        else:
            feedback_parts.append("Simulations did not complete successfully (not enough trips).")
    else:
        feedback_parts.append("Simulation outputs (tripinfo XML) are missing.")

    for f in [ti_uncoord, ti_phased]:
        if f and os.path.exists(f): os.unlink(f)

    # Criterion 4: Analytical Accuracy (30 points)
    metrics_file = get_env_file("evacuation_metrics.json")
    if metrics_file and sim_executed:
        try:
            with open(metrics_file, 'r') as f:
                agent_metrics = json.load(f)
            
            pts = 0
            for scenario in ["uncoordinated", "phased"]:
                if scenario in agent_metrics and scenario in ground_truth:
                    agt_ct = float(agent_metrics[scenario].get('clearance_time', 0))
                    agt_ad = float(agent_metrics[scenario].get('average_duration', 0))
                    gt_ct = float(ground_truth[scenario]['clearance_time'])
                    gt_ad = float(ground_truth[scenario]['average_duration'])
                    
                    if abs(agt_ct - gt_ct) <= 1.0:
                        pts += 7.5
                    if abs(agt_ad - gt_ad) <= 1.0:
                        pts += 7.5
            
            score += int(pts)
            if pts == 30:
                feedback_parts.append("Agent analytics match ground truth perfectly.")
            else:
                feedback_parts.append(f"Agent analytics partially correct (+{int(pts)}/30 pts).")
                
        except Exception as e:
            feedback_parts.append(f"Failed to parse agent metrics JSON: {e}")
    else:
        if not sim_executed:
            feedback_parts.append("Analytics check skipped because simulation failed.")
        else:
            feedback_parts.append("Metrics JSON file missing.")

    if metrics_file and os.path.exists(metrics_file):
        os.unlink(metrics_file)

    passed = score >= 70 and sim_executed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }