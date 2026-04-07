#!/usr/bin/env python3
"""
Verifier for record_track_statistics task.

Verifies the accuracy of extracted GPX properties written to a report file.
Combines programmatic verification with robust anti-gaming checks.
"""

import json
import os
import tempfile
import logging
import re
import math
import xml.etree.ElementTree as ET

try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def haversine(lat1, lon1, lat2, lon2):
    """Compute distance in meters between two lat/lon points."""
    R = 6371000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlam/2)**2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1-a))

def parse_gpx(gpx_path):
    """Extract ground truth properties from the GPX file."""
    tree = ET.parse(gpx_path)
    root = tree.getroot()
    
    # Detect XML namespace
    ns = ""
    if root.tag.startswith("{"):
        ns = root.tag.split("}")[0] + "}"
    
    gt = {
        "track_name": "",
        "total_distance_m": 0.0,
        "track_points": []
    }
    
    for trk in root.iter(f"{ns}trk"):
        name_el = trk.find(f"{ns}name")
        if name_el is not None and name_el.text:
            gt["track_name"] = name_el.text.strip()
        
        for trkseg in trk.iter(f"{ns}trkseg"):
            for trkpt in trkseg.iter(f"{ns}trkpt"):
                lat = float(trkpt.get("lat", 0))
                lon = float(trkpt.get("lon", 0))
                gt["track_points"].append((lat, lon))
    
    # Compute total track distance via Haversine
    pts = gt["track_points"]
    for i in range(1, len(pts)):
        gt["total_distance_m"] += haversine(pts[i-1][0], pts[i-1][1], pts[i][0], pts[i][1])
    
    return gt

def parse_report(report_path):
    """Parse the agent's text report."""
    with open(report_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    
    report = {}
    
    # Track Name
    m = re.search(r"Track\s*Name\s*[:=]\s*(.+)", content, re.IGNORECASE)
    if m: report["track_name"] = m.group(1).strip()
    
    # Distance
    m = re.search(r"Distance\s*[:=]\s*([\d.]+)\s*(mi|km|miles?|kilometers?|metres?|meters?|m)", content, re.IGNORECASE)
    if m:
        val = float(m.group(1))
        unit = m.group(2).lower()
        if unit.startswith("mi"):
            report["distance_m"] = val * 1609.34
        elif unit.startswith("k"):
            report["distance_m"] = val * 1000.0
        else:
            report["distance_m"] = val
    
    # Track Points
    m = re.search(r"Track\s*Points?\s*[:=]\s*(\d+)", content, re.IGNORECASE)
    if m: report["track_points"] = int(m.group(1))
    
    # Start Latitude
    m = re.search(r"Start\s*Lat(?:itude)?\s*[:=]\s*([-\d.]+)", content, re.IGNORECASE)
    if m: report["start_lat"] = float(m.group(1))
    
    # Start Longitude
    m = re.search(r"Start\s*Lon(?:gitude)?\s*[:=]\s*([-\d.]+)", content, re.IGNORECASE)
    if m: report["start_lon"] = float(m.group(1))
    
    return report

def verify_vlm(traj):
    """Use VLM on trajectory to confirm agent opened Track Properties dialog."""
    if not VLM_AVAILABLE or not sample_trajectory_frames or not query_vlm:
        return 0, "VLM evaluation skipped (tools unavailable)."

    frames = sample_trajectory_frames(traj, n=5)
    if not frames:
        return 0, "No trajectory frames available for visual verification."

    prompt = """Analyze these screenshots from a Windows desktop session.
The user is working with Garmin BaseCamp. 
Does any screenshot clearly show the 'Track Properties' or 'Properties' dialog window open, displaying track statistics like distance and points?

Respond in JSON format:
{
    "properties_dialog_open": true/false,
    "reasoning": "Brief explanation of what is visible"
}"""
    
    try:
        result = query_vlm(images=frames, prompt=prompt)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            if parsed.get("properties_dialog_open"):
                return 15, "VLM confirmed Track Properties dialog was viewed (+15)"
            return 0, "VLM did not detect Track Properties dialog."
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        
    return 0, "VLM evaluation failed."

def verify_record_track_statistics(traj, env_info, task_info):
    """
    Verify that the extracted statistics match the GPX ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    
    try:
        # Load Result JSON
        try:
            copy_from_env(metadata.get('result_json_path', 'C:\\tmp\\task_result.json'), temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result state: {e}"}

        # Check Anti-Gaming logic
        output_exists = result.get('output_exists', False)
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Report file C:\\workspace\\track_report.txt was not found."}
            
        if not result.get('file_created_during_task', False):
            return {"passed": False, "score": 10, "feedback": "File exists but predates task execution (possible gaming attempt)."}

        # Load and Parse the Agent's Report
        try:
            copy_from_env(metadata.get('expected_output_path', 'C:\\workspace\\track_report.txt'), temp_report.name)
            report_data = parse_report(temp_report.name)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"Failed to retrieve or read report: {e}"}

        # Load and Parse the Ground Truth GPX
        try:
            copy_from_env(metadata.get('gpx_data_path', 'C:\\workspace\\data\\fells_loop.gpx'), temp_gpx.name)
            gt_data = parse_gpx(temp_gpx.name)
        except Exception as e:
            logger.error(f"Failed to load ground truth GPX: {e}")
            return {"passed": False, "score": 10, "feedback": "Internal verifier error handling GPX file."}

        score = 10  # 10 points for valid file created during task
        feedback_parts = ["Report file created (+10)"]
        
        # Unpack Ground Truth
        gt_dist = gt_data["total_distance_m"]
        gt_pts_count = len(gt_data["track_points"])
        gt_start_lat = gt_data["track_points"][0][0] if gt_pts_count else 0
        gt_start_lon = gt_data["track_points"][0][1] if gt_pts_count else 0
        gt_name = gt_data["track_name"]

        # 1. Track Name (15 points)
        if "track_name" in report_data and gt_name:
            if report_data["track_name"].lower() == gt_name.lower():
                score += 15
                feedback_parts.append("Track name correct (+15)")
            elif gt_name.lower() in report_data["track_name"].lower():
                score += 10
                feedback_parts.append("Track name partially correct (+10)")
            else:
                feedback_parts.append(f"Track name mismatch (expected {gt_name})")

        # 2. Distance (25 points) - 15% tolerance
        if "distance_m" in report_data and gt_dist > 0:
            ratio = report_data["distance_m"] / gt_dist
            if 0.85 <= ratio <= 1.15:
                score += 25
                feedback_parts.append("Distance accurate (+25)")
            else:
                feedback_parts.append(f"Distance inaccurate (ratio {ratio:.2f})")
        else:
            feedback_parts.append("Distance missing/unparseable")

        # 3. Track Points (15 points) - exact or close (+/- 5 points margin for UI segment merging)
        if "track_points" in report_data:
            if abs(report_data["track_points"] - gt_pts_count) <= 5:
                score += 15
                feedback_parts.append("Track points accurate (+15)")
            else:
                feedback_parts.append(f"Track points mismatch (got {report_data['track_points']}, expected {gt_pts_count})")
        else:
            feedback_parts.append("Track points missing")

        # 4. Start Latitude (10 points) - 0.05 tolerance
        if "start_lat" in report_data:
            if abs(report_data["start_lat"] - gt_start_lat) <= 0.05:
                score += 10
                feedback_parts.append("Start latitude accurate (+10)")
            else:
                feedback_parts.append(f"Start latitude mismatch")
                
        # 5. Start Longitude (10 points) - 0.05 tolerance
        if "start_lon" in report_data:
            if abs(report_data["start_lon"] - gt_start_lon) <= 0.05:
                score += 10
                feedback_parts.append("Start longitude accurate (+10)")
            else:
                feedback_parts.append(f"Start longitude mismatch")

        # 6. VLM Check (15 points) - Trajectory evidence of correct procedure
        vlm_score, vlm_msg = verify_vlm(traj)
        score += vlm_score
        feedback_parts.append(vlm_msg)

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        for p in [temp_result.name, temp_report.name, temp_gpx.name]:
            if os.path.exists(p):
                try:
                    os.unlink(p)
                except Exception:
                    pass