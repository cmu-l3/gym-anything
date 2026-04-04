import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_nighttime_colregs_assessment(traj, env_info, task_info):
    """
    Verify the nighttime COLREGS assessment scenario creation.

    Scoring breakdown (100 points total):
    - Scenario structure (3 INI files exist): 20 pts
    - Environment config (Solent, nighttime, visibility, weather): 15 pts
    - Own ship placement (name, coordinates, speed): 10 pts
    - Traffic vessels (4 vessels with correct encounter types): 25 pts
    - Radar/ARPA configuration: 15 pts
    - Assessment briefing document: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback = []

    # Copy result file from VM
    try:
        local_path = os.path.join(tempfile.gettempdir(), 'nighttime_colregs_assessment_result.json')
        copy_from_env('/tmp/nighttime_colregs_assessment_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file: {e}. Export script may not have run."
        }

    # --- Criterion 1: Scenario Structure (20 pts) ---
    scenario_score = 0
    if result.get('scenario_exists'):
        scenario_score += 5
        feedback.append("Scenario directory exists")
    else:
        feedback.append("FAIL: Scenario directory not found")
        # If no scenario at all, return 0 immediately
        return {
            "passed": False,
            "score": 0,
            "feedback": "Scenario directory does not exist. No work detected. " + "; ".join(feedback)
        }

    if result.get('env_ini_exists'):
        scenario_score += 5
        feedback.append("environment.ini exists")
    else:
        feedback.append("FAIL: environment.ini missing")

    if result.get('ownship_ini_exists'):
        scenario_score += 5
        feedback.append("ownship.ini exists")
    else:
        feedback.append("FAIL: ownship.ini missing")

    if result.get('othership_ini_exists'):
        scenario_score += 5
        feedback.append("othership.ini exists")
    else:
        feedback.append("FAIL: othership.ini missing")

    score += scenario_score

    # --- Criterion 2: Environment Configuration (15 pts) ---
    env_score = 0
    env_data = result.get('environment', {})

    setting = env_data.get('setting', '').strip().lower()
    if 'solent' in setting:
        env_score += 4
        feedback.append("Setting is Solent")
    else:
        feedback.append(f"FAIL: Setting is '{env_data.get('setting', '')}', expected Solent")

    try:
        start_time = float(env_data.get('start_time', -1))
        if start_time >= 22.0 or start_time <= 4.0:
            env_score += 4
            feedback.append(f"Nighttime start: {start_time}")
        else:
            feedback.append(f"FAIL: StartTime={start_time} is not nighttime (need 22-4)")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse StartTime")

    try:
        vis = float(env_data.get('visibility_range', 0))
        if vis >= 5.0:
            env_score += 4
            feedback.append(f"Visibility {vis} nm >= 5.0")
        else:
            feedback.append(f"FAIL: VisibilityRange={vis} < 5.0")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse VisibilityRange")

    try:
        weather = float(env_data.get('weather', 99))
        if weather <= 2.0:
            env_score += 3
            feedback.append(f"Weather {weather} <= 2.0")
        else:
            feedback.append(f"FAIL: Weather={weather} > 2.0")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse Weather")

    score += env_score

    # --- Criterion 3: Own Ship (10 pts) ---
    own_score = 0
    own = result.get('ownship', {})

    own_name = own.get('name', '').strip()
    if 'dorado' in own_name.lower():
        own_score += 4
        feedback.append(f"Own ship name: {own_name}")
    else:
        feedback.append(f"FAIL: Own ship name '{own_name}' doesn't contain 'Dorado'")

    try:
        lat = float(own.get('lat', 0))
        lng = float(own.get('long', 0))
        lat_range = metadata.get('own_ship_lat_range', [50.77, 50.82])
        lng_range = metadata.get('own_ship_long_range', [-1.20, -1.10])
        if lat_range[0] <= lat <= lat_range[1] and lng_range[0] <= lng <= lng_range[1]:
            own_score += 4
            feedback.append(f"Own ship coordinates valid: {lat}, {lng}")
        else:
            # Allow wider tolerance for Solent area
            if 50.5 <= lat <= 51.0 and -1.5 <= lng <= -0.8:
                own_score += 2
                feedback.append(f"Own ship coords in wider Solent area: {lat}, {lng}")
            else:
                feedback.append(f"FAIL: Own ship coords {lat}, {lng} outside Solent")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse own ship coordinates")

    try:
        speed = float(own.get('speed', 0))
        if 5.0 <= speed <= 20.0:
            own_score += 2
            feedback.append(f"Own ship speed {speed} kts reasonable")
        else:
            feedback.append(f"FAIL: Own ship speed {speed} unrealistic")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse own ship speed")

    score += own_score

    # --- Criterion 4: Traffic Vessels (25 pts) ---
    vessel_score = 0
    other = result.get('othership', {})
    vessel_count = other.get('vessel_count', 0)

    if vessel_count >= 4:
        vessel_score += 10
        feedback.append(f"Vessel count: {vessel_count} >= 4")
    elif vessel_count >= 2:
        vessel_score += 5
        feedback.append(f"Partial vessel count: {vessel_count}")
    else:
        feedback.append(f"FAIL: Only {vessel_count} vessels (need 4)")

    # Check vessel types for diversity
    vessel_types_str = other.get('vessel_types', '').lower()
    vessel_details = other.get('vessel_details', {})

    # Check for legs in each vessel
    vessels_with_legs = 0
    for vid, vdata in vessel_details.items():
        legs = int(vdata.get('legs', 0))
        if legs >= 2:
            vessels_with_legs += 1

    if vessels_with_legs >= 4:
        vessel_score += 5
        feedback.append(f"{vessels_with_legs} vessels have 2+ waypoint legs")
    elif vessels_with_legs >= 2:
        vessel_score += 3
        feedback.append(f"Only {vessels_with_legs} vessels have 2+ legs")
    else:
        feedback.append(f"FAIL: {vessels_with_legs} vessels have proper waypoint legs")

    # Check for diversity of encounter types by vessel type names
    encounter_keywords = {
        'head-on': ['container', 'cargo', 'tanker'],
        'crossing': ['bulk', 'carrier', 'cargo'],
        'overtaking': ['ferry', 'fast', 'patrol'],
        'restricted': ['fish', 'trawl', 'dredg', 'restrict']
    }
    encounters_found = 0
    for encounter_type, keywords in encounter_keywords.items():
        for kw in keywords:
            if kw in vessel_types_str:
                encounters_found += 1
                feedback.append(f"Found {encounter_type} vessel type")
                break

    if encounters_found >= 4:
        vessel_score += 10
    elif encounters_found >= 3:
        vessel_score += 7
        feedback.append(f"Found {encounters_found}/4 encounter types")
    elif encounters_found >= 2:
        vessel_score += 4
        feedback.append(f"Found {encounters_found}/4 encounter types")
    else:
        # Even without matching keywords, give partial credit if vessel count is right
        if vessel_count >= 4:
            vessel_score += 3
            feedback.append(f"4 vessels present but encounter types unclear from names")
        else:
            feedback.append(f"FAIL: Only {encounters_found}/4 recognizable encounter types")

    score += vessel_score

    # --- Criterion 5: Radar/ARPA Configuration (15 pts) ---
    radar_score = 0
    radar = result.get('radar_config', {})
    expected_radar = metadata.get('radar_config', {})

    try:
        if str(radar.get('arpa_on', '')).strip() == '1':
            radar_score += 4
            feedback.append("ARPA enabled")
        else:
            feedback.append(f"FAIL: arpa_on={radar.get('arpa_on', 'missing')}")
    except Exception:
        feedback.append("FAIL: Could not check arpa_on")

    try:
        if str(radar.get('full_radar', '')).strip() == '1':
            radar_score += 4
            feedback.append("Full radar enabled")
        else:
            feedback.append(f"FAIL: full_radar={radar.get('full_radar', 'missing')}")
    except Exception:
        feedback.append("FAIL: Could not check full_radar")

    try:
        res = int(radar.get('radar_range_resolution', 0))
        if res >= 256:
            radar_score += 4
            feedback.append(f"Radar resolution {res} >= 256")
        elif res > 128:
            radar_score += 2
            feedback.append(f"Radar resolution {res} improved but < 256")
        else:
            feedback.append(f"FAIL: radar_range_resolution={res}")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse radar_range_resolution")

    try:
        max_r = int(radar.get('max_radar_range', 0))
        if max_r >= 96:
            radar_score += 3
            feedback.append(f"Max radar range {max_r} >= 96")
        elif max_r > 48:
            radar_score += 1
            feedback.append(f"Max radar range {max_r} improved but < 96")
        else:
            feedback.append(f"FAIL: max_radar_range={max_r}")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not parse max_radar_range")

    score += radar_score

    # --- Criterion 6: Assessment Briefing (15 pts) ---
    briefing_score = 0
    briefing = result.get('briefing', {})

    if briefing.get('exists'):
        briefing_score += 5
        feedback.append("Briefing document exists")

        content = briefing.get('content', '').lower()
        required_keywords = metadata.get('briefing_required_keywords',
                                          ['head-on', 'crossing', 'overtaking', 'rule 13', 'rule 14', 'rule 15'])
        found_keywords = []
        for kw in required_keywords:
            if kw.lower() in content:
                found_keywords.append(kw)

        kw_ratio = len(found_keywords) / max(len(required_keywords), 1)
        kw_points = int(kw_ratio * 10)
        briefing_score += kw_points
        feedback.append(f"Briefing keywords: {len(found_keywords)}/{len(required_keywords)} found ({found_keywords})")
    else:
        feedback.append("FAIL: Briefing document not found")

    score += briefing_score

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
