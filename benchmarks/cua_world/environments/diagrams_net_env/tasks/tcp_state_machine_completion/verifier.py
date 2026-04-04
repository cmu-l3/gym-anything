#!/usr/bin/env python3
import json
import os
import tempfile
import logging

def verify_tcp_state_machine(traj, env_info, task_info):
    """
    Verifies the TCP State Machine task.
    
    Criteria:
    1. File modified during task (5 pts)
    2. All 11 TCP states present (25 pts)
    3. Missing states specifically checked (FIN_WAIT_2, CLOSING, etc) (25 pts)
    4. Transition count >= 18 (10 pts)
    5. Transition labels contain syntax (10 pts)
    6. Erroneous ESTABLISHED->CLOSED edge REMOVED (10 pts)
    7. Simultaneous Open path added (5 pts)
    8. PNG Export exists (10 pts)
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}
        
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Extract Graph Data
    graph = result.get('graph_data', {})
    if 'error' in graph:
        return {"passed": False, "score": 0, "feedback": f"XML Parse Error: {graph['error']}"}
        
    nodes = graph.get('nodes', [])
    edges = graph.get('edges', [])
    
    # Normalize node labels (uppercase, strip)
    node_map = {} # id -> label
    found_labels = set()
    for n in nodes:
        label = n['label'].upper().replace('-', '_').replace(' ', '_').strip()
        node_map[n['id']] = label
        found_labels.add(label)
        
    # --- Scoring ---
    score = 0
    feedback = []
    
    # 1. File Modification (5 pts)
    if result.get('modified_during_task'):
        score += 5
    else:
        feedback.append("File not modified.")
        
    # 2. State Presence (25 pts total)
    required_states = {
        "CLOSED", "LISTEN", "SYN_SENT", "SYN_RCVD", "ESTABLISHED",
        "FIN_WAIT_1", "FIN_WAIT_2", "CLOSING", "TIME_WAIT", "CLOSE_WAIT", "LAST_ACK"
    }
    present_states = found_labels.intersection(required_states)
    missing_states = required_states - found_labels
    
    # Partial credit for states: 2.27 pts per state
    state_score = len(present_states) * (25 / 11)
    score += int(state_score)
    
    if missing_states:
        feedback.append(f"Missing states: {', '.join(missing_states)}")
    else:
        feedback.append("All 11 TCP states found.")
        
    # 3. Specific Difficult States (25 pts)
    # These 5 were missing in the start state
    difficult_states = ["FIN_WAIT_2", "CLOSING", "TIME_WAIT", "CLOSE_WAIT", "LAST_ACK"]
    for ds in difficult_states:
        if ds in found_labels:
            score += 5
            
    # 4. Transition Count (10 pts)
    # A complete diagram has ~20-22 transitions. Start state had ~6.
    if len(edges) >= 18:
        score += 10
    elif len(edges) >= 12:
        score += 5
        feedback.append(f"Low transition count: {len(edges)}")
        
    # 5. Transition Labels (10 pts)
    # Check if edges have text like "rcv" or "snd" or "SYN"
    labeled_edges = 0
    for e in edges:
        lbl = e['label'].lower()
        if any(x in lbl for x in ['rcv', 'snd', 'syn', 'ack', 'fin', 'close']):
            labeled_edges += 1
            
    if labeled_edges >= 6:
        score += 10
    else:
        feedback.append("Transitions missing descriptive labels.")

    # 6. Error Removal (10 pts)
    # Check for direct edge from ESTABLISHED to CLOSED
    # We need to look up IDs from labels
    estab_ids = [nid for nid, lbl in node_map.items() if lbl == "ESTABLISHED"]
    closed_ids = [nid for nid, lbl in node_map.items() if lbl == "CLOSED"]
    
    error_found = False
    for e in edges:
        if e['source'] in estab_ids and e['target'] in closed_ids:
            error_found = True
            break
            
    if not error_found:
        score += 10
        feedback.append("Erroneous ESTABLISHED->CLOSED link removed.")
    else:
        feedback.append("FAIL: Erroneous ESTABLISHED->CLOSED link still exists.")

    # 7. Simultaneous Open (5 pts)
    # Edge from SYN_SENT to SYN_RCVD
    syn_sent_ids = [nid for nid, lbl in node_map.items() if lbl == "SYN_SENT"]
    syn_rcvd_ids = [nid for nid, lbl in node_map.items() if lbl == "SYN_RCVD"]
    
    sim_open_found = False
    for e in edges:
        if e['source'] in syn_sent_ids and e['target'] in syn_rcvd_ids:
            sim_open_found = True
            break
            
    if sim_open_found:
        score += 5
    else:
        feedback.append("Missing Simultaneous Open transition.")

    # 8. PNG Export (10 pts)
    if result.get('export_exists') and result.get('export_size', 0) > 1000:
        score += 10
    else:
        feedback.append("PNG export missing or empty.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }