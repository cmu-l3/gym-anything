#!/usr/bin/env python3
"""
Verifier for Freelance Tier Proposal task

Checks that the agent created a professional proposal document with:
1. Valid DOCX file exists
2. Proposal context (title/heading indicating a proposal)
3. Three distinct pricing tiers with different names
4. Pricing information for each tier
5. Structured formatting (tables or lists)
6. Basic formatting applied (headings, bold, etc.)
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, List, Tuple, Set

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_tier_keywords(text: str) -> List[str]:
    """
    Extract potential tier naming patterns from text.
    Returns list of found tier indicators.
    """
    text_lower = text.lower()
    found_tiers = []
    
    # Define tier naming patterns (category name, list of variants)
    tier_patterns = [
        # Basic/Standard/Premium pattern
        (["basic", "standard", "premium"], "Basic/Standard/Premium"),
        # Tier numbers
        (["tier 1", "tier 2", "tier 3", "tier one", "tier two", "tier three"], "Tier 1/2/3"),
        # Metal tiers
        (["bronze", "silver", "gold"], "Bronze/Silver/Gold"),
        # Options
        (["option a", "option b", "option c", "option 1", "option 2", "option 3"], "Option A/B/C"),
        # Professional naming
        (["essential", "professional", "complete"], "Essential/Professional/Complete"),
        (["starter", "growth", "enterprise"], "Starter/Growth/Enterprise"),
        (["lite", "pro", "ultimate"], "Lite/Pro/Ultimate"),
        (["small", "medium", "large"], "Small/Medium/Large"),
        # Package naming
        (["package a", "package b", "package c", "package 1", "package 2", "package 3"], "Package A/B/C"),
        # Plan naming
        (["plan a", "plan b", "plan c", "plan 1", "plan 2", "plan 3"], "Plan A/B/C"),
    ]
    
    for variants, category_name in tier_patterns:
        matches_in_category = []
        for variant in variants:
            if variant in text_lower:
                matches_in_category.append(variant)
        
        # If we found at least 2 variants from this category, consider it a match
        if len(matches_in_category) >= 2:
            found_tiers.extend(matches_in_category)
    
    return found_tiers


def extract_prices(text: str) -> List[float]:
    """
    Extract dollar amounts from text.
    Returns list of numeric prices found.
    """
    prices = []
    
    # Pattern 1: $XXX or $XXX.XX
    pattern1 = r'\$\s*(\d+(?:,\d{3})*(?:\.\d{2})?)'
    matches1 = re.findall(pattern1, text)
    for match in matches1:
        try:
            price = float(match.replace(',', ''))
            prices.append(price)
        except:
            pass
    
    # Pattern 2: XXX USD or XXX dollars
    pattern2 = r'(\d+(?:,\d{3})*(?:\.\d{2})?)\s*(?:USD|usd|dollars?|Dollars?)'
    matches2 = re.findall(pattern2, text)
    for match in matches2:
        try:
            price = float(match.replace(',', ''))
            if price not in prices:  # Avoid duplicates
                prices.append(price)
        except:
            pass
    
    # Pattern 3: Price: XXX or Cost: XXX
    pattern3 = r'(?:price|cost|Price|Cost):\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d{2})?)'
    matches3 = re.findall(pattern3, text)
    for match in matches3:
        try:
            price = float(match.replace(',', ''))
            if price not in prices:
                prices.append(price)
        except:
            pass
    
    return prices


def check_has_lists(doc) -> bool:
    """
    Check if document contains bullet points or numbered lists.
    """
    try:
        for para in doc.paragraphs:
            # Check if paragraph is part of a list
            if para.style.name.startswith('List') or 'List' in para.style.name:
                return True
            # Check for bullet point characters
            if para.text.strip().startswith('•') or para.text.strip().startswith('-'):
                return True
            # Check for numbered list patterns
            if re.match(r'^\d+[\.)]\s+', para.text.strip()):
                return True
    except Exception as e:
        logger.warning(f"Error checking for lists: {e}")
    
    return False


def check_has_formatting(doc) -> bool:
    """
    Check if document has intentional formatting (headings, bold, etc.).
    """
    try:
        # Check for heading styles
        for para in doc.paragraphs:
            if 'Heading' in para.style.name:
                return True
            
            # Check for bold or italic runs
            for run in para.runs:
                if run.bold or run.italic:
                    return True
                if run.font.size and run.font.size.pt > 12:  # Larger than default
                    return True
    except Exception as e:
        logger.warning(f"Error checking formatting: {e}")
    
    return False


def verify_proposal_document(traj, env_info, task_info):
    """
    Verify that freelance tier proposal was created correctly.

    Scoring breakdown:
    - Document exists and readable: 15%
    - Contains proposal context: 15%
    - Three distinct tiers identified: 25%
    - Pricing information present: 20%
    - Structured format (table/lists): 15%
    - Basic formatting applied: 10%
    
    Passing threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/client_proposal.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_proposal_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False, 
                "score": 0.0, 
                "feedback": f"Failed to load proposal document: {error}"
            }

        score = 0.0
        feedback_parts = []
        
        # Extract full document text for analysis
        doc_text = get_document_text(doc)
        
        # ===== Criterion 1: Document exists and has content (15%) =====
        if len(doc_text) >= 200:
            score += 15.0
            feedback_parts.append(f"✅ Document has substantial content ({len(doc_text)} chars)")
        elif len(doc_text) >= 100:
            score += 10.0
            feedback_parts.append(f"⚠️ Document has minimal content ({len(doc_text)} chars)")
        else:
            feedback_parts.append(f"❌ Document is too short ({len(doc_text)} chars, need 200+)")
        
        # ===== Criterion 2: Contains proposal context (15%) =====
        proposal_keywords = [
            "proposal", "pricing", "services", "packages", "options",
            "service packages", "pricing options", "quote", "estimate"
        ]
        found_proposal_keywords = [kw for kw in proposal_keywords if kw in doc_text.lower()]
        
        if len(found_proposal_keywords) >= 2:
            score += 15.0
            feedback_parts.append(f"✅ Document has proposal context (found: {', '.join(found_proposal_keywords[:3])})")
        elif len(found_proposal_keywords) >= 1:
            score += 10.0
            feedback_parts.append(f"⚠️ Weak proposal context (found: {', '.join(found_proposal_keywords)})")
        else:
            # Check for business-like language as fallback
            business_keywords = ["client", "deliverable", "service", "package", "tier", "option"]
            found_business = [kw for kw in business_keywords if kw in doc_text.lower()]
            if len(found_business) >= 2:
                score += 8.0
                feedback_parts.append(f"⚠️ Has business language but no explicit proposal markers")
            else:
                feedback_parts.append("❌ Missing proposal context keywords")
        
        # ===== Criterion 3: Three distinct tiers (25%) =====
        tier_keywords = extract_tier_keywords(doc_text)
        unique_tiers = len(set(tier_keywords))
        
        if unique_tiers >= 3:
            score += 25.0
            feedback_parts.append(f"✅ Found {unique_tiers} distinct pricing tiers")
        elif unique_tiers == 2:
            score += 15.0
            feedback_parts.append(f"⚠️ Found only {unique_tiers} tiers (need 3)")
        elif unique_tiers == 1:
            score += 8.0
            feedback_parts.append(f"⚠️ Found only {unique_tiers} tier (need 3)")
        else:
            feedback_parts.append("❌ No clear pricing tiers identified")
        
        # ===== Criterion 4: Pricing information (20%) =====
        prices = extract_prices(doc_text)
        unique_prices = len(set(prices))
        
        if unique_prices >= 3:
            # Check if prices are meaningfully different (not just $1, $2, $3)
            prices_sorted = sorted(set(prices))
            if max(prices_sorted) > 100 or (max(prices_sorted) - min(prices_sorted) > 50):
                score += 20.0
                feedback_parts.append(f"✅ Found {unique_prices} distinct prices: {', '.join(['$' + str(int(p)) for p in prices_sorted[:3]])}")
            else:
                score += 15.0
                feedback_parts.append(f"⚠️ Found {unique_prices} prices but they seem like placeholders")
        elif unique_prices == 2:
            score += 10.0
            feedback_parts.append(f"⚠️ Found only {unique_prices} prices (need 3+)")
        elif unique_prices == 1:
            score += 5.0
            feedback_parts.append(f"⚠️ Found only {unique_prices} price (need 3+)")
        else:
            feedback_parts.append("❌ No pricing information found")
        
        # ===== Criterion 5: Structured format - tables or lists (15%) =====
        table_count = count_tables(doc)
        has_lists = check_has_lists(doc)
        
        if table_count >= 1:
            score += 15.0
            feedback_parts.append(f"✅ Document uses tables for structure ({table_count} table(s))")
        elif has_lists:
            score += 15.0
            feedback_parts.append("✅ Document uses formatted lists for structure")
        else:
            # Check for any structural indicators in text
            if "\n" in doc_text and len(doc_text.split("\n")) > 10:
                score += 8.0
                feedback_parts.append("⚠️ Document has paragraphs but no clear table/list structure")
            else:
                feedback_parts.append("❌ No structured format (tables or lists) detected")
        
        # ===== Criterion 6: Basic formatting (10%) =====
        has_formatting = check_has_formatting(doc)
        
        if has_formatting:
            score += 10.0
            feedback_parts.append("✅ Document has formatting (headings/bold/sizing)")
        else:
            feedback_parts.append("❌ No formatting detected (all plain text)")
        
        # ===== Final assessment =====
        passed = score >= 70.0
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Proposal verification - Score: {score:.1f}/100, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
