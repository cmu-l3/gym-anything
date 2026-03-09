#!/usr/bin/env python3
"""
Verifier for create_techdraw task.

Verifies that the agent:
1. Created a valid FreeCAD (.FCStd) file containing a TechDraw page.
2. Inserted orthographic projection views (Front, Top, Right).
3. Exported the drawing to a PDF file.

Verification Method:
- Inspects file metadata and timestamps (via JSON result).
- Copies the .FCStd file to host and inspects internal `Document.xml` to verify TechDraw objects exist.
- Uses VLM to visually confirm the final screenshot looks like a technical drawing.
"""

import json
import os
import tempfile
import zipfile
import re
import logging
from typing import Dict, Any

# VLM utilities provided by the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_techdraw(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the TechDraw creation task.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scoring = metadata.get('scoring', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}

    # 2. Retrieve Task Result JSON
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

    # 3. Verify PDF Export (File Existence & Properties)
    pdf_exists = result.get('pdf_exists', False)
    pdf_size = result.get('pdf_size_bytes', 0)
    pdf_fresh = result.get('pdf_created_during_task', False)
    
    if pdf_exists:
        score += scoring.get('pdf_exists', 15)
        feedback_parts.append("PDF export found")
        
        if pdf_size > metadata.get('min_pdf_size_bytes', 5000):
            score += scoring.get('pdf_content', 10)
            feedback_parts.append(f"PDF content valid ({pdf_size} bytes)")
        else:
            feedback_parts.append("PDF file seems empty or too small")
            
        if pdf_fresh:
             # Part of anti-gaming score
             pass
    else:
        feedback_parts.append("PDF export missing")

    # 4. Deep Inspection of FCStd File
    fcstd_exists = result.get('fcstd_exists', False)
    fcstd_path = result.get('fcstd_path')
    fcstd_fresh = result.get('fcstd_created_during_task', False)
    
    techdraw_page_found = False
    views_found = 0
    template_found = False
    
    if fcstd_exists and fcstd_path:
        # Copy FCStd file to host for analysis
        temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd')
        try:
            copy_from_env(fcstd_path, temp_fcstd.name)
            
            # FCStd is a ZIP file. We need to parse Document.xml inside it.
            if zipfile.is_zipfile(temp_fcstd.name):
                score += scoring.get('fcstd_valid', 10)
                feedback_parts.append("Valid FCStd file created")
                
                with zipfile.ZipFile(temp_fcstd.name, 'r') as zf:
                    if 'Document.xml' in zf.namelist():
                        doc_xml = zf.read('Document.xml').decode('utf-8', errors='ignore')
                        
                        # Check for Page
                        if 'TechDraw::DrawPage' in doc_xml or 'TechDraw::DrawSVGPage' in doc_xml:
                            techdraw_page_found = True
                            score += scoring.get('page_exists', 20)
                            feedback_parts.append("TechDraw page created")
                        
                        # Check for Template
                        if 'TechDraw::DrawSVGTemplate' in doc_xml or 'Template' in doc_xml:
                            template_found = True
                            score += scoring.get('template_exists', 5)
                            
                        # Check for Views (DrawViewPart, DrawProjGroup, etc.)
                        # Simple views or projection groups count
                        # DrawViewPart is the base type for views
                        view_matches = re.findall(r'Type="TechDraw::DrawViewPart"', doc_xml)
                        proj_group_matches = re.findall(r'Type="TechDraw::DrawProjGroup"', doc_xml)
                        
                        # Approximate count: Projection groups usually contain views, 
                        # but sometimes are just containers. 
                        # We count distinct view objects.
                        views_found = len(view_matches)
                        
                        details['view_objects'] = views_found
                        details['projection_groups'] = len(proj_group_matches)
                        
                        if views_found >= 1:
                            score += scoring.get('views_exist', 20)
                            feedback_parts.append(f"Found {views_found} view(s)")
                        
                        if views_found >= 3:
                            score += scoring.get('full_projection', 15)
                            feedback_parts.append("Full orthographic projection set found")
                    else:
                        feedback_parts.append("Corrupt FCStd: Document.xml missing")
            else:
                feedback_parts.append("Invalid FCStd file (not a zip archive)")
                
        except Exception as e:
            feedback_parts.append(f"Error analyzing FCStd file: {str(e)}")
        finally:
            if os.path.exists(temp_fcstd.name):
                os.unlink(temp_fcstd.name)
    else:
        feedback_parts.append("FCStd file missing")

    # 5. Anti-Gaming Check (Time)
    if (pdf_exists and pdf_fresh) or (fcstd_exists and fcstd_fresh):
        score += scoring.get('anti_gaming', 5)
    else:
        if pdf_exists or fcstd_exists:
            feedback_parts.append("Warning: Files were not created during this task session")

    # 6. VLM Visual Verification (Secondary Signal)
    # We check if the screen actually shows a drawing sheet
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vlm_prompt = """
        Does this screenshot verify that a technical engineering drawing was created in FreeCAD?
        I am looking for:
        1. A white drawing sheet/page with a border.
        2. Technical drawings/views of a mechanical part (orthographic views).
        3. The FreeCAD 'TechDraw' interface (icons of compass/square, rulers, or 'Page' in the tree view).
        
        Answer JSON: {"is_technical_drawing": bool, "has_orthographic_views": bool, "confidence": "high/medium/low"}
        """
        vlm_result = query_vlm(prompt=vlm_prompt, image=final_screenshot)
        
        if vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            details['vlm_analysis'] = parsed
            
            # If we missed programmatic signals (e.g. file save failed but UI shows success),
            # give partial credit or reinforce success
            if parsed.get('is_technical_drawing') and parsed.get('has_orthographic_views'):
                if not techdraw_page_found:
                    # Grant partial fallback points if file analysis failed but visual is good
                    score += 10 
                    feedback_parts.append("Visual verification passed (TechDraw visible)")

    # 7. Final Scoring Calculation
    # Pass if we have a valid file with at least one view OR 
    # if we have a valid PDF and strong visual evidence.
    
    # Primary Pass Condition: FCStd valid + Page + At least 1 View
    primary_success = (techdraw_page_found and views_found >= 1)
    
    # Secondary Pass Condition: PDF Valid + Content
    secondary_success = (pdf_exists and pdf_size > 5000)
    
    passed = (score >= metadata.get('pass_threshold', 50)) and (primary_success or secondary_success)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "; ".join(feedback_parts),
        "details": details
    }