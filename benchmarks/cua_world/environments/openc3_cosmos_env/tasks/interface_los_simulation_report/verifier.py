#!/usr/bin/env python3
"""
Verifier for interface_los_simulation_report task.

A network controller must intentionally disconnect and reconnect the INST_INT
interface in OpenC3 COSMOS to simulate a network dropout, waiting at least 15s.
They must produce a JSON report documenting the exact timestamps.
A background process independently records the interface state.

Scoring breakdown (100 pts total, pass threshold = 70):
  5pts   JSON Report Exists
  5pts   Report created during session
  10pts  Schema compliance met (all 5 required keys present)
  30pts  Ground truth log confirms interface was disconnected and reconnected
  10pts  Ground truth confirms gap was >= 15 seconds
  20pts  Reported LOS timestamp accurate within 10 seconds of true disconnect time
  20pts  Reported AOS timestamp accurate within 10 seconds of true reconnect time
 ---
 100pts total
"""

import json
import os
import tempfile
from datetime import datetime

def parse_iso(ts_str):
    if not isinstance(ts_str, str):
        return None
    s = ts_str.strip().replace('Z', '+00:00')
    dt = None
    try:
        dt = datetime.fromisoformat(s)
    except ValueError:
        for fmt in (
            '%Y-%m-%dT%H:%M:%S',
            '%Y-%m-%dT%H:%M:%S.%f',
            '%Y-%m-%d %H:%M:%S',
            '%Y-%m-%d %H:%M:%S UTC'
        ):
            try:
                dt = datetime.strptime(s, fmt)
                break
            except ValueError:
                continue
    
    if dt is not None:
        if dt.tzinfo is not None:
            dt = dt.replace(tzinfo=None)
        return dt
    return None

def verify_interface_los_simulation_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if copy_from_env is None:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}
        
    result_file = '/tmp/los_simulation_result.json'
    export_meta = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_name = tmp.name
        copy_from_env(result_file, tmp_name)
        with open(tmp_name, 'r') as f:
            export_meta = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Export metadata not found: {e}'}
    finally:
        if os.path.exists(tmp_name): os.unlink(tmp_name)

    score = 0
    feedback = []

    file_exists = export_meta.get('file_exists', False)
    file_is_new = export_meta.get('file_is_new', False)
    gt_log = export_meta.get('gt_log', '')

    if file_exists:
        score += 5
        feedback.append("JSON Report Exists (+5)")
        if file_is_new:
            score += 5
            feedback.append("Report created during session (+5)")
        else:
            feedback.append("Report predates task start (no content credit)")
            file_exists = False
    else:
        feedback.append("JSON Report NOT found")

    agent_report = {}
    if file_exists:
        agent_file = '/home/ga/Desktop/los_event_report.json'
        try:
            with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
                tmp_name = tmp.name
            copy_from_env(agent_file, tmp_name)
            with open(tmp_name, 'r') as f:
                agent_report = json.load(f)
        except Exception as e:
            feedback.append(f'Could not parse agent JSON: {e}')
            agent_report = None
        finally:
            if os.path.exists(tmp_name): os.unlink(tmp_name)

    if agent_report:
        required = {'interface_name', 'los_timestamp', 'aos_timestamp', 'gap_duration_seconds', 'recovery_successful'}
        missing = required - set(agent_report.keys())
        if not missing:
            score += 10
            feedback.append("Schema compliance met (+10)")
        else:
            feedback.append(f"Missing keys: {missing}")

    events = []
    for line in gt_log.strip().split('\n'):
        parts = line.split()
        if len(parts) >= 2:
            ts = parse_iso(parts[0])
            state = parts[1]
            if ts:
                events.append((ts, state))

    gaps = []
    los_time = None
    for ts, state in events:
        if state == "DISCONNECTED" and los_time is None:
            los_time = ts
        elif state == "CONNECTED" and los_time is not None:
            aos_time = ts
            duration = (aos_time - los_time).total_seconds()
            gaps.append((los_time, aos_time, duration))
            los_time = None

    if not gaps:
        feedback.append("Ground truth log shows no completed DISCONNECTED periods")
    else:
        score += 30
        feedback.append("Interface successfully disconnected and reconnected (+30)")
        
        longest_gap = max(gaps, key=lambda x: x[2])
        if longest_gap[2] >= 15:
            score += 10
            feedback.append(f"Gap duration met: {longest_gap[2]:.1f}s >= 15s (+10)")
        else:
            feedback.append(f"Longest gap was only {longest_gap[2]:.1f}s (needed >= 15s)")

        if agent_report:
            agt_los_str = agent_report.get('los_timestamp', '')
            agt_aos_str = agent_report.get('aos_timestamp', '')
            
            agt_los = parse_iso(agt_los_str)
            agt_aos = parse_iso(agt_aos_str)

            if agt_los:
                closest_los_diff = min([abs((agt_los - g[0]).total_seconds()) for g in gaps])
                if closest_los_diff <= 10:
                    score += 20
                    feedback.append(f"LOS time accurate within {closest_los_diff:.1f}s (+20)")
                else:
                    feedback.append(f"LOS time inaccurate (diff {closest_los_diff:.1f}s > 10s)")
            else:
                feedback.append("Agent LOS timestamp missing or invalid format")

            if agt_aos:
                closest_aos_diff = min([abs((agt_aos - g[1]).total_seconds()) for g in gaps])
                if closest_aos_diff <= 10:
                    score += 20
                    feedback.append(f"AOS time accurate within {closest_aos_diff:.1f}s (+20)")
                else:
                    feedback.append(f"AOS time inaccurate (diff {closest_aos_diff:.1f}s > 10s)")
            else:
                feedback.append("Agent AOS timestamp missing or invalid format")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }