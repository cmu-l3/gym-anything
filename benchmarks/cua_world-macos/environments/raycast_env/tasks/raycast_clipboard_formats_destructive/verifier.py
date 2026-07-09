"""Verifier for raycast_clipboard_formats_destructive.

Scoring (100 pts, pass >= 70):
  C1 — Final system clipboard equals 'call mom after 6'                    25 pts
        (the ultimate test that the agent pinned it BEFORE bulk-delete and
         the destructive delete preserved its pinned state)
  C2 — ~/Desktop/Household Inbox contains receipt.pdf (new, >0 bytes)      15 pts
  C3 — ~/Desktop/Household Inbox contains warranty.png (new, >0 bytes)     15 pts
  C4 — Mail draft contains 'Margaret Lin' (signature pasted into draft)    15 pts
  C5 — Mail draft signature is plain-style (no <html>, <b>, <span>, etc.   15 pts
        appear in the draft body — best-effort plain-text check)
  C6 — Raycast WAL changed after setup (proxy: agent interacted with       15 pts
        Raycast — required since the task forbids retyping content)

Notes:
- Bulk-delete state of Clipboard History entries cannot be inspected
  (encrypted DB). We accept that the final clipboard value + WAL change
  together are strong evidence of the destructive operation.
- 'rich vs plain paste' verification is best-effort. AppleScript's
  `content of message` returns plain text; we look for HTML markup
  fragments leaking through, which would indicate the rich version was
  pasted with formatting.
"""

import json
import os
import re
import tempfile

PASS_THRESHOLD = 70

CRITERION_POINTS = {
    "C1_final_clipboard":   25,
    "C2_receipt_in_inbox":  15,
    "C3_warranty_in_inbox": 15,
    "C4_signature_in_mail": 15,
    "C5_plain_signature":   15,
    "C6_raycast_touched":   15,
}

HTML_FRAGMENTS = [
    re.compile(r"<\s*html",   re.IGNORECASE),
    re.compile(r"<\s*body",   re.IGNORECASE),
    re.compile(r"<\s*b\s*>",  re.IGNORECASE),
    re.compile(r"<\s*span",   re.IGNORECASE),
    re.compile(r"<\s*p\s*>",  re.IGNORECASE),
    re.compile(r"<\s*br",     re.IGNORECASE),
    re.compile(r"style\s*=",  re.IGNORECASE),
]


def verify_clipboard_formats_destructive(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    result_path = "/tmp/raycast_clipboard_formats_destructive_result.json"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()

    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    subscores = {}

    clipboard_final = (result.get("final_clipboard") or "").strip()
    mail_content    = result.get("mail_draft_content") or ""
    inbox_files     = result.get("inbox_files", []) or []
    wal_changed     = result.get("raycast_wal_changed_after_setup", False)

    # C1 — Final clipboard is the pinned value
    if clipboard_final == "call mom after 6":
        score += CRITERION_POINTS["C1_final_clipboard"]
        subscores["C1"] = CRITERION_POINTS["C1_final_clipboard"]
        feedback.append("C1 PASS: final clipboard preserved as 'call mom after 6'")
    else:
        subscores["C1"] = 0
        feedback.append(
            f"C1 FAIL: final clipboard is {clipboard_final!r} (expected 'call mom after 6')"
        )

    # C2 — receipt.pdf in inbox (new, non-empty)
    receipt = next((f for f in inbox_files if f.get("name") == "receipt.pdf"), None)
    if receipt and receipt.get("is_new") and receipt.get("size_bytes", 0) > 0:
        score += CRITERION_POINTS["C2_receipt_in_inbox"]
        subscores["C2"] = CRITERION_POINTS["C2_receipt_in_inbox"]
        feedback.append(f"C2 PASS: receipt.pdf in Household Inbox ({receipt['size_bytes']} bytes)")
    else:
        subscores["C2"] = 0
        feedback.append("C2 FAIL: receipt.pdf not found in Household Inbox (or stale/empty)")

    # C3 — warranty.png in inbox
    warranty = next((f for f in inbox_files if f.get("name") == "warranty.png"), None)
    if warranty and warranty.get("is_new") and warranty.get("size_bytes", 0) > 0:
        score += CRITERION_POINTS["C3_warranty_in_inbox"]
        subscores["C3"] = CRITERION_POINTS["C3_warranty_in_inbox"]
        feedback.append(f"C3 PASS: warranty.png in Household Inbox ({warranty['size_bytes']} bytes)")
    else:
        subscores["C3"] = 0
        feedback.append("C3 FAIL: warranty.png not found in Household Inbox (or stale/empty)")

    # C4 — Mail draft contains 'Margaret Lin' (signature was pasted)
    if "margaret lin" in mail_content.lower():
        score += CRITERION_POINTS["C4_signature_in_mail"]
        subscores["C4"] = CRITERION_POINTS["C4_signature_in_mail"]
        feedback.append("C4 PASS: 'Margaret Lin' signature pasted into Mail draft")
    else:
        subscores["C4"] = 0
        feedback.append("C4 FAIL: signature ('Margaret Lin') not found in Mail draft")

    # C5 — Plain-text signature (no HTML markup fragments)
    html_hits = [p.pattern for p in HTML_FRAGMENTS if p.search(mail_content)]
    if not html_hits:
        score += CRITERION_POINTS["C5_plain_signature"]
        subscores["C5"] = CRITERION_POINTS["C5_plain_signature"]
        feedback.append("C5 PASS: no HTML markup leaked into Mail draft (paste-as-plain worked)")
    else:
        subscores["C5"] = 0
        feedback.append(f"C5 FAIL: HTML markup fragments in Mail draft ({html_hits})")

    # C6 — Raycast was actually used
    if wal_changed:
        score += CRITERION_POINTS["C6_raycast_touched"]
        subscores["C6"] = CRITERION_POINTS["C6_raycast_touched"]
        feedback.append("C6 PASS: Raycast settings DB modified after setup")
    else:
        subscores["C6"] = 0
        feedback.append("C6 FAIL: Raycast WAL unchanged — agent may have bypassed Raycast")

    passed = score >= PASS_THRESHOLD

    return {
        "passed":    passed,
        "score":     score,
        "feedback":  " | ".join(feedback),
        "subscores": subscores,
    }
