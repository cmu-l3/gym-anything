#!/usr/bin/env python3
"""
Verifier for comprehensive_inbox_triage_and_report task.

Scoring (100 pts, pass threshold: 60):

  1. Active-Threads folder (10 pts)
     - Folder exists with name containing 'thread' or 'active'

  2. Thread email accuracy (25 pts)
     - Precision >= 75% AND recall >= 75% -> 25 pts
     - Precision >= 50% AND recall >= 50% -> 15 pts
     - Any correct placements -> 8 pts

  3. Security-Review folder (15 pts)
     - Folder exists (5 pts)
     - Has 4+ emails (5 pts), else 2+ (3 pts)
     - Recall >= 50% (5 pts)

  4. Report file (25 pts)
     - Exists at correct path (5 pts)
     - Contains '50' (total count) (5 pts)
     - Contains 2+ thread topic names (5 pts)
     - Contains 3+ full names from thread participants (5 pts)
     - Contains a consistency/verification line or matching subcounts (5 pts)

  5. Summary email (15 pts)
     - Email to engineering-manager@company.com (5 pts)
     - Subject contains relevant keywords (5 pts)
     - Body references most active thread topic (5 pts)

  6. Inbox reduction (10 pts)
     - Inbox reduced by 15+ emails (10 pts)
     - Inbox reduced by 8+ (5 pts)
"""

import json
import re
import tempfile


def verify_comprehensive_inbox_triage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # Load task result
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env('/tmp/task_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Failed to load task_result.json: {e}"}

    # Load ground truth
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            gt_path = tmp.name
        copy_from_env('/tmp/ground_truth.json', gt_path)
        with open(gt_path, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        gt = {}
        feedback_parts.append(f"Warning: could not load ground truth: {e}")

    # ── 1. Active-Threads folder exists (10 pts) ──
    tf = result.get('threads_folder', {})
    if tf.get('exists'):
        score += 10
        feedback_parts.append(f"Active-Threads folder '{tf.get('name')}' found (+10)")
    else:
        feedback_parts.append("Active-Threads folder not found (+0)")

    # ── 2. Thread email accuracy (25 pts) ──
    gt_thread_total = gt.get('total_thread_emails', 15)
    tp = tf.get('true_positives', 0)
    folder_count = tf.get('count', 0)

    if gt_thread_total > 0 and folder_count > 0:
        recall = tp / gt_thread_total
        precision = tp / folder_count
        if recall >= 0.75 and precision >= 0.75:
            score += 25
            feedback_parts.append(
                f"Thread accuracy: recall={recall:.0%}, precision={precision:.0%} (+25)")
        elif recall >= 0.50 and precision >= 0.50:
            score += 15
            feedback_parts.append(
                f"Thread accuracy: recall={recall:.0%}, precision={precision:.0%} (+15)")
        elif tp > 0:
            score += 8
            feedback_parts.append(
                f"Thread accuracy: {tp} correct placements (+8)")
        else:
            feedback_parts.append("Thread accuracy: no correct placements (+0)")
    elif tp > 0:
        score += 8
        feedback_parts.append(f"Thread accuracy: {tp} emails found (+8)")
    else:
        feedback_parts.append("Thread accuracy: no data (+0)")

    # ── 3. Security-Review folder (15 pts) ──
    sf = result.get('security_folder', {})
    gt_sec_count = gt.get('security_emails', {}).get('count', 8)

    if sf.get('exists'):
        score += 5
        feedback_parts.append(f"Security-Review folder '{sf.get('name')}' found (+5)")
    else:
        feedback_parts.append("Security-Review folder not found (+0)")

    sec_count = sf.get('count', 0)
    if sec_count >= 4:
        score += 5
        feedback_parts.append(f"Security folder has {sec_count} emails (+5)")
    elif sec_count >= 2:
        score += 3
        feedback_parts.append(f"Security folder has {sec_count} emails (+3)")
    else:
        feedback_parts.append(f"Security folder has {sec_count} emails (+0)")

    sec_tp = sf.get('true_positives', 0)
    if gt_sec_count > 0 and sec_tp > 0:
        sec_recall = sec_tp / gt_sec_count
        if sec_recall >= 0.50:
            score += 5
            feedback_parts.append(f"Security recall: {sec_recall:.0%} (+5)")
        else:
            feedback_parts.append(f"Security recall: {sec_recall:.0%} (+0)")
    else:
        feedback_parts.append("Security recall: no data (+0)")

    # ── 4. Report file (25 pts) ──
    report = result.get('report', {})
    report_content = report.get('content', '').lower()

    if report.get('exists') and report.get('created_during_task', False):
        score += 5
        feedback_parts.append("Report file exists and created during task (+5)")
    elif report.get('exists'):
        score += 3
        feedback_parts.append("Report file exists but may predate task (+3)")
    else:
        feedback_parts.append("Report file not found (+0)")

    # Check for total count '50'
    if re.search(r'\b50\b', report_content):
        score += 5
        feedback_parts.append("Report contains total count 50 (+5)")
    else:
        feedback_parts.append("Report missing total count (+0)")

    # Check for thread topic names
    thread_topic_keywords = ['solaris', 'mama', 'entrepreneur', 'muppet']
    topics_found = sum(1 for kw in thread_topic_keywords if kw in report_content)
    if topics_found >= 2:
        score += 5
        feedback_parts.append(f"Report mentions {topics_found} thread topics (+5)")
    else:
        feedback_parts.append(f"Report mentions {topics_found} thread topics (+0)")

    # Check for participant full names from ground truth
    gt_senders = set()
    for thread_data in gt.get('threads', {}).values():
        for sender in thread_data.get('senders', []):
            # Extract display name from "Name <email>" format
            match = re.match(r'^"?([^"<]+)"?\s*<?', sender)
            if match:
                name = match.group(1).strip()
                if len(name) > 3:
                    gt_senders.add(name.lower())
    names_found = sum(1 for name in gt_senders if name in report_content)
    if names_found >= 3:
        score += 5
        feedback_parts.append(f"Report contains {names_found} participant names (+5)")
    else:
        feedback_parts.append(f"Report contains {names_found} participant names (+0)")

    # Check for consistency/verification line
    # Look for numbers that could represent subcounts summing to 50
    numbers_in_report = [int(n) for n in re.findall(r'\b(\d+)\b', report_content)
                         if 1 <= int(n) <= 50]
    has_consistency = False
    for i, a in enumerate(numbers_in_report):
        for j, b in enumerate(numbers_in_report):
            if j <= i:
                continue
            for k, c in enumerate(numbers_in_report):
                if k <= j:
                    continue
                if a + b + c == 50:
                    has_consistency = True
                    break
    if has_consistency or 'verification' in report_content or 'total' in report_content:
        score += 5
        feedback_parts.append("Report has consistency/verification data (+5)")
    else:
        feedback_parts.append("Report missing consistency check (+0)")

    # ── 5. Summary email (15 pts) ──
    target_email = 'engineering-manager@company.com'
    email_found = False
    email_subject_ok = False
    email_body_ok = False

    for em in result.get('outgoing_emails', []):
        if target_email in em.get('to', ''):
            email_found = True
            subj = em.get('subject', '').lower()
            body = em.get('body', '').lower()
            combined = subj + ' ' + body
            if any(kw in subj for kw in ['triage', 'report', 'weekly', 'inbox', 'thread']):
                email_subject_ok = True
            if 'solaris' in combined or 'sun' in combined:
                email_body_ok = True

    if email_found:
        score += 5
        feedback_parts.append(f"Email to {target_email} found (+5)")
    else:
        feedback_parts.append(f"No email to {target_email} (+0)")

    if email_subject_ok:
        score += 5
        feedback_parts.append("Email subject has relevant keywords (+5)")
    else:
        feedback_parts.append("Email subject missing keywords (+0)")

    if email_body_ok:
        score += 5
        feedback_parts.append("Email body references most active thread (+5)")
    else:
        feedback_parts.append("Email body missing thread reference (+0)")

    # ── 6. Inbox reduction (10 pts) ──
    inbox_count = result.get('inbox_count', 50)
    reduction = 50 - inbox_count
    if reduction >= 15:
        score += 10
        feedback_parts.append(f"Inbox reduced by {reduction} (+10)")
    elif reduction >= 8:
        score += 5
        feedback_parts.append(f"Inbox reduced by {reduction} (+5)")
    else:
        feedback_parts.append(f"Inbox reduced by {reduction} (+0)")

    passed = score >= 60
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
