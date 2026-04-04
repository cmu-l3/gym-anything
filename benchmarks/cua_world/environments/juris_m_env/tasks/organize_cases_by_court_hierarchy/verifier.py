#!/usr/bin/env python3
"""
Verifier for organize_cases_by_court_hierarchy task.

Logic:
1. Reconstruct collection tree from flat list.
2. Verify specific paths exist (e.g. Case Law -> Federal Courts -> Supreme Court).
3. Verify specific items are in specific leaf collections.
4. Verify negative constraints (items NOT in wrong collections).
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_cases_by_court_hierarchy(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    collections = result.get('collections', [])
    items = result.get('items', [])
    
    # 2. Build Tree Helper
    # Map ID -> {name, children[], parent_id}
    col_map = {c['id']: {'name': c['name'], 'children': [], 'id': c['id'], 'parent_id': c['parent_id']} for c in collections}
    
    # Populate children
    roots = []
    for cid, node in col_map.items():
        pid = node['parent_id']
        if pid is not None and pid in col_map:
            col_map[pid]['children'].append(node)
        else:
            roots.append(node)

    def find_node(start_nodes, path_names):
        """Recursively find a node by name path."""
        if not path_names:
            return start_nodes # Should not happen with valid call
        
        current_name = path_names[0]
        for node in start_nodes:
            if node['name'].strip() == current_name:
                if len(path_names) == 1:
                    return node
                return find_node(node['children'], path_names[1:])
        return None

    score = 0
    feedback = []

    # 3. Verify Hierarchy Structure (25 points)
    # Required paths:
    # Case Law
    # Case Law -> Federal Courts
    # Case Law -> State Courts
    # Case Law -> Federal Courts -> Supreme Court
    # Case Law -> Federal Courts -> Courts of Appeals
    # Case Law -> State Courts -> New York
    
    required_paths = [
        ["Case Law"],
        ["Case Law", "Federal Courts"],
        ["Case Law", "State Courts"],
        ["Case Law", "Federal Courts", "Supreme Court"],
        ["Case Law", "Federal Courts", "Courts of Appeals"],
        ["Case Law", "State Courts", "New York"]
    ]
    
    hierarchy_score = 0
    missing_paths = []
    
    # Map path string to node ID for item verification later
    path_ids = {}

    for path in required_paths:
        node = find_node(roots, path)
        if node:
            hierarchy_score += 1
            path_ids["/".join(path)] = node['id']
        else:
            missing_paths.append(" > ".join(path))

    # Scale 6 paths to 25 points (~4.16 pts each)
    score += int((hierarchy_score / 6) * 25)
    
    if missing_paths:
        feedback.append(f"Missing collections: {', '.join(missing_paths)}")
    else:
        feedback.append("Collection hierarchy created correctly (+25)")

    # 4. Verify Item Placements
    # Helper to check if item (by name substring) is in collection ID
    def check_item(name_part, col_id):
        if col_id is None: return False
        for item in items:
            if item['collection_id'] == col_id and name_part.lower() in item['case_name'].lower():
                return True
        return False

    # Get IDs for leaf nodes
    id_sc = path_ids.get("Case Law/Federal Courts/Supreme Court")
    id_app = path_ids.get("Case Law/Federal Courts/Courts of Appeals")
    id_ny = path_ids.get("Case Law/State Courts/New York")
    id_fed = path_ids.get("Case Law/Federal Courts") # For negative check

    # SC Cases (15 pts) - 5 pts each
    sc_cases = ["Brown", "Miranda", "Gideon"]
    sc_hits = 0
    for case in sc_cases:
        if check_item(case, id_sc):
            sc_hits += 1
    
    score += sc_hits * 5
    if sc_hits == 3:
        feedback.append("All Supreme Court cases sorted correctly (+15)")
    else:
        feedback.append(f"Sorted {sc_hits}/3 Supreme Court cases correctly")

    # Alcoa (20 pts)
    if check_item("Aluminum", id_app):
        score += 20
        feedback.append("Alcoa case sorted correctly (+20)")
    else:
        feedback.append("Alcoa case NOT found in 'Courts of Appeals'")

    # Palsgraf (20 pts)
    if check_item("Palsgraf", id_ny):
        score += 20
        feedback.append("Palsgraf case sorted correctly (+20)")
    else:
        feedback.append("Palsgraf case NOT found in 'New York'")

    # 5. Separation Checks (20 pts)
    # Alcoa should NOT be in Supreme Court
    # Palsgraf should NOT be in Federal Courts (or children of Federal)
    
    sep_fail = False
    
    if check_item("Aluminum", id_sc):
        feedback.append("FAIL: Alcoa incorrectly placed in Supreme Court")
        sep_fail = True
        
    # Check Palsgraf in Federal tree
    # Recursive check for item in node or children
    def is_in_tree(name_part, node):
        if check_item(name_part, node['id']):
            return True
        for child in node['children']:
            if is_in_tree(name_part, child):
                return True
        return False

    fed_node = find_node(roots, ["Case Law", "Federal Courts"])
    if fed_node and is_in_tree("Palsgraf", fed_node):
        feedback.append("FAIL: Palsgraf incorrectly placed in Federal Courts hierarchy")
        sep_fail = True

    if not sep_fail:
        score += 20
        feedback.append("Jurisdiction separation checks passed (+20)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "hierarchy_score": hierarchy_score,
            "sc_hits": sc_hits,
            "missing_paths": missing_paths
        }
    }