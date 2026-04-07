#!/usr/bin/env python3
"""
Verifier for incident_event_annotation_dashboard task.

Scoring (100 pts, pass >= 60):
  30 pts  Event 'Cache Flush' with tag 'mitigation_applied' injected successfully via API
  10 pts  Dashboard 'Sev1 Mitigation Review' exists
  15 pts  Graph 'Database Load' contains movingAverage target
  15 pts  Graph 'Database Load' contains events overlay target
  15 pts  Graph 'Frontend Traffic' contains load balancer target
  15 pts  Graph 'Frontend Traffic' contains events overlay target

Pass threshold requires BOTH the API event injection AND at least one events overlay.
"""

import json
import os
import tempfile

RESULT_PATH = "/tmp/incident_event_annotation_dashboard_result.json"
DASHBOARD_NAME = "Sev1 Mitigation Review"


def _get_graphs(dashboard_state):
    graphs = []
    raw_graphs = dashboard_state.get("graphs", [])
    for entry in raw_graphs:
        if not isinstance(entry, (list, tuple)) or len(entry) < 2:
            continue
        params = entry[1] if isinstance(entry[1], dict) else {}
        title = params.get("title", "")
        targets = params.get("target", [])
        if isinstance(targets, str):
            targets = [targets]
        graphs.append((title, [str(t) for t in targets]))
    return graphs


def _find_graph(graphs, expected_title):
    for title, targets in graphs:
        if title == expected_title:
            return title, targets
    for title, targets in graphs:
        if expected_title.lower() in title.lower():
            return title, targets
    return None


def verify_incident_event_annotation_dashboard(trajectory, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    score = 0
    feedback = []

    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path) as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result file: {e}"}

    dashboards = result.get("dashboards", {})
    events = result.get("events", [])

    has_db_event = False
    has_fe_event = False

    # Check 1: Event Injected (30 pts)
    event_found = False
    if isinstance(events, list):
        for ev in events:
            if isinstance(ev, dict):
                what = ev.get("what", "")
                tags = ev.get("tags", "")
                # Flexible matching to handle both string and list tag types
                if "Cache Flush" in what and "mitigation_applied" in tags:
                    event_found = True
                    break
    
    if event_found:
        score += 30
        feedback.append("[+30] Event 'Cache Flush' with tag 'mitigation_applied' injected successfully via API")
    else:
        feedback.append("[-] Required event not found in Graphite Events API")

    # Check 2: Dashboard Exists (10 pts)
    if DASHBOARD_NAME not in dashboards:
        feedback.append(f"[-] Dashboard '{DASHBOARD_NAME}' not found")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}
    
    score += 10
    feedback.append(f"[+10] Dashboard '{DASHBOARD_NAME}' exists")
    
    dashboard_state = dashboards[DASHBOARD_NAME]
    graphs = _get_graphs(dashboard_state)

    # Check 3: Graph 1 - Database Load (15 pts base + 15 pts event overlay)
    db_match = _find_graph(graphs, "Database Load")
    if db_match:
        db_title, db_targets = db_match
        feedback.append(f"[+] Found graph '{db_title}'")
        
        has_db_ma = False
        
        for t in db_targets:
            tl = t.lower()
            if "movingaverage" in tl and "rds_database.cpu.utilization" in tl and "10" in tl:
                has_db_ma = True
            if "events" in tl and "mitigation_applied" in tl:
                has_db_event = True
                
        if has_db_ma:
            score += 15
            feedback.append("[+15] Graph 'Database Load' contains valid movingAverage target")
        else:
            feedback.append("[-] Graph 'Database Load' missing movingAverage target")
            
        if has_db_event:
            score += 15
            feedback.append("[+15] Graph 'Database Load' contains events overlay target")
        else:
            feedback.append("[-] Graph 'Database Load' missing events overlay target")
    else:
        feedback.append("[-] Graph 'Database Load' not found")

    # Check 4: Graph 2 - Frontend Traffic (15 pts base + 15 pts event overlay)
    fe_match = _find_graph(graphs, "Frontend Traffic")
    if fe_match:
        fe_title, fe_targets = fe_match
        feedback.append(f"[+] Found graph '{fe_title}'")
        
        has_fe_metric = False
        
        for t in fe_targets:
            tl = t.lower()
            if "load_balancer.requests.count" in tl:
                has_fe_metric = True
            if "events" in tl and "mitigation_applied" in tl:
                has_fe_event = True
                
        if has_fe_metric:
            score += 15
            feedback.append("[+15] Graph 'Frontend Traffic' contains valid load balancer target")
        else:
            feedback.append("[-] Graph 'Frontend Traffic' missing load balancer target")
            
        if has_fe_event:
            score += 15
            feedback.append("[+15] Graph 'Frontend Traffic' contains events overlay target")
        else:
            feedback.append("[-] Graph 'Frontend Traffic' missing events overlay target")
    else:
        feedback.append("[-] Graph 'Frontend Traffic' not found")

    # Anti-gaming: Agent must have successfully done the API portion AND linked it via the UI
    key_criteria_met = event_found and (has_db_event or has_fe_event)
    passed = score >= 60 and key_criteria_met
    
    if not key_criteria_met:
        feedback.append("[-] FAILED: Key criteria not met. You must both inject the API event and overlay it on a graph.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }