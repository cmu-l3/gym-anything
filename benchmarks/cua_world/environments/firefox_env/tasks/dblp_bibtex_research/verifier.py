#!/usr/bin/env python3
"""
Verifier for dblp_bibtex_research task.

Criteria:
1. File Creation (10 pts): deep_learning.bib exists and is fresh.
2. Entry Count (15 pts): File contains exactly 5 valid BibTeX entries.
3. Citation Accuracy (50 pts, 10 per paper):
    - Identify paper by title.
    - Check it is the correct peer-reviewed venue (NeurIPS, CVPR, etc.).
    - PENALTY for ArXiv/CoRR citations.
4. Bookmarks (10 pts): Folder exists with DBLP links.
5. History (15 pts): DBLP was used.
"""

import json
import base64
import re
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_dblp_bibtex_research(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    # Copy result file
    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/dblp_result.json", tmp_result.name)
        with open(tmp_result.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_result.name):
            os.unlink(tmp_result.name)

    # 2. Extract Data
    file_exists = result.get("file_exists", 0)
    file_fresh = result.get("file_fresh", 0)
    content_b64 = result.get("file_content_b64", "")
    dblp_visits = result.get("dblp_visits", 0)
    bookmark_folder = result.get("bookmark_folder_exists", 0)
    bookmark_count = result.get("dblp_bookmarks_count", 0)

    # Decode content
    bib_content = ""
    if content_b64:
        try:
            bib_content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        except:
            bib_content = ""

    score = 0
    feedback = []

    # 3. Criterion: History (15 pts)
    if dblp_visits > 0:
        score += 15
        feedback.append("History check passed: DBLP visited.")
    else:
        feedback.append("History check failed: DBLP not visited.")

    # 4. Criterion: Bookmarks (10 pts)
    if bookmark_folder:
        if bookmark_count >= 5:
            score += 10
            feedback.append(f"Bookmarks check passed: {bookmark_count} DBLP bookmarks found.")
        elif bookmark_count > 0:
            score += 5
            feedback.append(f"Bookmarks check partial: {bookmark_count}/5 found.")
        else:
            feedback.append("Bookmarks folder found but empty.")
    else:
        feedback.append("Bookmarks folder 'Bibliography Sources' not found.")

    # 5. Criterion: File Existence (10 pts)
    if file_exists and file_fresh:
        score += 10
        feedback.append("File 'deep_learning.bib' created successfully.")
    elif file_exists:
        score += 5
        feedback.append("File exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback.append("File 'deep_learning.bib' NOT found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 6. Criterion: Parse BibTeX (15 pts for count, 50 pts for accuracy)
    
    # Simple regex based BibTeX parser
    # Finds entries like @article{key, ... }
    # This is rough but sufficient for verification
    entries = []
    raw_entries = re.split(r'@\w+\s*\{', bib_content)
    # Remove empty first split if any
    raw_entries = [e for e in raw_entries if e.strip()]
    
    entry_count = len(raw_entries)
    
    if entry_count == 5:
        score += 15
        feedback.append("Found exactly 5 BibTeX entries.")
    elif entry_count > 0:
        score += max(0, 15 - (abs(5 - entry_count) * 3)) # Partial credit
        feedback.append(f"Found {entry_count} entries (expected 5).")
    else:
        feedback.append("No valid BibTeX entries found in file.")

    # 7. Analyze Entries (50 pts)
    targets = task_info.get("metadata", {}).get("target_papers", [])
    
    # Helper to find field value in a raw entry string
    def get_field(field, text):
        # matches field = {value} or field = "value"
        # simplistic match, handles multiline
        pattern = re.compile(rf"{field}\s*=\s*[\"\{](.*?)[\"\}]", re.IGNORECASE | re.DOTALL)
        match = pattern.search(text)
        if match:
            return match.group(1).replace('\n', ' ').strip()
        return ""

    papers_found = 0
    papers_correct_venue = 0

    for target in targets:
        # keywords to identify the paper
        keywords = target["title_keywords"]
        expected_venue = target["expected_venue_regex"]
        forbidden_venue = target["forbidden_venue_regex"]
        
        # Find matching entry
        matched_entry = None
        for entry_text in raw_entries:
            title = get_field("title", entry_text)
            if all(kw.lower() in title.lower() for kw in keywords):
                matched_entry = entry_text
                break
        
        if matched_entry:
            papers_found += 1
            venue_text = get_field("booktitle", matched_entry) + " " + get_field("journal", matched_entry) + " " + get_field("volume", matched_entry)
            
            is_forbidden = re.search(forbidden_venue, venue_text, re.IGNORECASE)
            is_expected = re.search(expected_venue, venue_text, re.IGNORECASE)
            
            if is_forbidden:
                feedback.append(f"❌ Paper matching '{keywords[0]}...' cites ArXiv/CoRR (Forbidden).")
            elif is_expected:
                papers_correct_venue += 1
                score += 10
                feedback.append(f"✅ Paper matching '{keywords[0]}...' cites correct venue.")
            else:
                # Ambiguous case: neither forbidden nor explicitly expected found (maybe abbreviated differently)
                # Check strict arxiv exclusion
                if "corr" in venue_text.lower() or "arxiv" in venue_text.lower():
                     feedback.append(f"❌ Paper matching '{keywords[0]}...' seems to be ArXiv.")
                else:
                    # Give partial credit if it looks like a conference citation (has pages, year, not corr)
                    score += 5
                    feedback.append(f"⚠️ Paper matching '{keywords[0]}...' venue ambiguous, partial credit.")
        else:
            feedback.append(f"❌ Paper matching '{keywords[0]}...' NOT found in bibliography.")

    passed = (score >= 75) and (papers_correct_venue >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }