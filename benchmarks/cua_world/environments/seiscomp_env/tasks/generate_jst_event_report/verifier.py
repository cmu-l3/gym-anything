#!/usr/bin/env python3
"""Verifier for generate_jst_event_report task."""

import json
import os
import tempfile
import logging
import re
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_floats(text):
    """Robustly extract floats from text to evaluate numerical equivalence."""
    matches = re.findall(r'-?\d+\.\d+', text)
    return [float(m) for m in matches]

def verify_generate_jst_event_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Copy the HTML report
    temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
    html_content = ""
    try:
        copy_from_env("/tmp/noto_report.html", temp_html.name)
        with open(temp_html.name, 'r') as f:
            html_content = f.read()
    except Exception as e:
        logger.warning(f"Could not read HTML file: {e}")
    finally:
        if os.path.exists(temp_html.name):
            os.unlink(temp_html.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File created and exists
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/Documents/noto_report.html does not exist"}
        
    if not result.get("file_created_during_task"):
        feedback_parts.append("File existed before task started (gaming detected?)")
    else:
        score += 10
        feedback_parts.append("File created successfully")
        
    html_text = html_content.lower()
    
    # Criterion 2: HTML Format
    if "<html>" in html_text or "<body>" in html_text or "<div" in html_text or "<p" in html_text:
        score += 10
        feedback_parts.append("Valid HTML structure")
    else:
        feedback_parts.append("Warning: Output lacks standard HTML tags")

    # Get GT data
    gt_id = result.get("gt_event_id", "")
    gt_utc_time = result.get("gt_utc_time", "")
    gt_lat = result.get("gt_lat", "0")
    gt_lon = result.get("gt_lon", "0")
    gt_mag = result.get("gt_mag", "0")

    if not gt_id or gt_lat == "" or gt_lon == "" or gt_mag == "":
        return {"passed": False, "score": score, "feedback": "Database ground truth missing. System error."}

    gt_lat = float(gt_lat)
    gt_lon = float(gt_lon)
    gt_mag = float(gt_mag)

    # Criterion 3: Event ID
    if gt_id in html_content:
        score += 20
        feedback_parts.append("Correct Event ID found")
    else:
        feedback_parts.append("Event ID missing or incorrect")

    # Criterion 4: Magnitude and Coordinates
    html_floats = extract_floats(html_content)
    
    mag_found = any(abs(f - gt_mag) < 0.11 for f in html_floats)
    lat_found = any(abs(f - gt_lat) < 0.11 for f in html_floats)
    lon_found = any(abs(f - gt_lon) < 0.11 for f in html_floats)
        
    if mag_found and lat_found and lon_found:
        score += 20
        feedback_parts.append("Magnitude and Coordinates match DB values")
    elif mag_found:
        score += 10
        feedback_parts.append("Magnitude found, but Coordinates missing/incorrect")
    elif lat_found and lon_found:
        score += 10
        feedback_parts.append("Coordinates found, but Magnitude missing/incorrect")
    else:
        feedback_parts.append("Magnitude and Coordinates missing or incorrect")

    # Criterion 5: Time Conversion
    utc_found = False
    jst_found = False
    
    try:
        # Extract main part of time string and parse it safely (handles different DB representations)
        clean_utc = gt_utc_time.replace('T', ' ').split('.')[0]
        dt_utc = datetime.strptime(clean_utc, "%Y-%m-%d %H:%M:%S")
        dt_jst = dt_utc + timedelta(hours=9)
        
        # Look for various representations
        jst_str1 = dt_jst.strftime("%Y-%m-%d %H:%M:%S")
        jst_str2 = dt_jst.strftime("%H:%M:%S")
        jst_str3 = dt_jst.strftime("%Y-%m-%d %H:%M")
        
        utc_str1 = dt_utc.strftime("%Y-%m-%d %H:%M:%S")
        utc_str2 = dt_utc.strftime("%H:%M:%S")
        utc_str3 = dt_utc.strftime("%Y-%m-%d %H:%M")
        
        if utc_str1 in html_content or utc_str2 in html_content or utc_str3 in html_content:
            utc_found = True
            
        if jst_str1 in html_content or jst_str2 in html_content or jst_str3 in html_content:
            jst_found = True
            
        if jst_found and utc_found:
            score += 30
            feedback_parts.append("JST and UTC times correctly calculated and formatted")
        elif jst_found:
            score += 20
            feedback_parts.append("JST correctly calculated, but UTC time missing")
        elif utc_found:
            score += 10
            feedback_parts.append("UTC time present, but JST conversion missing/incorrect")
        else:
            feedback_parts.append("Expected time strings not found in report")
            
    except Exception as e:
        feedback_parts.append(f"Time verification error: {e}")

    # Criterion 6: Google Maps Link
    maps_link_regex = re.compile(r"https://(?:www\.)?maps\.google\.com/\?q=([0-9.-]+),([0-9.-]+)")
    match = maps_link_regex.search(html_content)
    if match:
        lat_link, lon_link = float(match.group(1)), float(match.group(2))
        if abs(lat_link - gt_lat) < 0.1 and abs(lon_link - gt_lon) < 0.1:
            score += 10
            feedback_parts.append("Valid Google Maps link found")
        else:
            feedback_parts.append(f"Google Maps link found but coords ({lat_link},{lon_link}) don't match DB ({gt_lat},{gt_lon})")
    else:
        feedback_parts.append("Google Maps link not found or incorrectly formatted")

    # Final Pass Condition
    passed = score >= 70 and jst_found and result.get("output_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }