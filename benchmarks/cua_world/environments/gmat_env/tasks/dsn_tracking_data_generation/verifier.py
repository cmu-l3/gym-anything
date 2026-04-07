#!/usr/bin/env python3
"""
Verifier for dsn_tracking_data_generation@1

Evaluates the setup of a GMAT Orbit Determination Tracking Data Simulation.
It checks for the correct instantiation and configuration of Spacecraft, GroundStations,
Hardware components, TrackingFileSet, and Simulator, as well as the validity of the generated
measurement data (.gmd) file.

Scoring (total 100 pts, pass >= 70):
  - script_created (10): Script created during task window.
  - spacecraft_configured (10): Sun-centered frame and correct Cartesian velocity.
  - hardware_created (15): Transponders, Transmitters, Receivers, Antennas instantiated.
  - stations_configured (15): DSS14, DSS43, DSS63 defined with proper geodetic coordinates.
  - tracking_set_configured (15): TrackingFileSet defined for Range & RangeRate.
  - simulator_executed (15): Simulator defined and RunSimulator sequence executed.
  - gmd_file_exists (10): The target output file was successfully created.
  - gmd_data_valid (10): Contains >= 100 non-comment lines of tracking data.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dsn_tracking_data_generation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    script_path = metadata.get('script_path', '/home/ga/GMAT_output/dsn_sim.script')
    gmd_path = metadata.get('gmd_path', '/home/ga/GMAT_output/mars_tracking_sim.gmd')
    min_records = metadata.get('min_tracking_records', 100)

    scores = {
        "script_created": 10,
        "spacecraft_configured": 10,
        "hardware_created": 15,
        "stations_configured": 15,
        "tracking_set_configured": 15,
        "simulator_executed": 15,
        "gmd_file_exists": 10,
        "gmd_data_valid": 10,
    }

    total_score = 0
    feedback = []

    # 1. Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: Script Created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Analyze Script Content
    script_content = ""
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read script: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # Criterion 2: Spacecraft Configured (Sun-centered, ~1.49e8 X, 33 VY)
    sc_configured = False
    if script_content:
        has_sun_frame = re.search(r'CoordinateSystem\s*=\s*\w*(Sun|Heliocentric)', script_content, re.IGNORECASE)
        has_x = re.search(r'X\s*=\s*1\.49[0-9]*e\+?0?8', script_content, re.IGNORECASE)
        has_vy = re.search(r'VY\s*=\s*33\.0?', script_content, re.IGNORECASE)
        
        if has_sun_frame and (has_x or has_vy):
            total_score += scores["spacecraft_configured"]
            sc_configured = True
            feedback.append("Spacecraft correctly configured in Sun-centered frame.")
        else:
            feedback.append("Spacecraft not properly configured for heliocentric state.")

    # Criterion 3: Hardware Created
    hw_configured = False
    if script_content:
        has_transponder = "Create Transponder" in script_content
        has_transmitter = "Create Transmitter" in script_content
        has_receiver = "Create Receiver" in script_content
        has_antenna = "Create Antenna" in script_content
        
        if has_transponder and has_transmitter and has_receiver and has_antenna:
            total_score += scores["hardware_created"]
            hw_configured = True
            feedback.append("All OD hardware components (Transponder, Transmitter, Receiver, Antenna) defined.")
        else:
            feedback.append("Missing one or more OD hardware components.")

    # Criterion 4: Stations Configured
    stations_ok = False
    if script_content:
        has_goldstone = re.search(r'35\.42[0-9]', script_content) and re.search(r'243\.12[0-9]', script_content)
        has_canberra = re.search(r'-35\.4[0-9]', script_content) and re.search(r'148\.98[0-9]', script_content)
        has_madrid = re.search(r'40\.43[0-9]', script_content) and re.search(r'355\.75[0-9]', script_content)
        
        if has_goldstone and has_canberra and has_madrid:
            total_score += scores["stations_configured"]
            stations_ok = True
            feedback.append("All 3 DSN stations defined with correct geodetic coordinates.")
        else:
            feedback.append("GroundStations missing or coordinates incorrect.")

    # Criterion 5: TrackingFileSet Configured
    tfs_ok = False
    if script_content:
        has_tfs = "Create TrackingFileSet" in script_content
        has_range = re.search(r'Range|DSN_SeqRange', script_content, re.IGNORECASE)
        has_rangerate = re.search(r'RangeRate|DSN_TCP', script_content, re.IGNORECASE)
        
        if has_tfs and has_range and has_rangerate:
            total_score += scores["tracking_set_configured"]
            tfs_ok = True
            feedback.append("TrackingFileSet configured for Range and RangeRate.")
        else:
            feedback.append("TrackingFileSet missing or data types incorrect.")

    # Criterion 6: Simulator Executed
    sim_ok = False
    if script_content:
        has_simulator = "Create Simulator" in script_content
        has_run = "RunSimulator" in script_content
        if has_simulator and has_run:
            total_score += scores["simulator_executed"]
            sim_ok = True
            feedback.append("Simulator defined and RunSimulator executed in sequence.")
        else:
            feedback.append("Simulator not defined or missing RunSimulator command.")

    # 3. Analyze GMD file
    gmd_file_rerun = task_result.get('gmd_file_rerun', {})
    
    # Criterion 7: GMD File Exists
    gmd_exists = False
    if isinstance(gmd_file_rerun, dict) and gmd_file_rerun.get('exists'):
        total_score += scores["gmd_file_exists"]
        gmd_exists = True
        feedback.append("Output GMD file successfully generated.")
    else:
        feedback.append("Output GMD file was not generated.")

    # Criterion 8: GMD Data Valid
    data_valid = False
    if gmd_exists:
        temp_gmd = tempfile.NamedTemporaryFile(delete=False, suffix='.gmd')
        try:
            copy_from_env(gmd_path, temp_gmd.name)
            with open(temp_gmd.name, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                
            # Count data lines (ignoring comments starting with '%')
            data_lines = [line for line in lines if line.strip() and not line.strip().startswith('%')]
            
            if len(data_lines) >= min_records:
                total_score += scores["gmd_data_valid"]
                data_valid = True
                feedback.append(f"GMD file contains valid tracking records ({len(data_lines)} lines).")
            else:
                feedback.append(f"GMD file exists but contains too few records ({len(data_lines)}).")
        except Exception as e:
            feedback.append(f"Failed to read GMD file for validation: {e}")
        finally:
            if os.path.exists(temp_gmd.name):
                os.unlink(temp_gmd.name)

    # Determine passing status
    passed = (total_score >= 70) and gmd_exists and data_valid

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback),
        "details": {
            "script_created": script_file.get('created_during_task', False),
            "spacecraft_configured": sc_configured,
            "hardware_created": hw_configured,
            "stations_configured": stations_ok,
            "tracking_set_configured": tfs_ok,
            "simulator_executed": sim_ok,
            "gmd_exists": gmd_exists,
            "gmd_data_valid": data_valid
        }
    }