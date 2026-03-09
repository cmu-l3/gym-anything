#!/usr/bin/env python3
"""
Verifier for wedding_video_shotlist@1
Checks document organization, formatting, completeness, and professionalism
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_paragraphs,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Original shots from raw notes (for detecting creative additions)
ORIGINAL_SHOT_KEYWORDS = [
    "bride getting ready", "bridesmaids", "hair", "makeup",
    "ceremony entrance", "father", "walking", "aisle",
    "ring exchange", "closeup", "hands",
    "first kiss", "multiple angles",
    "family photos", "parents", "siblings",
    "fountain", "golden hour",
    "reception entrance", "dj", "announce",
    "first dance", "song",
    "cake cutting", "traditional",
    "speeches", "best man", "maid of honor", "brother", "sister",
    "detail shots", "rings", "dress", "bouquet", "flowers", "venue sign",
    "candid", "guest moments", "cocktail hour",
    "couple portraits", "garden", "greenery",
    "groom", "groomsmen", "getting dressed", "ties",
    "ceremony", "wide shot", "venue", "guests",
    "vows exchange", "audio",
    "bouquet toss",
    "establishing shots", "exterior", "interior"
]

PRIORITY_KEYWORDS = ["important", "must", "critical", "priority", "essential", "don't miss", "crucial"]

WEDDING_PHASE_KEYWORDS = [
    "pre-ceremony", "getting ready", "prep", "preparation",
    "ceremony", "wedding", "vows", "aisle",
    "formal", "family", "group photos", "portraits",
    "couple", "bride and groom", "newlyweds",
    "reception", "party", "celebration", "dinner",
    "detail", "details", "b-roll", "establishing"
]

TIME_PATTERN = re.compile(r'\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)')


def verify_wedding_video_shotlist(traj, env_info, task_info):
    """
    Verify the wedding videography shot list document
    
    Returns:
        dict: {"passed": bool, "score": float, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "❌ Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/Martinez_Wedding_ShotList.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_shotlist_')

    try:
        # Parse document
        success, doc, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            'docx'
        )
        
        if not success or doc is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Failed to parse document: {error}"
            }
        
        # Check if document is essentially empty
        para_count = count_paragraphs(doc)
        if para_count < 5:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document appears empty or incomplete (only {para_count} paragraphs)"
            }
        
        feedback_parts = []
        score = 0.0
        criteria_details = []
        
        # Criterion 1: Title Present and Formatted (10%)
        title_found, title_feedback = check_title(doc)
        if title_found:
            score += 0.10
            feedback_parts.append(f"✅ Title: {title_feedback}")
        else:
            feedback_parts.append(f"❌ Title: {title_feedback}")
        criteria_details.append(("Title", title_found, 0.10))
        
        # Criterion 2: Multiple Timeline Sections (25%)
        section_count, section_feedback = check_sections(doc)
        if section_count >= 5:
            score += 0.25
            feedback_parts.append(f"✅ Sections: {section_feedback}")
        elif section_count >= 3:
            # Partial credit for 3-4 sections
            score += 0.15
            feedback_parts.append(f"⚠️ Sections: {section_feedback} (partial credit)")
        else:
            feedback_parts.append(f"❌ Sections: {section_feedback}")
        criteria_details.append(("Sections", section_count >= 5, 0.25))
        
        # Criterion 3: Sufficient Shot Count (20%)
        shot_count, shot_feedback = count_shots(doc)
        if shot_count >= 18:
            score += 0.20
            feedback_parts.append(f"✅ Shot count: {shot_feedback}")
        elif shot_count >= 12:
            # Partial credit for 12-17 shots
            score += 0.12
            feedback_parts.append(f"⚠️ Shot count: {shot_feedback} (partial credit)")
        else:
            feedback_parts.append(f"❌ Shot count: {shot_feedback}")
        criteria_details.append(("Shot count", shot_count >= 18, 0.20))
        
        # Criterion 4: Priority Shots Marked (20%)
        priority_count, priority_feedback = check_priority_shots(doc)
        if priority_count >= 3:
            score += 0.20
            feedback_parts.append(f"✅ Priority shots: {priority_feedback}")
        elif priority_count >= 2:
            # Partial credit for 2 priority shots
            score += 0.12
            feedback_parts.append(f"⚠️ Priority shots: {priority_feedback} (partial credit)")
        else:
            feedback_parts.append(f"❌ Priority shots: {priority_feedback}")
        criteria_details.append(("Priority shots", priority_count >= 3, 0.20))
        
        # Criterion 5: List Formatting (15%)
        list_ratio, list_feedback = check_list_usage(doc)
        if list_ratio >= 0.50:
            score += 0.15
            feedback_parts.append(f"✅ List formatting: {list_feedback}")
        elif list_ratio >= 0.30:
            # Partial credit for 30-49% list usage
            score += 0.08
            feedback_parts.append(f"⚠️ List formatting: {list_feedback} (partial credit)")
        else:
            feedback_parts.append(f"❌ List formatting: {list_feedback}")
        criteria_details.append(("List formatting", list_ratio >= 0.50, 0.15))
        
        # Criterion 6: Production Notes / Creative Additions (10%)
        creative_found, creative_feedback = check_creative_content(doc)
        if creative_found:
            score += 0.10
            feedback_parts.append(f"✅ Creative content: {creative_feedback}")
        else:
            feedback_parts.append(f"❌ Creative content: {creative_feedback}")
        criteria_details.append(("Creative content", creative_found, 0.10))
        
        # Overall result
        passed = score >= 0.70
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        score_pct = int(score * 100)
        criteria_passed = sum(1 for _, passed, _ in criteria_details if passed)
        total_criteria = len(criteria_details)
        
        summary = f"Score: {score_pct}% | Criteria passed: {criteria_passed}/{total_criteria}"
        
        return {
            "passed": passed,
            "score": round(score, 2),
            "feedback": f"{summary} | {feedback}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)


def check_title(doc) -> tuple:
    """Check if document has properly formatted title"""
    # Check first 5 paragraphs for title
    for i, para in enumerate(doc.paragraphs[:5]):
        text = para.text.strip()
        if not text:
            continue
            
        text_lower = text.lower()
        
        # Must mention wedding/shot list and ideally the couple names
        has_wedding_ref = any(keyword in text_lower for keyword in ["martinez", "chen", "wedding", "shot list", "shotlist"])
        
        if not has_wedding_ref:
            continue
        
        # Check formatting
        is_large = False
        is_centered = False
        is_bold = False
        
        # Check if any run has large font
        for run in para.runs:
            if run.font.size and run.font.size.pt >= 14:
                is_large = True
            if run.bold:
                is_bold = True
        
        # Check alignment (1 = CENTER)
        if para.alignment == 1:
            is_centered = True
        
        # Title should have at least one formatting element
        if is_large or is_centered or is_bold:
            formatting = []
            if is_large:
                formatting.append("large font")
            if is_centered:
                formatting.append("centered")
            if is_bold:
                formatting.append("bold")
            return True, f"Found title in para {i+1} ({', '.join(formatting)})"
    
    # Check if there's at least some title-like text even without formatting
    for i, para in enumerate(doc.paragraphs[:5]):
        text_lower = para.text.lower()
        if any(keyword in text_lower for keyword in ["martinez", "chen", "wedding", "shot list"]):
            return True, f"Found title text in para {i+1} (minimal formatting)"
    
    return False, "No title found mentioning wedding/shot list in first 5 paragraphs"


def check_sections(doc) -> tuple:
    """Count timeline sections with proper formatting"""
    section_count = 0
    section_indicators = []
    
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text or len(text) < 3:
            continue
        
        text_lower = text.lower()
        
        # Check if it's a heading/section
        is_section = False
        
        # Method 1: Heading style (most reliable)
        if para.style.name and 'Heading' in para.style.name:
            is_section = True
        
        # Method 2: Bold text that contains wedding phase keywords
        if not is_section:
            is_bold = any(run.bold for run in para.runs if run.text.strip())
            has_phase_keyword = any(keyword in text_lower for keyword in WEDDING_PHASE_KEYWORDS)
            if is_bold and has_phase_keyword and len(text) < 100:  # Sections are usually short
                is_section = True
        
        # Method 3: Contains time markers (e.g., "2:00 PM")
        if not is_section:
            has_time = TIME_PATTERN.search(text)
            if has_time and len(text) < 100:
                is_section = True
        
        # Method 4: All caps and contains phase keyword
        if not is_section:
            if text.isupper() and any(keyword in text_lower for keyword in WEDDING_PHASE_KEYWORDS):
                is_section = True
        
        # Method 5: Ends with colon and contains phase keyword
        if not is_section:
            if text.endswith(':') and any(keyword in text_lower for keyword in WEDDING_PHASE_KEYWORDS):
                is_section = True
        
        if is_section:
            section_count += 1
            section_indicators.append(text[:50])
    
    if section_count >= 5:
        return section_count, f"{section_count} timeline sections identified"
    elif section_count >= 3:
        return section_count, f"{section_count} sections found (need 5+ for full credit)"
    else:
        return section_count, f"Only {section_count} sections detected (need 5+)"


def count_shots(doc) -> tuple:
    """Count individual shot items in document"""
    shot_count = 0
    heading_styles = {'Heading 1', 'Heading 2', 'Heading 3', 'Heading 4', 'Heading 5', 'Heading 6'}
    
    # Count meaningful content paragraphs/list items
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text or len(text) < 5:
            continue
        
        # Skip if it looks like a heading
        if para.style.name in heading_styles:
            continue
        
        # Skip if it looks like a section header
        text_lower = text.lower()
        is_likely_section = False
        
        # Check various section indicators
        if len(text) < 80:  # Sections are usually short
            # Contains time pattern
            if TIME_PATTERN.search(text):
                is_likely_section = True
            # All caps
            elif text.isupper():
                is_likely_section = True
            # Ends with colon
            elif text.endswith(':'):
                is_likely_section = True
            # Contains phase keyword and is bold
            elif any(keyword in text_lower for keyword in WEDDING_PHASE_KEYWORDS):
                is_bold = any(run.bold for run in para.runs if run.text.strip())
                if is_bold:
                    is_likely_section = True
        
        if is_likely_section:
            continue
        
        # Skip metadata/notes that aren't shots
        skip_keywords = [
            "venue:", "location:", "notes:", "equipment:", "client priorities:",
            "ceremony starts", "golden hour:", "second shooter:", "backup",
            "rosewood gardens", "oak street"
        ]
        if any(skip in text_lower for skip in skip_keywords):
            continue
        
        # Count this as a shot
        shot_count += 1
    
    if shot_count >= 18:
        return shot_count, f"{shot_count} shots listed"
    elif shot_count >= 12:
        return shot_count, f"{shot_count} shots listed (need 18+ for full credit)"
    else:
        return shot_count, f"Only {shot_count} shots listed (need 18+)"


def check_priority_shots(doc) -> tuple:
    """Check for priority shot markers"""
    priority_count = 0
    priority_examples = []
    
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text or len(text) < 5:
            continue
        
        # Skip if it's a heading
        if para.style.name and 'Heading' in para.style.name:
            continue
        
        text_lower = text.lower()
        is_priority = False
        
        # Method 1: Contains priority keywords
        has_keyword = any(keyword in text_lower for keyword in PRIORITY_KEYWORDS)
        
        # Method 2: Text is bold
        is_bold = False
        # Check if entire paragraph is bold or significant portion
        bold_chars = sum(len(run.text) for run in para.runs if run.bold and run.text.strip())
        total_chars = len(text)
        if total_chars > 0 and bold_chars / total_chars > 0.5:
            is_bold = True
        
        # Method 3: Contains [PRIORITY] or similar markers
        has_marker = any(marker in text_lower for marker in ["[priority]", "[important]", "[critical]", "[must]"])
        
        if has_keyword or is_bold or has_marker:
            is_priority = True
        
        # Also check if this looks like it could be a priority shot from original notes
        original_priority_indicators = ["ceremony entrance", "first kiss", "first dance", "vows exchange", "father"]
        if any(indicator in text_lower for indicator in original_priority_indicators):
            if is_bold or has_keyword:
                is_priority = True
        
        if is_priority:
            priority_count += 1
            priority_examples.append(text[:60])
    
    if priority_count >= 3:
        return priority_count, f"{priority_count} priority shots marked"
    elif priority_count >= 2:
        return priority_count, f"{priority_count} priority shots (need 3+ for full credit)"
    else:
        examples = f" (e.g., {priority_examples[0]})" if priority_examples else ""
        return priority_count, f"Only {priority_count} priority shots detected{examples}"


def check_list_usage(doc) -> tuple:
    """Check if shots are formatted as lists"""
    total_content_items = 0
    list_items = 0
    
    heading_styles = {'Heading 1', 'Heading 2', 'Heading 3', 'Heading 4', 'Heading 5', 'Heading 6'}
    list_style_indicators = ['List', 'Bullet', 'Numbered']
    
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text or len(text) < 5:
            continue
        
        # Skip headings
        if para.style.name in heading_styles:
            continue
        
        # Skip section headers (same logic as count_shots)
        if len(text) < 80:
            text_lower = text.lower()
            if (TIME_PATTERN.search(text) or 
                text.isupper() or 
                text.endswith(':') or
                any(skip in text_lower for skip in ["venue:", "notes:", "equipment:", "location:"])):
                continue
        
        # This is a content item
        total_content_items += 1
        
        # Check if it's a list item
        style_name = para.style.name if para.style.name else ""
        if any(indicator in style_name for indicator in list_style_indicators):
            list_items += 1
    
    if total_content_items == 0:
        return 0.0, "No content items found"
    
    ratio = list_items / total_content_items
    percentage = int(ratio * 100)
    
    if ratio >= 0.50:
        return ratio, f"{percentage}% of content uses lists"
    elif ratio >= 0.30:
        return ratio, f"{percentage}% of content uses lists (need 50%+ for full credit)"
    else:
        return ratio, f"Only {percentage}% of content uses lists (need 50%+)"


def check_creative_content(doc) -> tuple:
    """Check for production notes or creative additions beyond raw notes"""
    full_text = get_document_text(doc).lower()
    
    found_elements = []
    
    # Production/technical keywords that wouldn't be in raw notes
    production_keywords = [
        "lens", "mm", "35mm", "50mm", "70-200", "24-70",
        "gimbal", "stabilizer", "slider", "jib",
        "lighting setup", "reflector", "diffuser",
        "b-roll", "cutaway", "insert shot",
        "slow motion", "slo-mo", "120fps", "60fps",
        "drone shot", "aerial", "overhead",
        "shallow depth", "bokeh", "depth of field",
        "natural light", "backlit", "backlight", "rim light",
        "color grade", "log profile", "flat picture",
        "lavalier", "lav mic", "boom", "audio recorder",
        "focus pull", "rack focus", "follow focus"
    ]
    
    found_production = [kw for kw in production_keywords if kw in full_text]
    
    # Creative shot ideas that suggest thinking beyond the checklist
    creative_indicators = [
        "sunset silhouette", "twilight", "dusk",
        "reflection", "mirror shot", "through",
        "shadow play", "shadow", "contrast",
        "candlelight", "low light", "ambient",
        "motion blur", "movement",
        "intimate moment", "quiet moment", "tender",
        "detail macro", "extreme closeup", "ring detail",
        "emotional reaction", "tears", "joy",
        "dancing crowd", "celebration", "energy",
        "architectural", "symmetry", "leading lines",
        "foreground element", "frame within frame",
        "texture", "fabric detail", "lace detail"
    ]
    
    found_creative = [ci for ci in creative_indicators if ci in full_text]
    
    # Specific shot ideas not in original notes
    unique_shots = [
        "sunset", "twilight", "dusk", "night",
        "sparklers", "send-off", "exit",
        "ring bearer", "flower girl",
        "getting ready detail", "dress hanging",
        "shoes", "jewelry", "accessories",
        "venue detail", "architecture", "decor",
        "table setting", "centerpiece", "place card",
        "ceremony program", "invitation",
        "first look", "before ceremony",
        "cocktail", "appetizer", "food",
        "band", "musicians", "entertainment",
        "dance floor", "crowd dancing",
        "parent dance", "mother-son", "father-daughter dance",
        "toasts", "champagne", "clinking glasses"
    ]
    
    found_unique = [us for us in unique_shots if us in full_text]
    
    # Check for any evidence of production thinking
    if found_production:
        found_elements.append(f"Production notes: {', '.join(found_production[:2])}")
    
    if found_creative:
        found_elements.append(f"Creative direction: {', '.join(found_creative[:2])}")
    
    if found_unique:
        found_elements.append(f"Additional shots: {', '.join(found_unique[:2])}")
    
    # Need at least 2 different types of additions OR 3+ production keywords
    has_sufficient_creative = (len(found_elements) >= 2) or (len(found_production) >= 3)
    
    if has_sufficient_creative:
        return True, " | ".join(found_elements) if found_elements else "Production thinking detected"
    else:
        if found_elements:
            return False, f"Some creative content ({', '.join(found_elements[:1])}) but need more"
        else:
            return False, "No production notes or creative additions beyond raw notes"
