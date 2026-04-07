#!/usr/bin/env python3
import json
import logging
import os
import sys

# Import shared verification utilities from the calligra_words_env
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_lease_template_completion(traj, env_info, task_info):
    """
    Verify the lease template completion task.
    Scores based on placeholder replacement, textual presence, style formatting, and VLM trajectory check.
    """
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/commercial_lease.odt")

    # Fetch export JSON to check timestamps
    temp_json = "/tmp/verifier_result.json"
    try:
        copy_from_env("/tmp/task_result.json", temp_json)
        with open(temp_json, "r") as f:
            export_data = json.load(f)
        os.unlink(temp_json)
    except Exception:
        export_data = {}

    if export_data and not export_data.get("file_modified_during_task", True):
        return {"passed": False, "score": 0, "feedback": "Failed: The document was not saved/modified during the task."}

    # Extract and parse the ODT document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document."}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        full_text = get_document_text_odt(content_tree)
        
        # 1. No remaining placeholders (15 pts)
        placeholders = [
            "[LANDLORD_NAME]", "[TENANT_NAME]", "[PROPERTY_ADDRESS]", 
            "[EFFECTIVE_DATE]", "[LEASE_TERM]", "[MONTHLY_RENT]", 
            "[SECURITY_DEPOSIT]", "[PERMITTED_USE]", "[LANDLORD_ADDRESS]", 
            "[TENANT_ADDRESS]", "[COMMENCEMENT_DATE]", "[EXPIRATION_DATE]"
        ]
        remaining = [p for p in placeholders if p in full_text]
        replaced_count = len(placeholders) - len(remaining)
        placeholder_score = int(15 * (replaced_count / len(placeholders)))
        score += placeholder_score
        
        if len(remaining) == 0:
            feedback_parts.append("All placeholders replaced (15/15)")
        else:
            feedback_parts.append(f"{len(remaining)} placeholders remain ({placeholder_score}/15)")

        # 2. Landlord details (10 pts)
        if "Meridian Properties LLC" in full_text:
            score += 10
            feedback_parts.append("Landlord details present (10/10)")
        else:
            feedback_parts.append("Landlord details missing (0/10)")

        # 3. Tenant details (10 pts)
        if "Coastal Brewing Company" in full_text:
            score += 10
            feedback_parts.append("Tenant details present (10/10)")
        else:
            feedback_parts.append("Tenant details missing (0/10)")

        # 4. Property/Financial terms (10 pts)
        fin_count = sum(1 for term in ["1847 Harbor", "8,750", "17,500"] if term in full_text)
        if fin_count == 3:
            score += 10
            feedback_parts.append("Financial terms present (10/10)")
        else:
            fin_pts = int(10 * fin_count / 3)
            score += fin_pts
            feedback_parts.append(f"Financial terms partial ({fin_pts}/10)")

        # 5. Date terms (10 pts)
        date_count = sum(1 for term in ["January 15", "March 1", "February 28"] if term in full_text)
        if date_count == 3:
            score += 10
            feedback_parts.append("Date terms present (10/10)")
        else:
            date_pts = int(10 * date_count / 3)
            score += date_pts
            feedback_parts.append(f"Date terms partial ({date_pts}/10)")

        # 6. Title Formatting (10 pts)
        title_bold = check_text_bold_odt(content_tree, styles_tree, "COMMERCIAL LEASE AGREEMENT")
        title_size = check_text_font_size_odt(content_tree, styles_tree, "COMMERCIAL LEASE AGREEMENT", 13.9)
        title_pts = 0
        if title_bold: title_pts += 5
        if title_size: title_pts += 5
        score += title_pts
        feedback_parts.append(f"Title formatting: bold={title_bold}, size={title_size} ({title_pts}/10)")

        # 7. H1 Articles (10 pts)
        articles = [f"ARTICLE {r}" for r in ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]]
        h1_matched, _, _ = check_heading_styles_odt(content_tree, styles_tree, articles, 1)
        if h1_matched >= 6:
            score += 10
            feedback_parts.append(f"H1 Articles ({h1_matched}/8) OK (10/10)")
        elif h1_matched >= 4:
            score += 5
            feedback_parts.append(f"H1 Articles ({h1_matched}/8) Partial (5/10)")
        else:
            feedback_parts.append(f"H1 Articles ({h1_matched}/8) missing (0/10)")

        # 8. H2 Sections (5 pts)
        sections = ["1.1", "1.2", "2.1", "2.2", "3.1", "3.2", "4.1", "4.2", "5.1", "5.2"]
        h2_matched, _, _ = check_heading_styles_odt(content_tree, styles_tree, sections, 2)
        if h2_matched >= 5:
            score += 5
            feedback_parts.append(f"H2 Sections ({h2_matched}/10) OK (5/5)")
        elif h2_matched >= 3:
            score += 3
            feedback_parts.append(f"H2 Sections ({h2_matched}/10) Partial (3/5)")
        else:
            feedback_parts.append(f"H2 Sections ({h2_matched}/10) missing (0/5)")

        # 9. Body text justified (10 pts)
        # Using invariant phrases to check paragraph alignment
        samples = [
            "This Commercial Lease Agreement",
            "Beginning on the first anniversary of the",
            "The occurrence of any of the following shall constitute an event of default"
        ]
        just_pts = 0
        for s in samples:
            m, _ = check_paragraph_alignment_odt(content_tree, styles_tree, s, "justify")
            if m > 0:
                just_pts += 1
        
        if just_pts >= 2:
            score += 10
            feedback_parts.append(f"Body text justified ({just_pts}/3 samples) (10/10)")
        else:
            feedback_parts.append(f"Body text justified ({just_pts}/3 samples) (0/10)")

        # 10. VLM Trajectory Verification (10 pts)
        vlm_pts = 0
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images and query_vlm:
                prompt = (
                    "You are analyzing a sequence of screenshots from an agent editing a commercial lease document in Calligra Words. "
                    "Did the agent successfully perform find-and-replace to substitute bracketed placeholders (like [LANDLORD_NAME]) "
                    "with actual text, AND format the document with headings and justified text?\n"
                    "Reply in JSON with a single boolean key 'success'."
                )
                vlm_resp = query_vlm(images=images, prompt=prompt)
                if vlm_resp and vlm_resp.get("parsed", {}).get("success", False):
                    vlm_pts = 10
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

        score += vlm_pts
        if vlm_pts > 0:
            feedback_parts.append("VLM visual verification passed (10/10)")
        else:
            feedback_parts.append("VLM visual verification failed/unavailable (0/10)")

        # Evaluate Penalties
        preservation = metadata.get("preservation_keywords", [])
        missing_pres = [p for p in preservation if p.lower() not in full_text.lower()]
        if missing_pres:
            score -= len(missing_pres) * 5
            feedback_parts.append(f"PENALTY: Missing preserved text {missing_pres}")

        score = max(0, min(100, score))
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        cleanup_verification_temp(temp_dir)