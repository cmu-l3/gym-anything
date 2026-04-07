#!/usr/bin/env python3
"""
Verifier for generate_snr_report_scamp task.

Verifies that the SeisComP offline processing tools were run and
the agent successfully extracted the station codes and SNR values
into a well-formatted CSV file.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_snr_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')

    score = 0
    feedback = []

    try:
        # Step 1: Read the task metadata result exported from the container
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Pipeline Execution Evidence (20 points)
        # Prevent gaming by ensuring scautopick/scamp actually ran
        xml_generated = result.get('xml_generated', False)
        db_generated = result.get('db_generated', False)
        if xml_generated or db_generated:
            score += 20
            feedback.append("Evidence of SeisComP processing found (XML or DB updates).")
        else:
            feedback.append("Warning: No new XML files or DB records for Picks/Amplitudes detected.")

        # Criterion 2: Report file existence and timeline validity (20 points)
        report_exists = result.get('report_exists', False)
        report_created = result.get('report_created_during_task', False)

        if report_exists:
            if report_created:
                score += 20
                feedback.append("Report file created during task execution.")
            else:
                feedback.append("Report file exists but timestamp is invalid (possibly pre-existing).")
                return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
        else:
            feedback.append("Report file (/home/ga/snr_report.csv) not found.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Step 2: Read and parse the CSV file
        try:
            copy_from_env("/tmp/snr_report.csv", temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                lines = content.split('\n')
                reader = csv.reader(lines)
                data = list(reader)
        except Exception as e:
            feedback.append(f"Failed to read or parse CSV: {e}")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Criterion 3: CSV Format (10 points)
        if len(data) > 1:
            header = [h.strip().upper() for h in data[0]]
            if len(header) >= 3 and 'STATION' in header[0] and 'PHASE' in header[1] and 'SNR' in header[2]:
                score += 10
                feedback.append("CSV header format matches EXACT expected structure.")
            elif len(header) >= 3:
                score += 5
                feedback.append("CSV has columns but header names differ from exact specification.")
        else:
            feedback.append("CSV file is empty or missing data rows.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

        # Criterion 4: CSV Content Accuracy (up to 50 points)
        metadata = task_info.get('metadata', {})
        expected_stations = set(metadata.get('expected_stations', ['TOLI', 'GSI', 'KWP', 'SANI', 'BKB']))
        
        stations_found = set()
        valid_snrs = 0

        for row in data[1:]:
            if len(row) >= 3:
                sta = row[0].strip().upper()
                snr_str = row[2].strip()

                if sta in expected_stations:
                    stations_found.add(sta)

                # Check if SNR is numeric and reasonably positive
                try:
                    snr = float(snr_str)
                    if snr > 0:
                        valid_snrs += 1
                except ValueError:
                    pass

        # 5 points per valid station found (max 25)
        station_score = min(25, len(stations_found) * 5)
        if station_score > 0:
            score += station_score
            feedback.append(f"Found accurate data for {len(stations_found)} expected station(s).")
        else:
            feedback.append("No matching expected stations found in the report.")

        # 5 points per valid numeric SNR (max 25)
        snr_score = min(25, valid_snrs * 5)
        if snr_score > 0:
            score += snr_score
            feedback.append(f"Found {valid_snrs} valid numeric SNR measurements.")
        else:
            feedback.append("No valid numeric SNR values found in the report.")

    finally:
        # Cleanup temp files
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}