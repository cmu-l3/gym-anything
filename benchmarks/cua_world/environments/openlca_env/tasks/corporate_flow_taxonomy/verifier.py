#!/usr/bin/env python3
"""
Verifier for Corporate Flow Taxonomy task.

Criteria:
1. Database 'ChemCorp_LCA' exists and was created during task.
2. Contains >= 5 Elementary Flows.
3. Contains >= 3 Product Flows.
4. Contains specific named flows (exact or robust partial match).
5. Category structure exists.
6. Flows are linked to flow properties (Mass).

Scoring:
- DB exists & valid: 15 pts
- Elementary Flows count: 15 pts
- Product Flows count: 10 pts
- Specific Flow Names (8 flows * 5 pts): 40 pts
- Categories exist: 8 pts
- Flow properties linked: 7 pts
- VLM Trajectory: 5 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

# VLM Prompt for trajectory verification
TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent using openLCA.

The task is to create a new database 'ChemCorp_LCA', create categories (e.g., 'Air emissions', 'Intermediates'), and define new flows.

Look for:
1. DATABASE_CREATION: A dialog for creating a new database or 'ChemCorp_LCA' appearing in the navigation tree.
2. CATEGORY_CREATION: The agent right-clicking to create categories or using the category dialog.
3. FLOW_CREATION: The flow editor open, typing names like 'Catalyst residue' or 'Palladium catalyst'.
4. NAVIGATION_TREE: The tree showing the new structure.

Return JSON:
{
  "database_created": true/false,
  "flow_editor_seen": true/false,
  "categories_visible": true/false,
  "meaningful_progression": true/false,
  "confidence": "low"/"medium"/"high"
}"""


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None


def verify_corporate_flow_taxonomy(traj, env_info, task_info):
    """Verify the Corporate Flow Taxonomy task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Retrieve Result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # 2. Verify Database Existence (15 pts)
    # Anti-gaming: Must be created during task
    db_exists = result.get('db_exists', False)
    db_fresh = result.get('db_created_during_task', False)
    
    if db_exists and db_fresh:
        score += 15
        feedback.append("New database 'ChemCorp_LCA' created successfully.")
    elif db_exists:
        score += 5
        feedback.append("Database exists but timestamp suggests pre-existence or generic creation.")
    else:
        feedback.append("Database 'ChemCorp_LCA' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 3. Verify Flow Counts (25 pts total)
    elem_count = result.get('elem_flow_count', 0)
    prod_count = result.get('prod_flow_count', 0)
    
    if elem_count >= 5:
        score += 15
        feedback.append(f"Elementary flows count ({elem_count}) met requirement.")
    elif elem_count > 0:
        score += int(15 * (elem_count / 5))
        feedback.append(f"Partial elementary flows: {elem_count}/5.")
    
    if prod_count >= 3:
        score += 10
        feedback.append(f"Product flows count ({prod_count}) met requirement.")
    elif prod_count > 0:
        score += int(10 * (prod_count / 3))
        feedback.append(f"Partial product flows: {prod_count}/3.")

    # 4. Verify Specific Flow Names (40 pts)
    flow_checks = result.get('flow_checks', {})
    flows_found = 0
    for name, found in flow_checks.items():
        if found:
            score += 5
            flows_found += 1
    
    if flows_found == 8:
        feedback.append("All 8 specific flows found.")
    else:
        feedback.append(f"Found {flows_found}/8 specific named flows.")

    # 5. Verify Categories (8 pts)
    cat_checks = result.get('category_checks', {})
    cats_found = sum(1 for v in cat_checks.values() if v)
    
    if cats_found >= 4:
        score += 8
        feedback.append("Category hierarchy verified.")
    else:
        score += int(8 * (cats_found / 4))
        feedback.append(f"Categories found: {cats_found}/4.")

    # 6. Verify Flow Property Links (7 pts)
    # Checks if flows are actually usable (linked to Mass)
    prop_links = result.get('flow_prop_link_count', 0)
    total_flows = elem_count + prod_count
    
    if total_flows > 0 and prop_links >= total_flows:
        score += 7
        feedback.append("Flows properly linked to flow properties.")
    elif prop_links > 0:
        score += 3
        feedback.append("Some flows missing property links.")

    # 7. VLM Verification (5 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if vlm_res:
            if vlm_res.get('database_created') or vlm_res.get('flow_editor_seen'):
                score += 5
                feedback.append("Visual verification passed.")

    # 8. Final Assessment
    # Pass threshold: 60 pts + DB existence + at least 5 correct flows
    passed = score >= 60 and db_fresh and flows_found >= 5
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback),
        "details": result
    }