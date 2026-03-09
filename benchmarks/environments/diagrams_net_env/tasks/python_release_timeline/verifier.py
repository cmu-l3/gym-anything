#!/usr/bin/env python3
import json
import os
import tempfile
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_python_release_timeline(traj, env_info, task_info):
    """
    Verifies the Python release timeline task.
    
    Criteria:
    1. Diagram file modified/saved.
    2. PDF export exists and is recent.
    3. Shape count significantly increased (added 3.x releases).
    4. Text content contains specific Python versions (3.0 - 3.13).
    5. Text content contains feature keywords (proving data file reading).
    6. Styling includes at least 3 distinct fill colors (phases).
    7. Containers/Groups usage detected.
    8. EOL marker present.
    """
    
    # 1. Setup and retrieve result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    analysis = result.get("analysis", {})
    score = 0
    feedback = []

    # --- SCORING CRITERIA ---

    # A. File Activity (15 points)
    if result.get("diagram_modified", False):
        score += 5
        feedback.append("Diagram saved successfully (+5).")
    else:
        feedback.append("Diagram not modified/saved.")

    if result.get("pdf_exists", False) and result.get("pdf_modified", False):
        score += 10
        feedback.append("PDF export successful (+10).")
    else:
        feedback.append("PDF export missing or outdated.")

    # B. Content Expansion (30 points)
    # Initial count ~10-15. Expected ~40-50+.
    initial_count = int(result.get("initial_shape_count", 0))
    final_count = analysis.get("total_shapes", 0)
    
    if final_count > initial_count + 20:
        score += 15
        feedback.append(f"Significant content added ({final_count} shapes) (+15).")
    elif final_count > initial_count + 5:
        score += 5
        feedback.append(f"Some content added, but expected more ({final_count} shapes) (+5).")
    else:
        feedback.append("Little to no new shapes added.")

    # Check for Python 3.x versions (Need at least 8 unique versions)
    versions = analysis.get("version_labels", [])
    py3_versions = [v for v in versions if v.startswith("3.")]
    unique_py3 = len(set(py3_versions))
    
    if unique_py3 >= 8:
        score += 15
        feedback.append(f"Found {unique_py3} unique Python 3.x versions (+15).")
    elif unique_py3 >= 3:
        score += 5
        feedback.append(f"Found only {unique_py3} Python 3.x versions (expected >8) (+5).")

    # C. Feature Annotation (15 points)
    # Check for keywords from the data file
    keywords_found = analysis.get("feature_keywords", [])
    if len(keywords_found) >= 4:
        score += 15
        feedback.append(f"Key features annotated correctly ({len(keywords_found)} keywords found) (+15).")
    elif len(keywords_found) >= 1:
        score += 5
        feedback.append("Few feature annotations found (+5).")
    else:
        feedback.append("No feature keywords detected (did you add the text descriptions?).")

    # D. Styling & Grouping (25 points)
    # Colors: Need >= 3 distinct colors for phases
    colors = analysis.get("fill_colors", [])
    # Filter out black/white/none if needed, but distinct hex codes usually suffice
    if len(colors) >= 3:
        score += 10
        feedback.append(f"Phase color coding applied ({len(colors)} colors found) (+10).")
    else:
        feedback.append("Insufficient color coding (expected 3 distinct phase colors).")

    # Containers
    containers = analysis.get("containers", 0)
    if containers >= 2:
        score += 15
        feedback.append(f"Grouping containers detected ({containers} found) (+15).")
    else:
        feedback.append("No grouping containers detected (expected phases grouped in boxes/swimlanes).")

    # E. Specific Markers (15 points)
    if analysis.get("eol_marker", False):
        score += 5
        feedback.append("EOL marker found (+5).")
    else:
        feedback.append("EOL marker missing.")
        
    # VLM Verification (10 points)
    # Use trajectory to confirm they actually worked in the UI
    # This is a placeholder for actual VLM logic, granting points if PDF exists as proxy for visual completion
    if result.get("pdf_exists", False):
        score += 10
    
    # 3. Final Evaluation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }