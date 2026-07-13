from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "clockwork_doppelganger_customs"


def _failure(message: str) -> dict[str, Any]:
    return {"graded": True, "passed": False, "score": 0, "feedback": message}


def _number(value: Any) -> float | None:
    try: result = float(value)
    except (TypeError, ValueError): return None
    return result if math.isfinite(result) else None


def _close(first: Any, second: Any, tolerance: float = 0.12) -> bool:
    a, b = _number(first), _number(second)
    return a is not None and b is not None and abs(a - b) <= tolerance


def _point(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, dict): return None
    x, y = _number(value.get("x")), _number(value.get("y"))
    return None if x is None or y is None else (x, y)


def _round(value: float) -> float:
    return round(float(value) + 1e-12, 2)


def _distance(first: tuple[float, float], second: tuple[float, float]) -> float:
    return math.hypot(first[0] - second[0], first[1] - second[1])


def _interpolate(recording: dict[str, Any], local_t: float) -> tuple[float, float]:
    samples = recording["samples"]
    if local_t <= samples[0]["local_t_ms"]: return samples[0]["position"]
    if local_t >= samples[-1]["local_t_ms"]: return samples[-1]["position"]
    for before, after in zip(samples, samples[1:]):
        if before["local_t_ms"] <= local_t <= after["local_t_ms"]:
            span = after["local_t_ms"] - before["local_t_ms"]
            amount = 0.0 if span <= 0 else (local_t - before["local_t_ms"]) / span
            return (before["position"][0] + (after["position"][0] - before["position"][0]) * amount, before["position"][1] + (after["position"][1] - before["position"][1]) * amount)
    return samples[-1]["position"]


def _simulate(recordings: list[dict[str, Any]], phases: list[int], until_ms: float, stations: dict[str, Any], conveyor: dict[str, Any], qualification: dict[str, Any]) -> dict[str, Any]:
    actions = []
    for slot, recording in enumerate(recordings):
        for action in recording["actions"]:
            global_t = phases[slot] + action["local_t_ms"]
            if global_t <= until_ms + 1e-9:
                actions.append((global_t, slot, action))
    actions.sort(key=lambda item: (item[0], {"release": 0, "grab": 1, "stamp": 2}.get(item[2]["action"], 3), item[1]))
    state: dict[str, Any] = {"mode": "conveyor", "position": (float(conveyor["start_x"]), float(conveyor["track_y"])), "holder": None, "stamped": False, "delivered": False, "last_release": None, "errors": 0}

    def position_at(time_ms: float) -> tuple[float, float]:
        if state["holder"] is not None:
            slot = int(state["holder"]); return _interpolate(recordings[slot], time_ms - phases[slot])
        if state["mode"] == "conveyor":
            return (float(conveyor["start_x"]) + float(conveyor["speed_px_per_ms"]) * time_ms, float(conveyor["track_y"]))
        return state["position"]

    for global_t, slot, action in actions:
        state["position"] = position_at(global_t)
        actor = _interpolate(recordings[slot], action["local_t_ms"])
        kind = action["action"]
        if kind == "grab":
            if state["holder"] is not None:
                state["errors"] += 1
            elif state["mode"] == "conveyor":
                if _distance(actor, state["position"]) <= float(qualification["grab_radius_px"]):
                    state["holder"] = slot; state["mode"] = "held"
                else: state["errors"] += 1
            elif state["mode"] == "free" and state["last_release"] is not None and global_t - state["last_release"] <= float(qualification["handoff_window_ms"]) and _distance(actor, state["position"]) <= float(qualification["grab_radius_px"]):
                state["holder"] = slot; state["mode"] = "held"
            else: state["errors"] += 1
        elif kind == "stamp":
            station = (float(stations["stamp"]["x"]), float(stations["stamp"]["y"]))
            if state["holder"] == slot and _distance(actor, station) <= float(qualification["station_radius_px"]): state["stamped"] = True
            else: state["errors"] += 1
        elif kind == "release":
            if state["holder"] != slot:
                state["errors"] += 1
            else:
                state["holder"] = None; state["position"] = actor; state["last_release"] = global_t
                exit_point = (float(stations["exit"]["x"]), float(stations["exit"]["y"]))
                if state["stamped"] and _distance(actor, exit_point) <= float(qualification["station_radius_px"]): state["mode"] = "delivered"; state["delivered"] = True
                else: state["mode"] = "free"
    state["position"] = position_at(until_ms)
    return {"x": _round(state["position"][0]), "y": _round(state["position"][1]), "mode": state["mode"], "holder": state["holder"], "stamped": bool(state["stamped"]), "delivered": bool(state["delivered"]), "errors": int(state["errors"])}


def _snapshot_claim(value: Any, expected: dict[str, Any]) -> bool:
    return isinstance(value, dict) and _close(value.get("x"), expected["x"], 0.6) and _close(value.get("y"), expected["y"], 0.6) and value.get("mode") == expected["mode"] and value.get("holder") == expected["holder"] and bool(value.get("stamped")) == expected["stamped"] and bool(value.get("delivered")) == expected["delivered"] and value.get("errors") == expected["errors"]


def grade(payload: dict[str, Any], ground_truth: dict[str, Any], public_state: dict[str, Any]) -> dict[str, Any]:
    challenge_id, task_id = str(ground_truth.get("challenge_id") or ""), str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "") != MECHANIC_ID or str(ground_truth.get("mechanic_id") or "") != MECHANIC_ID: return _failure("mechanic mismatch")
    if not task_id or str(payload.get("task_id") or "") != task_id: return _failure("task mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "") != challenge_id: return _failure("stale challenge")
    if str(public_state.get("mechanic_id") or "") != MECHANIC_ID or str(public_state.get("challenge_id") or "") != challenge_id or str(public_state.get("task_id") or "") != task_id: return _failure("public customs identity mismatch")
    canvas, stations, conveyor, roles = ground_truth.get("canvas"), ground_truth.get("stations"), ground_truth.get("conveyor"), ground_truth.get("roles")
    controls, qualification = ground_truth.get("controls"), ground_truth.get("qualification")
    if not isinstance(canvas, dict) or not isinstance(stations, dict) or not isinstance(conveyor, dict) or not isinstance(roles, list) or len(roles) != 3 or not isinstance(controls, dict) or not isinstance(qualification, dict): return _failure("hidden customs manifest is malformed")
    for key, value in (("canvas",canvas),("stations",stations),("conveyor",conveyor),("roles",roles),("controls",controls),("qualification",qualification)):
        if public_state.get(key) != value: return _failure(f"public {key} disagrees with hidden customs state")
    events = payload.get("events")
    if not isinstance(events, list) or not events or len(events) > 2400: return _failure("customs transcript is missing or too long")

    recordings: list[dict[str, Any] | None] = [None, None, None]
    revisions = [0,0,0]; phases=[0,0,0]; active=False; recording=None; cycle=None; terminal=False
    record_failures=0; phase_edits=0; cycle_attempts=0; successful_cycles=0; rewind_count=0; last_outcome=None
    previous_time=-1.0
    for sequence,event in enumerate(events,start=1):
        if terminal:return _failure(f"customs event {sequence} occurs after terminal filing")
        if not isinstance(event,dict) or event.get("seq")!=sequence:return _failure(f"customs event {sequence} has invalid sequence")
        event_time=_number(event.get("t_ms"))
        if event_time is None or not 0<=event_time<=1_200_000 or event_time<previous_time:return _failure(f"customs event {sequence} has invalid timestamp")
        previous_time=event_time;action=str(event.get("type") or "")
        if action=="challenge_start":
            if active or sequence!=1:return _failure("customs challenge start is malformed")
            active=True;continue
        if not active:return _failure("customs interaction occurred before the fail stamp cleared")
        if action=="record_start":
            slot=event.get("slot");pointer=_point(event.get("pointer"))
            if recording is not None or cycle is not None or slot not in {0,1,2} or pointer is None or not 0<=pointer[0]<=float(canvas["width"]) or not 0<=pointer[1]<=float(canvas["height"]):return _failure(f"recording {sequence} starts from impossible state")
            recording={"slot":slot,"start":event_time,"samples":[],"actions":[],"last_pointer":pointer,"last_local":None,"invalid":False};continue
        if action=="record_sample":
            if recording is None or event.get("slot")!=recording["slot"]:return _failure(f"record sample {sequence} is not bound to an active take")
            local=_number(event.get("local_t_ms"));pointer=_point(event.get("position"))
            if local is None or pointer is None:return _failure(f"record sample {sequence} is malformed")
            if not _close(local,event_time-recording["start"],12) or not 0<=pointer[0]<=float(canvas["width"]) or not 0<=pointer[1]<=float(canvas["height"]):recording["invalid"]=True
            if recording["last_local"] is not None and (local-recording["last_local"]<30 or local-recording["last_local"]>float(qualification["maximum_record_sample_gap_ms"])):recording["invalid"]=True
            if _distance(pointer,recording["last_pointer"])>float(qualification["maximum_pointer_step_px"]):recording["invalid"]=True
            recording["samples"].append({"local_t_ms":local,"position":pointer});recording["last_pointer"]=pointer;recording["last_local"]=local;continue
        if action=="record_action":
            if recording is None or event.get("slot")!=recording["slot"]:return _failure(f"record action {sequence} is not bound to an active take")
            local=_number(event.get("local_t_ms"));pointer=_point(event.get("position"));kind=str(event.get("action") or "")
            if local is None or pointer is None or kind not in {"grab","release","stamp"}:return _failure(f"record action {sequence} is malformed")
            if not _close(local,event_time-recording["start"],12):recording["invalid"]=True
            recording["actions"].append({"local_t_ms":local,"position":pointer,"action":kind});continue
        if action=="record_end":
            if recording is None or event.get("slot")!=recording["slot"]:return _failure(f"record end {sequence} has no active take")
            local=_number(event.get("local_t_ms"));samples=recording["samples"];actions=recording["actions"]
            valid=local is not None and abs(local-float(controls["record_duration_ms"]))<=130 and len(samples)>=int(qualification["minimum_record_samples"]) and samples and samples[-1]["local_t_ms"]-samples[0]["local_t_ms"]>=float(controls["record_duration_ms"])-220 and not recording["invalid"]
            travel=sum(_distance(a["position"],b["position"]) for a,b in zip(samples,samples[1:])) if samples else 0
            valid=valid and travel>=float(qualification["minimum_path_travel_px"]) and [item["action"] for item in actions]==roles[recording["slot"]]["required_actions"] and all(actions[index]["local_t_ms"]<actions[index+1]["local_t_ms"] for index in range(len(actions)-1))
            candidate={"samples":samples,"actions":actions,"duration_ms":local or 0,"travel":_round(travel)}
            if valid:
                for item in actions:
                    if _distance(item["position"],_interpolate(candidate,item["local_t_ms"]))>float(qualification["action_path_tolerance_px"]):valid=False;break
            if bool(event.get("accepted"))!=bool(valid):return _failure(f"record end {sequence} lies about take validity")
            if valid:recordings[recording["slot"]]=candidate;revisions[recording["slot"]]+=1;phases[recording["slot"]]=0
            else:record_failures+=1
            recording=None;continue
        if action=="record_reset":
            slot=event.get("slot")
            if recording is not None or cycle is not None or slot not in {0,1,2}:return _failure("record reset occurred during an active clock")
            recordings[slot]=None;phases[slot]=0;rewind_count+=1;continue
        if action=="phase_edit":
            slot=event.get("slot");before=event.get("from_ms");after=event.get("to_ms");step=int(controls["phase_step_ms"]);loop=int(controls["loop_duration_ms"])
            if recording is not None or cycle is not None or slot not in {0,1,2} or recordings[slot] is None or before!=phases[slot] or not isinstance(after,int) or not 0<=after<loop or after%step!=0:return _failure(f"phase edit {sequence} is malformed")
            phases[slot]=after;phase_edits+=1;continue
        if action=="cycle_start":
            if recording is not None or cycle is not None or any(item is None for item in recordings):return _failure("master cycle started without three complete recordings")
            cycle={"start":event_time,"samples":[],"last_local":None};continue
        if action=="cycle_sample":
            if cycle is None:return _failure(f"cycle sample {sequence} occurs outside playback")
            local=_number(event.get("cycle_t_ms"))
            if local is None or not _close(local,event_time-cycle["start"],15):return _failure(f"cycle sample {sequence} compresses or dilates master time")
            if cycle["last_local"] is not None and (local-cycle["last_local"]<45 or local-cycle["last_local"]>float(qualification["maximum_cycle_sample_gap_ms"])):return _failure(f"cycle sample {sequence} leaves an unverifiable timing gap")
            expected=_simulate(recordings,phases,local,stations,conveyor,qualification)
            if not _snapshot_claim(event.get("passport"),expected):return _failure(f"cycle sample {sequence} fabricates concurrent possession")
            cycle["samples"].append(local);cycle["last_local"]=local;continue
        if action=="cycle_end":
            if cycle is None:return _failure("cycle end occurred without playback")
            elapsed=event_time-cycle["start"];loop=float(controls["loop_duration_ms"]);samples=cycle["samples"]
            if not loop-90<=elapsed<=loop+320 or len(samples)<int(qualification["minimum_cycle_samples"]) or not samples or samples[0]>float(qualification["maximum_cycle_sample_gap_ms"]) or elapsed-samples[-1]>float(qualification["maximum_cycle_sample_gap_ms"]):return _failure("master cycle was compressed, sparse, or incomplete")
            outcome=_simulate(recordings,phases,loop,stations,conveyor,qualification)
            if bool(event.get("client_delivered"))!=outcome["delivered"] or not _snapshot_claim(event.get("passport"),outcome):return _failure("cycle end lies about delivery state")
            cycle_attempts+=1
            if outcome["delivered"] and outcome["stamped"] and outcome["errors"]==0:successful_cycles+=1
            last_outcome=outcome;cycle=None;continue
        if action=="cycle_rewind":
            if cycle is not None or recording is not None:return _failure("cycle rewind occurred during active time")
            rewind_count+=1;continue
        if action=="verify":
            if cycle is not None or recording is not None:return _failure("customs filing occurred during active time")
            if bool(event.get("claimed_delivered")) != bool(last_outcome and last_outcome["delivered"]):return _failure("terminal filing lies about delivered possession")
            terminal=True;continue
        return _failure(f"customs event {sequence} has invalid action {action!r}")

    summaries=[]
    for slot,item in enumerate(recordings):
        summaries.append(None if item is None else {"slot":slot,"samples":len(item["samples"]),"actions":[action["action"] for action in item["actions"]],"duration_ms":_round(item["duration_ms"]),"travel":_round(item["travel"])})
    expected_state={"recordings":summaries,"revisions":revisions,"phases_ms":phases,"record_failures":record_failures,"phase_edits":phase_edits,"cycle_attempts":cycle_attempts,"successful_cycles":successful_cycles,"rewind_count":rewind_count,"last_outcome":last_outcome}
    claimed=payload.get("final_state")
    state_matches=isinstance(claimed,dict) and all(claimed.get(key)==expected_state[key] for key in ("revisions","phases_ms","record_failures","phase_edits","cycle_attempts","successful_cycles","rewind_count"))
    claimed_recordings=claimed.get("recordings") if isinstance(claimed,dict) else None
    state_matches=state_matches and isinstance(claimed_recordings,list) and len(claimed_recordings)==3
    if state_matches:
        for claimed_record,expected_record in zip(claimed_recordings,summaries):
            if expected_record is None:
                if claimed_record is not None:state_matches=False;break
            elif not isinstance(claimed_record,dict) or claimed_record.get("slot")!=expected_record["slot"] or claimed_record.get("samples")!=expected_record["samples"] or claimed_record.get("actions")!=expected_record["actions"] or not _close(claimed_record.get("duration_ms"),expected_record["duration_ms"],2.0) or not _close(claimed_record.get("travel"),expected_record["travel"],0.25):state_matches=False;break
    claimed_outcome=claimed.get("last_outcome") if isinstance(claimed,dict) else None
    if last_outcome is None:state_matches=state_matches and claimed_outcome is None
    else:state_matches=state_matches and _snapshot_claim(claimed_outcome,last_outcome)
    if not state_matches:return _failure("claimed customs state does not match dense recording replay")
    passed=terminal and all(item is not None for item in recordings) and phase_edits>=3 and last_outcome is not None and last_outcome["delivered"] and last_outcome["stamped"] and last_outcome["errors"]==0
    return {"graded":True,"passed":passed,"score":100 if passed else 0,"feedback":f"replayed recordings {[len(item['samples']) if item else 0 for item in recordings]}; phases {phases}; cycles {successful_cycles}/{cycle_attempts}; rewinds {rewind_count}; possession errors {last_outcome['errors'] if last_outcome else 'n/a'}"}


def cheat(public_state: dict[str, Any], ground_truth: dict[str, Any]) -> dict[str, Any]:
    del public_state
    return {"solution":ground_truth.get("solution") or {},"answers":[]}
