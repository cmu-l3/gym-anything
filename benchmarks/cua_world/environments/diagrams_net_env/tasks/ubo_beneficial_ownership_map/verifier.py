#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ubo_beneficial_ownership_map(traj, env_info, task_info):
    """
    Verifies the UBO Beneficial Ownership Map task.
    
    Criteria:
    1. File Modification (Anti-gaming): File updated after start.
    2. Entity Presence: Nodes for specific companies and people.
    3. Math Logic: Effective ownership percentages in labels.
    4. Visual Logic: Red color for UBOs, Green/Default for others.
    5. Export: PDF file exists.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    nodes_data = result.get('parsed_data', {}).get('nodes', [])
    file_modified = result.get('file_modified', False)
    pdf_exists = result.get('pdf_exists', False)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # A. File Activity (10 pts)
    if file_modified:
        score += 10
        feedback.append("File was modified.")
    else:
        feedback.append("File was NOT modified.")

    # B. Entity Presence (20 pts)
    # Looking for: Stratosphere, Terra Firma, Nebula, Elena, Marcus
    required_entities = ["Stratosphere", "Terra Firma", "Nebula", "Elena", "Marcus"]
    found_entities = []
    
    # Helper to clean labels (remove HTML, lowercase)
    def clean_label(val):
        if not val: return ""
        # Remove simple HTML tags
        val = val.replace("&nbsp;", " ").replace("<div>", "").replace("</div>", "").replace("<br>", " ")
        return val.lower()

    node_labels = [clean_label(n.get('value', '')) for n in nodes_data if n.get('vertex') == '1']
    
    for req in required_entities:
        if any(req.lower() in label for label in node_labels):
            found_entities.append(req)
            score += 4  # 5 entities * 4 pts = 20
    
    if len(found_entities) == 5:
        feedback.append("All required entities found.")
    else:
        feedback.append(f"Missing entities: {list(set(required_entities) - set(found_entities))}")

    # C. Connectivity (20 pts)
    # Check if we have edges connecting these nodes. 
    # Hard to map exact graph without IDs, so we count edges.
    # Expecting at least: Omni<-Strat, Omni<-Terra, Strat<-Elena, Strat<-Nebula, Terra<-Elena, Terra<-Marcus (6 edges)
    # Plus maybe Nebula<-Marcus.
    edge_count = sum(1 for n in nodes_data if n.get('edge') == '1')
    if edge_count >= 6:
        score += 20
        feedback.append(f"Connectivity looks good ({edge_count} edges).")
    elif edge_count >= 3:
        score += 10
        feedback.append(f"Partial connectivity ({edge_count} edges).")
    else:
        feedback.append("Diagram is poorly connected.")

    # D. Math & UBO Logic (30 pts)
    # Elena: ~38%, Marcus: ~62%
    # UBOs should be Red (fillColor=#F8CECC or similar red-ish hex)
    
    elena_correct = False
    marcus_correct = False
    
    # Red hex codes often used in draw.io
    red_codes = ["#f8cecc", "#ff0000", "#ff3333", "red"]
    
    for n in nodes_data:
        val = clean_label(n.get('value', ''))
        style = n.get('style', '').lower()
        
        # Check Elena
        if "elena" in val:
            # Check Math (38%)
            if "38" in val:
                score += 7.5
                feedback.append("Elena R. calculation correct.")
            # Check Color (Red)
            if any(code in style for code in red_codes):
                score += 7.5
                feedback.append("Elena R. marked as UBO (Red).")
        
        # Check Marcus
        if "marcus" in val:
            # Check Math (62%)
            if "62" in val:
                score += 7.5
                feedback.append("Marcus T. calculation correct.")
            # Check Color (Red)
            if any(code in style for code in red_codes):
                score += 7.5
                feedback.append("Marcus T. marked as UBO (Red).")

    # E. PDF Export (20 pts)
    if pdf_exists:
        score += 20
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing.")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }