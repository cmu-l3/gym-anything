#!/usr/bin/env python3
"""Verifier for emergency_medical_cargo_drop task.

Scoring (100 pts total, pass = 70):
  10  File exists and modified during task
  10  WPNAV_SPEED == 300 (±5)
  10  WPNAV_ACCEL == 100 (±5)
  10  Mission contains Takeoff (cmd=22) and RTL (cmd=20)
  20  Mission contains a waypoint near (-35.3625, 149.1640)
  20  Mission contains an altitude drop <= 5.0m
  20  Mission contains DO_SET_SERVO (cmd=183) with param1=7, param2=1900
"""

import json
import os
import tempfile

def verify_cargo_drop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    target_speed = metadata.get('target_wpnav_speed', 300)
    target_accel = metadata.get('target_wpnav_accel', 100)
    target_lat = metadata.get('target_lat', -35.3625)
    target_lon = metadata.get('target_lon', 149.1640)
    target_alt = metadata.get('target_alt_max', 5.0)
    servo_cmd = metadata.get('servo_cmd', 183)
    servo_inst = metadata.get('servo_instance', 7)
    servo_pwm = metadata.get('servo_pwm', 1900)

    # Read the exported JSON payload securely
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Could not read export result: {e}'}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    details = {}

    # 1. File Status (10 pts)
    if result.get('file_found') and result.get('modified_during_task'):
        score += 10
        feedback.append('Plan file exists and was modified (+10)')
    else:
        feedback.append('Plan file not found or not modified (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # 2. Parameters (10 pts each)
    params = result.get('params', {})
    speed = params.get('WPNAV_SPEED')
    if speed is not None and abs(float(speed) - target_speed) <= 5:
        score += 10
        feedback.append(f'WPNAV_SPEED={speed} ✓ (+10)')
    else:
        feedback.append(f'WPNAV_SPEED={speed} (need {target_speed}) (+0)')

    accel = params.get('WPNAV_ACCEL')
    if accel is not None and abs(float(accel) - target_accel) <= 5:
        score += 10
        feedback.append(f'WPNAV_ACCEL={accel} ✓ (+10)')
    else:
        feedback.append(f'WPNAV_ACCEL={accel} (need {target_accel}) (+0)')

    # Parse JSON plan file content
    plan_content = result.get('plan_content', '')
    if isinstance(plan_content, str):
        plan_content = plan_content.replace('\\n', '\n').replace('\\t', '\t')
    try:
        plan = json.loads(plan_content)
    except Exception as e:
        feedback.append(f'Could not parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    items = plan.get('mission', {}).get('items', [])
    
    # 3. Takeoff and RTL (10 pts)
    cmds = [it.get('command') for it in items]
    has_takeoff = 22 in cmds
    has_rtl = 20 in cmds
    if has_takeoff and has_rtl:
        score += 10
        feedback.append('Takeoff and RTL found in mission (+10)')
    else:
        feedback.append(f'Missing Takeoff or RTL (Takeoff:{has_takeoff}, RTL:{has_rtl}) (+0)')

    # 4. Drop Location (20 pts)
    found_location = False
    for it in items:
        params_list = it.get('params', [])
        if len(params_list) >= 7:
            lat = params_list[4]
            lon = params_list[5]
            if lat is not None and lon is not None and lat != 0 and lon != 0:
                if abs(lat - target_lat) <= 0.0005 and abs(lon - target_lon) <= 0.0005:
                    found_location = True
                    break

    if found_location:
        score += 20
        feedback.append('Target location found in mission (+20)')
    else:
        feedback.append('Target location not found in mission (+0)')

    # 5. Safe Drop Altitude (20 pts)
    found_alt = False
    for it in items:
        params_list = it.get('params', [])
        if len(params_list) >= 7:
            alt = params_list[6]
            # Must be a navigation waypoint (16) to count as an altitude drop
            cmd = it.get('command', 0)
            if cmd == 16 and alt is not None and 0 < alt <= target_alt:
                found_alt = True
                break

    if found_alt:
        score += 20
        feedback.append(f'Safe drop altitude (<= {target_alt}m) found (+20)')
    else:
        feedback.append(f'Safe drop altitude (<= {target_alt}m) not found (+0)')

    # 6. Servo Release (20 pts)
    found_servo = False
    for it in items:
        cmd = it.get('command')
        params_list = it.get('params', [])
        if cmd == servo_cmd and len(params_list) >= 2:
            try:
                p1 = float(params_list[0]) if params_list[0] is not None else 0
                p2 = float(params_list[1]) if params_list[1] is not None else 0
                # Using robust float comparison instead of strict integer checking
                if abs(p1 - servo_inst) < 0.1 and abs(p2 - servo_pwm) < 1.0:
                    found_servo = True
                    break
            except (ValueError, TypeError):
                pass

    if found_servo:
        score += 20
        feedback.append('Servo release command found (+20)')
    else:
        feedback.append('Servo release command not found (+0)')

    passed = score >= 70
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }