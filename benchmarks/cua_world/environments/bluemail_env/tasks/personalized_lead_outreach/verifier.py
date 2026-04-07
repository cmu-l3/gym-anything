#!/usr/bin/env python3
"""
Verifier for personalized_lead_outreach task.

Scoring Breakdown (100 pts total):
1. Candidates Folder (20 pts):
   - Folder exists (10)
   - Contains 3+ emails (10)
2. CSV Log (30 pts):
   - File exists (10)
   - Header correct (5)
   - Data matches emails in Candidates folder (15)
3. Outreach Emails (50 pts):
   - 3 sent emails found to correct recipients (20)
   - Personalization check (Name + Topic) (30)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for comparison (lower case, remove special chars)."""
    if not text: return ""
    return re.sub(r'[^a-z0-9\s]', '', text.lower())

def verify_personalized_lead_outreach(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Unpack data
    csv_exists = result.get('csv_exists', False)
    csv_data = result.get('csv_data', [])
    candidates_exists = result.get('candidates_folder_exists', False)
    candidates_emails = result.get('candidates_emails', [])
    sent_emails = result.get('sent_emails', [])
    task_start_ts = result.get('task_start_ts', 0)
    csv_mtime = result.get('csv_mtime', 0)

    # ---------------------------------------------------------
    # Criterion 1: Candidates Folder (20 pts)
    # ---------------------------------------------------------
    if candidates_exists:
        score += 10
        feedback.append("Candidates folder created.")
        
        # Check uniqueness of authors
        unique_senders = set()
        for eml in candidates_emails:
            if eml.get('from_email'):
                unique_senders.add(eml['from_email'].lower())
        
        if len(unique_senders) >= 3:
            score += 10
            feedback.append(f"Folder contains {len(unique_senders)} unique candidates.")
        else:
            feedback.append(f"Folder contains {len(unique_senders)} candidates (need 3 distinct).")
    else:
        feedback.append("Candidates folder NOT found.")

    # ---------------------------------------------------------
    # Criterion 2: CSV Log (30 pts)
    # ---------------------------------------------------------
    if csv_exists:
        # Anti-gaming: Check if file was modified during task
        if csv_mtime > task_start_ts:
            score += 10
            feedback.append("CSV file created/modified during task.")
            
            # Check content
            if len(csv_data) >= 3:
                # Validate columns
                first_row = csv_data[0]
                if 'name' in first_row and 'email' in first_row and 'topic' in first_row:
                    score += 5
                    feedback.append("CSV header correct.")
                    
                    # Cross-reference with Candidates Folder
                    # We expect the CSV to list the people whose emails are in the folder
                    matches = 0
                    folder_emails = {e.get('from_email', '').lower(): e for e in candidates_emails}
                    
                    for row in csv_data:
                        csv_email = row.get('email', '').strip().lower()
                        csv_topic = row.get('topic', '').strip().lower()
                        
                        if csv_email in folder_emails:
                            # Verify topic matches subject (fuzzy match)
                            real_subject = folder_emails[csv_email].get('subject', '').lower()
                            if normalize_text(csv_topic) == normalize_text(real_subject):
                                matches += 1
                            elif len(csv_topic) > 5 and csv_topic in real_subject:
                                matches += 1 # Partial match accepted
                    
                    if matches >= 3:
                        score += 15
                        feedback.append("CSV data accurately matches folder contents.")
                    elif matches > 0:
                        score += 5
                        feedback.append(f"CSV partial match ({matches}/3). Check topic/email accuracy.")
                    else:
                        feedback.append("CSV data does not match folder contents.")
                else:
                    feedback.append(f"CSV missing required columns (Name,Email,Topic). Found: {list(first_row.keys())}")
            else:
                feedback.append(f"CSV has insufficient rows ({len(csv_data)}).")
        else:
            feedback.append("CSV file existed before task start (stale).")
    else:
        feedback.append("CSV file NOT found.")

    # ---------------------------------------------------------
    # Criterion 3: Outreach Emails (50 pts)
    # ---------------------------------------------------------
    # Map sent emails by recipient
    sent_map = {} # Recipient Email -> [Email Objects]
    for eml in sent_emails:
        # Extract recipient email from "To" header
        import email.utils
        _, to_addr = email.utils.parseaddr(eml.get('to', ''))
        to_addr = to_addr.lower()
        if to_addr not in sent_map:
            sent_map[to_addr] = []
        sent_map[to_addr].append(eml)

    # We need to verify that for each candidate in the folder/CSV, a tailored email was sent
    # We use the candidates_emails as the source of truth for "who should be emailed"
    
    valid_outreach_count = 0
    personalization_score = 0
    
    # Target candidates are those in the folder
    folder_candidates = {e.get('from_email', '').lower(): e for e in candidates_emails if e.get('from_email')}
    
    # Only evaluate top 3 if more exist
    targets = list(folder_candidates.items())[:3]
    
    for email_addr, original_email in targets:
        if email_addr in sent_map:
            # Found a sent email to this candidate
            sent_msgs = sent_map[email_addr]
            # Take the most recent one
            sent_msg = sent_msgs[-1]
            sent_body = sent_msg.get('body', '').lower()
            original_subject = original_email.get('subject', '').lower()
            original_name = original_email.get('from_name', '').lower()
            
            # Check 1: Was an email sent?
            valid_outreach_count += 1
            
            # Check 2: Subject Line (Task requested "Community Contribution Recognition")
            # We'll be lenient and allow similar subjects
            if "contribution" in sent_msg.get('subject', '').lower():
                pass # Good
                
            # Check 3: Personalization (Name)
            name_parts = normalize_text(original_name).split()
            name_found = False
            for part in name_parts:
                if len(part) > 2 and part in normalize_text(sent_body):
                    name_found = True
                    break
            
            # Check 4: Context (Original Topic)
            # We check if significant words from the original subject appear in the body
            # Filter out common stop words
            stop_words = {'re', 'fwd', 'the', 'and', 'for', 'that', 'with', 'about', 'from', 'this'}
            subj_words = [w for w in normalize_text(original_subject).split() if w not in stop_words and len(w) > 3]
            
            topic_found = False
            for word in subj_words:
                if word in normalize_text(sent_body):
                    topic_found = True
                    break
            
            if name_found and topic_found:
                personalization_score += 10
                feedback.append(f"Perfect personalization for {email_addr}")
            elif topic_found:
                personalization_score += 5
                feedback.append(f"Context found but name missing for {email_addr}")
            elif name_found:
                personalization_score += 5
                feedback.append(f"Name found but context missing for {email_addr}")
            else:
                feedback.append(f"Generic email sent to {email_addr} (no context/name)")
        else:
            feedback.append(f"No email sent to candidate {email_addr}")

    # Score calculation for emails
    # Max 20 pts for sending emails (approx 6.6 pts per email)
    score += int((valid_outreach_count / 3) * 20)
    
    # Max 30 pts for personalization (accumulated above)
    score += min(30, personalization_score)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }