from __future__ import annotations

import math
from typing import Any


MECHANIC_ID = "zero_g_cable_autopsy"


def _failure(message: str) -> dict[str, Any]: return {"graded": True, "passed": False, "score": 0, "feedback": message}
def _number(value: Any) -> float | None:
    try: result=float(value)
    except (TypeError,ValueError): return None
    return result if math.isfinite(result) else None
def _close(a: Any,b: Any,tolerance: float=.01)->bool:
    x,y=_number(a),_number(b);return x is not None and y is not None and abs(x-y)<=tolerance
def _round(value: float,digits: int=5)->float:return round(float(value)+1e-12,digits)
def _vadd(a,b):return[a[i]+b[i] for i in range(3)]
def _vsub(a,b):return[a[i]-b[i] for i in range(3)]
def _vmul(a,s):return[a[i]*s for i in range(3)]
def _dot(a,b):return sum(a[i]*b[i] for i in range(3))
def _length(a):return math.sqrt(_dot(a,a))
def _distance(a,b):return _length(_vsub(a,b))
def _normalize(a):
    length=_length(a);return [1.0,0.0,0.0] if length<1e-12 else [value/length for value in a]
def _vec_claim(value,expected,tolerance):return isinstance(value,list) and len(value)==3 and all(_close(value[i],expected[i],tolerance) for i in range(3))


def _camera_basis(camera: dict[str,Any]):
    yaw=math.radians(float(camera["yaw_deg"]));pitch=math.radians(float(camera["pitch_deg"]));target=[float(v) for v in camera["target"]];distance=float(camera["distance"])
    eye=[target[0]+distance*math.cos(pitch)*math.sin(yaw),target[1]+distance*math.sin(pitch),target[2]+distance*math.cos(pitch)*math.cos(yaw)]
    forward=_normalize(_vsub(target,eye));right=_normalize([forward[2],0.0,-forward[0]]);up=_normalize([right[1]*forward[2]-right[2]*forward[1],right[2]*forward[0]-right[0]*forward[2],right[0]*forward[1]-right[1]*forward[0]])
    return eye,forward,right,up


def _project(point,camera,canvas):
    eye,forward,right,up=_camera_basis(camera);relative=_vsub(point,eye);depth=_dot(relative,forward)
    if depth<=.1:return None
    focal=float(canvas["width"])/(2*math.tan(math.radians(float(camera["fov_deg"])/2)))
    return [float(canvas["width"])/2+_dot(relative,right)/depth*focal,float(canvas["height"])/2-_dot(relative,up)/depth*focal,depth]


def _closest_segment(point,a,b):
    segment=_vsub(b,a);denom=_dot(segment,segment);amount=0.0 if denom<1e-12 else max(0.0,min(1.0,_dot(_vsub(point,a),segment)/denom));return _vadd(a,_vmul(segment,amount)),amount


def _push_sphere_nodes(nodes,attached,center,radius):
    collisions=0
    for index,node in enumerate(nodes):
        if index in attached:continue
        delta=_vsub(node,center);distance=_length(delta)
        if distance<radius:
            normal=_normalize(delta);nodes[index]=_vadd(center,_vmul(normal,radius));collisions+=1
    return collisions


def _push_segment_sphere(nodes,attached,center,radius):
    collisions=0
    for index in range(len(nodes)-1):
        closest,amount=_closest_segment(center,nodes[index],nodes[index+1]);delta=_vsub(closest,center);distance=_length(delta)
        if distance<radius:
            correction=_vmul(_normalize(delta),radius-distance);wa=0 if index in attached else 1-amount;wb=0 if index+1 in attached else amount;total=wa+wb
            if total>1e-9:
                if wa:nodes[index]=_vadd(nodes[index],_vmul(correction,wa/total))
                if wb:nodes[index+1]=_vadd(nodes[index+1],_vmul(correction,wb/total))
            collisions+=1
    return collisions


def _push_ring_nodes(nodes,attached,ring,radius):
    collisions=0;center=ring["center"];ring_radius=float(ring["radius"]);normal=ring["normal"]
    for index,node in enumerate(nodes):
        if index in attached:continue
        relative=_vsub(node,center);axial=_dot(relative,normal);plane=_vsub(relative,_vmul(normal,axial));radial=_length(plane);rim=_vadd(center,_vmul(_normalize(plane),ring_radius));delta=_vsub(node,rim);distance=_length(delta)
        if distance<radius:
            nodes[index]=_vadd(rim,_vmul(_normalize(delta),radius));collisions+=1
    return collisions


def _push_segment_ring(nodes,attached,ring,radius):
    """Resolve a cable segment against a torus rim, not merely its endpoints.

    Quarter-point sampling is deterministic in both runtimes and closes the
    tunnelling case where a long segment straddles the rim while both nodes are
    clear.  The correction is distributed using the sampled barycentric weight.
    """
    collisions=0;center=ring["center"];ring_radius=float(ring["radius"]);normal=ring["normal"]
    for index in range(len(nodes)-1):
        best=None
        for amount in (.25,.5,.75):
            sample=_vadd(nodes[index],_vmul(_vsub(nodes[index+1],nodes[index]),amount));relative=_vsub(sample,center);axial=_dot(relative,normal);plane=_vsub(relative,_vmul(normal,axial));rim=_vadd(center,_vmul(_normalize(plane),ring_radius));delta=_vsub(sample,rim);distance=_length(delta)
            if best is None or distance<best[0]:best=(distance,amount,delta)
        distance,amount,delta=best
        if distance<radius:
            correction=_vmul(_normalize(delta),radius-distance);wa=0 if index in attached else 1-amount;wb=0 if index+1 in attached else amount;total=wa+wb
            if total>1e-9:
                if wa:nodes[index]=_vadd(nodes[index],_vmul(correction,wa/total))
                if wb:nodes[index+1]=_vadd(nodes[index+1],_vmul(correction,wb/total))
            collisions+=1
    return collisions


def _torus_distance(point,ring):
    relative=_vsub(point,ring["center"]);axial=_dot(relative,ring["normal"]);plane=_vsub(relative,_vmul(ring["normal"],axial))
    return math.hypot(_length(plane)-float(ring["radius"]),axial)


def _gripper_blocker(before,proposed,controls,pegs,rings):
    """Return the first independently reproducible swept-target blocker."""
    for axis,key in enumerate(("x","y","z")):
        low,high=map(float,controls["world_bounds"][key])
        if proposed[axis]<low-1e-9 or proposed[axis]>high+1e-9:return f"BOUND:{key.upper()}"
    cable_radius=float(controls["cable_radius"])
    for peg in pegs:
        closest,_amount=_closest_segment(peg["center"],before,proposed)
        if _distance(closest,peg["center"])<float(peg["radius"])+cable_radius-1e-9:return f"PEG:{peg['id']}"
    # A control step is only 0.25 world units.  Seventeen deterministic samples
    # leave a 0.015625 maximum interval, far below the 0.21+ solid tube width.
    for ring in rings:
        radius=float(ring["tube_radius"])+cable_radius
        for sample_index in range(17):
            amount=sample_index/16;sample=_vadd(before,_vmul(_vsub(proposed,before),amount))
            if _torus_distance(sample,ring)<radius-1e-9:return f"RING:{ring['id']}"
    return None


def _alarm_contacts(nodes,contacts,cable_radius):
    hits=0
    for contact in contacts:
        radius=float(contact["radius"])+cable_radius;center=contact["center"]
        if any(_distance(node,center)<=radius+1e-9 for node in nodes):hits+=1;continue
        if any(_distance(_closest_segment(center,nodes[i],nodes[i+1])[0],center)<=radius+1e-9 for i in range(len(nodes)-1)):hits+=1
    return hits


def _winding(nodes,peg):
    center=peg["center"];limit=float(peg["radius"])+.28;total=0.0
    for first,second in zip(nodes,nodes[1:]):
        if abs((first[1]+second[1])/2-center[1])>limit:continue
        a=math.atan2(first[2]-center[2],first[0]-center[0]);b=math.atan2(second[2]-center[2],second[0]-center[0]);total+=(b-a+math.pi)%(2*math.pi)-math.pi
    return abs(total)/(2*math.pi)


def _ring_crossings(previous,nodes,rings,passed):
    result=list(passed)
    for index,ring in enumerate(rings):
        endpoint=int(ring["endpoint_index"]);normal=ring["normal"];center=ring["center"]
        before=_dot(_vsub(previous[endpoint],center),normal);after=_dot(_vsub(nodes[endpoint],center),normal)
        if before<0<=after:
            amount=0 if abs(before-after)<1e-9 else before/(before-after);point=_vadd(previous[endpoint],_vmul(_vsub(nodes[endpoint],previous[endpoint]),amount));relative=_vsub(point,center);radial=_length(_vsub(relative,_vmul(normal,_dot(relative,normal))))
            if radial<=float(ring["radius"])-float(ring["tube_radius"]):result[index]=True
    return result


def _step(nodes,previous,grippers,rest_lengths,pegs,rings,contacts,controls,passed):
    old=[list(node) for node in nodes];attached={int(value["node_index"]):value for value in grippers.values() if value["node_index"] is not None};damping=float(controls["damping"])
    for index in range(len(nodes)):
        if index in attached:nodes[index]=list(attached[index]["target"]);previous[index]=list(attached[index]["target"])
        else:
            current=list(nodes[index]);velocity=_vmul(_vsub(nodes[index],previous[index]),damping);nodes[index]=_vadd(nodes[index],velocity);previous[index]=current
    collisions=0;cable_radius=float(controls["cable_radius"])
    for _ in range(int(controls["constraint_iterations"])):
        for index,rest in enumerate(rest_lengths):
            delta=_vsub(nodes[index+1],nodes[index]);distance=_length(delta)
            if distance<1e-10:continue
            correction=_vmul(delta,(distance-float(rest))/distance);wa=0 if index in attached else 1;wb=0 if index+1 in attached else 1;total=wa+wb
            if total:
                if wa:nodes[index]=_vadd(nodes[index],_vmul(correction,wa/total))
                if wb:nodes[index+1]=_vsub(nodes[index+1],_vmul(correction,wb/total))
        for peg in pegs:
            radius=float(peg["radius"])+cable_radius;collisions+=_push_sphere_nodes(nodes,attached,peg["center"],radius);collisions+=_push_segment_sphere(nodes,attached,peg["center"],radius)
        for ring in rings:
            radius=float(ring["tube_radius"])+cable_radius;collisions+=_push_ring_nodes(nodes,attached,ring,radius);collisions+=_push_segment_ring(nodes,attached,ring,radius)
        for node_index,value in attached.items():nodes[node_index]=list(value["target"])
    bounds=controls["world_bounds"]
    for node in nodes:
        for axis,key in enumerate(("x","y","z")):node[axis]=_round(max(float(bounds[key][0]),min(float(bounds[key][1]),node[axis])))
    for node in previous:
        for axis,key in enumerate(("x","y","z")):node[axis]=_round(max(float(bounds[key][0]),min(float(bounds[key][1]),node[axis])))
    passed=_ring_crossings(old,nodes,rings,passed);alarms=_alarm_contacts(nodes,contacts,cable_radius)
    return collisions,alarms,passed


def grade(payload:dict[str,Any],ground_truth:dict[str,Any],public_state:dict[str,Any])->dict[str,Any]:
    challenge_id,task_id=str(ground_truth.get("challenge_id") or ""),str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "")!=MECHANIC_ID or str(ground_truth.get("mechanic_id") or "")!=MECHANIC_ID:return _failure("mechanic mismatch")
    if not task_id or str(payload.get("task_id") or "")!=task_id:return _failure("task mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "")!=challenge_id:return _failure("stale challenge")
    if str(public_state.get("mechanic_id") or "")!=MECHANIC_ID or str(public_state.get("challenge_id") or "")!=challenge_id or str(public_state.get("task_id") or "")!=task_id:return _failure("public autopsy identity mismatch")
    keys=("canvas","nodes","rest_lengths","pegs","rings","contacts","controls","qualification","initial_camera")
    if any(public_state.get(key)!=ground_truth.get(key) for key in keys):return _failure("public cable geometry disagrees with hidden state")
    events=payload.get("events")
    if not isinstance(events,list) or not events or len(events)>1800:return _failure("cable transcript is missing or too long")
    nodes=[list(map(float,node)) for node in ground_truth["nodes"]];previous=[list(node) for node in nodes];camera=dict(ground_truth["initial_camera"]);controls=ground_truth["controls"];qualification=ground_truth["qualification"]
    grippers={"A":{"node_index":None,"target":[0,0,0]},"B":{"node_index":None,"target":[0,0,0]}};selected="A";passed=[False,False];pending=False;active=False;terminal=False;previous_time=-1
    collisions=alarms=ticks=dual_ticks=resets=orbit_moves=0;attachments={"A":0,"B":0}
    for sequence,event in enumerate(events,start=1):
        if terminal:return _failure(f"cable event {sequence} occurs after terminal seal")
        if not isinstance(event,dict) or event.get("seq")!=sequence:return _failure(f"cable event {sequence} has invalid sequence")
        event_time=_number(event.get("t_ms"))
        if event_time is None or not 0<=event_time<=1_200_000 or event_time<previous_time:return _failure(f"cable event {sequence} has invalid timestamp")
        previous_time=event_time;kind=str(event.get("type") or "")
        if kind=="challenge_start":
            if active or sequence!=1:return _failure("cable challenge start is malformed")
            active=True;continue
        if not active:return _failure("cable interaction occurred before fresh standby cleared")
        if kind=="orbit":
            axis=event.get("axis");delta=event.get("delta_deg")
            if pending or axis not in {"yaw","pitch"} or delta not in {-15,-10,10,15}:return _failure(f"orbit event {sequence} is malformed")
            expected_step=controls["orbit_yaw_step_deg"] if axis=="yaw" else controls["orbit_pitch_step_deg"]
            if abs(delta)!=expected_step or not _close(event.get("before_deg"),camera[f"{axis}_deg"]):return _failure(f"orbit event {sequence} reports stale camera")
            camera[f"{axis}_deg"]=_round(max(-70,min(70,camera[f"{axis}_deg"]+delta)),2)
            if not _close(event.get("after_deg"),camera[f"{axis}_deg"]):return _failure(f"orbit event {sequence} lies about camera")
            orbit_moves+=1;continue
        if kind=="select_gripper":
            if pending or event.get("gripper") not in {"A","B"}:return _failure("invalid gripper selection")
            selected=event["gripper"];continue
        if kind=="attach":
            pointer=event.get("pointer");gripper=event.get("gripper")
            if pending or gripper!=selected or gripper not in {"A","B"} or not isinstance(pointer,list) or len(pointer)!=2 or grippers[gripper]["node_index"] is not None:return _failure(f"attachment {sequence} is malformed")
            if not all(_close(event.get("camera",{}).get(key),camera[key]) for key in ("yaw_deg","pitch_deg","distance")):return _failure(f"attachment {sequence} uses stale orbit")
            projected=[_project(node,camera,ground_truth["canvas"]) for node in nodes];candidates=[(math.hypot(item[0]-pointer[0],item[1]-pointer[1]),index) for index,item in enumerate(projected) if item]
            distance,node_index=min(candidates)
            if distance>float(controls["attachment_pick_radius_px"]) or event.get("node_index")!=node_index or any(value["node_index"]==node_index for value in grippers.values()):return _failure(f"attachment {sequence} does not hit a free projected cable node")
            grippers[gripper]={"node_index":node_index,"target":list(nodes[node_index])};attachments[gripper]+=1;continue
        if kind=="detach":
            gripper=event.get("gripper")
            if pending or gripper not in {"A","B"} or grippers[gripper]["node_index"] is None:return _failure(f"detach {sequence} is malformed")
            grippers[gripper]={"node_index":None,"target":[0,0,0]};continue
        if kind=="gripper_move":
            gripper=event.get("gripper");axis=event.get("axis");delta=_number(event.get("delta"))
            if pending or gripper not in {"A","B"} or axis not in {"x","y","z"} or grippers[gripper]["node_index"] is None or delta is None or abs(abs(delta)-float(controls["move_step"]))>1e-9 or not _vec_claim(event.get("before"),grippers[gripper]["target"],.001):return _failure(f"gripper move {sequence} is malformed")
            target=list(grippers[gripper]["target"]);target[{"x":0,"y":1,"z":2}[axis]]=_round(target[{"x":0,"y":1,"z":2}[axis]]+delta);blocker=_gripper_blocker(grippers[gripper]["target"],target,controls,ground_truth["pegs"],ground_truth["rings"]);accepted=blocker is None
            if not _vec_claim(event.get("proposed"),target,.001) or event.get("accepted") is not accepted or event.get("blocker")!=(blocker or ""):return _failure(f"gripper move {sequence} fabricates swept collision acceptance")
            if accepted:grippers[gripper]["target"]=target;pending=True
            if not _vec_claim(event.get("after"),grippers[gripper]["target"],.001):return _failure(f"gripper move {sequence} lies about target")
            continue
        if kind=="physics_tick":
            source=event.get("source");substeps=event.get("substeps")
            if source not in {"control","settle"} or substeps!=int(controls["pbd_substeps"]) or (source=="control")!=pending:return _failure(f"physics tick {sequence} has impossible ordering")
            for _ in range(substeps):
                new_collisions,new_alarms,passed=_step(nodes,previous,grippers,ground_truth["rest_lengths"],ground_truth["pegs"],ground_truth["rings"],ground_truth["contacts"],controls,passed);collisions+=new_collisions;alarms+=new_alarms;ticks+=1
                if all(value["node_index"] is not None for value in grippers.values()):dual_ticks+=1
            claimed=event.get("nodes")
            if not isinstance(claimed,list) or len(claimed)!=len(nodes) or any(not _vec_claim(claimed[i],nodes[i],float(qualification["maximum_client_node_error"])) for i in range(len(nodes))):return _failure(f"physics tick {sequence} fabricates deterministic cable nodes")
            if event.get("ring_passed")!=passed:return _failure(f"physics tick {sequence} lies about ring topology")
            pending=False;continue
        if kind=="reset":
            if pending:return _failure("reset occurred between a control and physics tick")
            nodes=[list(map(float,node)) for node in ground_truth["nodes"]];previous=[list(node) for node in nodes];grippers={"A":{"node_index":None,"target":[0,0,0]},"B":{"node_index":None,"target":[0,0,0]}};passed=[False,False];collisions=alarms=ticks=dual_ticks=0;attachments={"A":0,"B":0};resets+=1;continue
        if kind=="verify":
            if pending:return _failure("autopsy sealed before pending physics")
            contact_now=_alarm_contacts(nodes,ground_truth["contacts"],float(controls["cable_radius"]));winding=_winding(nodes,ground_truth["pegs"][0]);cleared=all(passed) and winding<=float(qualification["maximum_final_winding"]) and alarms==0 and contact_now==0
            if bool(event.get("claimed_clear"))!=cleared:return _failure("terminal seal lies about cable topology or alarms")
            terminal=True;continue
        return _failure(f"cable event {sequence} has invalid action {kind!r}")
    winding=_round(_winding(nodes,ground_truth["pegs"][0]),5);contact_now=_alarm_contacts(nodes,ground_truth["contacts"],float(controls["cable_radius"]));expected={"nodes":[[_round(value) for value in node] for node in nodes],"ring_passed":passed,"winding":winding,"alarm_count":alarms,"active_alarm_contacts":contact_now,"collision_count":collisions,"substeps":ticks,"dual_control_substeps":dual_ticks,"attachments":attachments,"orbit_moves":orbit_moves,"resets":resets,"grippers":grippers}
    claimed=payload.get("final_state");matches=isinstance(claimed,dict) and all(claimed.get(key)==expected[key] for key in ("ring_passed","alarm_count","active_alarm_contacts","collision_count","substeps","dual_control_substeps","attachments","orbit_moves","resets")) and _close(claimed.get("winding"),winding,.002) and claimed.get("grippers")==grippers
    claimed_nodes=claimed.get("nodes") if isinstance(claimed,dict) else None;matches=matches and isinstance(claimed_nodes,list) and len(claimed_nodes)==len(nodes) and all(_vec_claim(claimed_nodes[i],nodes[i],float(qualification["maximum_client_node_error"])) for i in range(len(nodes)))
    if not matches:return _failure("claimed autopsy state does not match independent PBD replay")
    passed_final=terminal and all(passed) and winding<=float(qualification["maximum_final_winding"]) and alarms==0 and contact_now==0 and all(attachments[key]>=1 for key in ("A","B")) and dual_ticks>=int(qualification["minimum_dual_ticks"]) and ticks>=int(qualification["minimum_total_substeps"])
    return {"graded":True,"passed":passed_final,"score":100 if passed_final else 0,"feedback":f"replayed {ticks} zero-g PBD substeps; ring crossings {passed}; winding {winding:.3f}; dual substeps {dual_ticks}; constraint contacts {collisions}; alarms {alarms}/{contact_now}"}


def cheat(public_state:dict[str,Any],ground_truth:dict[str,Any])->dict[str,Any]:
    del public_state
    return {"solution":ground_truth.get("solution") or {},"answers":[]}
