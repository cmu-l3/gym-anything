#!/usr/bin/env python3
"""
Verifier for create_concept_map task.

Verification Strategy:
1. File Existence & Timestamps (20 pts): Checks .eddx and .png were created during task.
2. File Properties (10 pts): Checks file sizes and image dimensions to ensure non-trivial content.
3. Content Verification (Text Extraction) (30 pts): Unzips .eddx (XML) to check for specific concept keywords.
4. Visual Verification (VLM) (40 pts): Analyzes the exported PNG to verify diagram structure, connectivity, and layout.
"""

import json
import os
import tempfile
import zipfile
import logging
import re
# Assuming gym_anything.vlm provides these utilities
try:
    from gym_anything.vlm import query_vlm
except ImportError:
    # Mock for testing if environment not available
    def query_vlm(prompt, image):
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_concept_map(traj, env_info, task_info):
    """
    Verify that the concept map was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_nodes = metadata.get('required_nodes', [])
    required_relationships = metadata.get('required_relationships', [])

    score = 0
    feedback_parts = []
    
    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 1. File Existence & Timestamp Checks (20 pts)
    # ================================================================
    eddx_exists = result.get('eddx_exists', False)
    eddx_fresh = result.get('eddx_created_during_task', False)
    png_exists = result.get('png_exists', False)
    png_fresh = result.get('png_created_during_task', False)

    if eddx_exists and eddx_fresh:
        score += 10
        feedback_parts.append("EDDX file created successfully.")
    elif eddx_exists:
        score += 5
        feedback_parts.append("EDDX file exists but has old timestamp.")
    else:
        feedback_parts.append("EDDX file missing.")

    if png_exists and png_fresh:
        score += 10
        feedback_parts.append("PNG export created successfully.")
    elif png_exists:
        score += 5
        feedback_parts.append("PNG export exists but has old timestamp.")
    else:
        feedback_parts.append("PNG export missing.")

    # ================================================================
    # 2. File Properties Checks (10 pts)
    # ================================================================
    eddx_size = result.get('eddx_size_bytes', 0)
    png_size = result.get('png_size_bytes', 0)
    png_w = result.get('png_width', 0)
    png_h = result.get('png_height', 0)

    # A valid diagram file with 9 nodes and connectors should be > 5KB
    if eddx_size > 5000:
        score += 5
    
    # A readable export should have decent resolution
    if png_size > 10000 and png_w >= 400 and png_h >= 300:
        score += 5
    else:
        feedback_parts.append("Exported image too small or low resolution.")

    # ================================================================
    # 3. Content Verification via Text Extraction (30 pts)
    # ================================================================
    # We copy the .eddx file (which is a zip) and grep the XML content
    eddx_content_score = 0
    
    if eddx_exists:
        temp_eddx = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
        try:
            copy_from_env("/home/ga/Documents/ehr_concept_map.eddx", temp_eddx.name)
            
            with zipfile.ZipFile(temp_eddx.name, 'r') as zf:
                # EdrawMax stores data in .xml or .json files inside the zip
                all_text = ""
                for filename in zf.namelist():
                    if filename.endswith('.xml') or filename.endswith('.json'):
                        try:
                            content = zf.read(filename).decode('utf-8', errors='ignore')
                            all_text += content
                        except:
                            pass
                
                # Check for required nodes
                found_nodes = 0
                for node in required_nodes:
                    # Simple case-insensitive check
                    if re.search(re.escape(node), all_text, re.IGNORECASE):
                        found_nodes += 1
                
                # Check for required relationships
                found_rels = 0
                for rel in required_relationships:
                    if re.search(re.escape(rel), all_text, re.IGNORECASE):
                        found_rels += 1

                # Scoring logic for content
                # 9 nodes * 2 pts approx = 18 pts
                # 9 rels * 1.3 pts approx = 12 pts
                
                node_score = min(18, found_nodes * 2)
                rel_score = min(12, int(found_rels * 1.34))
                
                eddx_content_score = node_score + rel_score
                score += eddx_content_score
                
                feedback_parts.append(f"Found {found_nodes}/{len(required_nodes)} concept nodes in file data.")
                feedback_parts.append(f"Found {found_rels}/{len(required_relationships)} relationship labels in file data.")
                
        except zipfile.BadZipFile:
            feedback_parts.append("EDDX file is not a valid zip archive.")
        except Exception as e:
            feedback_parts.append(f"Error analyzing EDDX content: {e}")
        finally:
            if os.path.exists(temp_eddx.name):
                os.unlink(temp_eddx.name)

    # ================================================================
    # 4. Visual Verification via VLM (40 pts)
    # ================================================================
    vlm_score = 0
    if png_exists:
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Documents/ehr_concept_map.png", temp_png.name)
            
            prompt = """
            Analyze this diagram image. It should be a concept map for an EHR system architecture.
            
            Check for the following:
            1. Is there a central node labeled "EHR System"?
            2. Are there at least 6 other labeled nodes visible (e.g., Patient Portal, Clinical Database, FHIR API)?
            3. Are the nodes connected by arrows/lines?
            4. Do the connector lines have text labels describing relationships (e.g., "serves", "stores data", "connects to")?
            5. Is the layout a network/graph structure (nodes surrounding a center) rather than a simple list?
            
            Provide a JSON response:
            {
                "central_node_present": boolean,
                "node_count_approx": integer,
                "connectors_visible": boolean,
                "relationship_labels_visible": boolean,
                "network_layout": boolean,
                "confidence": "low/medium/high"
            }
            """
            
            vlm_result = query_vlm(prompt=prompt, image=temp_png.name)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("central_node_present"): vlm_score += 10
                if parsed.get("node_count_approx", 0) >= 6: vlm_score += 10
                if parsed.get("connectors_visible"): vlm_score += 5
                if parsed.get("relationship_labels_visible"): vlm_score += 10
                if parsed.get("network_layout"): vlm_score += 5
                
                feedback_parts.append(f"Visual verification score: {vlm_score}/40")
            else:
                feedback_parts.append("VLM analysis failed.")
                # Fallback: if EDDX content was perfect, give some credit here
                if eddx_content_score >= 25:
                    vlm_score += 20
                    feedback_parts.append("Allocating partial visual credit based on strong file content match.")

        except Exception as e:
            feedback_parts.append(f"Visual verification error: {e}")
        finally:
            if os.path.exists(temp_png.name):
                os.unlink(temp_png.name)
    
    score += vlm_score

    # Final tally
    passed = score >= 60 and eddx_exists and png_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }