#!/usr/bin/env python3
import json
import os
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_legacy_scenario_migration(traj, env_info, task_info):
    """
    Verify the legacy scenario migration task.
    
    Checks:
    1. Directory structure (3 migrated folders).
    2. Model replacement (Old -> New).
    3. Coordinate Datum Shift (Lat +0.0015, Long -0.0022).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    spec = metadata.get('migration_spec', {})
    scenarios_meta = metadata.get('scenarios', {})
    
    # Expected shifts
    LAT_SHIFT = spec.get('lat_shift', 0.0015)
    LONG_SHIFT = spec.get('long_shift', -0.0022)
    MODEL_MAP = spec.get('model_map', {})
    
    # Tolerances
    COORD_TOLERANCE = 0.00002  # Allow small float rounding errors
    
    score = 0
    feedback = []
    
    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    migrated = result.get('migrated_scenarios', {})
    
    # --- Criterion 1: Directories Created (10 pts) ---
    found_scenarios = list(migrated.keys())
    expected_scenarios = ["Scenario_A", "Scenario_B", "Scenario_C"]
    
    dir_score = 0
    for name in expected_scenarios:
        if name in migrated:
            dir_score += 3.33
            feedback.append(f"Found migrated folder for {name}")
        else:
            feedback.append(f"Missing migrated folder for {name}")
    
    score += int(dir_score)

    # --- Process Each Scenario ---
    model_score = 0     # Max 30
    lat_score = 0       # Max 25
    long_score = 0      # Max 25
    integrity_score = 0 # Max 10 (Env file exists)

    for name in expected_scenarios:
        if name not in migrated:
            continue
            
        data = migrated[name]
        meta = scenarios_meta.get(name, {})
        
        # Check Integrity (Environment.ini exists)
        if data.get('environment_exists'):
            integrity_score += 3.33
        
        # --- Check Model Replacement ---
        # Get target model from map using legacy model from meta
        legacy_model = meta.get('legacy_model')
        target_model = MODEL_MAP.get(legacy_model)
        
        actual_model = data.get('othership', {}).get('type', 'Unknown')
        
        if actual_model == target_model:
            model_score += 10
            feedback.append(f"[{name}] Model correctly updated to {actual_model}")
        else:
            feedback.append(f"[{name}] Incorrect model: Got '{actual_model}', expected '{target_model}'")
            
        # --- Check Coordinates (Ownship & Othership) ---
        # Need to check 4 values per scenario: OwnLat, OwnLong, OtherLat, OtherLong
        # Weighting: Total 50 pts for coords. 3 scenarios. ~16 pts per scenario.
        # ~4 pts per coordinate check.
        
        # Helper to check shift
        def check_coord(val_name, original, actual, expected_shift):
            if actual is None:
                return False, f"{val_name} missing"
            expected = original + expected_shift
            diff = abs(actual - expected)
            if diff <= COORD_TOLERANCE:
                return True, f"{val_name} correct ({actual})"
            else:
                return False, f"{val_name} mismatch: Got {actual}, Expected {expected:.4f} (Base {original} + Shift {expected_shift})"

        # Ownship Lat
        ok, msg = check_coord("OwnLat", meta['original_own_lat'], data.get('ownship', {}).get('lat'), LAT_SHIFT)
        if ok: lat_score += 4.16
        else: feedback.append(f"[{name}] {msg}")
        
        # Ownship Long
        ok, msg = check_coord("OwnLong", meta['original_own_long'], data.get('ownship', {}).get('long'), LONG_SHIFT)
        if ok: long_score += 4.16
        else: feedback.append(f"[{name}] {msg}")
        
        # Othership Lat
        ok, msg = check_coord("OtherLat", meta['original_other_lat'], data.get('othership', {}).get('lat'), LAT_SHIFT)
        if ok: lat_score += 4.16
        else: feedback.append(f"[{name}] {msg}")
        
        # Othership Long
        ok, msg = check_coord("OtherLong", meta['original_other_long'], data.get('othership', {}).get('long'), LONG_SHIFT)
        if ok: long_score += 4.16
        else: feedback.append(f"[{name}] {msg}")

    # Add accumulated scores (capped at max values)
    score += min(30, int(model_score))
    score += min(25, int(lat_score))
    score += min(25, int(long_score))
    score += min(10, int(integrity_score))

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }