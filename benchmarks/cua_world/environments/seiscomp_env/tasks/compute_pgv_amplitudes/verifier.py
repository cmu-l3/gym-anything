#!/usr/bin/env python3
"""
Verifier for compute_pgv_amplitudes task.

Scoring Criteria (100 points total):
1. Config updated: scamp configuration includes PGV (20 points)
2. DB Execution: PGV amplitudes successfully computed and stored in DB (40 points)
3. CSV Created: pgv_report.csv created during task execution (15 points)
4. CSV Content: Contains expected stations matching the DB records (25 points)

Pass threshold: 60 points (Must generate valid DB amplitudes)
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_pgv_amplitudes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the main results JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Parse core metrics
    pgv_db_count = int(result.get('pgv_db_count', 0))
    config_has_pgv = result.get('config_has_pgv', False)
    csv_exists = result.get('csv_exists', False)
    csv_modified = result.get('csv_modified_during_task', False)
    
    # Check Config
    if config_has_pgv:
        score += 20
        feedback_parts.append("scamp config properly includes PGV")
    else:
        feedback_parts.append("scamp config missing PGV parameter")
        
    # Check Database Amplitudes (Critical Path)
    if pgv_db_count > 0:
        score += 40
        feedback_parts.append(f"Successfully generated {pgv_db_count} PGV amplitudes in DB")
    else:
        feedback_parts.append("No PGV amplitudes generated in database (scamp failed or skipped)")
        
    # Check CSV Report Creation
    if csv_exists and csv_modified:
        score += 15
        feedback_parts.append("CSV report created during task")
    elif csv_exists:
        feedback_parts.append("CSV report exists but timestamp is old")
    else:
        feedback_parts.append("CSV report missing")
        
    # Check CSV Content against DB Samples
    if csv_exists and csv_modified and pgv_db_count > 0:
        db_samples = {}
        temp_samples = tempfile.NamedTemporaryFile(delete=False)
        temp_csv = tempfile.NamedTemporaryFile(delete=False)
        
        try:
            # Copy DB samples and agent CSV
            copy_from_env("/tmp/pgv_db_samples.txt", temp_samples.name)
            copy_from_env("/tmp/pgv_report.csv", temp_csv.name)
            
            # Read DB samples
            with open(temp_samples.name, 'r') as f:
                for line in f:
                    parts = line.strip().split('\t')
                    if len(parts) >= 2:
                        db_samples[parts[0]] = float(parts[1])
                        
            # Read CSV content
            with open(temp_csv.name, 'r') as f:
                csv_content = f.read()
                
            # Verify stations from DB are mentioned in the CSV
            stations_found = 0
            for station, value in db_samples.items():
                if station in csv_content:
                    stations_found += 1
            
            if stations_found >= 2:
                score += 25
                feedback_parts.append(f"CSV content verified (matched {stations_found} stations with DB)")
            elif stations_found > 0:
                score += 10
                feedback_parts.append("CSV content partially correct (only matched 1 station)")
            else:
                feedback_parts.append("CSV content does not match DB amplitudes")
                
        except Exception as e:
            feedback_parts.append(f"Content verification failed: {e}")
        finally:
            for tf in [temp_samples.name, temp_csv.name]:
                if os.path.exists(tf):
                    os.unlink(tf)

    # Determine passing status
    passed = score >= 60 and pgv_db_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }