#!/usr/bin/env python3
"""
Verifier for capture_departing_knowledge@1
Checks that tribal knowledge was properly documented in code and guide document
"""

import sys
import os
import re
import logging
import tempfile
import shutil
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that departing knowledge was captured via inline docs and guide document.
    
    Returns:
        dict with keys: passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='knowledge_verify_')
    
    try:
        workspace_base = "/home/ga/workspace/payment_api"
        processor_file_path = f"{workspace_base}/payment_processor.py"
        guide_file_path = f"{workspace_base}/PAYMENT_SYSTEM_GUIDE.md"
        
        local_processor = os.path.join(temp_dir, "payment_processor.py")
        local_guide = os.path.join(temp_dir, "PAYMENT_SYSTEM_GUIDE.md")
        
        feedback = {}
        score = 0.0
        max_score = 100.0
        
        # Copy files from container
        try:
            copy_from_env(processor_file_path, local_processor)
        except Exception as e:
            logger.error(f"Failed to copy payment_processor.py: {e}")
            return {"passed": False, "score": 0, "feedback": f"payment_processor.py not found or inaccessible: {str(e)}"}
        
        try:
            copy_from_env(guide_file_path, local_guide)
            guide_exists = True
        except Exception as e:
            logger.warning(f"Failed to copy PAYMENT_SYSTEM_GUIDE.md: {e}")
            guide_exists = False
        
        # Read processor file
        if not os.path.exists(local_processor) or os.path.getsize(local_processor) == 0:
            return {"passed": False, "score": 0, "feedback": "payment_processor.py is empty or not found"}
        
        with open(local_processor, 'r', encoding='utf-8') as f:
            processor_content = f.read()
        
        # Part 1: Inline documentation (40 points)
        inline_score = 0.0
        
        # Check for docstrings (triple-quoted strings after function definitions)
        docstring_pattern = r'def\s+\w+\([^)]*\):\s*\n\s*"""'
        docstrings = re.findall(docstring_pattern, processor_content)
        docstring_count = len(docstrings)
        
        if docstring_count >= 5:
            inline_score += 10.0
            feedback["docstrings"] = f"✅ Found {docstring_count} function docstrings"
        elif docstring_count >= 3:
            inline_score += 6.0
            feedback["docstrings"] = f"⚠️ Found {docstring_count} docstrings (need 5+)"
        else:
            feedback["docstrings"] = f"❌ Only {docstring_count} docstrings (need 5+)"
        
        # Check for explanatory WHY comments
        why_keywords = ["why", "because", "reason", "rationale", "decision", 
                        "gotcha", "important", "critical", "note", "warning",
                        "issue", "incident", "bug", "problem", "never", "always"]
        comment_lines = [line for line in processor_content.split('\n') if '#' in line]
        why_comments = [c for c in comment_lines 
                       if any(kw in c.lower() for kw in why_keywords)]
        
        if len(why_comments) >= 8:
            inline_score += 12.0
            feedback["why_comments"] = f"✅ Found {len(why_comments)} explanatory comments"
        elif len(why_comments) >= 5:
            inline_score += 8.0
            feedback["why_comments"] = f"⚠️ Found {len(why_comments)} explanatory comments (need 8+)"
        else:
            feedback["why_comments"] = f"❌ Only {len(why_comments)} explanatory comments (need 8+)"
        
        # Check for WARNING comments
        warning_count = processor_content.upper().count("WARNING")
        warning_count += processor_content.upper().count("CAUTION")
        warning_count += processor_content.upper().count("CRITICAL")
        
        if warning_count >= 2:
            inline_score += 10.0
            feedback["warnings"] = f"✅ Found {warning_count} WARNING/CRITICAL markers"
        elif warning_count >= 1:
            inline_score += 5.0
            feedback["warnings"] = f"⚠️ Found {warning_count} WARNING marker (need 2+)"
        else:
            feedback["warnings"] = "❌ No WARNING/CRITICAL markers found"
        
        # Check for TODO comments
        todo_count = processor_content.upper().count("TODO")
        todo_count += processor_content.upper().count("FIXME")
        
        if todo_count >= 1:
            inline_score += 8.0
            feedback["todos"] = f"✅ Found {todo_count} TODO/FIXME marker(s)"
        else:
            feedback["todos"] = "❌ No TODO/FIXME markers found"
        
        score += inline_score
        
        # Part 2: Guide document (35 points)
        guide_score = 0.0
        
        if not guide_exists or not os.path.exists(local_guide):
            feedback["guide_exists"] = "❌ PAYMENT_SYSTEM_GUIDE.md not found"
        else:
            guide_score += 5.0
            feedback["guide_exists"] = "✅ Guide document created"
            
            with open(local_guide, 'r', encoding='utf-8') as f:
                guide_content = f.read()
            
            # Check for gotchas/issues section
            has_gotchas = any(term in guide_content.lower() 
                             for term in ["gotcha", "known issue", "common issue", 
                                         "pitfall", "watch out", "careful", "common problem"])
            if has_gotchas:
                guide_score += 10.0
                feedback["gotchas_section"] = "✅ Has gotchas/known issues section"
            else:
                feedback["gotchas_section"] = "❌ No gotchas/known issues section found"
            
            # Check for file references
            referenced_files = []
            for file in ["webhook_handler", "refund_logic", "fraud_checker"]:
                if file in guide_content:
                    referenced_files.append(file)
            
            if len(referenced_files) >= 3:
                guide_score += 8.0
                feedback["file_refs"] = f"✅ References {len(referenced_files)} related files"
            elif len(referenced_files) >= 2:
                guide_score += 5.0
                feedback["file_refs"] = f"⚠️ References {len(referenced_files)} files (need 3+)"
            else:
                feedback["file_refs"] = f"❌ Only references {len(referenced_files)} files (need 3+)"
            
            # Check for external links
            url_pattern = r'https?://[\w\./\-#?=&%]+'
            urls = re.findall(url_pattern, guide_content)
            
            if len(urls) >= 1:
                guide_score += 6.0
                feedback["external_links"] = f"✅ Has {len(urls)} external resource link(s)"
            else:
                feedback["external_links"] = "❌ No external resource links found"
            
            # Check for contact/troubleshooting info
            has_contact = any(term in guide_content.lower() 
                             for term in ["contact", "support", "on-call", "email", 
                                         "troubleshoot", "help"]) or '@' in guide_content
            if has_contact:
                guide_score += 6.0
                feedback["contact_info"] = "✅ Has contact/troubleshooting information"
            else:
                feedback["contact_info"] = "❌ No contact/troubleshooting information"
        
        score += guide_score
        
        # Part 3: Documentation quality (25 points)
        quality_score = 0.0
        
        # Check docstring format (proper triple quotes with content)
        proper_docstrings = re.findall(
            r'def\s+\w+\([^)]*\):\s*\n\s*"""[^"]{10,}"""', 
            processor_content, 
            re.MULTILINE | re.DOTALL
        )
        if len(proper_docstrings) >= 3:
            quality_score += 8.0
            feedback["docstring_format"] = "✅ Docstrings follow Python conventions"
        elif len(proper_docstrings) >= 1:
            quality_score += 4.0
            feedback["docstring_format"] = "⚠️ Some docstrings follow conventions"
        else:
            feedback["docstring_format"] = "❌ Docstrings don't follow Python conventions"
        
        # Check that comments explain WHY not WHAT (heuristic: avoid obvious comments)
        obvious_patterns = [
            r'#\s*loop', r'#\s*return', r'#\s*call', r'#\s*set', 
            r'#\s*get', r'#\s*initialize', r'#\s*create', r'#\s*check'
        ]
        obvious_comments = sum(
            1 for pattern in obvious_patterns 
            if re.search(pattern, processor_content, re.IGNORECASE)
        )
        
        total_comments = len(comment_lines)
        if total_comments > 0:
            non_obvious_ratio = 1.0 - (obvious_comments / total_comments)
            if non_obvious_ratio >= 0.8:
                quality_score += 7.0
                feedback["comment_quality"] = "✅ Comments focus on WHY not WHAT"
            elif non_obvious_ratio >= 0.6:
                quality_score += 4.0
                feedback["comment_quality"] = "⚠️ Some obvious comments present"
            else:
                feedback["comment_quality"] = "❌ Too many obvious WHAT comments"
        
        # Check for proper cross-references in guide
        if guide_exists and os.path.exists(local_guide):
            with open(local_guide, 'r', encoding='utf-8') as f:
                guide_content = f.read()
            
            cross_refs = re.findall(r'`[\w_/\.]+`', guide_content)
            if len(cross_refs) >= 5:
                quality_score += 5.0
                feedback["cross_refs"] = "✅ Good use of cross-references"
            elif len(cross_refs) >= 2:
                quality_score += 3.0
                feedback["cross_refs"] = "⚠️ Some cross-references present"
            else:
                feedback["cross_refs"] = "❌ Few/no proper cross-references"
            
            # Check readability (reasonable line length)
            guide_lines = guide_content.split('\n')
            non_empty_lines = [l for l in guide_lines if l.strip()]
            if non_empty_lines:
                avg_line_length = sum(len(l) for l in non_empty_lines) / len(non_empty_lines)
                
                # Good documentation has reasonable line length (20-120 chars average)
                if 20 <= avg_line_length <= 120:
                    quality_score += 5.0
                    feedback["readability"] = "✅ Documentation is well-formatted"
                else:
                    quality_score += 2.0
                    feedback["readability"] = "⚠️ Formatting could be improved"
        
        score += quality_score
        
        # Normalize to 0-1
        final_score = score / max_score
        passed = final_score >= 0.70
        
        # Create summary feedback string
        feedback_parts = []
        for key, value in feedback.items():
            if key not in ["summary", "breakdown"]:
                feedback_parts.append(f"{key}: {value}")
        
        feedback_str = " | ".join(feedback_parts)
        breakdown_str = f"Inline docs: {inline_score:.0f}/40, Guide: {guide_score:.0f}/35, Quality: {quality_score:.0f}/25"
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": f"Score: {final_score:.2%} ({score:.0f}/{max_score:.0f}) | {breakdown_str} | {feedback_str}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
