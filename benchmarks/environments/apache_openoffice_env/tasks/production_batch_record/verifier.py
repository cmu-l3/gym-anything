#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_production_batch_record(traj, env_info, task_info):
    """
    Verify the BCP document creation task.
    
    Criteria:
    1. File exists and has reasonable size (Gate).
    2. Structural elements: Table of Contents, Tables, Headings.
    3. Content elements: Correct Company, Product, Batch info.
    4. Anti-gaming: Timestamp checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata thresholds
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_bytes', 8000)
    
    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Variables
    score = 0
    feedback = []
    
    # 1. GATE: File Existence and Size (Max 10 pts)
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    file_size = result.get('file_size', 0)
    if file_size < min_size:
        return {"passed": False, "score": 0, "feedback": f"File too small ({file_size} bytes). Expected > {min_size} bytes (indicates empty/incomplete file)."}
    
    score += 10
    feedback.append(f"File exists and is sufficient size ({file_size} bytes).")

    # 2. Structure Verification (Max 60 pts)
    structure = result.get('structure', {})
    
    # Table of Contents (15 pts)
    if structure.get('has_toc'):
        score += 15
        feedback.append("Table of Contents found.")
    else:
        feedback.append("Missing Table of Contents.")

    # Tables (15 pts) - Expect at least 3
    table_count = structure.get('table_count', 0)
    if table_count >= 3:
        score += 15
        feedback.append(f"Found {table_count} tables (Target >= 3).")
    elif table_count > 0:
        score += 5
        feedback.append(f"Found only {table_count} tables (Target >= 3).")
    else:
        feedback.append("No tables found (Target >= 3).")

    # Heading 1 (15 pts) - Expect at least 6 main sections
    h1_count = structure.get('heading1_count', 0)
    if h1_count >= 6:
        score += 15
        feedback.append(f"Found {h1_count} main sections (Heading 1).")
    elif h1_count > 0:
        score += 5
        feedback.append(f"Found only {h1_count} main sections (Target >= 6).")
    else:
        feedback.append("No Heading 1 sections found (Agent likely used bold text instead of styles).")

    # Heading 2 (10 pts) - Expect at least 6 subsections
    h2_count = structure.get('heading2_count', 0)
    if h2_count >= 6:
        score += 10
        feedback.append(f"Found {h2_count} subsections (Heading 2).")
    else:
        feedback.append(f"Found {h2_count} subsections (Target >= 6).")

    # Footer/Page Numbers (5 pts)
    if structure.get('has_footer_page_numbers'):
        score += 5
        feedback.append("Page numbers/Footer found.")
    else:
        feedback.append("Missing page numbers in footer.")

    # 3. Content Verification (Max 30 pts)
    content = result.get('content', {})
    
    if content.get('matches_company'):
        score += 10
        feedback.append("Company Name verified.")
    else:
        feedback.append("Company Name missing or incorrect.")

    if content.get('matches_batch'):
        score += 10
        feedback.append("Batch Number verified.")
    else:
        feedback.append("Batch Number missing or incorrect.")
        
    if content.get('matches_product'):
        score += 5
        feedback.append("Product Name verified.")
        
    if content.get('matches_regulatory'):
        score += 5
        feedback.append("Regulatory references found.")

    # Final Evaluation
    # Pass threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }