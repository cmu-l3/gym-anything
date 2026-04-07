#!/usr/bin/env python3
"""
Verifier for gps_trackpoint_geolocation_analysis task.

Scoring System (100 points, Pass threshold = 60):
  10 pts - Autopsy case created and SQLite DB found
  15 pts - Disk image data source ingested
  20 pts - TSK_GPS_TRACKPOINT artifacts extracted successfully
  20 pts - Valid UI Table CSV export generated
  10 pts - Reported total trackpoints is accurate within tolerance
  25 pts - Reported Last Known Coordinates match ground-truth (Most recent timestamp)

Anti-gaming logic checks file modified times against recorded task start times.
"""

import json
import os
import re
import tempfile

def verify_gps_trackpoint(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    
    meta = task_info.get("metadata", {})
    result_file_vm = meta.get("result_file", "/tmp/gps_trackpoint_result.json")
    gt_file_vm = meta.get("gt_file", "/tmp/gps_trackpoint_gt.json")

    # Safe extraction of evaluation results from VM via framework bindings
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        env_info["copy_from_env"](result_file_vm, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — task was not successfully completed or exported."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}

    # Safe extraction of dynamically generated ground truth constraints
    gt = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_gt = tmp.name
        env_info["copy_from_env"](gt_file_vm, tmp_gt)
        with open(tmp_gt) as f:
            gt = json.load(f)
        os.unlink(tmp_gt)
    except Exception:
        pass
        
    gt_total = gt.get("total_trackpoints", 4)
    gt_lat = gt.get("last_known_latitude", 44.4301)
    gt_lon = gt.get("last_known_longitude", -110.5915)

    # Criterion 1: Case Database Identification (10 pts)
    if result.get("case_db_found"):
        score += 10
        feedback_parts.append("PASS Case Database found (+10)")
    else:
        feedback_parts.append("FAIL Case Database for SAR_GPS_2024 not found")

    # Criterion 2: Data Source Ingested (15 pts)
    if result.get("data_source_added"):
        score += 15
        feedback_parts.append("PASS Disk image data source ingested (+15)")
    else:
        feedback_parts.append("FAIL Disk image not found in Autopsy database")

    # Criterion 3: Artifact Generation / Module Triggering (20 pts)
    db_arts = result.get("db_gps_artifacts", 0)
    if db_arts > 0:
        score += 20
        feedback_parts.append(f"PASS Extracted {db_arts} GPS artifacts into database (+20)")
    else:
        feedback_parts.append("FAIL No GPS Trackpoint artifacts detected in database. GPX Parser module likely not run.")

    # Criterion 4: CSV Report Delivery (20 pts)
    start_time = result.get("start_time", 0)
    csv_mtime = result.get("csv_export_mtime", 0)
    csv_content = result.get("csv_export_content", "")
    
    if result.get("csv_export_exists"):
        if csv_mtime >= start_time or start_time == 0:
            if len(csv_content.splitlines()) >= 2:
                score += 20
                feedback_parts.append("PASS CSV UI Export detected with payload (+20)")
            else:
                score += 10
                feedback_parts.append("PARTIAL CSV export exists but appears blank (+10)")
        else:
            score += 5
            feedback_parts.append("PARTIAL CSV export exists but predates task initialization (stale artifact) (+5)")
    else:
        feedback_parts.append("FAIL Trackpoints CSV Export file not found")

    # Criteria 5 & 6: Report Structure & Analysis Validation
    report_exists = result.get("report_file_exists", False)
    report_content = result.get("report_content", "").replace("\\n", "\n")
    report_mtime = result.get("report_mtime", 0)

    if report_exists and (report_mtime >= start_time or start_time == 0):
        # 5. Trackpoint Volume Validation (10 pts)
        m_tot = re.search(r'TOTAL_TRACKPOINTS:\s*(\d+)', report_content)
        if m_tot:
            val = int(m_tot.group(1))
            if abs(val - gt_total) <= 1:
                score += 10
                feedback_parts.append("PASS Reported total trackpoint count aligns with evidence (+10)")
            else:
                feedback_parts.append(f"FAIL Reported trackpoint count ({val}) deviates from expected count ({gt_total})")
        else:
            feedback_parts.append("FAIL Missing TOTAL_TRACKPOINTS field in report")

        # 6. Critical Location Validation (25 pts)
        m_lat = re.search(r'LAST_KNOWN_LATITUDE:\s*([+-]?\d+\.\d+)', report_content)
        m_lon = re.search(r'LAST_KNOWN_LONGITUDE:\s*([+-]?\d+\.\d+)', report_content)
        if m_lat and m_lon:
            lat = float(m_lat.group(1))
            lon = float(m_lon.group(1))
            
            # Accommodate minor rounding deviations
            if abs(lat - gt_lat) <= 0.01 and abs(lon - gt_lon) <= 0.01:
                score += 25
                feedback_parts.append("PASS Reported final coordinates match Ground-Truth location accurately (+25)")
            else:
                feedback_parts.append(f"FAIL Reported coordinates ({lat}, {lon}) deviate from expected ground truth ({gt_lat}, {gt_lon})")
        else:
            feedback_parts.append("FAIL Missing or incorrectly formatted coordinate constraints in report")
    else:
        feedback_parts.append("FAIL Final SAR report file not found or was generated prior to execution")

    # Essential criterion: To pass the task, the agent must successfully identify the last known coordinates
    passed = score >= 60 and "PASS Reported final coordinates match Ground-Truth location accurately (+25)" in " ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }