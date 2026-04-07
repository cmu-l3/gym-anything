#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_weather_variant_batch_creation(traj, env_info, task_info):
    """
    Verify the batch creation of meteorological scenarios.
    
    Scoring Criteria:
    1. Directories Created (10 pts)
    2. Environment Config (Visibility, Weather, Rain, Fog) (40 pts)
    3. Speed Logic (Calculated correctly from base speed) (30 pts)
    4. Briefing Files (Content matches config) (10 pts)
    5. Manifest CSV (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Get Expected Config from metadata
    metadata = task_info.get('metadata', {})
    expected_variants = metadata.get('variants', [])
    
    # Get Truth Data
    try:
        base_speed = float(result.get('base_speed_truth', 0))
    except:
        base_speed = 0
        
    if base_speed == 0:
        return {"passed": False, "score": 0, "feedback": "Critical Error: Could not determine base speed truth."}

    score = 0
    max_score = 100
    feedback = []
    
    variants_data = result.get('variants', {})
    
    # 1. Directories (10 pts total, 2.5 each)
    dir_score = 0
    for v in expected_variants:
        name = v['name']
        if variants_data.get(name, {}).get('exists'):
            dir_score += 2.5
    score += dir_score
    if dir_score < 10:
        feedback.append(f"Directory creation partial: {dir_score}/10")
    else:
        feedback.append("All directories created.")

    # 2 & 3. Config Verification (Env: 40 pts, Speed: 30 pts)
    env_score = 0
    speed_score = 0
    
    # We evaluate each variant
    for v_def in expected_variants:
        name = v_def['name']
        v_res = variants_data.get(name, {})
        
        if not v_res.get('exists'):
            feedback.append(f"Skipping checks for missing {name}")
            continue

        env_ini = v_res.get('environment', {})
        own_ini = v_res.get('ownship', {})
        
        # -- Env Checks (10 pts per variant) --
        # Visibility
        try:
            vis = float(env_ini.get('VisibilityRange', -1))
            if abs(vis - v_def['vis']) < 0.1:
                env_score += 2.5
            else:
                feedback.append(f"[{name}] Wrong Vis: {vis} (Exp: {v_def['vis']})")
        except:
            feedback.append(f"[{name}] Missing Vis")

        # Weather
        try:
            wx = float(env_ini.get('Weather', -1))
            if abs(wx - v_def['wx']) < 0.1:
                env_score += 2.5
            else:
                feedback.append(f"[{name}] Wrong Wx: {wx} (Exp: {v_def['wx']})")
        except:
             feedback.append(f"[{name}] Missing Wx")

        # Rain
        try:
            rain = int(float(env_ini.get('RainVisible', -1)))
            if rain == v_def['rain']:
                env_score += 2.5
            else:
                feedback.append(f"[{name}] Wrong Rain: {rain}")
        except: pass

        # Fog
        try:
            fog = int(float(env_ini.get('Fog', -1)))
            if fog == v_def['fog']:
                env_score += 2.5
            else:
                feedback.append(f"[{name}] Wrong Fog: {fog}")
        except: pass

        # -- Speed Logic (7.5 pts per variant) --
        # Logic: Base * Factor, rounded to 1 decimal
        expected_speed = round(base_speed * v_def['speed_factor'], 1)
        
        try:
            actual_speed = float(own_ini.get('InitialSpeed', -1))
            # Tolerance 0.2 to handle slight rounding differences
            if abs(actual_speed - expected_speed) <= 0.2:
                speed_score += 7.5
            else:
                feedback.append(f"[{name}] Wrong Speed: {actual_speed} (Exp: {expected_speed} from base {base_speed})")
        except:
            feedback.append(f"[{name}] Missing/Invalid Speed")

    score += env_score
    score += speed_score

    # 4. Briefing Files (10 pts)
    briefing_score = 0
    briefings_exist = 0
    for v_def in expected_variants:
        name = v_def['name']
        v_res = variants_data.get(name, {})
        if v_res.get('briefing', {}).get('exists'):
            briefings_exist += 1
            content = v_res['briefing']['content']
            # Check if it contains the calculated speed
            expected_speed = str(round(base_speed * v_def['speed_factor'], 1))
            if expected_speed in content:
                briefing_score += 2.5
    
    if briefings_exist == 4 and briefing_score < 10:
        # Give partial credit if files exist but numbers wrong
        briefing_score = max(briefing_score, 5)
        
    score += briefing_score
    if briefing_score == 10:
        feedback.append("Briefings correct.")

    # 5. Manifest CSV (10 pts)
    manifest_score = 0
    if result.get('manifest_exists'):
        manifest_score += 5
        content = result.get('manifest_content', [])
        # Simple check: more than 4 lines (header + 4 variants)
        if len(content) >= 5:
            manifest_score += 5
    score += manifest_score
    if manifest_score == 10:
        feedback.append("Manifest created.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }