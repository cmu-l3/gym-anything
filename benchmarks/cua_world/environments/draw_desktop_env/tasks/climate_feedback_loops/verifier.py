#!/usr/bin/env python3
"""
Verifier for climate_feedback_loops task.

Scoring (100 points):
- File saved & valid (10 pts)
- Central Node "Temperature" identified (10 pts)
- Loop 1 (Ice/Albedo) detected (20 pts)
- Loop 2 (Permafrost) detected (20 pts)
- Loop 3 (Water Vapor) detected (20 pts)
- Polarity labels (+/-) present (10 pts)
- PNG exported (10 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import re

def verify_climate_feedback_loops(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Read basic result
    result_data = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Read error: {e}"}
    finally:
        if os.path.exists(temp_res.name): os.unlink(temp_res.name)

    # 2. Read graph structure
    graph_data = {}
    temp_graph = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/graph_structure.json", temp_graph.name)
        with open(temp_graph.name, 'r') as f:
            graph_data = json.load(f)
    except Exception:
        pass # Graph might be empty if file missing
    finally:
        if os.path.exists(temp_graph.name): os.unlink(temp_graph.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Checks (10 pts) ---
    if result_data.get('file_exists') and result_data.get('file_modified'):
        score += 10
        feedback.append("File saved")
    else:
        feedback.append("File missing/unmodified")
        return {"passed": False, "score": 0, "feedback": "No file saved"}

    # Build simple graph for analysis
    nodes = {n['id']: n['text'].lower() for n in graph_data.get('nodes', [])}
    adj = {nid: [] for nid in nodes}
    for e in graph_data.get('edges', []):
        s, t = e['source'], e['target']
        if s in adj and t in adj:
            adj[s].append(t)

    # Helper to find text in node values
    def find_node_id(keyword):
        for nid, text in nodes.items():
            if keyword in text:
                return nid
        return None

    # --- Criterion 2: Central Node (10 pts) ---
    temp_node = find_node_id("temperature") or find_node_id("temp")
    if temp_node:
        score += 10
        feedback.append("Central 'Temperature' node found")
    else:
        feedback.append("Missing 'Temperature' node")

    # --- Criteria 3-5: Loops (60 pts) ---
    # We look for cycles containing specific keywords
    
    def check_cycle(keywords):
        # 1. Find candidate nodes for each keyword
        candidates = []
        for kw in keywords:
            matches = [nid for nid, text in nodes.items() if kw in text]
            if not matches: return False
            candidates.append(matches)
        
        # 2. Check if a path exists: node0 -> ... -> node1 -> ... -> node0
        # Simple DFS for cycle
        # We simplify: check if we can traverse from Keywords[i] to Keywords[i+1]
        
        def has_path(start_ids, end_ids, max_depth=3):
            stack = [(s, 0) for s in start_ids]
            visited = set()
            while stack:
                curr, depth = stack.pop()
                if curr in end_ids: return True
                if depth >= max_depth: continue
                if curr in visited: continue
                visited.add(curr)
                for neighbor in adj.get(curr, []):
                    stack.append((neighbor, depth + 1))
            return False

        # Check full loop sequence
        # We allow flexible ordering, just checking connectivity between key concepts
        # Cycle: A -> B -> C -> A
        if not has_path(candidates[0], candidates[1]): return False
        if len(keywords) > 2:
            if not has_path(candidates[1], candidates[2]): return False
            if not has_path(candidates[2], candidates[0]): return False
        else:
            if not has_path(candidates[1], candidates[0]): return False
        return True

    # Loop 1: Ice-Albedo (Temp -> Ice -> Albedo -> Temp)
    if check_cycle(["temp", "ice"]): # Minimal check
        # Stronger check
        if check_cycle(["ice", "albedo", "temp"]):
            score += 20
            feedback.append("Ice-Albedo loop detected")
        else:
            score += 10
            feedback.append("Ice-Albedo loop incomplete (connectivity issues)")
    else:
        feedback.append("Ice-Albedo loop missing")

    # Loop 2: Permafrost (Temp -> Permafrost -> Greenhouse -> Temp)
    if check_cycle(["temp", "permafrost"]):
        if check_cycle(["permafrost", "greenhouse", "temp"]) or check_cycle(["permafrost", "co2", "temp"]):
            score += 20
            feedback.append("Permafrost loop detected")
        else:
            score += 10
            feedback.append("Permafrost loop incomplete")
    else:
        feedback.append("Permafrost loop missing")

    # Loop 3: Water Vapor (Temp -> Vapor -> Greenhouse -> Temp)
    if check_cycle(["temp", "vapor"]):
        if check_cycle(["vapor", "greenhouse", "temp"]) or check_cycle(["vapor", "evaporation", "temp"]):
            score += 20
            feedback.append("Water Vapor loop detected")
        else:
            score += 10
            feedback.append("Water Vapor loop incomplete")
    else:
        feedback.append("Water Vapor loop missing")

    # --- Criterion 6: Polarity Labels (10 pts) ---
    all_text = graph_data.get('text_content', '')
    # Check for + or - labels, or "plus"/"minus", "pos"/"neg"
    has_plus = '+' in all_text or 'plus' in all_text.lower() or 'same' in all_text.lower()
    has_minus = '-' in all_text or 'minus' in all_text.lower() or 'opposite' in all_text.lower()
    
    if has_plus and has_minus:
        score += 10
        feedback.append("Polarity labels found")
    else:
        feedback.append("Missing polarity labels (+/-)")

    # --- Criterion 7: PNG Export (10 pts) ---
    if result_data.get('png_exists') and result_data.get('png_size', 0) > 1000:
        score += 10
        feedback.append("PNG export verified")
    else:
        feedback.append("PNG export missing/empty")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }