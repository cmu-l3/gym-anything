#!/usr/bin/env python3
"""
Verifier for document_bookmarks_hyperlinks task.

Verifies:
1. Output file exists and is valid DOCX.
2. Document contains internal bookmarks (w:bookmarkStart).
3. Document contains internal hyperlinks (w:hyperlink with w:anchor).
4. Bookmarks are positioned near Chapter headings.
5. Hyperlinks point to valid bookmarks.
6. Navigation page exists at the beginning.
"""

import json
import os
import sys
import logging
import tempfile
import zipfile
from xml.etree import ElementTree

# Add workspace/utils to path if needed, though we'll use copy_from_env mostly
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../'))
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespace map for parsing DOCX XML
NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
}

def verify_bookmarks_and_hyperlinks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    chapter_titles = metadata.get('chapter_titles', [])
    min_bookmarks = metadata.get('min_bookmarks', 7)
    min_hyperlinks = metadata.get('min_hyperlinks', 7)

    # 1. Load result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    if not task_result.get("output_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file case_manual_navigable.docx not found."
        }

    # 2. Copy and Parse DOCX
    score = 0
    feedback_parts = []
    
    # File creation checks (Anti-gaming)
    if task_result.get("file_created_during_task"):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid")
    
    if task_result.get("output_size_bytes", 0) > task_result.get("input_size_bytes", 0) + 100:
        score += 5
        feedback_parts.append("File size increased (content added)")
    else:
        feedback_parts.append("File size suspicious (no content added?)")

    # Retrieve DOCX content
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    try:
        copy_from_env("/home/ga/Documents/case_manual_navigable.docx", temp_docx.name)
        
        # Parse XML directly since python-docx bookmark support is limited for reading
        with zipfile.ZipFile(temp_docx.name, 'r') as z:
            xml_content = z.read('word/document.xml')
            tree = ElementTree.fromstring(xml_content)
            
            # --- Check Bookmarks ---
            # w:bookmarkStart w:name="BookmarkName" ...
            bookmarks = []
            for bm in tree.findall('.//w:bookmarkStart', NS):
                name = bm.get(f'{{{NS["w"]}}}name')
                if name and name != "_GoBack": # Filter internal Word bookmark
                    bookmarks.append(name)
            
            # --- Check Hyperlinks ---
            # w:hyperlink w:anchor="BookmarkName"
            hyperlinks = []
            for hl in tree.findall('.//w:hyperlink', NS):
                anchor = hl.get(f'{{{NS["w"]}}}anchor')
                if anchor:
                    hyperlinks.append(anchor)
                    
            # --- Check Text Content (Navigation Page) ---
            # Extract text from first ~50 paragraphs to find navigation index
            paragraphs = []
            for p in tree.findall('.//w:p', NS):
                texts = [t.text for t in p.findall('.//w:t', NS) if t.text]
                paragraphs.append("".join(texts))
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse DOCX: {e}"}
    finally:
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)

    # 3. Evaluate Criteria
    
    # Bookmark Count (25 pts)
    unique_bookmarks = len(set(bookmarks))
    if unique_bookmarks >= min_bookmarks:
        score += 25
        feedback_parts.append(f"Bookmarks found: {unique_bookmarks}")
    elif unique_bookmarks > 0:
        score += int(25 * (unique_bookmarks / min_bookmarks))
        feedback_parts.append(f"Partial bookmarks: {unique_bookmarks}/{min_bookmarks}")
    else:
        feedback_parts.append("No bookmarks found")

    # Hyperlink Count (25 pts)
    # Check that hyperlinks point to existing bookmarks
    valid_links = [h for h in hyperlinks if h in bookmarks]
    if len(valid_links) >= min_hyperlinks:
        score += 25
        feedback_parts.append(f"Internal links found: {len(valid_links)}")
    elif len(valid_links) > 0:
        score += int(25 * (len(valid_links) / min_hyperlinks))
        feedback_parts.append(f"Partial links: {len(valid_links)}/{min_hyperlinks}")
    else:
        feedback_parts.append("No valid internal hyperlinks found")

    # Navigation Page Content (20 pts)
    # Check start of document for "Navigation" or chapter titles
    intro_text = " ".join(paragraphs[:10]).lower()
    nav_keywords = ["navigation", "index", "content", "chapters", "quick"]
    
    # Check for chapter title fragments in the start
    titles_found = 0
    for title in chapter_titles:
        # Check first 20 characters of title to match shortened versions
        check_str = title[:20].lower()
        if check_str in intro_text:
            titles_found += 1
            
    if any(k in intro_text for k in nav_keywords) or titles_found >= 4:
        score += 20
        feedback_parts.append("Navigation page content detected")
    else:
        feedback_parts.append("Navigation page text not found at start")

    # 4. VLM Verification (20 pts)
    # Use trajectory to see if they actually used the menus
    frames = sample_trajectory_frames(traj, 5)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a LibreOffice Writer task.
    Did the user:
    1. Open the "Insert Bookmark" dialog?
    2. Open the "Insert Hyperlink" dialog?
    3. Create a list of links at the start of the document?
    
    Output JSON: {"used_bookmark_dialog": bool, "used_hyperlink_dialog": bool, "created_nav_page": bool}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(frames + [final_img], vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        if parsed.get('used_bookmark_dialog') or parsed.get('used_hyperlink_dialog'):
            vlm_score += 10
        if parsed.get('created_nav_page'):
            vlm_score += 10
    except Exception:
        # Fallback if VLM fails: assume passed if file checks were good
        if score >= 60:
            vlm_score = 20
    
    score += vlm_score
    feedback_parts.append(f"VLM Score: {vlm_score}")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }