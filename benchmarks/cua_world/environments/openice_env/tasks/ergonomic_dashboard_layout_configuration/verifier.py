#!/usr/bin/env python3
"""Verifier for Ergonomic Dashboard Layout Configuration task."""

import json
import tempfile
import os
import re
import math

def parse_wmctrl_output(raw_output):
    """Parses wmctrl -lG output into a list of dictionaries."""
    windows = []
    # wmctrl -lG output format: 
    # 0x01600007  0 65   304  1326 737  host Title String
    # ID, Desktop, X, Y, W, H, Host, Title
    for line in raw_output.strip().split('\n'):
        if not line:
            continue
        parts = line.split(maxsplit=7)
        if len(parts) < 8:
            continue
        try:
            win = {
                'id': parts[0],
                'x': int(parts[2]),
                'y': int(parts[3]),
                'w': int(parts[4]),
                'h': int(parts[5]),
                'title': parts[7]
            }
            # Calculate center point
            win['cx'] = win['x'] + win['w'] / 2
            win['cy'] = win['y'] + win['h'] / 2
            # Calculate area
            win['area'] = win['w'] * win['h']
            windows.append(win)
        except (ValueError, IndexError):
            continue
    return windows

def get_overlap_area(r1, r2):
    """Calculates intersection area of two rectangles."""
    x_overlap = max(0, min(r1['x'] + r1['w'], r2['x'] + r2['w']) - max(r1['x'], r2['x']))
    y_overlap = max(0, min(r1['y'] + r1['h'], r2['y'] + r2['h']) - max(r1['y'], r2['y']))
    return x_overlap * y_overlap

def verify_ergonomic_layout(traj, env_info, task_info):
    """
    Verify the OpenICE window layout.
    
    Criteria:
    1. Vital Signs App: Center Y < ScreenHeight/2 (Top Half)
    2. Infusion Pump: Center Y > ScreenHeight/2, Center X < ScreenWidth/2 (Bottom Left)
    3. Monitor: Center Y > ScreenHeight/2, Center X > ScreenWidth/2 (Bottom Right)
    4. Minimal Overlap: < 10% overlap between any pair.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Screen dimensions from metadata
    metadata = task_info.get('metadata', {})
    SCREEN_W = metadata.get('screen_width', 1920)
    SCREEN_H = metadata.get('screen_height', 1080)
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    raw_windows = result.get('window_list_raw', '')
    windows = parse_wmctrl_output(raw_windows)
    
    # Identify target windows
    # OpenICE window titles usually contain specific keywords
    vital_signs_win = None
    pump_win = None
    monitor_win = None
    
    # Heuristics for window identification
    for w in windows:
        title = w['title'].lower()
        if 'vital' in title and 'app' in title:
            vital_signs_win = w
        elif 'infusion' in title and ('pump' in title or 'device' in title):
            pump_win = w
        elif ('multiparameter' in title or 'monitor' in title) and 'device' in title and 'infusion' not in title:
            # exclude infusion from monitor check to prevent ambiguity if "Infusion Monitor" string exists
            monitor_win = w

    score = 0
    feedback = []
    
    # 1. Existence Check (30 pts)
    if vital_signs_win:
        score += 10
        feedback.append("Vital Signs App found.")
    else:
        feedback.append("Vital Signs App NOT found.")
        
    if pump_win:
        score += 10
        feedback.append("Infusion Pump found.")
    else:
        feedback.append("Infusion Pump NOT found.")
        
    if monitor_win:
        score += 10
        feedback.append("Multiparameter Monitor found.")
    else:
        feedback.append("Multiparameter Monitor NOT found.")

    # 2. Position Check (40 pts)
    pos_score = 0
    
    if vital_signs_win:
        # Should be in top half
        if vital_signs_win['cy'] < SCREEN_H / 2:
            pos_score += 15
            feedback.append("Vital Signs in Top Half.")
        else:
            feedback.append(f"Vital Signs not in Top Half (Cy={vital_signs_win['cy']}).")

    if pump_win:
        # Should be Bottom Left
        if pump_win['cy'] > SCREEN_H / 2 and pump_win['cx'] < SCREEN_W / 2:
            pos_score += 12.5
            feedback.append("Pump in Bottom-Left.")
        else:
            feedback.append(f"Pump not in Bottom-Left (Cx={pump_win['cx']}, Cy={pump_win['cy']}).")

    if monitor_win:
        # Should be Bottom Right
        if monitor_win['cy'] > SCREEN_H / 2 and monitor_win['cx'] > SCREEN_W / 2:
            pos_score += 12.5
            feedback.append("Monitor in Bottom-Right.")
        else:
            feedback.append(f"Monitor not in Bottom-Right (Cx={monitor_win['cx']}, Cy={monitor_win['cy']}).")

    score += int(pos_score)

    # 3. Overlap Check (20 pts)
    # Only check if we have the windows
    overlap_score = 20
    failed_overlaps = []
    
    target_windows = [w for w in [vital_signs_win, pump_win, monitor_win] if w is not None]
    
    if len(target_windows) > 1:
        for i in range(len(target_windows)):
            for j in range(i + 1, len(target_windows)):
                w1 = target_windows[i]
                w2 = target_windows[j]
                
                intersection = get_overlap_area(w1, w2)
                min_area = min(w1['area'], w2['area'])
                
                if min_area > 0:
                    overlap_pct = intersection / min_area
                    if overlap_pct > 0.10: # > 10% overlap
                        failed_overlaps.append(f"{w1['title']} overlaps {w2['title']} ({int(overlap_pct*100)}%)")
                        overlap_score = 0
    
    if failed_overlaps:
        feedback.append("Overlap check FAILED: " + ", ".join(failed_overlaps))
    elif len(target_windows) > 1:
        feedback.append("Overlap check PASSED (clean layout).")
    
    score += overlap_score

    # 4. Screenshot Evidence (10 pts)
    if result.get('agent_screenshot_exists', False):
        score += 10
        feedback.append("Screenshot saved.")
    else:
        feedback.append("Screenshot NOT saved.")

    # Pass Threshold
    # Needs existence of all 3 (30) + rough position (at least 15) + mostly clean layout
    passed = score >= 60 and vital_signs_win and pump_win and monitor_win

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "windows_found": len(target_windows),
            "position_score": pos_score,
            "overlap_score": overlap_score
        }
    }