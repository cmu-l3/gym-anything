#!/usr/bin/env python3
"""
Verifier for create_data_flow_diagram task.

Verification Strategy:
1. File Integrity (Programmatic):
   - Check if .eddx and .png files exist.
   - Verify timestamps (created *during* task).
   - Verify file sizes (non-empty/non-trivial).
   - Verify .eddx is a valid ZIP archive (EdrawMax format).

2. Content Verification (VLM on Exported PNG):
   - The agent is required to export a PNG. This is the best artifact for checking
     diagram content (readability, labels, connections).
   - VLM checks for: Central process, 4 entities, 8 specific data flow labels.

3. Process Verification (VLM on Trajectory):
   - Ensures the agent actually built the diagram rather than just copying a file.
   - Checks for workflow: Shape placement -> Text editing -> Connector drawing.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Required labels from task description
REQUIRED_LABELS = [
    "Online Order Processing System",
    "Customer", "Payment Gateway", "Inventory Database", "Shipping Provider",
    "Order Request", "Order Confirmation",
    "Payment Details", "Payment Status",
    "Stock Query", "Stock Availability",
    "Shipping Request", "Tracking Number"
]

def verify_create_data_flow_diagram(traj, env_info, task_info):
    """
    Verify the creation of the Data Flow Diagram.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_eddx = metadata.get('expected_eddx_path', '/home/ga/Diagrams/dfd_context_diagram.eddx')
    expected_png = metadata.get('expected_png_path', '/home/ga/Diagrams/dfd_context_diagram.png')
    
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. Retrieve Task Result Metadata
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # =========================================================
    # 2. Verify File Existence & Anti-Gaming (Timestamps)
    # =========================================================
    eddx_ok = task_result.get('eddx_exists') and task_result.get('eddx_created_during_task') and task_result.get('eddx_size_bytes', 0) > 10000
    png_ok = task_result.get('png_exists') and task_result.get('png_created_during_task') and task_result.get('png_size_bytes', 0) > 20000

    if eddx_ok:
        score += 15
        feedback_parts.append("Project file (.eddx) saved successfully.")
    else:
        feedback_parts.append("Project file (.eddx) missing, too small, or pre-existing.")

    if png_ok:
        score += 15
        feedback_parts.append("Exported image (.png) saved successfully.")
    else:
        feedback_parts.append("Exported image (.png) missing, too small, or pre-existing.")

    # Early exit if basic files are missing
    if not eddx_ok and not png_ok:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # =========================================================
    # 3. Retrieve PNG for Content Verification
    # =========================================================
    png_temp_path = None
    if png_ok:
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_png, temp_png.name)
            png_temp_path = temp_png.name
        except Exception as e:
            feedback_parts.append(f"Failed to retrieve PNG for verification: {e}")
            png_ok = False # Downgrade status if we can't inspect it

    # =========================================================
    # 4. VLM Content Verification (Using Exported PNG)
    # =========================================================
    content_score = 0
    vlm_content_feedback = ""
    
    if png_ok and png_temp_path:
        prompt = f"""
        Analyze this diagram image. It should be a Level 0 Data Flow Diagram (Context Diagram).
        
        Check for the following SPECIFIC elements:
        1. Central Process: A central shape labeled "Online Order Processing System".
        2. External Entities: 4 distinct shapes around the center labeled "Customer", "Payment Gateway", "Inventory Database", "Shipping Provider".
        3. Data Flows: Arrows connecting these entities to the center.
        4. Flow Labels: Look for text labels on arrows like "Order Request", "Payment Status", "Stock Availability", "Tracking Number".
        
        Provide a JSON response:
        {{
            "central_process_found": true/false,
            "entity_count": <number_found>,
            "entities_correct_labels": true/false,
            "data_flows_present": true/false,
            "flow_labels_readable": true/false,
            "diagram_readable": true/false
        }}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=png_temp_path)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                
                # Central Process (10 pts)
                if parsed.get('central_process_found'):
                    content_score += 10
                    
                # Entities (15 pts)
                e_count = parsed.get('entity_count', 0)
                if e_count >= 4 and parsed.get('entities_correct_labels'):
                    content_score += 15
                elif e_count >= 1:
                    content_score += 5 # Partial credit
                    
                # Data Flows & Labels (15 pts)
                if parsed.get('data_flows_present'):
                    content_score += 5
                if parsed.get('flow_labels_readable'):
                    content_score += 10
                    
                # Layout (5 pts)
                if parsed.get('diagram_readable'):
                    content_score += 5
                    
                vlm_content_feedback = "Diagram content verified."
            else:
                vlm_content_feedback = "VLM analysis of diagram failed."
        except Exception as e:
            logger.error(f"VLM Content check error: {e}")
            vlm_content_feedback = "VLM error during content check."
            
        score += content_score
        feedback_parts.append(vlm_content_feedback)
        
        # Cleanup temp PNG
        if os.path.exists(png_temp_path):
            os.unlink(png_temp_path)

    # =========================================================
    # 5. VLM Process Verification (Trajectory)
    # =========================================================
    # Ensure the agent actually built it, not just downloaded/opened a file
    
    frames = sample_trajectory_frames(traj, n=4)
    process_score = 0
    
    if frames:
        traj_prompt = """
        Review these screenshots of a user creating a diagram in EdrawMax.
        I need to verify that the user actually BUILT the diagram (added shapes, typed text, connected lines) 
        rather than just opening a finished file.
        
        Do you see evidence of:
        1. Empty canvas or template selection at the start?
        2. Dragging/dropping shapes or drawing connectors?
        3. Editing text (highlighted text, cursor)?
        4. Progressive construction (more elements appearing over time)?
        
        Reply JSON: {"construction_process_visible": true/false, "confidence": "high/medium/low"}
        """
        
        try:
            traj_res = query_vlm(prompt=traj_prompt, images=frames)
            if traj_res.get('success'):
                if traj_res.get('parsed', {}).get('construction_process_visible'):
                    process_score += 25
                    feedback_parts.append("Construction workflow confirmed.")
                else:
                    feedback_parts.append("No construction process visible in trajectory.")
        except Exception as e:
            logger.error(f"VLM Trajectory check error: {e}")
            
    score += process_score

    # =========================================================
    # Final Result
    # =========================================================
    # Total possible: 30 (files) + 45 (content) + 25 (process) = 100
    
    passed = score >= 60 and eddx_ok and png_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }