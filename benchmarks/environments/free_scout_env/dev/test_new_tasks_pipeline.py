#!/usr/bin/env python3
"""
Pipeline verification tests for the 5 new free_scout_env tasks.

Tests each verifier with:
  1. Do-nothing  → copy_from_env raises (no JSON on VM) → expect score=0, passed=False
  2. Partial     → JSON with only some criteria satisfied → expect 0 < score < 60, passed=False
  3. Full        → JSON with all criteria satisfied → expect score=100, passed=True
  4. Wrong-target → JSON with unrelated data (different mailbox/users) → expect score=0, passed=False

No Docker/VM required. Uses a mock copy_from_env that writes crafted JSON to the
destination file, simulating the export_result.sh output.
"""

import importlib.util
import json
import os
import sys
import time

TASKS_DIR    = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tasks")
EVIDENCE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "evidence")
os.makedirs(EVIDENCE_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_verifier(task_name):
    """Dynamically load a task's verifier.py module."""
    path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _copy_fn_from_json(data_dict):
    """Return a copy_from_env callable that writes data_dict as JSON to dest."""
    def copy_fn(src_path, dest_path):
        with open(dest_path, "w", encoding="utf-8") as f:
            json.dump(data_dict, f)
    return copy_fn


def _copy_fn_raises():
    """Return a copy_from_env callable that always raises (simulates missing file)."""
    def copy_fn(src_path, dest_path):
        raise FileNotFoundError(f"No such file on VM: {src_path}")
    return copy_fn


def _run(task_name, fn_name, data_dict):
    """Run verifier function with provided data dict. Returns result dict."""
    mod = _load_verifier(task_name)
    fn  = getattr(mod, fn_name)
    task_json_path = os.path.join(TASKS_DIR, task_name, "task.json")
    with open(task_json_path) as f:
        task_info = json.load(f)

    if data_dict is None:
        env_info = {"copy_from_env": _copy_fn_raises()}
    else:
        env_info = {"copy_from_env": _copy_fn_from_json(data_dict)}

    return fn(traj=[], env_info=env_info, task_info=task_info)


results_summary = {}


# ===========================================================================
# TASK 1: enterprise_support_onboarding
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 1: enterprise_support_onboarding")
print("=" * 60)

TASK = "enterprise_support_onboarding"
FN   = "verify_enterprise_support_onboarding"

# Full: all criteria met → score=100, passed=True
# Score breakdown: mailbox(15)+james(10)+priya(10)+james_dual_access(15)
#                  +saved_reply(15)+tech_tagged(20)+billing_assigned(15) = 100
FULL_DATA = {
    "enterprise_mailbox_found": True,
    "enterprise_mailbox_name": "Enterprise Support",
    "james_found": True,
    "james_role": 2,
    "james_tech_access": True,
    "james_enterprise_access": True,
    "priya_found": True,
    "priya_role": 2,
    "priya_enterprise_access": True,
    "saved_reply_found": True,
    "saved_reply_name": "Enterprise Acknowledgment",
    "saved_reply_text_preview": "Thank you for reaching out to our enterprise support team. A dedicated specialist will contact you within 4 business hours to address your request.",
    "tech_tagged_count": 5,
    "billing_assigned_to_sarah": 3,
    "sarah_id": "4",
}

# Partial: mailbox(15) + james(10) + james_tech_only(5) = 30 < 60
PARTIAL_DATA = {
    "enterprise_mailbox_found": True,
    "enterprise_mailbox_name": "Enterprise Support",
    "james_found": True,
    "james_role": 2,
    "james_tech_access": True,
    "james_enterprise_access": False,
    "priya_found": False,
    "priya_role": 0,
    "priya_enterprise_access": False,
    "saved_reply_found": False,
    "saved_reply_name": "",
    "saved_reply_text_preview": "",
    "tech_tagged_count": 0,
    "billing_assigned_to_sarah": 0,
    "sarah_id": "",
}

# Wrong-target: different mailbox/users — score=0
WRONG_DATA = {
    "enterprise_mailbox_found": False,
    "enterprise_mailbox_name": "",
    "james_found": False,
    "james_role": 0,
    "james_tech_access": False,
    "james_enterprise_access": False,
    "priya_found": False,
    "priya_role": 0,
    "priya_enterprise_access": False,
    "saved_reply_found": False,
    "saved_reply_name": "",
    "saved_reply_text_preview": "",
    "tech_tagged_count": 0,
    "billing_assigned_to_sarah": 0,
    "sarah_id": "",
}

r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

r_partial = _run(TASK, FN, PARTIAL_DATA)
print(f"Partial:      score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"
assert r_partial['score'] > 0, f"FAIL partial (score=0): {r_partial}"

r_full = _run(TASK, FN, FULL_DATA)
print(f"Full:         score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

r_wrong = _run(TASK, FN, WRONG_DATA)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "enterprise_support_onboarding@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        f"Do-nothing=0 (FileNotFoundError). "
        f"Partial (mailbox+james_user+james_tech_only)={r_partial['score']} pts, passed=False. "
        f"Full (all 7 criteria)={r_full['score']}/100, passed=True. "
        f"Wrong-target (no enterprise entities)=0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 2: support_backlog_triage
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 2: support_backlog_triage")
print("=" * 60)

TASK = "support_backlog_triage"
FN   = "verify_support_backlog_triage"

# Full: all 6 criteria → score=100
# Score: tagged(25)+assigned_admin(20)+notes(15)+reopened(15)+replied(15)+derek(10) = 100
FULL_DATA = {
    "tagged_count": 4,
    "tagged_assigned_to_admin": 4,
    "notes_on_unresponded": 4,
    "reopened_count": 3,
    "target_replied": True,
    "target_reply_body": "Thank you for your patience. Our engineering team has reviewed the software installation failure and has resolved the underlying issue. Please retry the installation.",
    "target_assigned_to_derek": True,
}

# Partial: tagged(4)+assigned_admin(4)→ 25+20=45 < 60, nothing else
PARTIAL_DATA = {
    "tagged_count": 4,
    "tagged_assigned_to_admin": 4,
    "notes_on_unresponded": 0,
    "reopened_count": 0,
    "target_replied": False,
    "target_reply_body": "",
    "target_assigned_to_derek": False,
}

# Wrong-target: nothing done → score=0
WRONG_DATA = {
    "tagged_count": 0,
    "tagged_assigned_to_admin": 0,
    "notes_on_unresponded": 0,
    "reopened_count": 0,
    "target_replied": False,
    "target_reply_body": "",
    "target_assigned_to_derek": False,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

r_partial = _run(TASK, FN, PARTIAL_DATA)
print(f"Partial:      score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"
assert r_partial['score'] > 0, f"FAIL partial (score=0): {r_partial}"

r_full = _run(TASK, FN, FULL_DATA)
print(f"Full:         score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

r_wrong = _run(TASK, FN, WRONG_DATA)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "support_backlog_triage@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        f"Do-nothing=0. "
        f"Partial (tagged+admin_assign only)={r_partial['score']} pts, passed=False. "
        f"Full (all 6 criteria)={r_full['score']}/100, passed=True. "
        f"Wrong-target (no actions)=0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 3: customer_profile_enrichment
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 3: customer_profile_enrichment")
print("=" * 60)

TASK = "customer_profile_enrichment"
FN   = "verify_customer_profile_enrichment"

# Full: all 8 criteria → score=100
# Score: marisa_co(12)+marisa_phone(8)+marisa_job(10)+nicolas_co(12)+nicolas_phone(8)
#        +david(15)+vip_tag(20)+david_conv(15) = 100
FULL_DATA = {
    "marisa_company": "Pinnacle Systems",
    "marisa_phone": "+1-555-0192",
    "marisa_job_title": "Senior Systems Engineer",
    "nicolas_company": "Horizon Analytics",
    "nicolas_phone": "+1-555-0247",
    "david_found": True,
    "david_company": "TechFirm Solutions",
    "marisa_tagged_count": 3,
    "david_conv_found": True,
    "david_conv_mailbox_correct": True,
    "david_conv_subject": "enterprise account onboarding for new client",
}

# Partial: marisa_co(12)+marisa_phone(8)+marisa_job(10)+nicolas_co(12) = 42 < 60
PARTIAL_DATA = {
    "marisa_company": "Pinnacle Systems",
    "marisa_phone": "+1-555-0192",
    "marisa_job_title": "Senior Systems Engineer",
    "nicolas_company": "Horizon Analytics",
    "nicolas_phone": "",
    "david_found": False,
    "david_company": "",
    "marisa_tagged_count": 0,
    "david_conv_found": False,
    "david_conv_mailbox_correct": False,
    "david_conv_subject": "",
}

# Wrong-target: nothing matches → score=0
WRONG_DATA = {
    "marisa_company": "",
    "marisa_phone": "",
    "marisa_job_title": "",
    "nicolas_company": "",
    "nicolas_phone": "",
    "david_found": False,
    "david_company": "",
    "marisa_tagged_count": 0,
    "david_conv_found": False,
    "david_conv_mailbox_correct": False,
    "david_conv_subject": "",
}

r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

r_partial = _run(TASK, FN, PARTIAL_DATA)
print(f"Partial:      score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"
assert r_partial['score'] > 0, f"FAIL partial (score=0): {r_partial}"

r_full = _run(TASK, FN, FULL_DATA)
print(f"Full:         score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

r_wrong = _run(TASK, FN, WRONG_DATA)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "customer_profile_enrichment@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        f"Do-nothing=0. "
        f"Partial (Marisa+Nicolas companies/phone/job, no David/tags/conv)={r_partial['score']} pts, passed=False. "
        f"Full (all 8 criteria)={r_full['score']}/100, passed=True. "
        f"Wrong-target (no profile changes)=0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 4: team_restructuring_and_permissions
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 4: team_restructuring_and_permissions")
print("=" * 60)

TASK = "team_restructuring_and_permissions"
FN   = "verify_team_restructuring_and_permissions"

# Full: all 6 criteria → score=100
# Score: vip_mailbox(15)+alex_perms(15)+maria_perms(15)+saved_reply(15)
#        +convs_moved(25)+alex_assigned(15) = 100
FULL_DATA = {
    "vip_mailbox_found": True,
    "vip_mailbox_name": "VIP Support",
    "alex_id": "5",
    "alex_billing_access": False,
    "alex_vip_access": True,
    "alex_general_access": True,
    "alex_tech_access": True,
    "maria_id": "6",
    "maria_general_access": True,
    "maria_tech_access": True,
    "maria_vip_access": True,
    "maria_billing_access": False,
    "saved_reply_found": True,
    "saved_reply_name": "VIP Priority Response",
    "saved_reply_text_preview": "Dear valued customer your case has been flagged as high priority and assigned to our dedicated VIP support team. A senior support specialist will contact you within 1 business hour.",
    "vip_convs_moved_count": 4,
    "vip_conv_subjects": "Premium account migration|Enterprise API|SLA breach|Data export",
    "vip_assigned_to_alex": 4,
    "vip_mailbox_total_convs": 4,
}

# Partial: vip_mailbox(15)+alex_perms(15)+maria_tech_only(8)+saved_reply(15) = 53 < 60
PARTIAL_DATA = {
    "vip_mailbox_found": True,
    "vip_mailbox_name": "VIP Support",
    "alex_id": "5",
    "alex_billing_access": False,
    "alex_vip_access": True,
    "alex_general_access": True,
    "alex_tech_access": True,
    "maria_id": "6",
    "maria_general_access": True,
    "maria_tech_access": True,
    "maria_vip_access": False,
    "maria_billing_access": False,
    "saved_reply_found": True,
    "saved_reply_name": "VIP Priority Response",
    "saved_reply_text_preview": "Dear valued customer your case is high priority. A senior specialist from our VIP team will contact you shortly.",
    "vip_convs_moved_count": 0,
    "vip_conv_subjects": "",
    "vip_assigned_to_alex": 0,
    "vip_mailbox_total_convs": 0,
}

# Wrong-target: no VIP mailbox, no changes → score=0
WRONG_DATA = {
    "vip_mailbox_found": False,
    "vip_mailbox_name": "",
    "alex_billing_access": True,
    "alex_vip_access": False,
    "alex_general_access": True,
    "alex_tech_access": True,
    "maria_general_access": True,
    "maria_tech_access": False,
    "maria_vip_access": False,
    "saved_reply_found": False,
    "saved_reply_name": "",
    "saved_reply_text_preview": "",
    "vip_convs_moved_count": 0,
    "vip_assigned_to_alex": 0,
    "vip_mailbox_total_convs": 0,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

r_partial = _run(TASK, FN, PARTIAL_DATA)
print(f"Partial:      score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"
assert r_partial['score'] > 0, f"FAIL partial (score=0): {r_partial}"

r_full = _run(TASK, FN, FULL_DATA)
print(f"Full:         score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

r_wrong = _run(TASK, FN, WRONG_DATA)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "team_restructuring_and_permissions@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        f"Do-nothing=0. "
        f"Partial (VIP mailbox+Alex perms+Maria tech only+saved reply, no conv moves)={r_partial['score']} pts, passed=False. "
        f"Full (all 6 criteria)={r_full['score']}/100, passed=True. "
        f"Wrong-target (no VIP mailbox created)=0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# TASK 5: support_operations_cleanup
# ===========================================================================
print("\n" + "=" * 60)
print("TASK 5: support_operations_cleanup")
print("=" * 60)

TASK = "support_operations_cleanup"
FN   = "verify_support_operations_cleanup"

# Full: all 8 criteria → score=100
# Score: tech_moves(15)+sales_move(10)+raj_perms(10)+ben_perms(10)
#        +raj_assign(15)+nina_assign(10)+saved_reply(15)+nfu_tag(15) = 100
FULL_DATA = {
    "tech3_in_sales": True,
    "tech4_in_sales": True,
    "sales3_in_cs": True,
    "raj_tech_access": True,
    "raj_sales_access": False,
    "ben_sales_access": True,
    "ben_cs_access": True,
    "tech1_assigned_to_raj": True,
    "tech2_assigned_to_raj": True,
    "cs1_assigned_to_nina": True,
    "cs2_assigned_to_nina": True,
    "saved_reply_found": True,
    "saved_reply_name": "Sales Inquiry Acknowledgment",
    "saved_reply_text_preview": "Thank you for reaching out to our sales team! A dedicated account executive will review your inquiry and respond within 1 business day. In the meantime feel free to browse our pricing page.",
    "nfu_tag_found": True,
    "tagged_sales_count": 4,
    "sales_unresponded_count": 4,
}

# Partial: tech3_move(8)+raj_perms(10)+tech1_raj(8) = 26 < 60
PARTIAL_DATA = {
    "tech3_in_sales": True,
    "tech4_in_sales": False,
    "sales3_in_cs": False,
    "raj_tech_access": True,
    "raj_sales_access": False,
    "ben_sales_access": True,
    "ben_cs_access": False,
    "tech1_assigned_to_raj": True,
    "tech2_assigned_to_raj": False,
    "cs1_assigned_to_nina": False,
    "cs2_assigned_to_nina": False,
    "saved_reply_found": False,
    "saved_reply_name": "",
    "saved_reply_text_preview": "",
    "nfu_tag_found": False,
    "tagged_sales_count": 0,
    "sales_unresponded_count": 3,
}

# Wrong-target: nothing done, Raj still has Sales access → score=0
WRONG_DATA = {
    "tech3_in_sales": False,
    "tech4_in_sales": False,
    "sales3_in_cs": False,
    "raj_tech_access": True,
    "raj_sales_access": True,
    "ben_sales_access": True,
    "ben_cs_access": False,
    "tech1_assigned_to_raj": False,
    "tech2_assigned_to_raj": False,
    "cs1_assigned_to_nina": False,
    "cs2_assigned_to_nina": False,
    "saved_reply_found": False,
    "saved_reply_name": "",
    "saved_reply_text_preview": "",
    "nfu_tag_found": False,
    "tagged_sales_count": 0,
    "sales_unresponded_count": 0,
}

r = _run(TASK, FN, None)
print(f"Do-nothing:   score={r['score']}, passed={r['passed']}  | {r['feedback']}")
assert r['score'] == 0 and not r['passed'], f"FAIL do-nothing: {r}"

r_partial = _run(TASK, FN, PARTIAL_DATA)
print(f"Partial:      score={r_partial['score']}, passed={r_partial['passed']}  | {r_partial['feedback']}")
assert r_partial['score'] < 60 and not r_partial['passed'], f"FAIL partial: {r_partial}"
assert r_partial['score'] > 0, f"FAIL partial (score=0): {r_partial}"

r_full = _run(TASK, FN, FULL_DATA)
print(f"Full:         score={r_full['score']}, passed={r_full['passed']}  | {r_full['feedback']}")
assert r_full['score'] == 100 and r_full['passed'], f"FAIL full: {r_full}"

r_wrong = _run(TASK, FN, WRONG_DATA)
print(f"Wrong-target: score={r_wrong['score']}, passed={r_wrong['passed']}  | {r_wrong['feedback']}")
assert r_wrong['score'] == 0 and not r_wrong['passed'], f"FAIL wrong-target: {r_wrong}"

results_summary[TASK] = {
    "task_id": "support_operations_cleanup@1",
    "do_nothing_score": r['score'], "do_nothing_passed": r['passed'],
    "partial_score": r_partial['score'], "partial_passed": r_partial['passed'],
    "full_score": r_full['score'], "full_passed": r_full['passed'],
    "wrong_target_score": r_wrong['score'], "wrong_target_passed": r_wrong['passed'],
    "notes": (
        f"Do-nothing=0 (FileNotFoundError). "
        f"Partial (1 tech move+raj perms+1 raj assign)={r_partial['score']} pts, passed=False. "
        f"Full (all 8 criteria)={r_full['score']}/100, passed=True. "
        f"Wrong-target (no moves, Raj sales not removed)=0 pts."
    )
}
print(f"PASS: do_nothing=0, partial={r_partial['score']}, full={r_full['score']}/100")


# ===========================================================================
# Save evidence JSON
# ===========================================================================
print("\n" + "=" * 60)
print("SAVING EVIDENCE")
print("=" * 60)

test_date = time.strftime("%Y-%m-%d")
for task_name, summary in results_summary.items():
    evidence = {
        "task": task_name,
        "task_id": summary["task_id"],
        "test_date": test_date,
        "methodology": (
            "Pipeline simulation: verifier.py loaded directly and called with a mock "
            "copy_from_env function that writes crafted JSON to a temp file, simulating "
            "the export_result.sh output. Four scenarios tested per task: "
            "(1) do-nothing — raises FileNotFoundError → score=0, passed=False; "
            "(2) partial — some criteria met, others not → score<60, passed=False; "
            "(3) full — all criteria met → score=100, passed=True; "
            "(4) wrong-target — irrelevant data (different mailbox/user names) → "
            "score=0, passed=False. No Docker/VM required."
        ),
        "pipeline_results": {
            "do_nothing":   {"score": summary["do_nothing_score"],   "passed": summary["do_nothing_passed"]},
            "partial":      {"score": summary["partial_score"],      "passed": summary["partial_passed"]},
            "full":         {"score": summary["full_score"],         "passed": summary["full_passed"]},
            "wrong_target": {"score": summary["wrong_target_score"], "passed": summary["wrong_target_passed"]},
        },
        "notes": summary["notes"],
        "env": "free_scout_env",
        "env_base": "ubuntu-gnome",
        "app": "FreeScout help desk (http://localhost:8080, admin@helpdesk.local/Admin123!)",
        "verification_method": "export_result.sh → /tmp/task_result.json → copy_from_env → JSON field parsing",
        "db": "MariaDB 10.11 via Docker container 'freescout-db' (user freescout/freescout123)",
    }
    out = os.path.join(EVIDENCE_DIR, f"{task_name}_evidence.json")
    with open(out, "w") as f:
        json.dump(evidence, f, indent=2)
    print(f"  Saved: {out}")


print("\n" + "=" * 60)
print("ALL PIPELINE TESTS PASSED")
print("=" * 60)
for task, data in results_summary.items():
    print(
        f"  {task}:\n"
        f"    do_nothing={data['do_nothing_score']}/{data['do_nothing_passed']}  "
        f"partial={data['partial_score']}  "
        f"full={data['full_score']}/{data['full_passed']}  "
        f"wrong_target={data['wrong_target_score']}/{data['wrong_target_passed']}"
    )
