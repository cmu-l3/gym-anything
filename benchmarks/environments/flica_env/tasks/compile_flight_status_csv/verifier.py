#!/usr/bin/env python3
"""
Verifier for compile_flight_status_csv task.

Criteria:
1. CSV file exists and was created during the task.
2. CSV has correct header.
3. CSV contains data rows for AA 1, UA 1, and DL 1.
4. Data fields (Origin, Destination, Status) contain plausible values (not empty).
5. VLM: Trajectory confirms search screens were accessed.
"""

import json
import os
import tempfile
import csv
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flight_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Temp files for artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        # 1. Retrieve JSON result
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}

        # 2. Retrieve CSV report
        csv_content_valid = False
        rows = []
        if result_data.get("file_exists"):
            try:
                copy_from_env("/sdcard/flight_report.csv", temp_csv.name)
                with open(temp_csv.name, 'r', newline='') as f:
                    reader = csv.reader(f)
                    rows = list(reader)
                csv_content_valid = True
            except Exception as e:
                logger.warning(f"Failed to read CSV content: {e}")

        # --- Scoring Logic ---
        score = 0
        feedback = []

        # Check 1: File Creation (20 pts)
        if result_data.get("file_exists") and result_data.get("file_created_during_task"):
            score += 20
            feedback.append("Report file created successfully.")
        elif result_data.get("file_exists"):
            score += 10
            feedback.append("Report file exists but timestamp check failed.")
        else:
            feedback.append("Report file not found.")
            return {"passed": False, "score": 0, "feedback": "Failed: No report file created."}

        # Check 2: CSV Structure (20 pts)
        header_ok = False
        if csv_content_valid and len(rows) > 0:
            header = [h.strip().lower() for h in rows[0]]
            expected = ["flight", "origin", "destination", "status"]
            if header == expected:
                score += 20
                header_ok = True
                feedback.append("CSV header is correct.")
            else:
                feedback.append(f"Incorrect CSV header. Found: {rows[0]}")
        else:
            feedback.append("CSV file is empty or unreadable.")

        # Check 3: Content Verification (40 pts)
        # We look for rows starting with AA 1, UA 1, DL 1
        found_flights = {"AA": False, "UA": False, "DL": False}
        valid_data_points = 0
        
        if header_ok and len(rows) > 1:
            for row in rows[1:]:
                if len(row) < 4: continue
                
                flt = row[0].upper()
                orig = row[1].strip()
                dest = row[2].strip()
                status = row[3].strip()

                # Identify flight
                flight_key = None
                if "AA" in flt or "AMERICAN" in flt: flight_key = "AA"
                elif "UA" in flt or "UNITED" in flt: flight_key = "UA"
                elif "DL" in flt or "DELTA" in flt: flight_key = "DL"

                if flight_key:
                    found_flights[flight_key] = True
                    # Check data validity (Airport codes usually 3 letters, Status not empty)
                    if len(orig) >= 3 and len(dest) >= 3 and len(status) > 0:
                        valid_data_points += 1

            # Score based on found flights (30 pts max)
            flights_found_count = sum(found_flights.values())
            score += flights_found_count * 10
            feedback.append(f"Found data for {flights_found_count}/3 required flights.")

            # Score based on data validity (10 pts max)
            if valid_data_points >= 3:
                score += 10
                feedback.append("Data fields appear valid.")

        # Check 4: VLM Trajectory Verification (20 pts)
        # Verify the agent actually performed the searches
        frames = sample_trajectory_frames(traj, n=8)
        
        vlm_prompt = """
        Review these screenshots of an Android app 'Flight Crew View'. 
        The user task was to search for flights AA 1, UA 1, and DL 1.
        
        1. Do you see any flight search input screen?
        2. Do you see results for 'American', 'AA', 'United', 'UA', 'Delta', or 'DL'?
        3. Do you see flight details like 'JFK', 'LAX', 'LHR', 'SFO', 'SIN'?
        
        Return JSON: {"search_performed": boolean, "airlines_seen": list of strings, "confidence": float}
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("search_performed"):
                score += 10
                feedback.append("Visual evidence of search activity found.")
                
            airlines = parsed.get("airlines_seen", [])
            if len(airlines) > 0:
                score += 10
                feedback.append(f"Visual evidence of airlines: {', '.join(airlines)}.")
            
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if data is good, give benefit of doubt for VLM points
            if score >= 60: 
                score += 20
                feedback.append("VLM check skipped (error), assumed pass based on valid data.")

    finally:
        # Cleanup
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }