#!/usr/bin/env python3
"""
Verifier for create_uml_deployment_diagram task.
Checks for correct file creation, content labels in EDDX, and VLM visual verification.
"""

import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_uml_deployment_diagram(traj, env_info, task_info):
    """
    Verify creation of UML deployment diagram.
    
    Scoring Breakdown (100 pts):
    - 20 pts: EDDX file exists, created during task, valid format.
    - 10 pts: PNG export exists, created during task.
    - 20 pts: Required Node labels found in EDDX text.
    - 20 pts: Required Artifact labels found in EDDX text.
    - 15 pts: Required Protocol labels found in EDDX text.
    - 15 pts: VLM visual verification of layout and notation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_nodes = metadata.get('required_nodes', [])
    required_artifacts = metadata.get('required_artifacts', [])
    required_protocols = metadata.get('required_protocols', [])

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify EDDX File (20 pts)
    eddx_exists = result.get('eddx_exists', False)
    eddx_created = result.get('eddx_created_during_task', False)
    eddx_size = result.get('eddx_size_bytes', 0)

    # Retrieve actual EDDX file for content analysis
    eddx_content_valid = False
    eddx_text_content = ""
    
    if eddx_exists and eddx_created and eddx_size > 1000: # Min 1KB
        score += 10
        feedback_parts.append("EDDX file created")
        
        # Download and verify zip integrity
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Diagrams/wms_deployment_diagram.eddx", temp_eddx.name)
            
            if zipfile.is_zipfile(temp_eddx.name):
                score += 10
                feedback_parts.append("Valid EDDX format")
                eddx_content_valid = True
                
                # Extract text content from all XML files in archive
                with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                    for filename in zf.namelist():
                        if filename.endswith('.xml'):
                            try:
                                eddx_text_content += zf.read(filename).decode('utf-8', errors='ignore')
                            except:
                                pass
            else:
                feedback_parts.append("EDDX file is not a valid zip archive")
        except Exception as e:
            feedback_parts.append(f"Failed to analyze EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)
    else:
        feedback_parts.append("EDDX file missing, too small, or pre-existing")

    # 3. Verify PNG File (10 pts)
    png_exists = result.get('png_exists', False)
    png_created = result.get('png_created_during_task', False)
    png_size = result.get('png_size_bytes', 0)
    
    if png_exists and png_created and png_size > 10000: # Min 10KB
        score += 10
        feedback_parts.append("PNG export created")
    else:
        feedback_parts.append("PNG export missing or invalid")

    # 4. Content Verification (55 pts total)
    if eddx_content_valid:
        # Check Nodes (20 pts)
        nodes_found = 0
        for node in required_nodes:
            if node in eddx_text_content:
                nodes_found += 1
        
        if len(required_nodes) > 0:
            node_score = int((nodes_found / len(required_nodes)) * 20)
            score += node_score
            feedback_parts.append(f"Found {nodes_found}/{len(required_nodes)} nodes")

        # Check Artifacts (20 pts)
        artifacts_found = 0
        for artifact in required_artifacts:
            if artifact in eddx_text_content:
                artifacts_found += 1
        
        if len(required_artifacts) > 0:
            artifact_score = int((artifacts_found / len(required_artifacts)) * 20)
            score += artifact_score
            feedback_parts.append(f"Found {artifacts_found}/{len(required_artifacts)} artifacts")

        # Check Protocols (15 pts)
        protocols_found = 0
        for proto in required_protocols:
            if proto in eddx_text_content:
                protocols_found += 1
        
        if len(required_protocols) > 0:
            proto_score = int((protocols_found / len(required_protocols)) * 15)
            score += proto_score
            feedback_parts.append(f"Found {protocols_found}/{len(required_protocols)} protocols")

    # 5. VLM Visual Verification (15 pts)
    # Using trajectory frames to prove work was done + final state
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames and final:
        vlm_images = frames + [final]
        prompt = """
        You are evaluating an agent creating a UML Deployment Diagram in EdrawMax.
        
        Review the sequence of images. The final goal is a diagram showing server nodes (3D boxes) connected by lines.
        
        Check for:
        1. **Deployment Notation**: Are there 3D box shapes representing servers/devices?
        2. **Connections**: Are there lines connecting these boxes?
        3. **Labels**: Can you see text inside or near the boxes (e.g., "Web Server", "Database")?
        4. **Progress**: Do the images show the diagram being built over time?
        
        Return JSON:
        {
            "has_3d_nodes": boolean,
            "has_connections": boolean,
            "text_visible": boolean,
            "shows_progress": boolean,
            "diagram_quality_score_0_to_10": int
        }
        """
        
        try:
            vlm_res = query_vlm(images=vlm_images, prompt=prompt)
            if vlm_res and 'parsed' in vlm_res:
                parsed = vlm_res['parsed']
                vlm_score = 0
                if parsed.get('has_3d_nodes'): vlm_score += 4
                if parsed.get('has_connections'): vlm_score += 4
                if parsed.get('text_visible'): vlm_score += 3
                if parsed.get('shows_progress'): vlm_score += 4
                
                score += vlm_score
                feedback_parts.append(f"VLM verification: {vlm_score}/15 pts")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: give partial credit if files are good
            if score > 50:
                score += 10
                feedback_parts.append("VLM skipped (error), +10 fallback")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }