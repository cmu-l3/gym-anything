def check_greeting(traj, env_info, task_info):
    # Simple programmatic verifier: check that a step typed expected text
    steps = traj.get("steps", [])
    found = False
    for e in steps:
        if e.get("event") == "step":
            a = e.get("action", {})
            kb = a.get("keyboard", {})
            text = kb.get("text")
            if text and "Hello" in text:
                found = True
                break
    return {"passed": bool(found), "score": 100 if found else 0, "feedback": "Found greeting" if found else "No greeting"}

