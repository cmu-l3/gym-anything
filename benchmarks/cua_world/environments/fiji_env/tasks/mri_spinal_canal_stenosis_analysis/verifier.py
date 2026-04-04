#!/usr/bin/env python3
"""
Verifier for Spinal Canal Stenosis Quantification task.

Scoring Criteria (100 points total):
1. Output files exist and created during task (15 pts)
2. CSV contains data for slices 10-19 (25 pts)
3. Measurements are physiologically plausible (30 pts)
   - Checks if area is not too small (noise) or too large (whole head)
4. Diagnosis matches the data provided (20 pts)
   - Internal consistency: Does diagnosis.txt match the min row in CSV?
5. Segmentation evidence exists (10 pts)

Pass Threshold: 70 points
"""

import json
import base64
import csv
import io
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_spinal_stenosis(traj, env_info, task_info):
    """
    Verify the spinal stenosis analysis task.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/stenosis_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback = []
    
    # 2. Verify File Existence and Timing (15 pts)
    files_ok = (result_data.get('csv_exists') and 
                result_data.get('csv_modified_after_start') and
                result_data.get('diagnosis_exists') and
                result_data.get('diagnosis_modified_after_start'))
    
    if files_ok:
        score += 15
        feedback.append("All output files created successfully.")
    else:
        feedback.append("Missing or unmodified output files.")

    # 3. Verify CSV Content (Rows and Values)
    csv_content_b64 = result_data.get('csv_content_base64', '')
    measurements = {}
    
    if csv_content_b64:
        try:
            csv_text = base64.b64decode(csv_content_b64).decode('utf-8')
            reader = csv.reader(io.StringIO(csv_text))
            
            # Skip header if present
            rows = list(reader)
            # Simple heuristic to identify header
            if rows and any(c.lower() in ['slice', 'id', 'area'] for c in rows[0]):
                header = rows.pop(0)

            # Parse measurements
            for row in rows:
                if len(row) >= 2:
                    try:
                        # Extract numbers from potential string cruft
                        slice_id_str = ''.join(filter(str.isdigit, row[0]))
                        area_str = row[1].replace(',', '') # handle 1,000
                        slice_id = int(slice_id_str)
                        area = float(area_str)
                        measurements[slice_id] = area
                    except ValueError:
                        continue
            
            # Check range 10-19 (25 pts)
            target_slices = set(range(10, 20)) # 10 to 19 inclusive
            found_slices = set(measurements.keys())
            
            # Allow some flexibility (e.g. they did 9-18 or 10-20)
            overlap = target_slices.intersection(found_slices)
            if len(overlap) >= 8: # Missed at most 2
                score += 25
                feedback.append(f"Measurements found for required slices ({len(overlap)}/10).")
            else:
                feedback.append(f"Missing measurements for required slices. Found: {sorted(list(found_slices))}")

            # Check Physiological Plausibility (30 pts)
            # T1 Head sample: Canal is roughly 100-600 pixels depending on contrast/zoom
            # Air is >2000 or ~0. Bone/Head is >10000.
            # We look for a reasonable range [20, 1500] to cover varied units/segmentation styles
            valid_values = [v for v in measurements.values() if 20 < v < 1500]
            
            if len(valid_values) >= len(measurements) * 0.8 and len(measurements) > 0:
                score += 30
                feedback.append("Measurement values appear physiologically reasonable.")
            else:
                feedback.append("Measurement values outside expected range (20-1500). Are units correct?")

        except Exception as e:
            feedback.append(f"Error parsing CSV: {str(e)}")
    
    # 4. Verify Diagnosis (20 pts)
    # Check internal consistency: Did they pick the minimum from THEIR data?
    try:
        agent_diagnosis_str = result_data.get('diagnosis_content', '').strip()
        # Extract number
        import re
        match = re.search(r'\d+', agent_diagnosis_str)
        if match and measurements:
            agent_min_slice = int(match.group())
            
            # Find actual minimum in their data
            actual_min_slice = min(measurements, key=measurements.get)
            
            # Allow if it's the absolute min OR very close (within 5% of min value)
            min_val = measurements[actual_min_slice]
            is_valid_diagnosis = False
            
            if agent_min_slice == actual_min_slice:
                is_valid_diagnosis = True
            elif agent_min_slice in measurements:
                # Check value proximity
                if measurements[agent_min_slice] <= min_val * 1.05:
                    is_valid_diagnosis = True
            
            if is_valid_diagnosis:
                score += 20
                feedback.append(f"Diagnosis ({agent_min_slice}) correctly identifies max stenosis from data.")
            else:
                feedback.append(f"Diagnosis ({agent_min_slice}) does not match the minimum area in your CSV ({actual_min_slice}).")
        elif not measurements:
             feedback.append("Cannot verify diagnosis without valid measurements.")
        else:
             feedback.append("Could not parse slice number from diagnosis.txt.")
             
    except Exception as e:
        feedback.append(f"Error verifying diagnosis: {str(e)}")

    # 5. Verify Evidence (10 pts)
    if result_data.get('evidence_exists') and result_data.get('evidence_modified_after_start'):
        score += 10
        feedback.append("Segmentation evidence screenshot provided.")
    else:
        feedback.append("Missing evidence screenshot.")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }