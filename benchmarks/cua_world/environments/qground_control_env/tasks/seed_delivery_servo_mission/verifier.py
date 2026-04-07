#!/usr/bin/env python3
"""
Verifier for seed_delivery_servo_mission task.

Scoring (110 pts total, capped at 100, pass = 70):
  10  Plan file exists
   5  File modified during task
  10  Takeoff command present (cmd 22)
  10  >=2 NAV_WAYPOINT commands (cmd 16)
  15  >=2 DO_SET_SERVO commands (cmd 183)
   5  Bonus: >=4 DO_SET_SERVO commands
  10  Servo channel correct (param1 == 9)
  10  Open PWM present (param2 in [1050, 1150])
  10  Close PWM present (param2 in [1850, 1950])
  10  NAV_DELAY present (cmd 93) ~5s
  15  RTL command present (cmd 20)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Command IDs from MAVLink standard
CMD_TAKEOFF = 22
CMD_WAYPOINT = 16
CMD_DO_SET_SERVO = 183
CMD_NAV_DELAY = 93
CMD_RTL = 20

def _extract_all_items(plan_dict):
    """Recursively search for all mission items inside the plan JSON."""
    items = []
    
    # Standard QGC format
    if 'mission' in plan_dict and 'items' in plan_dict['mission']:
        items.extend(plan_dict['mission']['items'])
        return items
        
    # Fallback recursive search if QGC changes format
    def recurse(obj):
        if isinstance(obj, dict):
            if 'command' in obj and 'params' in obj:
                items.append(obj)
            for v in obj.values():
                recurse(v)
        elif isinstance(obj, list):
            for i in obj:
                recurse(i)
                
    recurse(plan_dict)
    return items

def verify_seed_delivery_mission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Copy the result file from the environment
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

    # 1. File exists (10 pts)
    file_found = result.get('file_found', False)
    if file_found:
        score += 10
        feedback.append('Plan file exists (+10)')
    else:
        feedback.append('Plan file not found (+0)')
        return {'passed': False, 'score': 0, 'feedback': ' | '.join(feedback), 'details': details}

    # 2. Modified during task (5 pts)
    if result.get('modified_during_task', False):
        score += 5
        feedback.append('File modified during task (+5)')
    else:
        feedback.append('File not modified during task (+0)')

    # Parse plan content
    plan_content_raw = result.get('plan_content', '')
    if isinstance(plan_content_raw, str):
        # Handle double escapes if present
        plan_content_raw = plan_content_raw.replace('\\n', '\n').replace('\\t', '\t')
        
    try:
        plan = json.loads(plan_content_raw)
    except Exception as e:
        feedback.append(f'Cannot parse plan JSON: {e}')
        return {'passed': False, 'score': score, 'feedback': ' | '.join(feedback), 'details': details}

    # Extract items
    items = _extract_all_items(plan)
    details['total_items'] = len(items)
    
    # Categorize items
    takeoff_cmds = []
    waypoint_cmds = []
    servo_cmds = []
    delay_cmds = []
    rtl_cmds = []
    
    for item in items:
        cmd = item.get('command')
        if cmd == CMD_TAKEOFF:
            takeoff_cmds.append(item)
        elif cmd == CMD_WAYPOINT:
            waypoint_cmds.append(item)
        elif cmd == CMD_DO_SET_SERVO:
            servo_cmds.append(item)
        elif cmd == CMD_NAV_DELAY:
            delay_cmds.append(item)
        elif cmd == CMD_RTL:
            rtl_cmds.append(item)
            
    # 3. Takeoff command present (10 pts)
    if len(takeoff_cmds) > 0:
        score += 10
        feedback.append('Takeoff command found (+10)')
    else:
        feedback.append('Takeoff command missing (+0)')

    # 4. >=2 NAV_WAYPOINT commands (10 pts)
    if len(waypoint_cmds) >= 2:
        score += 10
        feedback.append(f'{len(waypoint_cmds)} Waypoints found (+10)')
    else:
        feedback.append(f'Only {len(waypoint_cmds)} waypoints found (need >=2) (+0)')

    # 5. DO_SET_SERVO commands
    num_servo = len(servo_cmds)
    if num_servo >= 2:
        score += 15
        feedback.append(f'>=2 DO_SET_SERVO commands found (+15)')
        if num_servo >= 4:
            score += 5
            feedback.append(f'>=4 DO_SET_SERVO commands found bonus (+5)')
    elif num_servo == 1:
        score += 5
        feedback.append('Only 1 DO_SET_SERVO command found (+5 partial)')
    else:
        feedback.append('No DO_SET_SERVO commands found (+0)')

    # 6. Check Servo Parameters (Channel, Open PWM, Close PWM)
    has_correct_channel = False
    has_open_pwm = False
    has_close_pwm = False
    
    for item in servo_cmds:
        params = item.get('params', [])
        if len(params) >= 2:
            try:
                channel = float(params[0])
                pwm = float(params[1])
                
                # Check channel (9)
                if abs(channel - 9.0) < 0.1:
                    has_correct_channel = True
                    
                # Check PWM values
                if 1050 <= pwm <= 1150:
                    has_open_pwm = True
                elif 1850 <= pwm <= 1950:
                    has_close_pwm = True
            except (ValueError, TypeError):
                continue
                
    if has_correct_channel:
        score += 10
        feedback.append('Servo channel 9 verified (+10)')
    else:
        feedback.append('Correct servo channel (9) not found in commands (+0)')
        
    if has_open_pwm:
        score += 10
        feedback.append('Servo OPEN PWM (~1100) verified (+10)')
    else:
        feedback.append('Servo OPEN PWM (~1100) not found (+0)')
        
    if has_close_pwm:
        score += 10
        feedback.append('Servo CLOSE PWM (~1900) verified (+10)')
    else:
        feedback.append('Servo CLOSE PWM (~1900) not found (+0)')

    # 7. NAV_DELAY present ~5s (10 pts)
    has_correct_delay = False
    for item in delay_cmds:
        params = item.get('params', [])
        if len(params) >= 1:
            try:
                delay = float(params[0])
                if 2.0 <= delay <= 8.0:  # Allow 2-8s to capture "approx 5s"
                    has_correct_delay = True
                    break
            except (ValueError, TypeError):
                continue
                
    if has_correct_delay:
        score += 10
        feedback.append('NAV_DELAY (~5s) verified (+10)')
    else:
        feedback.append('NAV_DELAY of ~5s not found (+0)')

    # 8. RTL command present (15 pts)
    if len(rtl_cmds) > 0:
        score += 15
        feedback.append('RTL command found (+15)')
    else:
        feedback.append('RTL command missing (+0)')

    # Final scoring calculation
    if score > 100:
        score = 100
        
    passed = score >= 70
    
    details['score'] = score
    details['servo_count'] = num_servo
    details['delay_count'] = len(delay_cmds)
    
    return {
        'passed': passed,
        'score': score,
        'feedback': ' | '.join(feedback),
        'details': details
    }