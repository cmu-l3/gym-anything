import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_instrument_failure_diagnosis(traj, env_info, task_info):
    """
    Verify instrument failure diagnosis and repair.

    Scoring breakdown (100 points total):
    - bc5.ini faults fixed (3 faults x 10 pts): 30 pts
    - Scenario faults fixed (3 faults x 10 pts): 30 pts
    - Fault diagnosis report: 40 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    faults = metadata.get('faults', {})

    score = 0
    feedback = []

    # Copy result file
    try:
        local_path = os.path.join(tempfile.gettempdir(), 'instrument_failure_diagnosis_result.json')
        copy_from_env('/tmp/instrument_failure_diagnosis_result.json', local_path)
        with open(local_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file: {e}"
        }

    bc5 = result.get('bc5_values', {})
    scenario = result.get('scenario_values', {})
    report = result.get('report', {})

    # --- bc5.ini Faults (30 pts) ---

    # Fault 1: view_angle should be 90 (was 5)
    try:
        va = int(bc5.get('view_angle', 0))
        if va == 90:
            score += 10
            feedback.append("view_angle restored to 90")
        elif 60 <= va <= 120:
            score += 5
            feedback.append(f"view_angle={va}, reasonable but not exact (expected 90)")
        else:
            feedback.append(f"FAIL: view_angle={va} (expected 90, was broken at 5)")
    except (ValueError, TypeError):
        feedback.append(f"FAIL: view_angle not parseable: {bc5.get('view_angle')}")

    # Fault 2: radar_range_resolution should be 128 (was 8)
    try:
        rr = int(bc5.get('radar_range_resolution', 0))
        if rr == 128:
            score += 10
            feedback.append("radar_range_resolution restored to 128")
        elif rr >= 64:
            score += 5
            feedback.append(f"radar_range_resolution={rr}, improved but not 128")
        else:
            feedback.append(f"FAIL: radar_range_resolution={rr} (expected 128, was broken at 8)")
    except (ValueError, TypeError):
        feedback.append(f"FAIL: radar_range_resolution not parseable")

    # Fault 3: max_radar_range should be 48 (was 2)
    try:
        mr = int(bc5.get('max_radar_range', 0))
        if mr == 48:
            score += 10
            feedback.append("max_radar_range restored to 48")
        elif mr >= 24:
            score += 5
            feedback.append(f"max_radar_range={mr}, improved but not 48")
        else:
            feedback.append(f"FAIL: max_radar_range={mr} (expected 48, was broken at 2)")
    except (ValueError, TypeError):
        feedback.append(f"FAIL: max_radar_range not parseable")

    # --- Scenario Faults (30 pts) ---

    # Fault 4: VisibilityRange should be 10.0 (was 0.1)
    try:
        vr = float(scenario.get('visibility_range', 0))
        if abs(vr - 10.0) < 0.5:
            score += 10
            feedback.append("VisibilityRange restored to 10.0")
        elif vr >= 5.0:
            score += 5
            feedback.append(f"VisibilityRange={vr}, improved but not 10.0")
        else:
            feedback.append(f"FAIL: VisibilityRange={vr} (expected 10.0, was broken at 0.1)")
    except (ValueError, TypeError):
        feedback.append(f"FAIL: VisibilityRange not parseable")

    # Fault 5: InitialSpeed should be 8.0 (was 85.0)
    try:
        sp = float(scenario.get('initial_speed', 0))
        if abs(sp - 8.0) < 0.5:
            score += 10
            feedback.append("InitialSpeed restored to 8.0")
        elif 5.0 <= sp <= 15.0:
            score += 5
            feedback.append(f"InitialSpeed={sp}, realistic but not exact (expected 8.0)")
        else:
            feedback.append(f"FAIL: InitialSpeed={sp} (expected 8.0, was broken at 85.0)")
    except (ValueError, TypeError):
        feedback.append(f"FAIL: InitialSpeed not parseable")

    # Fault 6: Number of vessels should be 2 (was 0)
    try:
        vc = int(scenario.get('vessel_count', 0))
        if vc == 2:
            score += 10
            feedback.append("Vessel count restored to 2")
        elif vc >= 1:
            score += 5
            feedback.append(f"Vessel count={vc}, partially restored (expected 2)")
        else:
            feedback.append(f"FAIL: Vessel count={vc} (expected 2, was broken at 0)")
    except (ValueError, TypeError):
        feedback.append(f"FAIL: Vessel count not parseable")

    # --- Fault Report (40 pts) ---
    report_score = 0

    if report.get('exists'):
        report_score += 10
        feedback.append("Fault report exists")

        content = report.get('content', '').lower()
        line_count = report.get('line_count', 0)

        # Check report length — should be substantive
        if line_count >= 15:
            report_score += 5
            feedback.append(f"Report is substantive ({line_count} lines)")
        elif line_count >= 5:
            report_score += 2
            feedback.append(f"Report is short ({line_count} lines)")

        # Check for fault-related keywords
        fault_indicators = {
            'view_angle': ['view_angle', 'view angle', 'field of view', 'fov'],
            'radar_resolution': ['radar_range_resolution', 'radar resolution', 'range resolution'],
            'max_radar': ['max_radar_range', 'max radar', 'maximum radar', 'radar range'],
            'visibility': ['visibility', 'visibilityrange', 'fog', 'vis range'],
            'speed': ['speed', 'initialspeed', 'knots', '85'],
            'vessels': ['vessel', 'number', 'othership', 'traffic', 'ship count']
        }

        faults_mentioned = 0
        for fault_name, keywords in fault_indicators.items():
            for kw in keywords:
                if kw in content:
                    faults_mentioned += 1
                    break

        # Up to 25 points for fault coverage in report
        if faults_mentioned >= 6:
            report_score += 25
            feedback.append(f"Report covers all 6 faults")
        elif faults_mentioned >= 4:
            report_score += 17
            feedback.append(f"Report covers {faults_mentioned}/6 faults")
        elif faults_mentioned >= 2:
            report_score += 10
            feedback.append(f"Report covers {faults_mentioned}/6 faults")
        elif faults_mentioned >= 1:
            report_score += 5
            feedback.append(f"Report covers only {faults_mentioned}/6 faults")
        else:
            feedback.append("FAIL: Report doesn't describe any recognizable faults")
    else:
        feedback.append("FAIL: No fault report found at /home/ga/Documents/fault_report.txt")

    score += report_score

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }
