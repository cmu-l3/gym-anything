#!/usr/bin/env python3
"""Verifier for organize_working_sets task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging
import sys

# Add local utils to path if needed, though mostly using standard libs
sys.path.append('/workspace/utils')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_working_sets(traj, env_info, task_info):
    """Verify that the working set was created and view configured.
    
    Criteria:
    1. workingsets.xml exists and was modified (10 pts)
    2. Working Set 'ActiveDoseDev' exists in the XML (30 pts)
    3. The set contains exactly the 3 required projects (30 pts)
    4. VLM: Package Explorer shows Working Sets grouping (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_workingset_name', 'ActiveDoseDev')
    required_projects = set(metadata.get('required_projects', []))
    excluded_projects = set(metadata.get('excluded_projects', []))

    score = 0
    feedback_parts = []
    
    # --- Step 1: Analyze workingsets.xml ---
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    xml_content = result_data.get('xml_content', '')
    
    if not xml_content:
        feedback_parts.append("No working set configuration found (workingsets.xml empty or missing)")
    else:
        score += 10 # File exists
        
        # Parse XML
        # Structure is typically: <workingSetManager> <workingSet name="..."> <item path="/ProjName"/> ...
        try:
            root = ET.fromstring(xml_content)
            target_set_node = None
            
            # Find the specific working set
            for ws in root.findall('.//workingSet'):
                name = ws.get('name') or ws.get('label')
                if name == target_name:
                    target_set_node = ws
                    break
            
            if target_set_node is not None:
                score += 30
                feedback_parts.append(f"Working Set '{target_name}' found")
                
                # Check contents
                # Items usually look like <item path="/DoseEngine" .../> or element adapter
                # We look for the project names in the 'path' attribute or inner text
                contained_projects = set()
                
                for item in target_set_node.findall('.//item'):
                    path = item.get('path', '')
                    # path usually looks like "/DoseEngine"
                    for proj in required_projects | excluded_projects:
                        if f"/{proj}" == path or proj == path:
                            contained_projects.add(proj)
                
                # Verify exact match
                missing = required_projects - contained_projects
                extra = contained_projects.intersection(excluded_projects)
                
                if not missing and not extra:
                    score += 30
                    feedback_parts.append("Working Set contains exactly the required projects")
                else:
                    if missing:
                        feedback_parts.append(f"Missing projects: {', '.join(missing)}")
                    if extra:
                        feedback_parts.append(f"Incorrectly included: {', '.join(extra)}")
                    # Partial credit for mostly correct
                    if len(missing) < 2 and not extra:
                        score += 15
            else:
                feedback_parts.append(f"Working Set '{target_name}' NOT found in configuration")
                
        except ET.ParseError:
            feedback_parts.append("Error parsing workingsets.xml")

    # --- Step 2: VLM Verification of View State ---
    # We need to verify the user actually switched the view to "Working Sets" mode.
    # The XML only proves the set exists, not that the view is using it.
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Create a Working Set 'ActiveDoseDev' and configure Package Explorer to show Working Sets as top level elements.",
            checklist_items=[
                f"Package Explorer view is visible",
                f"A grouping/folder named '{target_name}' is visible in Package Explorer",
                "The view is NOT a flat list of 5 projects",
                "The projects DoseEngine, DoseUI, DoseTests are inside the group (if expanded)"
            ]
        )
        
        if vlm_result:
            vlm_score = vlm_result.get('vlm_score', 0)
            # Map VLM score (0-100) to our 30 points allocation
            score += int(vlm_score * 0.3)
            feedback_parts.append(f"Visual Verification: {vlm_result.get('vlm_feedback')}")
        else:
            feedback_parts.append("VLM verification unavailable")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        feedback_parts.append(f"Visual verification error: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }