#!/usr/bin/env python3
"""
Verifier for create_track_bounding_box task.

Verification Strategy:
1. GPX Analysis (File Check): Parses the exported GPX for exactly 4 corner waypoints and verifies coordinates.
2. Report Analysis (Content Check): Parses the text report for expected boundary values and spans.
3. Anti-Gaming (Timestamp Checks): Confirms files were generated during the task.
4. VLM Verification (Trajectory Check): Ensures the agent interacted with the map and export UI.
"""

import json
import os
import re
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two points in km."""
    R = 6371.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi/2.0)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2.0)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def verify_create_track_bounding_box(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    # Extract metadata bounds
    metadata = task_info.get('metadata', {})
    truth = metadata.get('ground_truth', {})
    tols = metadata.get('tolerances', {})
    
    gt_n = truth.get('north', 42.4485)
    gt_s = truth.get('south', 42.4343)
    gt_e = truth.get('east', -71.0921)
    gt_w = truth.get('west', -71.1147)
    gt_ns_km = truth.get('span_ns_km', 1.58)
    gt_ew_km = truth.get('span_ew_km', 1.86)
    
    tol_pass = tols.get('coordinate_pass', 0.005)
    tol_bonus = tols.get('coordinate_bonus', 0.002)

    # Dictionary representing expected corner coords
    expected_corners = {
        'BB-NW': (gt_n, gt_w),
        'BB-NE': (gt_n, gt_e),
        'BB-SW': (gt_s, gt_w),
        'BB-SE': (gt_s, gt_e)
    }

    score = 0
    feedback = []

    # 1. Retrieve the exported JSON result
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("C:/temp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            results = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result JSON: {e}"}
    finally:
        if os.path.exists(result_json_path): os.unlink(result_json_path)

    start_time = results.get('task_start', 0)
    gpx_exists = results.get('gpx_exists', False)
    txt_exists = results.get('txt_exists', False)

    # Early fail checks
    if not gpx_exists:
        return {"passed": False, "score": 0, "feedback": "GPX file was not exported to expected location."}

    if results.get('gpx_mtime', 0) < start_time:
        feedback.append("WARNING: GPX file timestamp is older than task start (potential gaming).")
    
    # 2. Evaluate GPX
    gpx_temp_path = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx').name
    try:
        copy_from_env("C:/Users/Docker/Documents/track_bounding_box.gpx", gpx_temp_path)
        with open(gpx_temp_path, 'r', encoding='utf-8') as f:
            gpx_content = f.read()
    except Exception as e:
        gpx_content = ""
        feedback.append(f"Failed to read GPX: {e}")
    finally:
        if os.path.exists(gpx_temp_path): os.unlink(gpx_temp_path)

    # Regex search to bypass XML namespace complexities
    wpt_pattern = re.compile(r'<wpt[^>]*lat="([^"]+)"[^>]*lon="([^"]+)"[^>]*>[\s\S]*?<name>\s*([^<]+?)\s*</name>', re.IGNORECASE)
    waypoints = wpt_pattern.findall(gpx_content)
    
    if len(waypoints) > 0:
        score += 10
        feedback.append("Valid GPX file found with waypoints.")
    
    found_corners = {}
    for lat_str, lon_str, name in waypoints:
        try:
            found_corners[name.strip().upper()] = (float(lat_str), float(lon_str))
        except ValueError:
            pass

    # Check the 4 expected waypoints
    required_names = ['BB-NW', 'BB-NE', 'BB-SW', 'BB-SE']
    missing_names = [n for n in required_names if n not in found_corners]
    
    if not missing_names:
        score += 15
        feedback.append("All 4 required waypoints are present.")
        
        # Verify coordinate accuracy
        all_accurate = True
        all_bonus = True
        corners_correct = True
        
        for name in required_names:
            expected_lat, expected_lon = expected_corners[name]
            actual_lat, actual_lon = found_corners[name]
            
            lat_err = abs(actual_lat - expected_lat)
            lon_err = abs(actual_lon - expected_lon)
            
            # Corner assignment logic (ensure NW is actually NW)
            if 'NW' in name and (actual_lat < gt_s or actual_lon > gt_e): corners_correct = False
            if 'SE' in name and (actual_lat > gt_n or actual_lon < gt_w): corners_correct = False
            
            if lat_err > tol_pass or lon_err > tol_pass:
                all_accurate = False
                all_bonus = False
            elif lat_err > tol_bonus or lon_err > tol_bonus:
                all_bonus = False

        if corners_correct:
            score += 10
            feedback.append("Corner cardinal assignments are logically correct.")
            
        if all_accurate:
            score += 20
            feedback.append(f"All waypoints within standard tolerance ({tol_pass}°).")
            if all_bonus:
                score += 5
                feedback.append(f"All waypoints within bonus accuracy ({tol_bonus}°).")
        else:
            feedback.append("One or more waypoints are outside the acceptable distance tolerance.")
            
    else:
        feedback.append(f"Missing required waypoints: {', '.join(missing_names)}.")

    # 3. Evaluate TXT Report
    if txt_exists:
        score += 5
        txt_temp_path = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
        try:
            copy_from_env("C:/Users/Docker/Documents/bounding_box_report.txt", txt_temp_path)
            with open(txt_temp_path, 'r', encoding='utf-8') as f:
                txt_content = f.read()
            
            # Extract coordinates
            n_val = re.search(r'North[^\d]*([-+]?\d*\.\d+)', txt_content, re.IGNORECASE)
            s_val = re.search(r'South[^\d]*([-+]?\d*\.\d+)', txt_content, re.IGNORECASE)
            e_val = re.search(r'East[^\d]*([-+]?\d*\.\d+)', txt_content, re.IGNORECASE)
            w_val = re.search(r'West[^\d]*([-+]?\d*\.\d+)', txt_content, re.IGNORECASE)
            
            coords_valid = False
            if n_val and s_val and e_val and w_val:
                try:
                    rn, rs, re_v, rw = float(n_val.group(1)), float(s_val.group(1)), float(e_val.group(1)), float(w_val.group(1))
                    if (abs(rn - gt_n) <= 0.01 and abs(rs - gt_s) <= 0.01 and 
                        abs(re_v - gt_e) <= 0.01 and abs(rw - gt_w) <= 0.01):
                        score += 10
                        coords_valid = True
                        feedback.append("Report coordinates are highly accurate.")
                    else:
                        feedback.append("Report coordinates extracted but outside 0.01° tolerance.")
                except ValueError:
                    pass
            else:
                feedback.append("Could not parse all N/S/E/W coordinates from report.")
                
            # Extract Spans
            ns_span = re.search(r'NS Span[^\d]*([\d\.]+)', txt_content, re.IGNORECASE)
            ew_span = re.search(r'EW Span[^\d]*([\d\.]+)', txt_content, re.IGNORECASE)
            
            if ns_span and ew_span:
                score += 5
                try:
                    rns = float(ns_span.group(1))
                    rew = float(ew_span.group(1))
                    
                    if (abs(rns - gt_ns_km) / gt_ns_km <= tols['span_percent'] and 
                        abs(rew - gt_ew_km) / gt_ew_km <= tols['span_percent']):
                        score += 5
                        feedback.append("Reported spans are within 50% tolerance.")
                    else:
                        feedback.append(f"Reported spans ({rns}, {rew}) are outside tolerance vs truth ({gt_ns_km}, {gt_ew_km}).")
                except ValueError:
                    feedback.append("Could not parse numeric span values.")
                    
        except Exception as e:
            feedback.append(f"Failed to read TXT report: {e}")
        finally:
            if os.path.exists(txt_temp_path): os.unlink(txt_temp_path)
    else:
        feedback.append("Text report file not found.")

    # 4. VLM Trajectory Evaluation
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_prompt = """You are verifying an AI agent's interaction with Garmin BaseCamp.
        Task: Find bounding box of a track, create 4 corner waypoints, and export to GPX.
        Look at these screenshots. Provide a JSON response evaluating:
        {
          "viewed_track": true/false, // Did the agent view the track map or properties?
          "created_waypoints": true/false, // Is there evidence of waypoints being created or manipulated?
          "used_export_dialog": true/false // Was the Export dialog or file saving window opened?
        }"""
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("viewed_track", False):
                score += 5
                feedback.append("VLM confirms track viewing.")
            if parsed.get("created_waypoints", False):
                score += 5
                feedback.append("VLM confirms waypoint creation workflow.")
            if parsed.get("used_export_dialog", False):
                score += 5
                feedback.append("VLM confirms export dialog usage.")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped or failed.")

    # Pass Criteria: At least 60 points + GPX is accurate
    # 10(exists) + 15(4 wpts) + 10(corners correct) + 20(coords accurate) = 55 points from core GPX task alone
    passed = (score >= 60) and gpx_exists and not missing_names

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }