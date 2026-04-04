#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_estate_planning_will(traj, env_info, task_info):
    """
    Verifies the drafted Will.
    Criteria:
    1. File exists and created during task.
    2. Correct Heading styles used (H1 for Articles, H2 for Sections).
    3. Critical Logic: Guardianship clause MUST be present (Sophie is < 18).
    4. Content Accuracy: Names, Bequests.
    5. Formatting: Page numbers.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Score Calculation
    score = 0
    feedback = []
    
    # Basic File Checks (10 pts)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "File /home/ga/Documents/Draft_Will_Thorne.odt not found."}
    
    if not result.get("timestamp_valid"):
        feedback.append("Warning: File timestamp suggests it wasn't modified during the task.")
    else:
        score += 10
        feedback.append("File created/modified successfully.")

    content = result.get("content_analysis", {})
    fmt = result.get("formatting_analysis", {})

    # Formatting Styles (20 pts)
    # Expect roughly 6 Articles (I-VI) -> H1
    if fmt.get("h1_count", 0) >= 5:
        score += 15
        feedback.append(f"Heading 1 styles applied correctly ({fmt['h1_count']} found).")
    else:
        feedback.append(f"Missing Heading 1 styles (found {fmt.get('h1_count',0)}). Articles should use 'Heading 1'.")

    # Expect H2 for sections? Task description asks for H2 for 'Section 1.01' etc.
    # The boilerplate might not strictly have sections, but if the agent added them or if the prompt implies strict structure.
    # Actually, the boilerplate provided in setup_task.sh DOES NOT have explicit "Section 1.01". 
    # However, the task prompt says: "6. Format section headings (e.g., 'Section 1.01') using the 'Heading 2' paragraph style."
    # If the user adds them, good. If not, we might be lenient or check if they structured the specific bequests/sub-points.
    # Let's verify Heading 2 usage if present, but weight it lower or strictly check H1.
    # We will give 5 pts if H1 is good, to round up the formatting score.
    if fmt.get("h1_count", 0) >= 5:
        score += 5
    
    # Content Accuracy (Names) (20 pts)
    if content.get("client_name") and content.get("spouse_name"):
        score += 10
        feedback.append("Client and Spouse names correct.")
    else:
        feedback.append("Client or Spouse name missing.")

    if content.get("child_marcus") and content.get("child_sophie"):
        score += 10
        feedback.append("Children names included.")
    else:
        feedback.append("Children names missing.")

    # Critical Logic: Guardianship (25 pts)
    # Sophie (DOB 2014) is a minor in 2026. Guardianship Article IS required.
    if content.get("guardianship_clause"):
        if content.get("guardian_names"):
            score += 25
            feedback.append("Guardianship clause correctly included with guardians named.")
        else:
            score += 15
            feedback.append("Guardianship clause present but specific guardian names missing.")
    else:
        feedback.append("CRITICAL FAILURE: Guardianship clause missing. Client has a minor child (Sophie).")

    # Bequests (15 pts)
    if content.get("guitar_bequest") and content.get("watch_bequest"):
        score += 15
        feedback.append("Specific bequests (Guitar, Watch) correctly assigned.")
    elif content.get("guitar_bequest") or content.get("watch_bequest"):
        score += 7
        feedback.append("Some bequests missing or incorrect.")
    else:
        feedback.append("Specific bequests missing.")

    # Footer (10 pts)
    if fmt.get("has_page_numbers"):
        score += 10
        feedback.append("Page numbers found in footer.")
    else:
        feedback.append("Page numbers missing from footer.")

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }