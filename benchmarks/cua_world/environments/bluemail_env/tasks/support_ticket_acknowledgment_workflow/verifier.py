#!/usr/bin/env python3
"""
Verifier for support_ticket_acknowledgment_workflow.

Checks:
1. 'Tickets-Created' folder exists and contains 3 emails.
2. 3 Replies sent.
3. Replies follow the template.
4. Replies use unique random IDs.
5. Replies address the sender by name.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_support_ticket_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
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

    # Requirements
    target_count = 3
    
    # 1. Folder Verification (10 pts + 20 pts)
    if result.get('tickets_folder_exists', False):
        score += 10
        feedback.append("Folder 'Tickets-Created' created.")
    else:
        feedback.append("Folder 'Tickets-Created' NOT found.")

    processed_count = result.get('processed_count', 0)
    if processed_count >= target_count:
        score += 20
        feedback.append(f"Correctly moved {processed_count} emails.")
    elif processed_count > 0:
        score += int((processed_count / target_count) * 20)
        feedback.append(f"Moved {processed_count}/{target_count} emails.")
    else:
        feedback.append("No emails moved to target folder.")

    # 2. Sent Verification (20 pts)
    sent_emails = result.get('sent_emails', [])
    sent_count = len(sent_emails)
    
    # Filter sent emails to only those relevant to the moved emails
    # This matches Sent 'To' with Processed 'From'
    # Simple normalization of email addresses
    def extract_email(s):
        match = re.search(r'<([^>]+)>', s)
        return match.group(1).lower() if match else s.lower()

    processed_senders = set()
    for e in result.get('processed_emails', []):
        processed_senders.add(extract_email(e.get('from', '')))

    relevant_sent = []
    for e in sent_emails:
        to_addr = extract_email(e.get('to', ''))
        # Allow fuzzy match or direct match
        if any(p in to_addr or to_addr in p for p in processed_senders):
            relevant_sent.append(e)
    
    # If we can't match strictly, fall back to just counting new sent emails (agent might have replied to different ones)
    if len(relevant_sent) < sent_count and sent_count == target_count:
        relevant_sent = sent_emails

    if len(relevant_sent) >= target_count:
        score += 20
        feedback.append(f"Sent {len(relevant_sent)} replies.")
    else:
        partial = int((len(relevant_sent) / target_count) * 20)
        score += partial
        feedback.append(f"Sent {len(relevant_sent)}/{target_count} replies.")

    # 3. Template Compliance (20 pts)
    # Template: "Reference Ticket ID: [ID]"
    # Phrases: "automated acknowledgment", "review your inquiry shortly"
    template_score = 0
    ids_found = []
    
    for email_obj in relevant_sent:
        body = email_obj.get('body', '')
        
        # Check standard phrases
        phrases_hit = 0
        if "automated acknowledgment" in body: phrases_hit += 1
        if "review your inquiry shortly" in body: phrases_hit += 1
        if "Reference Ticket ID:" in body: phrases_hit += 1
        
        # Check ID format
        id_match = re.search(r'Reference Ticket ID:\s*(\d{4})', body)
        if id_match:
            ids_found.append(id_match.group(1))
            phrases_hit += 1 # Bonus for correct ID syntax
        
        # Max 4 points per email for template compliance -> 12 pts total?
        # Let's just average it.
        # We need ~6.6 pts per email to reach 20 total.
        
        if phrases_hit >= 3:
            template_score += (20 / target_count)
        elif phrases_hit > 0:
            template_score += (10 / target_count)

    score += int(template_score)
    if template_score > 15:
        feedback.append("Template followed correctly.")

    # 4. Unique IDs (15 pts)
    unique_ids = set(ids_found)
    if len(unique_ids) >= target_count:
        score += 15
        feedback.append("Unique IDs used for all tickets.")
    elif len(unique_ids) > 0:
        score += 5
        feedback.append(f"Repeated or missing IDs found (found {len(unique_ids)} unique).")
    else:
        feedback.append("No Ticket IDs found in replies.")

    # 5. Name Personalization (15 pts)
    # Check if "Dear [Name]" matches the To field
    personalization_score = 0
    for email_obj in relevant_sent:
        body = email_obj.get('body', '')
        to_header = email_obj.get('to', '') # e.g. "John Doe <john@example.com>"
        
        # Extract greeting name
        greeting_match = re.search(r'Dear\s+([^,\n]+)', body)
        if greeting_match:
            greeting_name = greeting_match.group(1).strip().lower()
            
            # Extract expected name parts
            # Remove email part <...>
            name_part = re.sub(r'<[^>]+>', '', to_header).strip().lower()
            
            # Check overlap
            if greeting_name in name_part or name_part in greeting_name:
                personalization_score += (15 / target_count)
            # Fallback: check against email user part
            elif extract_email(to_header).split('@')[0] in greeting_name:
                personalization_score += (15 / target_count)
                
    score += int(personalization_score)
    if personalization_score > 10:
        feedback.append("Personalization verified.")

    # Final Check
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }