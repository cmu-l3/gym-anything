#!/usr/bin/env python3
"""
Verifier for aggregate_edge_data task in SUMO.

Verifies:
1. XML meandata output exists and is properly formatted.
2. Interval properties are correct (300s).
3. Congestion text report exists and contains 5 ranked edges.
4. Edge IDs match real edges from the network file.
5. Analytical ranking matches ground truth computed from the XML.
6. File timestamps confirm work was done during the task block.
"""

import os
import json
import re
import tempfile
import xml.etree.ElementTree as ET
from collections import defaultdict

def verify_aggregate_edge_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Temporary paths for extracted files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_edges = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    result_data = {}
    try:
        # Load task result metadata
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export JSON: {e}"}

    # CRITERION 1: XML Exists & Timestamps (15 pts combined)
    xml_exists = result_data.get('xml_exists', False)
    xml_recent = result_data.get('xml_created_during_task', False)
    if xml_exists and xml_recent:
        score += 15
        feedback_parts.append("XML output created during task")
    elif xml_exists:
        score += 5
        feedback_parts.append("XML output exists (but timestamp check failed)")
    else:
        feedback_parts.append("XML meandata output NOT found")

    # CRITERION 2 & 3: Valid XML & Interval Check (20 pts)
    edge_data = defaultdict(list)
    intervals = []
    valid_xml = False
    interval_ok = False

    if xml_exists:
        try:
            copy_from_env("/tmp/edge_meandata.xml", temp_xml.name)
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            for interval in root.findall(".//interval"):
                begin = float(interval.get("begin", 0))
                end = float(interval.get("end", 0))
                intervals.append((begin, end))
                for edge in interval.findall("edge"):
                    eid = edge.get("id", "")
                    occ = edge.get("occupancy")
                    if eid and occ is not None and not eid.startswith(":"):
                        edge_data[eid].append(float(occ))
            
            if len(edge_data) > 0:
                valid_xml = True
                score += 10
                feedback_parts.append(f"Valid XML parsed ({len(edge_data)} edges)")
            
            if len(intervals) >= 2:
                diffs = [intervals[i+1][0] - intervals[i][0] for i in range(min(5, len(intervals)-1))]
                if all(abs(d - 300.0) < 1.0 for d in diffs):
                    interval_ok = True
                    score += 10
                    feedback_parts.append("300s interval verified")
                else:
                    feedback_parts.append(f"Intervals incorrect: {diffs}")
        except Exception as e:
            feedback_parts.append(f"Failed to parse XML: {e}")

    # Load known network edges
    network_edges = set()
    try:
        copy_from_env("/tmp/network_edge_ids.txt", temp_edges.name)
        with open(temp_edges.name, 'r') as f:
            network_edges = {line.strip() for line in f if line.strip()}
    except Exception:
        pass

    # CRITERION 4: Report Exists (10 pts)
    report_exists = result_data.get('report_exists', False)
    report_recent = result_data.get('report_created_during_task', False)
    
    if report_exists and report_recent:
        score += 10
        feedback_parts.append("Congestion report created")
    elif report_exists:
        score += 5
        feedback_parts.append("Congestion report exists (timestamp failed)")
    else:
        feedback_parts.append("Congestion report NOT found")

    # CRITERION 5, 6, 7: Parse Report (30 pts)
    report_edges = []
    report_values = []
    
    if report_exists:
        try:
            copy_from_env("/tmp/congestion_report.txt", temp_report.name)
            with open(temp_report.name, 'r') as f:
                for line in f:
                    line = line.strip()
                    # Match pattern: optional numbering, edge id, occupancy val
                    match = re.search(r'(?:^\d+\.\s*)?([A-Za-z0-9_\-]+)\s+.*occupancy\s*[=:]\s*([0-9.]+)', line, re.IGNORECASE)
                    if match:
                        report_edges.append(match.group(1))
                        report_values.append(float(match.group(2)))
        except Exception as e:
            feedback_parts.append(f"Error reading report: {e}")

    if len(report_edges) >= 5:
        score += 10
        feedback_parts.append("Report has 5+ extracted edges")
    elif len(report_edges) > 0:
        score += 5
        feedback_parts.append(f"Report has only {len(report_edges)} edges")
        
    valid_ids_count = sum(1 for e in report_edges[:5] if e in network_edges)
    if valid_ids_count == 5 and network_edges:
        score += 10
        feedback_parts.append("All top 5 edge IDs exist in network")
    elif valid_ids_count > 0:
        score += (valid_ids_count * 2)
        feedback_parts.append(f"{valid_ids_count}/5 edge IDs are valid")
        
    if len(report_values) >= 5 and all(0 <= v <= 100 for v in report_values[:5]):
        score += 10
        feedback_parts.append("Reported occupancy values are in valid range [0-100]")

    # CRITERION 8: Ranking Matches Independent Calculation (10 pts)
    ranking_ok = False
    if valid_xml and len(report_edges) >= 5:
        avg_occ = {}
        for eid, occs in edge_data.items():
            if not eid.startswith(":"):
                avg_occ[eid] = sum(occs) / len(occs)
        
        # Determine actual top 5
        top5_truth = sorted(avg_occ.items(), key=lambda x: x[1], reverse=True)[:5]
        top5_truth_ids = {e[0] for e in top5_truth}
        
        # Check against reported (allow 1 mismatch for edge cases/rounding)
        reported_top5_ids = set(report_edges[:5])
        if len(top5_truth_ids.intersection(reported_top5_ids)) >= 4:
            ranking_ok = True
            score += 10
            feedback_parts.append("Ranked edges strongly match ground truth")
        else:
            feedback_parts.append(f"Rankings differ. Expected top: {list(top5_truth_ids)}")

    # CRITERION 9: VLM Trajectory Verification (5 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "Look at these screenshots representing a task trajectory in a Linux environment. "
                    "The user is supposed to use a terminal to configure and run the headless command-line 'sumo' traffic simulator "
                    "and then write a Python script or use terminal utilities to parse output XML. "
                    "Do you see clear evidence of terminal usage, executing SUMO, or text/code editors being open? "
                    "Answer in JSON: {'terminal_used': true/false}"
                )
                vlm_result = query_vlm(images=frames, prompt=prompt)
                if vlm_result.get("success"):
                    if vlm_result.get("parsed", {}).get("terminal_used", False):
                        vlm_score = 5
                        feedback_parts.append("VLM confirmed CLI/terminal workflow")
                    else:
                        feedback_parts.append("VLM did not see terminal workflow")
    except Exception as e:
        pass # VLM check is optional fallback
    score += vlm_score

    # Cleanup temp files
    for tmp in [temp_result, temp_xml, temp_report, temp_edges]:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # Key threshold: must have created output files
    key_criteria = xml_recent and report_recent and valid_xml
    passed = (score >= 70) and key_criteria

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }