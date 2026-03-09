import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_channel_passage_planning(traj, env_info, task_info):
    """
    Verify channel passage planning scenario and document creation.

    Scoring breakdown (100 points total):
    - Scenario structure (3 INI files): 15 pts
    - Environment config: 15 pts
    - Own ship: 10 pts
    - Traffic vessels (5 with diverse types): 25 pts
    - Radar configuration: 15 pts
    - Passage plan document: 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback = []

    try:
        local_path = os.path.join(tempfile.gettempdir(), 'channel_passage_planning_result.json')
        copy_from_env('/tmp/channel_passage_planning_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1: Scenario Structure (15 pts) ---
    struct_score = 0
    if result.get('scenario_exists'):
        struct_score += 3
    else:
        return {"passed": False, "score": 0, "feedback": "Scenario directory not found. No work detected."}

    if result.get('env_ini_exists'):
        struct_score += 4
    else:
        feedback.append("FAIL: environment.ini missing")
    if result.get('ownship_ini_exists'):
        struct_score += 4
    else:
        feedback.append("FAIL: ownship.ini missing")
    if result.get('othership_ini_exists'):
        struct_score += 4
    else:
        feedback.append("FAIL: othership.ini missing")

    score += struct_score
    feedback.append(f"Structure: {struct_score}/15")

    # --- Criterion 2: Environment Config (15 pts) ---
    env_score = 0
    env = result.get('environment', {})

    setting = env.get('setting', '').strip().lower()
    if 'english channel' in setting or 'channel' in setting or 'dover' in setting:
        env_score += 3
    else:
        feedback.append(f"FAIL: Setting='{env.get('setting')}', expected English Channel")

    try:
        st = float(env.get('start_time', -1))
        if 4.0 <= st <= 7.0:
            env_score += 3
        else:
            feedback.append(f"StartTime={st}, expected pre-dawn ~5.5")
    except (ValueError, TypeError):
        feedback.append("FAIL: StartTime not parseable")

    try:
        w = float(env.get('weather', -1))
        if 3.0 <= w <= 5.0:
            env_score += 3
        else:
            feedback.append(f"Weather={w}, expected ~4.0")
    except (ValueError, TypeError):
        pass

    try:
        v = float(env.get('visibility', 0))
        if 6.0 <= v <= 12.0:
            env_score += 3
        else:
            feedback.append(f"Visibility={v}, expected ~8.0")
    except (ValueError, TypeError):
        pass

    try:
        m = int(env.get('month', 0))
        if m == 11:
            env_score += 3
        elif 10 <= m <= 12:
            env_score += 1
    except (ValueError, TypeError):
        pass

    score += env_score
    feedback.append(f"Environment: {env_score}/15")

    # --- Criterion 3: Own Ship (10 pts) ---
    own_score = 0
    own = result.get('ownship', {})

    if 'northern crown' in own.get('name', '').lower():
        own_score += 3
    else:
        feedback.append(f"FAIL: Ship name '{own.get('name')}' not 'MV Northern Crown'")

    try:
        lat = float(own.get('lat', 0))
        lng = float(own.get('long', 0))
        lat_range = metadata.get('own_ship_lat_range', [51.00, 51.20])
        lng_range = metadata.get('own_ship_long_range', [1.10, 1.50])
        if lat_range[0] <= lat <= lat_range[1] and lng_range[0] <= lng <= lng_range[1]:
            own_score += 3
        elif 50.5 <= lat <= 51.5 and 0.5 <= lng <= 2.0:
            own_score += 1
            feedback.append("Own ship in wider Channel area")
        else:
            feedback.append(f"FAIL: Coords {lat},{lng} outside Dover Strait")
    except (ValueError, TypeError):
        feedback.append("FAIL: Own ship coords not parseable")

    try:
        spd = float(own.get('speed', 0))
        if 10.0 <= spd <= 15.0:
            own_score += 2
    except (ValueError, TypeError):
        pass

    try:
        brg = float(own.get('bearing', 0))
        if 180.0 <= brg <= 260.0:
            own_score += 2
    except (ValueError, TypeError):
        pass

    score += own_score
    feedback.append(f"Own ship: {own_score}/10")

    # --- Criterion 4: Traffic Vessels (25 pts) ---
    vessel_score = 0
    other = result.get('othership', {})
    vc = other.get('vessel_count', 0)

    if vc >= 5:
        vessel_score += 10
    elif vc >= 3:
        vessel_score += 6
    elif vc >= 1:
        vessel_score += 3
    else:
        feedback.append(f"FAIL: No vessels (count={vc})")

    # Check vessel type diversity
    types_str = other.get('vessel_types', '').lower()
    required_types = metadata.get('required_vessel_types', ['container', 'tanker', 'ferry', 'fishing', 'yacht'])
    types_found = 0
    for vtype in required_types:
        if vtype in types_str:
            types_found += 1

    vessel_score += min(types_found * 3, 15)
    feedback.append(f"Vessel types found: {types_found}/{len(required_types)}")

    score += vessel_score
    feedback.append(f"Vessels: {vessel_score}/25")

    # --- Criterion 5: Radar Config (15 pts) ---
    radar_score = 0
    radar = result.get('radar_config', {})

    if str(radar.get('full_radar', '')).strip() == '1':
        radar_score += 4
    else:
        feedback.append(f"FAIL: full_radar={radar.get('full_radar')}")

    try:
        mr = int(radar.get('max_radar_range', 0))
        if mr >= 72:
            radar_score += 4
        elif mr > 48:
            radar_score += 2
    except (ValueError, TypeError):
        pass

    try:
        ar = int(radar.get('radar_angular_resolution', 0))
        if ar >= 720:
            radar_score += 4
        elif ar > 360:
            radar_score += 2
    except (ValueError, TypeError):
        pass

    if str(radar.get('hide_instruments', '')).strip() == '0':
        radar_score += 3
    else:
        feedback.append(f"hide_instruments={radar.get('hide_instruments')}")

    score += radar_score
    feedback.append(f"Radar: {radar_score}/15")

    # --- Criterion 6: Passage Plan (20 pts) ---
    plan_score = 0
    plan = result.get('passage_plan', {})

    if plan.get('exists'):
        plan_score += 5
        content = plan.get('content', '').lower()

        keywords = metadata.get('passage_plan_keywords',
                                ['waypoint', 'lat', 'long', 'speed', 'hazard', 'tss', 'vhf', 'eta'])
        found = sum(1 for kw in keywords if kw.lower() in content)
        kw_points = int((found / max(len(keywords), 1)) * 15)
        plan_score += kw_points
        feedback.append(f"Passage plan keywords: {found}/{len(keywords)}")
    else:
        feedback.append("FAIL: Passage plan not found")

    score += plan_score
    feedback.append(f"Passage plan: {plan_score}/20")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
