def typed_greeting(traj, env_info, task_info):
    steps = traj.get("steps", [])
    found = False
    for e in steps:
        if e.get("event") == "step":
            # A step's action is a list of action dicts (step() takes a
            # batch); a single dict is also accepted for older traces.
            actions = e.get("action", [])
            if isinstance(actions, dict):
                actions = [actions]
            for a in actions:
                if not isinstance(a, dict):
                    continue
                text = a.get("keyboard", {}).get("text")
                if text and "Hello" in text:
                    found = True
                    break
        if found:
            break
    return {"passed": bool(found), "score": 100 if found else 0, "feedback": "Greeting typed" if found else "No greeting detected"}

