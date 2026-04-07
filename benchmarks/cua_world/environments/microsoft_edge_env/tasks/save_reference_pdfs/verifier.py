#!/usr/bin/env python3
"""
Verifier for save_reference_pdfs task.

Verification Logic:
1. Directory Creation (5 pts)
2. PDF Files Existence & Validity (15 pts * 3 = 45 pts)
   - Must exist
   - Must be valid PDF format
   - Must be > 20KB (non-empty content)
   - Must be created AFTER task start (anti-gaming)
3. Browser History Verification (10 pts * 3 = 30 pts)
   - Must show visits to the specific Wikipedia articles
4. README Index Creation (20 pts)
   - Exists & created during task (5 pts)
   - Mentions all 3 topics (15 pts)

Pass Threshold: 65 points (Allows passing if PDFs are correct but README is messy, or minor history issues)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_reference_pdfs(traj, env_info, task_info):
    """Verify that 3 Wikipedia articles were saved as PDFs and indexed."""
    
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. verify Directory (5 pts)
    if result.get("directory_exists"):
        score += 5
        feedback_parts.append("Directory created (5/5)")
    else:
        feedback_parts.append("Directory ~/Documents/Workshop_Materials/ NOT found (0/5)")
        # Critical failure if dir doesn't exist, but we check files anyway just in case they put them elsewhere (though export script checks specific dir)

    # 3. Verify PDF Files (45 pts total)
    files_data = result.get("files", {})
    required_files = [
        ("blooms_taxonomy.pdf", "Bloom"),
        ("constructivism.pdf", "Constructivism"),
        ("differentiated_instruction.pdf", "Differentiated")
    ]
    
    for filename, topic in required_files:
        file_info = files_data.get(filename, {})
        file_score = 0
        
        if file_info.get("exists"):
            # Check validity
            is_pdf = file_info.get("is_valid_pdf", False)
            is_fresh = file_info.get("created_during_task", False)
            is_large_enough = file_info.get("size", 0) > 20480 # 20KB
            
            if is_pdf and is_fresh and is_large_enough:
                file_score = 15
                feedback_parts.append(f"{filename} valid (15/15)")
            else:
                # Partial credit logic
                reasons = []
                if not is_pdf: reasons.append("not a valid PDF")
                if not is_fresh: reasons.append("old timestamp")
                if not is_large_enough: reasons.append("file too small/empty")
                feedback_parts.append(f"{filename} invalid: {', '.join(reasons)} (0/15)")
        else:
            feedback_parts.append(f"{filename} missing (0/15)")
            
        score += file_score

    # 4. Verify Browser History (30 pts total)
    history_visits = result.get("history", {}).get("visits", [])
    # Flatten history to a searchable string
    history_str = json.dumps(history_visits).lower()
    
    history_score = 0
    # topic is already defined in required_files list above
    for _, topic in required_files:
        # Check if topic keyword appears in history URLs
        # (Using topic fragment from filenames which matches URL fragments)
        if topic.lower() in history_str:
            history_score += 10
            
    if history_score == 30:
        feedback_parts.append("History shows all visits (30/30)")
    else:
        feedback_parts.append(f"History incomplete ({history_score}/30)")
    
    score += history_score

    # 5. Verify README (20 pts total)
    readme = result.get("readme", {})
    readme_score = 0
    if readme.get("exists") and readme.get("created_during_task"):
        readme_score += 5 # Base points for existence
        content = readme.get("content", "").lower()
        
        # Check content for topics
        topics_found = 0
        if "bloom" in content: topics_found += 1
        if "constructivism" in content: topics_found += 1
        if "differentiat" in content: topics_found += 1
        
        # 15 points for content, 5 per topic
        content_points = topics_found * 5
        readme_score += content_points
        
        feedback_parts.append(f"README valid covering {topics_found}/3 topics ({readme_score}/20)")
    else:
        feedback_parts.append("README missing or pre-existing (0/20)")
        
    score += readme_score

    # 6. Final Result
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }