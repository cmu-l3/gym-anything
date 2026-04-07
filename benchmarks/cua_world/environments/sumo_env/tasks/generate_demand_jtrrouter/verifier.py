#!/usr/bin/env python3
"""
Verifier for generate_demand_jtrrouter task.

Programmatic Verification checks:
1. Expected files exist and were created during the task.
2. flows.xml correctness (attributes match constraints).
3. turns.xml correctness (multiple valid turn edges).
4. Network Topology (verify that the turns declared actually exist in the .net.xml).
5. jtr_routes.rou.xml generated and valid.
6. jtr.sumocfg valid.
7. jtr_tripinfo.xml has completed trips (proves the scenario works end-to-end).
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_xml_safe(file_path):
    """Safely parse an XML file and return the root, or None if invalid."""
    try:
        tree = ET.parse(file_path)
        return tree.getroot()
    except Exception as e:
        logger.error(f"Failed to parse XML {file_path}: {e}")
        return None

def verify_generate_demand_jtrrouter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Load exported result JSON
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    files_info = result.get('files', {})
    flows_info = files_info.get('flows', {})
    turns_info = files_info.get('turns', {})
    routes_info = files_info.get('routes', {})
    sumocfg_info = files_info.get('sumocfg', {})
    tripinfo_info = files_info.get('tripinfo', {})

    # Criterion 1: Files Existence & Anti-Gaming (10 pts)
    all_exist = all([f.get('exists', False) for f in [flows_info, turns_info, routes_info, sumocfg_info, tripinfo_info]])
    all_created_during = all([f.get('created_during_task', False) for f in [flows_info, turns_info, routes_info, sumocfg_info, tripinfo_info]])

    if all_exist and all_created_during:
        score += 10
        feedback_parts.append("All required files created during task.")
    elif all_exist:
        score += 5
        feedback_parts.append("Files exist but some were not created during the task window.")
    else:
        feedback_parts.append("Not all required output files exist.")

    # We need to copy files to verify contents
    temp_dir = tempfile.mkdtemp()
    
    def fetch_file(remote_path, local_name):
        local_path = os.path.join(temp_dir, local_name)
        try:
            copy_from_env(remote_path, local_path)
            if os.path.getsize(local_path) > 0:
                return local_path
        except Exception:
            pass
        return None

    local_flows = fetch_file(metadata['flows_file'], "flows.xml")
    local_turns = fetch_file(metadata['turns_file'], "turns.xml")
    local_routes = fetch_file(metadata['routes_file'], "jtr_routes.rou.xml")
    local_sumocfg = fetch_file(metadata['sumocfg_file'], "jtr.sumocfg")
    local_tripinfo = fetch_file(metadata['tripinfo_file'], "jtr_tripinfo.xml")
    local_net = fetch_file(metadata['network_file'], "pasubio_buslanes.net.xml")

    # Tracking valid variables for dependency checks
    flow_edge = None
    turn_edges = []
    
    # Criterion 2: flows.xml valid (15 pts)
    if local_flows:
        root = parse_xml_safe(local_flows)
        if root is not None:
            # Find a flow element
            flow_elem = root.find('.//flow') if root.tag != 'flow' else root
            if flow_elem is not None:
                vehs = flow_elem.get('vehsPerHour', '')
                begin = flow_elem.get('begin', '')
                end = flow_elem.get('end', '')
                flow_edge = flow_elem.get('from', '')
                
                if vehs == '600' and begin == '0' and end == '3600' and flow_edge:
                    score += 15
                    feedback_parts.append("flows.xml correctly configured.")
                else:
                    score += 5
                    feedback_parts.append("flows.xml found but parameters (vehsPerHour, begin, end, from) do not exactly match requirements.")
            else:
                feedback_parts.append("flows.xml missing <flow> element.")
        else:
            feedback_parts.append("flows.xml is invalid XML.")
    
    # Criterion 3: turns.xml valid (15 pts)
    if local_turns:
        root = parse_xml_safe(local_turns)
        if root is not None:
            interval_elem = root.find('.//interval') if root.tag != 'interval' else root
            if interval_elem is not None:
                i_begin = interval_elem.get('begin', '')
                i_end = interval_elem.get('end', '')
                
                # Turn definitions can be <fromEdge> -> <toEdge> OR <edgeRelation>
                from_edges = interval_elem.findall('.//fromEdge')
                edge_relations = interval_elem.findall('.//edgeRelation')
                
                turn_from_edge = None
                
                if from_edges:
                    for fe in from_edges:
                        if fe.get('id') == flow_edge or turn_from_edge is None:
                            turn_from_edge = fe.get('id')
                            to_edges = fe.findall('.//toEdge')
                            turn_edges = [te.get('id') for te in to_edges if te.get('id')]
                elif edge_relations:
                    for er in edge_relations:
                        tf = er.get('from')
                        if tf == flow_edge or turn_from_edge is None:
                            turn_from_edge = tf
                            turn_edges.append(er.get('to'))
                            
                if i_begin == '0' and i_end == '3600' and len(turn_edges) >= 2:
                    score += 15
                    feedback_parts.append("turns.xml correctly configured with multiple turn options.")
                else:
                    score += 5
                    feedback_parts.append(f"turns.xml found but invalid interval or missing multiple turn targets (found {len(turn_edges)}).")
            else:
                feedback_parts.append("turns.xml missing <interval> element.")
        else:
            feedback_parts.append("turns.xml is invalid XML.")

    # Criterion 4: Topology validation (15 pts)
    if local_net and flow_edge and len(turn_edges) >= 2:
        root = parse_xml_safe(local_net)
        if root is not None:
            connections = root.findall('.//connection')
            valid_connections = set()
            for conn in connections:
                valid_connections.add((conn.get('from'), conn.get('to')))
            
            valid_count = sum(1 for te in turn_edges if (flow_edge, te) in valid_connections)
            
            if valid_count >= 2:
                score += 15
                feedback_parts.append("Network topology validated: specified turns exist at a junction.")
            else:
                feedback_parts.append(f"Network topology validation failed: requested turns do not physically connect from {flow_edge}.")
        else:
            feedback_parts.append("Could not parse network file for topology validation.")

    # Criterion 5: routes.xml valid (15 pts)
    if local_routes:
        root = parse_xml_safe(local_routes)
        if root is not None:
            vehicles = root.findall('.//vehicle')
            if len(vehicles) > 50: # Expecting around ~600 vehicles total
                score += 15
                feedback_parts.append(f"jtr_routes.rou.xml successfully generated {len(vehicles)} vehicle routes.")
            else:
                score += 5
                feedback_parts.append(f"jtr_routes.rou.xml generated but too few vehicles ({len(vehicles)}).")
        else:
            feedback_parts.append("jtr_routes.rou.xml is invalid XML.")

    # Criterion 6: sumocfg valid (10 pts)
    if local_sumocfg:
        root = parse_xml_safe(local_sumocfg)
        if root is not None:
            input_net = root.find('.//net-file')
            input_route = root.find('.//route-files')
            output_tripinfo = root.find('.//tripinfo-output')
            
            if input_net is not None and input_route is not None and output_tripinfo is not None:
                score += 10
                feedback_parts.append("Simulation config properly references required inputs/outputs.")
            else:
                score += 5
                feedback_parts.append("Simulation config missing required elements.")
        else:
            feedback_parts.append("Simulation config is invalid XML.")

    # Criterion 7: tripinfo output valid (20 pts)
    if local_tripinfo:
        root = parse_xml_safe(local_tripinfo)
        if root is not None:
            trips = root.findall('.//tripinfo')
            if len(trips) > 10:
                score += 20
                feedback_parts.append(f"Simulation successfully executed and completed {len(trips)} trips.")
            else:
                feedback_parts.append("Simulation executed but very few or zero completed trips found.")
        else:
            feedback_parts.append("Tripinfo output is invalid XML.")

    passed = score >= 70 and all_exist

    # Cleanup temp dir
    import shutil
    shutil.rmtree(temp_dir, ignore_errors=True)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }