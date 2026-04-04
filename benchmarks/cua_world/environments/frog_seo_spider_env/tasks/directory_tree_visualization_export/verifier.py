#!/usr/bin/env python3
"""
Verifier for directory_tree_visualization_export task.

Scoring (100 points total):
1. File Existence & Validity (40 pts):
   - File exists at correct path
   - File was created during task (anti-gaming)
   - File is a valid PNG > 5KB
2. VLM Content Verification (40 pts):
   - Image actually looks like a directory tree (nodes, hierarchy)
   - Contains domain-specific text (catalogue, books, etc.)
3. App State (20 pts):
   - Screaming Frog running
   - Visualization window detected (or closed after export)

Pass Threshold: 80 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_directory_tree_export(traj, env_info, task_info):
    """Verify that the directory tree graph was generated and exported."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Artifacts (40 pts)
    file_exists = result.get('file_exists', False)
    file_fresh = result.get('file_fresh', False)
    is_png = result.get('is_png_format', False)
    file_size = result.get('file_size_bytes', 0)
    
    if file_exists and file_fresh and is_png and file_size > 5000:
        score += 40
        feedback_parts.append("Valid fresh PNG output found (40/40)")
        has_valid_image = True
    elif file_exists and file_fresh:
        score += 20
        feedback_parts.append(f"File exists but verification incomplete (size={file_size}, is_png={is_png}) (20/40)")
        has_valid_image = False # Might be empty or wrong format
    else:
        feedback_parts.append("No valid output file created (0/40)")
        has_valid_image = False

    # 3. App State (20 pts)
    sf_running = result.get('sf_running', False)
    vis_window = result.get('visualization_window_open', False)
    
    if sf_running:
        score += 10
        feedback_parts.append("App running (10/10)")
    
    if vis_window:
        score += 10
        feedback_parts.append("Visualization window detected (10/10)")
    elif has_valid_image:
        # If they closed the window but saved the file, give credit
        score += 10
        feedback_parts.append("Visualization window closed but file saved (10/10)")
    
    # 4. VLM Verification of Output Image (40 pts)
    vlm_score = 0
    if has_valid_image and query_vlm:
        # Retrieve the exported image
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/exported_site_tree.png", temp_img.name)
            
            prompt = """Analyze this image exported from Screaming Frog SEO Spider.
            
            Does this image show a 'Directory Tree Graph' or similar site visualization?
            Look for:
            1. A branching tree structure (circles/nodes connected by lines).
            2. Hierarchy (root node branching into sub-nodes).
            3. Text labels like 'catalogue', 'books', 'toscrape', 'category'.
            
            Return JSON:
            {
                "is_graph": true/false,
                "has_hierarchy": true/false,
                "visible_text": ["list", "of", "words"],
                "confidence": "high/medium/low"
            }
            """
            
            vlm_response = query_vlm(prompt=prompt, image=temp_img.name)
            
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                
                is_graph = parsed.get('is_graph', False)
                has_hierarchy = parsed.get('has_hierarchy', False)
                text_list = [t.lower() for t in parsed.get('visible_text', [])]
                
                # Check graph structure
                if is_graph or has_hierarchy:
                    vlm_score += 20
                    feedback_parts.append("Image verified as graph structure (20/20)")
                else:
                    feedback_parts.append("Image does not look like a graph (0/20)")
                    
                # Check content (domain specificity)
                relevant_terms = ['catalogue', 'books', 'toscrape', 'category', 'index']
                found_terms = [term for term in relevant_terms if any(term in t for t in text_list)]
                
                if found_terms:
                    vlm_score += 20
                    feedback_parts.append(f"Found relevant labels: {found_terms} (20/20)")
                else:
                    feedback_parts.append("No domain-specific labels found (0/20)")
            else:
                feedback_parts.append("VLM analysis failed (0/40)")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing image: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
                
    elif not has_valid_image:
        feedback_parts.append("Skipping VLM check due to missing output file (0/40)")
    
    score += vlm_score

    # Final Pass check
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }