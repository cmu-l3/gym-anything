#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_construction_pert_chart(traj, env_info, task_info):
    """
    Verifies the PERT chart task.
    Criteria:
    1. Files exist (10 pts)
    2. All 10 nodes created (20 pts)
    3. Topology: Critical Path edges exist (20 pts)
    4. Topology: Other edges exist (10 pts)
    5. Styling: Critical path edges are RED and THICK (30 pts)
    6. Styling: Non-critical edges are NOT highlighted (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Check (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 5
        feedback.append("Draw.io file saved.")
    else:
        feedback.append("Draw.io file not found or not modified.")
    
    if result.get('png_exists'):
        score += 5
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    # Graph Analysis Data
    graph = result.get('graph_data', {})
    nodes = graph.get('nodes', [])
    edges = graph.get('edges', [])
    
    # Required Node Names (partial matching)
    required_tasks = [
        "Demolition", "Structural", "Plumbing", "Electrical",
        "HVAC", "Drywall", "Painting", "Flooring", "Fixtures", "Cleanup"
    ]
    
    found_nodes = 0
    for req in required_tasks:
        if any(req.lower() in n.lower() for n in nodes):
            found_nodes += 1
    
    # 2. Node Count (20 pts)
    node_score = 0
    if found_nodes >= 10:
        node_score = 20
    elif found_nodes >= 5:
        node_score = 10
    score += node_score
    feedback.append(f"Found {found_nodes}/10 required task nodes.")

    # Define Critical Path connections (Source -> Target keywords)
    critical_path_pairs = [
        ("Demolition", "Structural"),
        ("Structural", "HVAC"),
        ("HVAC", "Drywall"),
        ("Drywall", "Painting"),
        ("Painting", "Flooring"),
        ("Flooring", "Cleanup")
    ]

    # Helper to check if an edge connects A -> B
    def find_edge(src_key, tgt_key, edge_list):
        for e in edge_list:
            s = e.get('source_name', '')
            t = e.get('target_name', '')
            if src_key.lower() in s.lower() and tgt_key.lower() in t.lower():
                return e
        return None

    # 3. Critical Path Topology (20 pts)
    cp_edges_found = 0
    cp_edges_highlighted = 0
    
    for src, tgt in critical_path_pairs:
        edge = find_edge(src, tgt, edges)
        if edge:
            cp_edges_found += 1
            # Check styling (Red AND Thick)
            if edge.get('is_highlighted'):
                cp_edges_highlighted += 1
            elif edge.get('is_red'):
                # Partial credit for just red
                cp_edges_highlighted += 0.5
    
    if cp_edges_found == len(critical_path_pairs):
        score += 20
        feedback.append("Critical path topology complete.")
    elif cp_edges_found >= 3:
        score += 10
        feedback.append(f"Critical path partial ({cp_edges_found}/{len(critical_path_pairs)} edges).")
    else:
        feedback.append("Critical path topology missing/broken.")

    # 4. Other Topology (10 pts)
    # Check a few non-critical connections
    # Demolition -> Plumbing, Demolition -> Electrical
    # Plumbing -> Drywall, Electrical -> Drywall
    # Painting -> Fixtures, Fixtures -> Cleanup
    non_critical_checks = [
        ("Demolition", "Plumbing"),
        ("Plumbing", "Drywall"),
        ("Painting", "Fixtures")
    ]
    nc_found = 0
    for src, tgt in non_critical_checks:
        if find_edge(src, tgt, edges):
            nc_found += 1
    
    if nc_found >= 2:
        score += 10
        feedback.append("Non-critical dependencies found.")
    
    # 5. Critical Path Highlighting (30 pts)
    # Scaled by how many critical edges were highlighted
    if cp_edges_found > 0:
        highlight_ratio = cp_edges_highlighted / cp_edges_found
        highlight_score = int(30 * highlight_ratio)
        score += highlight_score
        feedback.append(f"Critical path highlighting score: {highlight_score}/30")
    
    # 6. Non-Critical Styling (10 pts)
    # Verify non-critical edges are NOT highlighted
    # Find edges that are NOT in the critical path list
    bad_highlight = False
    for e in edges:
        s = e.get('source_name', '')
        t = e.get('target_name', '')
        
        is_cp = False
        for cp_s, cp_t in critical_path_pairs:
            if cp_s.lower() in s.lower() and cp_t.lower() in t.lower():
                is_cp = True
                break
        
        if not is_cp and e.get('is_highlighted'):
            bad_highlight = True
            break
            
    if not bad_highlight and len(edges) > 0:
        score += 10
        feedback.append("Non-critical edges correctly unformatted.")
    elif bad_highlight:
        feedback.append("Penalty: Non-critical edges were incorrectly highlighted.")

    # Final Check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }