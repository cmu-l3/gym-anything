#!/usr/bin/env python3
"""
Verifier for implement_new_bus_stop task in SUMO.

Verifies the spatial data integration of a new public transit stop, 
routing schedule configuration, output configuration, and resulting simulation data.
"""

import os
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def safe_parse_xml(file_path):
    """Safely parse XML file and return the root element."""
    if not os.path.exists(file_path):
        return None
    try:
        tree = ET.parse(file_path)
        return tree.getroot()
    except ET.ParseError as e:
        logger.error(f"Failed to parse XML {file_path}: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error parsing XML {file_path}: {e}")
        return None


def verify_implement_new_bus_stop(traj, env_info, task_info):
    """
    Evaluates the bus stop implementation workflow.

    CRITERIA:
    1. sumocfg has stopinfo-output element (10 pts)
    2. bus_stops.add.xml defines new_community_stop (20 pts)
    3. busses.rou.xml adds 30-sec stop for the bus (20 pts)
    4. stopinfos.xml was successfully generated and shows the actual bus stopping (30 pts)
    5. new_stop_report.txt exists and contains some findings (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stop_id = metadata.get('expected_stop_id', 'new_community_stop')
    expected_duration = metadata.get('expected_duration', 30)

    score = 0
    feedback_parts = []
    
    # 1. Fetch metadata result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)

    # Dictionary to hold local paths of fetched files
    local_files = {}
    files_to_fetch = [
        ("run.sumocfg.xml", result.get("sumocfg_exists")),
        ("pasubio_bus_stops.add.xml", result.get("bus_stops_exists")),
        ("pasubio_busses.rou.xml", result.get("busses_exists")),
        ("stopinfos.xml", result.get("stopinfos_exists")),
        ("new_stop_report.txt", result.get("report_exists"))
    ]

    # Fetch files into temporary space
    for fname, exists in files_to_fetch:
        if exists:
            tmp_f = tempfile.NamedTemporaryFile(delete=False, suffix='_' + fname)
            try:
                copy_from_env(f"/tmp/{fname}", tmp_f.name)
                local_files[fname] = tmp_f.name
            except Exception as e:
                logger.error(f"Failed to copy {fname}: {e}")
                if os.path.exists(tmp_f.name):
                    os.unlink(tmp_f.name)

    try:
        # Criterion 1: Check run.sumocfg (10 pts)
        sumocfg_path = local_files.get("run.sumocfg.xml")
        cfg_root = safe_parse_xml(sumocfg_path) if sumocfg_path else None
        has_stopinfo_output = False
        if cfg_root is not None:
            # Look for stopinfo-output element
            for elem in cfg_root.iter():
                if 'stopinfo' in elem.tag.lower() or elem.get('value', '').endswith('stopinfos.xml'):
                    has_stopinfo_output = True
                    break
        
        if has_stopinfo_output:
            score += 10
            feedback_parts.append("Configured stopinfo-output (+10)")
        else:
            feedback_parts.append("Missing <stopinfo-output> in run.sumocfg")

        # Criterion 2: Check pasubio_bus_stops.add.xml (20 pts)
        stops_path = local_files.get("pasubio_bus_stops.add.xml")
        stops_root = safe_parse_xml(stops_path) if stops_path else None
        has_stop_def = False
        if stops_root is not None:
            for bus_stop in stops_root.findall('.//busStop'):
                if bus_stop.get('id') == expected_stop_id:
                    has_stop_def = True
                    break
        
        if has_stop_def:
            score += 20
            feedback_parts.append("Defined new_community_stop (+20)")
        else:
            feedback_parts.append(f"Bus stop '{expected_stop_id}' not found in definitions")

        # Criterion 3: Check pasubio_busses.rou.xml (20 pts)
        routes_path = local_files.get("pasubio_busses.rou.xml")
        routes_root = safe_parse_xml(routes_path) if routes_path else None
        has_route_stop = False
        if routes_root is not None:
            for stop in routes_root.findall('.//stop'):
                b_stop = stop.get('busStop', '')
                dur = stop.get('duration', '0')
                try:
                    dur_val = float(dur)
                except ValueError:
                    dur_val = 0
                
                if b_stop == expected_stop_id and dur_val >= expected_duration:
                    has_route_stop = True
                    break

        if has_route_stop:
            score += 20
            feedback_parts.append("Added stop instruction to bus route (+20)")
        else:
            feedback_parts.append(f"Missing or invalid <stop> instruction for '{expected_stop_id}'")

        # Criterion 4: Simulation Execution -> stopinfos.xml (30 pts)
        # It must be created AFTER the task started (anti-gaming check)
        stopinfos_path = local_files.get("stopinfos.xml")
        stopinfos_mtime = result.get("stopinfos_mtime", 0)
        sim_success = False

        if stopinfos_path and stopinfos_mtime >= task_start:
            sim_root = safe_parse_xml(stopinfos_path)
            if sim_root is not None:
                for sinfo in sim_root.findall('.//stopinfo'):
                    if sinfo.get('busStop') == expected_stop_id:
                        try:
                            started = float(sinfo.get('started', 0))
                            ended = float(sinfo.get('ended', 0))
                            if (ended - started) >= expected_duration:
                                sim_success = True
                                break
                        except ValueError:
                            pass
        
        if sim_success:
            score += 30
            feedback_parts.append("Simulation successfully generated stopinfo data (+30)")
        elif stopinfos_path:
            feedback_parts.append("Simulation ran but target stop was not fully served (duration missed or bus didn't stop)")
        else:
            feedback_parts.append("Simulation did not run or stopinfos.xml was not generated")

        # Criterion 5: Analytical Report (20 pts)
        report_path = local_files.get("new_stop_report.txt")
        report_mtime = result.get("report_mtime", 0)
        has_report = False

        if report_path and report_mtime >= task_start:
            try:
                with open(report_path, 'r') as f:
                    content = f.read().lower()
                    if len(content.strip()) > 10 and expected_stop_id.replace("_", " ") in content or "target_edge" in content or "time" in content:
                        has_report = True
            except Exception:
                pass

        if has_report:
            score += 20
            feedback_parts.append("Summary report created (+20)")
        else:
            feedback_parts.append("Summary report missing or inadequate")

    finally:
        # Cleanup temporary files
        for path in local_files.values():
            if os.path.exists(path):
                try:
                    os.unlink(path)
                except:
                    pass

    # A successful run strictly requires the simulation to have worked
    key_criteria_met = sim_success and has_stop_def and has_route_stop
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }