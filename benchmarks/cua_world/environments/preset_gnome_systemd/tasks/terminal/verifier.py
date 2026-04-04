def typed_greeting(traj, env_info, task_info):
    steps = traj.get("steps", [])
    found = False
    for e in steps:
        if e.get("event") == "step":
            a = e.get("action", {}).get("keyboard", {})
            text = a.get("text")
            if text and "Hello" in text:
                found = True
                break
    return {"passed": bool(found), "score": 100 if found else 0, "feedback": "Greeting typed" if found else "No greeting detected"}

