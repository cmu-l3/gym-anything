#!/usr/bin/env python3
import json
import os
import base64
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sar_coordination(traj, env_info, task_info):
    """
    Verify the SAR Coordination Exercise task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    
    # Criteria 1: Scenario Directory & Files (10 pts)
    files_exist = result.get('scenario_dir_exists', False) and \
                  result['files'].get('environment', False) and \
                  result['files'].get('ownship', False) and \
                  result['files'].get('othership', False)
    
    if files_exist:
        score += 10
        feedback_parts.append("Scenario files created.")
    else:
        feedback_parts.append("Missing scenario configuration files.")

    # Criteria 2: Environment Config (10 pts)
    env = result.get('env_data', {})
    setting = env.get('Setting', '').lower()
    start_time = float(env.get('StartTime', -1))
    vis = float(env.get('VisibilityRange', 99))
    
    env_ok = True
    if 'solent' not in setting: env_ok = False
    if not (4.0 <= start_time <= 6.5): env_ok = False
    if vis > 2.0: env_ok = False # Fog required
    
    if env_ok:
        score += 10
        feedback_parts.append("Environment configured correctly (Solent/Night/Fog).")
    else:
        feedback_parts.append(f"Environment issues: Setting={setting}, Time={start_time}, Vis={vis}.")

    # Criteria 3: Own Ship (10 pts)
    own = result.get('own_data', {})
    lat = float(own.get('InitialLat', 0))
    lon = float(own.get('InitialLong', 0))
    
    # Datum is 50.765, -1.295. Allow small delta.
    dist = ((lat - 50.765)**2 + (lon - (-1.295))**2)**0.5
    if dist < 0.01 and "rnli" in own.get('ShipName', '').lower():
        score += 10
        feedback_parts.append("Own ship correctly positioned.")
    else:
        feedback_parts.append(f"Own ship incorrect (Dist={dist:.4f}).")

    # Criteria 4 & 5: Vessels and Geometry (30 pts)
    # Need 4 vessels. 3 searchers with >6 legs and square pattern. 1 casualty.
    geo = result.get('geometry', {})
    vessel_count = len(geo)
    
    searchers_ok = 0
    casualty_ok = 0
    
    for idx, v in geo.items():
        if v['is_casualty']:
            # Check position near datum
            d_lat = float(v['lat'])
            d_lon = float(v['long'])
            # Should be near but not exactly at datum usually, task said 50.768, -1.288
            c_dist = ((d_lat - 50.765)**2 + (d_lon - (-1.295))**2)**0.5
            if c_dist < 0.05:
                casualty_ok = 1
        elif v['legs_count'] >= 6 and v['is_square_pattern']:
            searchers_ok += 1
            
    if vessel_count == 4:
        score += 10
        feedback_parts.append("Correct number of vessels.")
    else:
        feedback_parts.append(f"Found {vessel_count} vessels (expected 4).")
        
    if casualty_ok:
        score += 5
        feedback_parts.append("Casualty vessel configured.")
        
    if searchers_ok >= 3:
        score += 15
        feedback_parts.append("3 Search vessels with expanding square patterns detected.")
    elif searchers_ok > 0:
        score += 5 * searchers_ok
        feedback_parts.append(f"Only {searchers_ok} valid search patterns found.")

    # Criteria 6: Radar Config (10 pts)
    conf = result.get('config_data', {})
    if conf.get('arpa_on') == '1' and conf.get('full_radar') == '1' and int(conf.get('radar_range_resolution', 0)) >= 256:
        score += 10
        feedback_parts.append("Radar configured correctly.")
    else:
        feedback_parts.append("Radar config incomplete.")

    # Criteria 7: SITREP Document (15 pts)
    if result.get('sitrep_exists'):
        score += 5
        content = ""
        try:
            content = base64.b64decode(result.get('sitrep_content_b64', '')).decode('utf-8', errors='ignore').lower()
        except:
            pass
            
        keywords = ["expanding square", "datum", "vhf", "rnli"]
        hits = sum(1 for k in keywords if k in content)
        
        if hits >= 3:
            score += 10
            feedback_parts.append("SITREP content verified.")
        else:
            feedback_parts.append("SITREP missing keywords.")
    else:
        feedback_parts.append("SITREP file missing.")

    # Pass logic
    passed = score >= 60 and files_exist and vessel_count >= 4
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }