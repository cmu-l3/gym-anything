import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_restricted_vis_emergency_drill(traj, env_info, task_info):
    """
    Verify restricted visibility emergency drill configuration.

    Scoring breakdown (100 points total):
    - Environment modified for fog: 15 pts
    - Own ship modified: 15 pts
    - Traffic vessels modified (3rd vessel + speed reduction): 20 pts
    - Radar/ARPA config for fog: 15 pts
    - Fog drill checklist: 35 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback = []

    try:
        local_path = os.path.join(tempfile.gettempdir(), 'restricted_vis_emergency_drill_result.json')
        copy_from_env('/tmp/restricted_vis_emergency_drill_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1: Environment Modified (15 pts) ---
    # Only score values that CHANGED from baseline (original: Vis=10.0, Weather=3.0, StartTime=14.0)
    # Rain=0.0 is already correct at baseline — do not score it (no agent work needed)
    env_score = 0
    env = result.get('environment', {})

    try:
        vis = float(env.get('visibility_range', 99))
        # Baseline is 10.0 — must change to 0.5
        if abs(vis - 0.5) < 0.2:
            env_score += 5
            feedback.append(f"Visibility={vis} (fog conditions)")
        elif vis <= 1.0:
            env_score += 3
            feedback.append(f"Visibility={vis} (reduced but not 0.5)")
        else:
            feedback.append(f"FAIL: Visibility={vis}, expected 0.5 (fog)")
    except (ValueError, TypeError):
        feedback.append("FAIL: Visibility not parseable")

    try:
        w = float(env.get('weather', 99))
        # Baseline is 3.0 — must change to 1.0
        if abs(w - 1.0) < 0.5:
            env_score += 5
            feedback.append(f"Weather={w} (calm for fog)")
        else:
            feedback.append(f"Weather={w}, expected 1.0")
    except (ValueError, TypeError):
        pass

    try:
        st = float(env.get('start_time', -1))
        # Baseline is 14.0 — must change to 8.0
        if abs(st - 8.0) < 1.0:
            env_score += 5
            feedback.append(f"StartTime={st} (morning fog)")
        elif 6.0 <= st <= 10.0:
            env_score += 3
    except (ValueError, TypeError):
        pass

    score += env_score
    feedback.append(f"Environment: {env_score}/15")

    # --- Criterion 2: Own Ship Modified (15 pts) ---
    own_score = 0
    own = result.get('ownship', {})

    if 'caution' in own.get('name', '').lower():
        own_score += 8
        feedback.append(f"Ship name: {own.get('name')}")
    else:
        feedback.append(f"FAIL: Ship name '{own.get('name')}', expected 'MV Caution'")

    try:
        spd = float(own.get('speed', 0))
        if abs(spd - 5.0) < 0.5:
            own_score += 7
            feedback.append(f"Speed={spd} (safe speed)")
        elif spd <= 7.0:
            own_score += 3
            feedback.append(f"Speed={spd} (reduced but not 5.0)")
        else:
            feedback.append(f"FAIL: Speed={spd}, expected 5.0 (safe speed)")
    except (ValueError, TypeError):
        feedback.append("FAIL: Speed not parseable")

    score += own_score
    feedback.append(f"Own ship: {own_score}/15")

    # --- Criterion 3: Traffic Vessels (20 pts) ---
    vessel_score = 0
    other = result.get('othership', {})

    vc = other.get('vessel_count', 0)
    # Baseline is 2 — must increase to 3. No partial credit for unchanged count.
    if vc >= 3:
        vessel_score += 6
        feedback.append(f"Vessel count: {vc}")
    else:
        feedback.append(f"FAIL: Vessel count={vc} (expected 3, baseline was 2)")

    # Check third vessel type
    third_type = other.get('third_vessel_type', '').lower()
    if 'cargo' in third_type:
        vessel_score += 6
        feedback.append(f"Third vessel: {third_type}")
    elif third_type:
        vessel_score += 3
        feedback.append(f"Third vessel type: {third_type} (expected Cargo)")
    else:
        if vc >= 3:
            vessel_score += 2
            feedback.append("Third vessel exists but type not detected as Cargo")

    # Check speed reduction — original speeds were 8,6,4 (tanker) and 5,5 (yacht)
    # Halved should be ~4,3,2 and ~3,3
    try:
        v1_spd = float(other.get('v1_speed', 0))
        v2_spd = float(other.get('v2_speed', 0))
        # Original v1 speed was 8, halved = 4
        if v1_spd <= 5:
            vessel_score += 4
            feedback.append(f"V1 speed reduced to {v1_spd}")
        else:
            feedback.append(f"V1 speed={v1_spd}, expected ~4 (halved from 8)")

        # Original v2 speed was 5, halved = 3 (rounded)
        if v2_spd <= 3:
            vessel_score += 4
            feedback.append(f"V2 speed reduced to {v2_spd}")
        else:
            feedback.append(f"V2 speed={v2_spd}, expected ~3 (halved from 5)")
    except (ValueError, TypeError):
        feedback.append("FAIL: Could not check vessel speeds")

    score += vessel_score
    feedback.append(f"Vessels: {vessel_score}/20")

    # --- Criterion 4: Radar/ARPA (15 pts) ---
    # Only score values that CHANGED from baseline (arpa_on=0, full_radar=0, resolution=128)
    # max_radar_range=48 is already correct at baseline — do not score it
    radar_score = 0
    radar = result.get('radar_config', {})

    if str(radar.get('full_radar', '')).strip() == '1':
        radar_score += 5
        feedback.append("Full radar enabled")
    else:
        feedback.append(f"FAIL: full_radar={radar.get('full_radar')}")

    if str(radar.get('arpa_on', '')).strip() == '1':
        radar_score += 5
        feedback.append("ARPA enabled")
    else:
        feedback.append(f"FAIL: arpa_on={radar.get('arpa_on')}")

    try:
        rr = int(radar.get('radar_range_resolution', 0))
        # Baseline is 128 — must change to 256
        if rr >= 256:
            radar_score += 5
        elif rr > 128:
            radar_score += 3
    except (ValueError, TypeError):
        pass

    score += radar_score
    feedback.append(f"Radar: {radar_score}/15")

    # --- Criterion 5: Fog Drill Checklist (35 pts) ---
    cl_score = 0
    cl = result.get('checklist', {})

    if cl.get('exists'):
        cl_score += 5
        feedback.append("Checklist file exists")

        # Check numbered items
        numbered = cl.get('numbered_items', 0)
        min_items = metadata.get('checklist_min_items', 10)
        if numbered >= min_items:
            cl_score += 10
            feedback.append(f"Checklist has {numbered} numbered items (>= {min_items})")
        elif numbered >= 5:
            cl_score += 5
            feedback.append(f"Checklist has {numbered} items (need {min_items})")
        elif numbered >= 1:
            cl_score += 2
            feedback.append(f"Checklist has only {numbered} items")

        # Check keywords
        content = cl.get('content', '').lower()
        keywords = metadata.get('checklist_keywords', [])
        found = []
        for kw in keywords:
            if kw.lower() in content:
                found.append(kw)

        kw_ratio = len(found) / max(len(keywords), 1)
        kw_points = int(kw_ratio * 20)
        cl_score += kw_points
        feedback.append(f"Checklist keywords: {len(found)}/{len(keywords)}")
    else:
        feedback.append("FAIL: Checklist not found")

    score += cl_score
    feedback.append(f"Checklist: {cl_score}/35")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
