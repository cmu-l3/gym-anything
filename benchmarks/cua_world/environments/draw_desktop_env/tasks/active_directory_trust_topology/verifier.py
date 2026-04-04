#!/usr/bin/env python3
"""
Verifier for Active Directory Trust Topology task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_label(label):
    """Normalize domain labels for comparison (remove HTML, lowercase)."""
    if not label: return ""
    # Simple HTML tag stripping
    import re
    clean = re.sub(r'<[^>]+>', '', label)
    return clean.strip().lower()

def verify_ad_topology(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Artifacts (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 5
        feedback.append("Draw.io file saved.")
    else:
        feedback.append("Draw.io file missing or not saved.")
        
    if result.get("png_exists"):
        score += 5
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    # Stop if no file to analyze
    if not result.get("file_exists"):
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    analysis = result.get("analysis", {})
    nodes = analysis.get("nodes", [])
    edges = analysis.get("edges", [])
    
    # Create a lookup for Node ID -> Label
    id_to_label = {n["id"]: normalize_label(n["label"]) for n in nodes}
    
    # 2. Domain Identification (25 pts)
    expected_domains = [
        "contoso.com", "corp.contoso.com", "research.contoso.com",
        "fabrikam.net", "legacy.fabrikam.net"
    ]
    found_domains = []
    
    for d in expected_domains:
        # Check if any node label contains the domain name
        match = any(d in lbl for lbl in id_to_label.values())
        if match:
            found_domains.append(d)
    
    domain_score = len(found_domains) * 5
    score += domain_score
    feedback.append(f"Found {len(found_domains)}/5 domains.")

    # 3. Shape Correctness (Triangles) (5 pts)
    # Just check if we detected triangle styles
    if analysis.get("triangle_shapes", 0) >= 3:
        score += 5
        feedback.append("Used triangle shapes.")

    # 4. Forest Grouping (15 pts)
    # Check for visual containers
    if analysis.get("forest_count", 0) >= 2:
        score += 15
        feedback.append("Forests visually grouped.")
    elif analysis.get("forest_count", 0) == 1:
        score += 5
        feedback.append("Partial grouping found.")

    # 5. Trust Relationships (45 pts)
    # We analyze the edges to find specific connections
    
    # Helper to check connection
    def check_connection(node_a, node_b, directed=False):
        """
        Returns:
        0: No connection
        1: Connection exists (undirected/wrong direction)
        2: Connection exists (correct direction if specified)
        """
        for e in edges:
            src_lbl = id_to_label.get(e["source"], "")
            tgt_lbl = id_to_label.get(e["target"], "")
            
            # Check A -> B
            if node_a in src_lbl and node_b in tgt_lbl:
                return 2 if directed else 2
                
            # Check B -> A
            if node_b in src_lbl and node_a in tgt_lbl:
                return 0 if directed else 2 # For directed, this is wrong direction
                
        # If directed, check if an undirected/bidirectional link exists as fallback
        if directed:
            for e in edges:
                src_lbl = id_to_label.get(e["source"], "")
                tgt_lbl = id_to_label.get(e["target"], "")
                if (node_a in src_lbl and node_b in tgt_lbl) or (node_b in src_lbl and node_a in tgt_lbl):
                    return 1
        return 0

    # A. Forest Trust (15 pts) - contoso.com <-> fabrikam.net
    ft_status = check_connection("contoso.com", "fabrikam.net")
    if ft_status == 2:
        score += 15
        feedback.append("Forest Trust correct.")
    else:
        feedback.append("Forest Trust missing.")

    # B. External Trust (20 pts) - corp.contoso.com -> legacy.fabrikam.net
    # Strict direction check
    et_status = check_connection("corp.contoso.com", "legacy.fabrikam.net", directed=True)
    if et_status == 2:
        score += 20
        feedback.append("External Trust correct (with direction).")
    elif et_status == 1:
        score += 10
        feedback.append("External Trust connected but direction ambiguous/wrong.")
    else:
        feedback.append("External Trust missing.")

    # C. Parent-Child Trusts (10 pts) - Generic check
    # Check for at least one root-child connection
    pc_connected = False
    if check_connection("contoso.com", "corp.contoso.com") or check_connection("fabrikam.net", "legacy.fabrikam.net"):
        pc_connected = True
    
    if pc_connected:
        score += 10
        feedback.append("Parent-Child hierarchy linked.")

    # Final tally
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }