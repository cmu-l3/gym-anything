#!/usr/bin/env python3

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simulate_emergency_vehicle(traj, env_info, task_info):
    """
    Verify that an emergency vehicle was correctly configured, successfully simulated,
    and its output metrics accurately captured into a JSON file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback_parts = []
    
    # 1. Valid Emergency vType (20 points)
    amb_xml = result.get('amb_xml', '')
    vtype_valid = False
    param_valid = False
    vehicle_valid = False
    route_edges_valid = False
    
    try:
        if amb_xml:
            root = ET.fromstring(amb_xml)
            for vtype in root.findall('vType'):
                if vtype.get('id') == 'rescue':
                    if vtype.get('vClass') == 'emergency':
                        vtype_valid = True
                    for param in vtype.findall('param'):
                        if param.get('key') == 'has.bluelight.device' and param.get('value', '').lower() == 'true':
                            param_valid = True
                            
            for veh in root.findall('vehicle'):
                if veh.get('id') == 'amb_1' and veh.get('type') == 'rescue':
                    vehicle_valid = True
                    # Check route edges definition
                    edges = None
                    if 'route' in veh.attrib:
                        route_id = veh.attrib['route']
                        for r in root.findall('route'):
                            if r.get('id') == route_id:
                                edges = r.get('edges', '')
                                break
                    else:
                        route_node = veh.find('route')
                        if route_node is not None:
                            edges = route_node.get('edges', '')
                    if edges and len(edges.split()) >= 5:
                        route_edges_valid = True
    except Exception as e:
        feedback_parts.append("Error parsing ambulance.rou.xml")

    if vtype_valid and param_valid:
        score += 20
        feedback_parts.append("vType 'rescue' with emergency class and bluelight correctly defined")
    elif vtype_valid:
        score += 10
        feedback_parts.append("vType 'rescue' defined but missing bluelight param")
    else:
        feedback_parts.append("vType 'rescue' not correctly defined")

    # 2. Valid Vehicle Config (10 points)
    if vehicle_valid and route_edges_valid:
        score += 10
        feedback_parts.append("Vehicle 'amb_1' correctly defined with >= 5 edges")
    elif vehicle_valid:
        score += 5
        feedback_parts.append("Vehicle 'amb_1' defined but route has < 5 edges or is missing")
    else:
        feedback_parts.append("Vehicle 'amb_1' not correctly defined")

    # 3. Configuration Setup (15 points)
    run_cfg = result.get('run_cfg', '')
    cfg_valid = False
    try:
        if run_cfg:
            root = ET.fromstring(run_cfg)
            input_node = root.find('input')
            if input_node is not None:
                route_files = input_node.find('route-files')
                if route_files is not None:
                    val = route_files.get('value', '')
                    if 'ambulance.rou.xml' in val and 'pasubio.rou.xml' in val:
                        cfg_valid = True
    except:
        pass

    if cfg_valid:
        score += 15
        feedback_parts.append("run_emergency.sumocfg correctly loads both route files")
    else:
        feedback_parts.append("run_emergency.sumocfg invalid or missing route files")

    # 4. Simulation Success (15 points)
    amb_trip = result.get('amb_trip')
    if result.get('tripinfo_exists') and amb_trip is not None:
        score += 15
        feedback_parts.append("tripinfos.xml generated and contains completed trip for amb_1")
    else:
        feedback_parts.append("Simulation failed or amb_1 was not successfully dispatched in tripinfos.xml")

    # 5. Metric Extraction (40 points)
    agent_report = result.get('agent_report', '')
    report_valid = False
    
    if amb_trip is not None:
        try:
            if agent_report:
                report_data = json.loads(agent_report)
                d1 = float(report_data.get('duration', -1))
                d2 = float(amb_trip.get('duration'))
                l1 = float(report_data.get('routeLength', -1))
                l2 = float(amb_trip.get('routeLength'))
                t1 = float(report_data.get('timeLoss', -1))
                t2 = float(amb_trip.get('timeLoss'))
                
                # Check metrics validity against simulation ground truth to prevent gaming
                if abs(d1 - d2) <= 0.1 and abs(l1 - l2) <= 0.1 and abs(t1 - t2) <= 0.1:
                    report_valid = True
        except:
            pass

    if report_valid:
        score += 40
        feedback_parts.append("JSON report correctly extracts duration, routeLength, and timeLoss")
    else:
        if not agent_report:
            feedback_parts.append("JSON report missing or empty")
        elif amb_trip is None:
            feedback_parts.append("Cannot verify JSON report because amb_1 tripinfo is missing")
        else:
            feedback_parts.append("JSON report metrics do not match actual simulation output (Anti-Gaming Check Failed)")

    passed = (score >= 70) and report_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }