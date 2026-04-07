#!/usr/bin/env python3
"""
Verifier for add_parking_simulation task.
Reads XML files created by the agent, validates their schema and contents,
and checks if the simulation produced the expected output files successfully.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def safe_parse_xml(file_path):
    """Safely parse an XML file and return the root element."""
    try:
        tree = ET.parse(file_path)
        return tree.getroot()
    except Exception as e:
        logger.error(f"Failed to parse XML {file_path}: {e}")
        return None

def verify_add_parking_simulation(traj, env_info, task_info):
    """
    Verify the parking simulation task execution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temporary directory for files copied from the environment
    temp_dir = tempfile.mkdtemp()
    
    # Files to copy
    files_to_copy = {
        "result.json": "/tmp/parking_task_result.json",
        "net.xml": "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_buslanes.net.xml",
        "parking.add.xml": "/home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_parking.add.xml",
        "vehicles.rou.xml": "/home/ga/SUMO_Scenarios/bologna_pasubio/parking_vehicles.rou.xml",
        "config.sumocfg": "/home/ga/SUMO_Scenarios/bologna_pasubio/run_parking.sumocfg",
        "log.txt": "/home/ga/SUMO_Output/sumo_parking_log.txt",
        "parking_output.xml": "/home/ga/SUMO_Output/parking_output.xml"
    }

    local_paths = {}
    for key, remote_path in files_to_copy.items():
        local_path = os.path.join(temp_dir, key)
        try:
            copy_from_env(remote_path, local_path)
            if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                local_paths[key] = local_path
        except Exception as e:
            logger.warning(f"Could not copy {remote_path}: {e}")

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 0. Check result JSON for anti-gaming timestamps
    # ---------------------------------------------------------
    if "result.json" not in local_paths:
        return {"passed": False, "score": 0, "feedback": "Task export results not found."}
        
    with open(local_paths["result.json"], 'r') as f:
        try:
            result_data = json.load(f)
        except json.JSONDecodeError:
            return {"passed": False, "score": 0, "feedback": "Invalid result JSON format."}

    task_start = result_data.get("task_start", 0)
    files_meta = result_data.get("files", {})

    # ---------------------------------------------------------
    # 1. Verify parking areas file (30 points)
    # ---------------------------------------------------------
    parking_root = safe_parse_xml(local_paths.get("parking.add.xml", "")) if "parking.add.xml" in local_paths else None
    net_root = safe_parse_xml(local_paths.get("net.xml", "")) if "net.xml" in local_paths else None

    valid_lanes = set()
    if net_root is not None:
        for edge in net_root.findall('.//edge'):
            for lane in edge.findall('lane'):
                valid_lanes.add(lane.get('id', ''))

    defined_parking_areas = set()
    
    if parking_root is not None and parking_root.tag == 'additional':
        score += 10
        feedback_parts.append("Valid parking.add.xml structure")
        
        parking_areas = parking_root.findall('.//parkingArea')
        if len(parking_areas) >= 4:
            all_pa_prefix = all(pa.get('id', '').startswith('pa_') for pa in parking_areas)
            if all_pa_prefix:
                score += 5
                feedback_parts.append(">=4 parking areas with pa_ prefix")
            else:
                feedback_parts.append("Found >=4 parking areas, but some lack 'pa_' prefix")
                
            total_cap = sum(int(pa.get('roadsideCapacity', '0')) for pa in parking_areas)
            if total_cap >= 40:
                score += 5
                feedback_parts.append(f"Total capacity {total_cap} >= 40")
            else:
                feedback_parts.append(f"Total capacity {total_cap} < 40")
                
            valid_edges = True
            for pa in parking_areas:
                defined_parking_areas.add(pa.get('id', ''))
                lane = pa.get('lane', '')
                if lane not in valid_lanes:
                    valid_edges = False
            
            if valid_edges and valid_lanes:
                score += 10
                feedback_parts.append("All parking areas placed on valid network lanes")
            elif not valid_edges:
                feedback_parts.append("Some parking areas placed on invalid/non-existent lanes")
        else:
            feedback_parts.append(f"Found {len(parking_areas)} parking areas, expected >=4")
    else:
        feedback_parts.append("parking.add.xml missing or invalid")

    # ---------------------------------------------------------
    # 2. Verify vehicle routes file (25 points)
    # ---------------------------------------------------------
    routes_root = safe_parse_xml(local_paths.get("vehicles.rou.xml", "")) if "vehicles.rou.xml" in local_paths else None
    
    if routes_root is not None and routes_root.tag == 'routes':
        score += 5
        feedback_parts.append("Valid vehicles.rou.xml structure")
        
        vtypes = routes_root.findall('.//vType')
        has_parking_car = any(vt.get('id') == 'parking_car' for vt in vtypes)
        if has_parking_car:
            score += 5
            feedback_parts.append("vType 'parking_car' found")
        else:
            feedback_parts.append("vType 'parking_car' missing")
            
        vehicles = routes_root.findall('.//vehicle')
        parking_vehicles = [v for v in vehicles if v.get('type') == 'parking_car']
        
        if len(parking_vehicles) >= 5:
            score += 5
            feedback_parts.append(">= 5 parking_car vehicles found")
            
            valid_stops = 0
            for v in parking_vehicles:
                # Stop can be direct child of vehicle or inside route child
                stops = v.findall('.//stop')
                for stop in stops:
                    pa_id = stop.get('parkingArea')
                    dur = int(stop.get('duration', '0'))
                    # Check if pa_id was defined in parking file or at least has the correct prefix
                    if pa_id and pa_id.startswith('pa_') and dur >= 60:
                        valid_stops += 1
                        break
                        
            if valid_stops >= 5:
                score += 10
                feedback_parts.append("Vehicles have valid parking stops (duration >= 60)")
            else:
                feedback_parts.append(f"Only {valid_stops}/5 vehicles have valid parking stops")
        else:
            feedback_parts.append(f"Found {len(parking_vehicles)} parking vehicles, expected >= 5")
    else:
        feedback_parts.append("vehicles.rou.xml missing or invalid")

    # ---------------------------------------------------------
    # 3. Verify simulation config (10 points)
    # ---------------------------------------------------------
    config_root = safe_parse_xml(local_paths.get("config.sumocfg", "")) if "config.sumocfg" in local_paths else None
    
    config_valid = False
    if config_root is not None and config_root.tag == 'sumoConfiguration':
        input_node = config_root.find('input')
        output_node = config_root.find('output')
        
        if input_node is not None and output_node is not None:
            # Basic validation that they included necessary files
            add_files = input_node.find('additional-files')
            route_files = input_node.find('route-files')
            pa_output = output_node.find('parking-area-output')
            
            if (add_files is not None and 'pasubio_parking.add.xml' in add_files.get('value', '') and
                route_files is not None and 'parking_vehicles.rou.xml' in route_files.get('value', '') and
                pa_output is not None):
                config_valid = True
                score += 10
                feedback_parts.append("sumocfg correctly points to required input/output files")
            else:
                feedback_parts.append("sumocfg missing references to new input files or parking output")
    
    if not config_valid and config_root is None:
        feedback_parts.append("run_parking.sumocfg missing or invalid")

    # ---------------------------------------------------------
    # 4. Verify simulation execution and outputs (35 points)
    # ---------------------------------------------------------
    # Did log get generated and show no fatal errors?
    if "log.txt" in local_paths:
        with open(local_paths["log.txt"], 'r', encoding='utf-8', errors='ignore') as f:
            log_content = f.read()
            
        if "Error:" not in log_content and "Quitting (on error)" not in log_content:
            if "Simulation ended at time:" in log_content or "Success." in log_content or "Step #" in log_content:
                score += 15
                feedback_parts.append("Simulation completed without fatal errors")
            else:
                feedback_parts.append("Log file exists but simulation completion not confirmed")
        else:
            feedback_parts.append("Simulation log contains fatal errors")
    else:
        feedback_parts.append("Simulation log not found (did not run headless command?)")

    # Did parking output get generated with data?
    if "parking_output.xml" in local_paths:
        # Check if it was modified AFTER task started (anti-gaming)
        mtime = files_meta.get("parking_output", {}).get("mtime", 0)
        size = files_meta.get("parking_output", {}).get("size", 0)
        
        if mtime >= task_start and size > 100:
            score += 10
            feedback_parts.append("parking_output.xml generated and contains data")
        else:
            if size <= 100:
                feedback_parts.append("parking_output.xml is empty or nearly empty")
            else:
                feedback_parts.append("parking_output.xml timestamp predates task start")
    else:
        feedback_parts.append("parking_output.xml not found")
        
    # Check tripinfo as supplementary confirmation
    tripinfo_size = files_meta.get("tripinfo_output", {}).get("size", 0)
    tripinfo_mtime = files_meta.get("tripinfo_output", {}).get("mtime", 0)
    if tripinfo_size > 100 and tripinfo_mtime >= task_start:
        score += 10
        feedback_parts.append("tripinfos_parking.xml successfully generated")

    # Clean up temp dir
    try:
        import shutil
        shutil.rmtree(temp_dir)
    except Exception as e:
        logger.warning(f"Failed to clean up temp dir: {e}")

    # Determine pass/fail
    # Threshold: >= 60 points, requiring parking.add.xml basics (10), vehicles valid (5), sumocfg valid (10), and log ran (15)
    key_criteria_met = score >= 60
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }