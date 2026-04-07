#!/usr/bin/env python3
"""
Verifier for the batch_import_legacy_events task.
Evaluates Python scripting capability and programmatic interactions with SeisComP APIs.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_import_legacy_events(traj, env_info, task_info):
    """
    Verifies the Batch Import Legacy Events task by checking DB contents and file artifacts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_event_count = metadata.get('expected_event_count', 5)
    expected_events = metadata.get('expected_events', [])

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    script_info = result.get('script_file', {})
    scml_info = result.get('scml_file', {})
    db_origins = result.get('origins', [])
    db_mags = result.get('magnitudes', [])
    db_events_count = result.get('events_count', 0)
    
    # 1. Check Python Script Artifact (10 points)
    if script_info.get('exists'):
        if script_info.get('size', 0) > 50:
            if script_info.get('created_during_task'):
                score += 10
                feedback_parts.append("Python script created correctly")
            else:
                score += 5
                feedback_parts.append("Python script exists but was not created during task window")
        else:
            feedback_parts.append("Python script exists but is too small to be valid")
    else:
        feedback_parts.append("Python script missing")

    # 2. Check SCML XML Artifact (10 points)
    if scml_info.get('exists'):
        if scml_info.get('size', 0) > 200 and scml_info.get('created_during_task'):
            score += 10
            feedback_parts.append("SCML output file generated successfully")
        else:
            score += 5
            feedback_parts.append("SCML file exists but appears invalid or unchanged")
    else:
        feedback_parts.append("SCML file not generated")

    # 3. Check Database Event Count & AgencyID mapping (30 points)
    if db_events_count == expected_event_count:
        score += 30
        feedback_parts.append(f"Successfully imported {expected_event_count} Events into database with AgencyID 'LEGACY_IMPORT'")
    elif db_events_count > 0:
        score += 10
        feedback_parts.append(f"Partial import: found {db_events_count}/{expected_event_count} Events in database")
    else:
        feedback_parts.append("No Events found in database with expected AgencyID 'LEGACY_IMPORT'")

    # 4. Data Accuracy Verification (50 points total: 25 for Origins, 25 for Mags)
    origins_matched = 0
    mags_matched = 0
    
    for expected in expected_events:
        # Check if any db origin matches within tolerance
        origin_found = any(
            abs(o.get('lat', 0) - expected['lat']) < 0.05 and
            abs(o.get('lon', 0) - expected['lon']) < 0.05 and
            abs(o.get('depth', 0) - expected['depth']) < 1.0
            for o in db_origins
        )
        if origin_found:
            origins_matched += 1
            
        # Check if any db magnitude matches
        mag_found = any(
            abs(m.get('mag', 0) - expected['mag']) < 0.05
            for m in db_mags
        )
        if mag_found:
            mags_matched += 1

    if len(expected_events) > 0:
        origin_score = int((origins_matched / len(expected_events)) * 25)
        mag_score = int((mags_matched / len(expected_events)) * 25)
        score += origin_score
        score += mag_score
        
        feedback_parts.append(f"Accuracy: {origins_matched}/{len(expected_events)} Origins correct")
        feedback_parts.append(f"Accuracy: {mags_matched}/{len(expected_events)} Magnitudes correct")

    # Final Evaluation
    key_criteria_met = db_events_count > 0 and origins_matched > 0
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "events_imported": db_events_count,
            "origins_accurate": origins_matched,
            "magnitudes_accurate": mags_matched
        }
    }