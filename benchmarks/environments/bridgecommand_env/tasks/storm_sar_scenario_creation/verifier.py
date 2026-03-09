import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_storm_sar_scenario_creation(traj, env_info, task_info):
    """
    Verify SAR scenario creation in storm conditions.

    Scoring breakdown (100 points total):
    - Scenario structure (3 INI files): 10 pts
    - Environment config (storm conditions): 15 pts
    - Own ship (SAR coordinator): 10 pts
    - Traffic vessels (6 with roles): 25 pts
    - Radar configuration: 15 pts
    - SAR briefing document: 25 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback = []

    try:
        local_path = os.path.join(tempfile.gettempdir(), 'storm_sar_scenario_creation_result.json')
        copy_from_env('/tmp/storm_sar_scenario_creation_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1: Scenario Structure (10 pts) ---
    struct_score = 0
    if not result.get('scenario_exists'):
        return {"passed": False, "score": 0, "feedback": "Scenario directory not found. No work detected."}

    struct_score += 2
    if result.get('env_ini_exists'):
        struct_score += 3
    if result.get('ownship_ini_exists'):
        struct_score += 3
    if result.get('othership_ini_exists'):
        struct_score += 2
    score += struct_score

    # --- Criterion 2: Environment — Storm (15 pts) ---
    env_score = 0
    env = result.get('environment', {})

    setting = env.get('setting', '').strip().lower()
    if 'falmouth' in setting:
        env_score += 2
    else:
        feedback.append(f"Setting='{env.get('setting')}', expected Falmouth")

    try:
        st = float(env.get('start_time', -1))
        if abs(st - 3.0) < 1.0:
            env_score += 2
        else:
            feedback.append(f"StartTime={st}, expected 3.0")
    except (ValueError, TypeError):
        pass

    try:
        w = float(env.get('weather', 0))
        if w >= 7.0:
            env_score += 3
            feedback.append(f"Weather={w} (storm)")
        elif w >= 5.0:
            env_score += 1
        else:
            feedback.append(f"Weather={w}, expected 8.0 (storm)")
    except (ValueError, TypeError):
        pass

    try:
        r = float(env.get('rain', 0))
        if r >= 4.0:
            env_score += 2
        else:
            feedback.append(f"Rain={r}, expected 5.0")
    except (ValueError, TypeError):
        pass

    try:
        v = float(env.get('visibility', 0))
        if 2.0 <= v <= 4.0:
            env_score += 2
        else:
            feedback.append(f"Visibility={v}, expected 3.0")
    except (ValueError, TypeError):
        pass

    try:
        m = int(env.get('month', 0))
        if m == 1:
            env_score += 2
    except (ValueError, TypeError):
        pass

    try:
        y = int(env.get('year', 0))
        if y == 2025:
            env_score += 2
    except (ValueError, TypeError):
        pass

    score += env_score
    feedback.append(f"Environment: {env_score}/15")

    # --- Criterion 3: Own Ship (10 pts) ---
    own_score = 0
    own = result.get('ownship', {})

    own_name = own.get('name', '').lower()
    if 'rnli' in own_name or 'severn' in own_name:
        own_score += 3
    else:
        feedback.append(f"Ship name '{own.get('name')}', expected 'RNLI Severn Class'")

    try:
        lat = float(own.get('lat', 0))
        lng = float(own.get('long', 0))
        # Lizard Point area: ~49.9-50.1 N, -5.0 to -5.4 W
        if 49.8 <= lat <= 50.2 and -5.5 <= lng <= -5.0:
            own_score += 3
        elif 49.5 <= lat <= 50.5 and -6.0 <= lng <= -4.5:
            own_score += 1
            feedback.append("Own ship in wider Cornwall area")
        else:
            feedback.append(f"Own ship coords {lat},{lng} outside Lizard area")
    except (ValueError, TypeError):
        feedback.append("FAIL: Own ship coords not parseable")

    if str(own.get('gps', '')) == '1':
        own_score += 2
    if str(own.get('depth_sounder', '')) == '1':
        own_score += 2

    score += own_score
    feedback.append(f"Own ship: {own_score}/10")

    # --- Criterion 4: Traffic Vessels (25 pts) ---
    vessel_score = 0
    other = result.get('othership', {})
    vc = other.get('vessel_count', 0)

    if vc >= 6:
        vessel_score += 10
    elif vc >= 4:
        vessel_score += 7
    elif vc >= 2:
        vessel_score += 4
    elif vc >= 1:
        vessel_score += 2
    else:
        feedback.append("FAIL: No vessels created")

    # Check vessel type diversity
    types_str = other.get('vessel_types', '').lower()
    expected_types = ['fishing', 'tanker', 'container', 'patrol', 'yacht', 'cargo']
    types_found = sum(1 for t in expected_types if t in types_str)

    if types_found >= 6:
        vessel_score += 15
    elif types_found >= 4:
        vessel_score += 10
    elif types_found >= 2:
        vessel_score += 5
    elif types_found >= 1:
        vessel_score += 2
    feedback.append(f"Vessel types: {types_found}/6 found")

    score += vessel_score
    feedback.append(f"Vessels: {vessel_score}/25")

    # --- Criterion 5: Radar Config (15 pts) ---
    radar_score = 0
    radar = result.get('radar_config', {})

    if str(radar.get('arpa_on', '')).strip() == '1':
        radar_score += 3
    else:
        feedback.append(f"arpa_on={radar.get('arpa_on')}")

    if str(radar.get('full_radar', '')).strip() == '1':
        radar_score += 3
    else:
        feedback.append(f"full_radar={radar.get('full_radar')}")

    try:
        rr = int(radar.get('radar_range_resolution', 0))
        if rr >= 512:
            radar_score += 3
        elif rr >= 256:
            radar_score += 2
        elif rr > 128:
            radar_score += 1
    except (ValueError, TypeError):
        pass

    try:
        ar = int(radar.get('radar_angular_resolution', 0))
        if ar >= 720:
            radar_score += 3
        elif ar > 360:
            radar_score += 1
    except (ValueError, TypeError):
        pass

    try:
        mr = int(radar.get('max_radar_range', 0))
        if mr >= 96:
            radar_score += 3
        elif mr > 48:
            radar_score += 1
    except (ValueError, TypeError):
        pass

    score += radar_score
    feedback.append(f"Radar: {radar_score}/15")

    # --- Criterion 6: SAR Briefing (25 pts) ---
    brief_score = 0
    brief = result.get('briefing', {})

    if brief.get('exists'):
        brief_score += 5

        line_count = brief.get('line_count', 0)
        min_lines = metadata.get('briefing_min_lines', 25)
        if line_count >= min_lines:
            brief_score += 5
            feedback.append(f"Briefing: {line_count} lines (>= {min_lines})")
        elif line_count >= 10:
            brief_score += 2
            feedback.append(f"Briefing: {line_count} lines (need {min_lines})")

        content = brief.get('content', '').lower()
        keywords = metadata.get('briefing_keywords', [])
        found = sum(1 for kw in keywords if kw.lower() in content)

        kw_points = int((found / max(len(keywords), 1)) * 15)
        brief_score += kw_points
        feedback.append(f"Briefing keywords: {found}/{len(keywords)}")
    else:
        feedback.append("FAIL: SAR briefing not found")

    score += brief_score
    feedback.append(f"Briefing: {brief_score}/25")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
