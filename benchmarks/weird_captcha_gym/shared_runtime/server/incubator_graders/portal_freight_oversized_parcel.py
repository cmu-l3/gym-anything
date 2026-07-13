from __future__ import annotations

import copy
import math
from typing import Any


MECHANIC_ID="portal_freight_oversized_parcel"


def _failure(message:str)->dict[str,Any]:return {"graded":True,"passed":False,"score":0,"feedback":message}
def _number(value:Any)->float|None:
    try:result=float(value)
    except (TypeError,ValueError):return None
    return result if math.isfinite(result) else None
def _close(first:Any,second:Any,tolerance:float=.001)->bool:
    a,b=_number(first),_number(second);return a is not None and b is not None and abs(a-b)<=tolerance
def _round(value:float,digits:int=5)->float:return round(float(value)+1e-12,digits)
def _add(a,b):return[a[i]+b[i] for i in range(3)]
def _sub(a,b):return[a[i]-b[i] for i in range(3)]
def _mul(a,s):return[a[i]*s for i in range(3)]
def _dot(a,b):return sum(a[i]*b[i] for i in range(3))
def _cross(a,b):return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def _vec_claim(value,expected,tolerance=.001):return isinstance(value,list) and len(value)==3 and all(_close(value[i],expected[i],tolerance) for i in range(3))


def _direction(yaw_deg:float)->list[float]:
    yaw=math.radians(yaw_deg);return[_round(math.cos(yaw)),0.0,_round(math.sin(yaw))]


def _frame(origin:list[float],normal:list[float],wall_id:str)->dict[str,Any]:
    return {"origin":[_round(value) for value in origin],"right":[_round(value) for value in _cross([0.0,1.0,0.0],normal)],"up":[0.0,1.0,0.0],"normal":list(normal),"wall_id":wall_id}


def _raycast(space:str,origin:list[float],direction:list[float],walls:list[dict[str,Any]],maximum:float)->dict[str,Any]|None:
    candidates=[]
    for wall in walls:
        if wall["space"]!=space:continue
        axis=0 if wall["axis"]=="x" else 2;other=2 if axis==0 else 0
        if abs(direction[axis])<1e-9:continue
        amount=(float(wall["value"])-origin[axis])/direction[axis]
        if amount<=1e-6 or amount>maximum+1e-9:continue
        point=_add(origin,_mul(direction,amount));low,high=map(float,wall["range"])
        if low-1e-9<=point[other]<=high+1e-9:candidates.append((amount,wall["id"],wall,[_round(value) for value in point]))
    if not candidates:return None
    _amount,_wall_id,wall,point=min(candidates,key=lambda item:(item[0],item[1]));return {"wall_id":wall["id"],"point":point,"frame":_frame(point,wall["normal"],wall["id"])}


def _placement_blocker(hit:dict[str,Any],walls:list[dict[str,Any]],controls:dict[str,Any])->str|None:
    wall=next(item for item in walls if item["id"]==hit["wall_id"]);coordinate=hit["point"][2 if wall["axis"]=="x" else 0];low,high=map(float,wall["range"]);half_width=float(controls["portal_half_width"])
    return "PORTAL_OVERHANG" if coordinate-half_width<low-1e-9 or coordinate+half_width>high+1e-9 else None


def _portal_matrix(source:dict[str,Any],destination:dict[str,Any])->list[list[float]]:
    source_basis=[[source[key][row] for key in ("right","up","normal")] for row in range(3)];destination_basis=[[destination[key][row] for key in ("right","up","normal")] for row in range(3)];flip=(-1.0,1.0,-1.0)
    rotation=[[sum(destination_basis[row][k]*flip[k]*source_basis[col][k] for k in range(3)) for col in range(3)] for row in range(3)];translation=[destination["origin"][row]-sum(rotation[row][col]*source["origin"][col] for col in range(3)) for row in range(3)]
    return [[_round(rotation[row][col]) for col in range(3)]+[_round(translation[row])] for row in range(3)]+[[0.0,0.0,0.0,1.0]]


def _transform(matrix:list[list[float]],point:list[float],vector:bool=False)->list[float]:
    return [_round(sum(matrix[row][col]*point[col] for col in range(3))+(0.0 if vector else matrix[row][3])) for row in range(3)]


def _linked(portals:dict[str,Any])->bool:return isinstance(portals.get("blue"),dict) and isinstance(portals.get("orange"),dict)


def _canonical_points(center:list[float],angle_deg:float,length:float,count:int)->list[list[float]]:
    angle=math.radians(angle_deg);axis=[math.cos(angle),0.0,math.sin(angle)];return [[_round(center[i]+axis[i]*(-length/2+length*index/(count-1))) for i in range(3)] for index in range(count)]


def _locate(point:list[float],portals:dict[str,Any],state:dict[str,Any])->tuple[str,list[float],str|None]:
    room,parcel,controls=state["room"],state["parcel"],state["controls"];half_width=float(parcel["half_width"]);half_height=float(parcel["half_height"])
    if point[0]-half_width<-1e-8 or point[2]-half_width<-1e-8 or point[2]+half_width>float(room["depth"])+1e-8:return "A",point,"SOURCE_WALL"
    if point[0]+half_width<=float(room["width"])+1e-8:return "A",point,None
    if not _linked(portals) or portals["blue"].get("space")!="A" or portals["blue"].get("wall_id")!="A-east":return "A",point,"UNLINKED_EAST_WALL"
    source=portals["blue"]["frame"];relative=_sub(point,source["origin"]);lateral=_dot(relative,source["right"]);vertical=_dot(relative,source["up"])
    if abs(lateral)+half_width>float(controls["portal_half_width"])+1e-8 or abs(vertical)+half_height>float(controls["portal_half_height"])+1e-8:return "A",point,"SOURCE_APERTURE"
    if point[0]<=float(room["width"])+1e-8:return "A",point,None
    matrix=_portal_matrix(source,portals["orange"]["frame"]);mapped=_transform(matrix,point)
    destination=portals["orange"];relative_destination=_sub(mapped,destination["frame"]["origin"]);destination_lateral=_dot(relative_destination,destination["frame"]["right"]);destination_vertical=_dot(relative_destination,destination["frame"]["up"])
    if abs(destination_lateral)+half_width>float(controls["portal_half_width"])+1e-8 or abs(destination_vertical)+half_height>float(controls["portal_half_height"])+1e-8:return "B",mapped,"DESTINATION_APERTURE"
    violations=[]
    if mapped[0]-half_width<-1e-8:violations.append("B-west")
    if mapped[0]+half_width>float(room["width"])+1e-8:violations.append("B-east")
    if mapped[2]-half_width<-1e-8:violations.append("B-north")
    if mapped[2]+half_width>float(room["depth"])+1e-8:violations.append("B-south")
    if any(wall_id!=destination["wall_id"] for wall_id in violations):return "B",mapped,"DESTINATION_WALL"
    return "B",mapped,None


def _configuration(center:list[float],angle_deg:float,portals:dict[str,Any],state:dict[str,Any],count:int)->tuple[list[dict[str,Any]],str|None]:
    result=[]
    for index,point in enumerate(_canonical_points(center,angle_deg,float(state["parcel"]["length"]),count)):
        space,position,blocker=_locate(point,portals,state)
        if blocker:return [],blocker
        result.append({"id":index,"space":space,"position":position})
    return result,None


def _proposal(before_center:list[float],before_angle:float,after_center:list[float],after_angle:float,portals:dict[str,Any],state:dict[str,Any])->tuple[list[dict[str,Any]],str|None]:
    for sweep in range(1,6):
        amount=sweep/5;center=[before_center[i]+(after_center[i]-before_center[i])*amount for i in range(3)];angle=before_angle+(after_angle-before_angle)*amount
        _dense,blocker=_configuration(center,angle,portals,state,int(state["controls"]["simulation_samples"]))
        if blocker:return [],blocker
    after_points,blocker=_configuration(after_center,after_angle,portals,state,int(state["parcel"]["display_samples"]))
    if blocker:return [],blocker
    before_canonical=_canonical_points(before_center,before_angle,float(state["parcel"]["length"]),int(state["parcel"]["display_samples"]));after_canonical=_canonical_points(after_center,after_angle,float(state["parcel"]["length"]),int(state["parcel"]["display_samples"]));matrix=_portal_matrix(portals["blue"]["frame"],portals["orange"]["frame"]) if _linked(portals) else None
    for index,sample in enumerate(after_points):
        velocity=_sub(after_canonical[index],before_canonical[index]);sample["velocity"]=_transform(matrix,velocity,vector=True) if sample["space"]=="B" and matrix else [_round(value) for value in velocity]
    return after_points,None


def _samples_claim(value:Any,expected:list[dict[str,Any]],tolerance:float=.002)->bool:
    return isinstance(value,list) and len(value)==len(expected) and all(isinstance(value[i],dict) and value[i].get("id")==expected[i]["id"] and value[i].get("space")==expected[i]["space"] and _vec_claim(value[i].get("position"),expected[i]["position"],tolerance) and _vec_claim(value[i].get("velocity"),expected[i]["velocity"],tolerance) for i in range(len(expected)))


def _delivered(samples:list[dict[str,Any]],angle:float,state:dict[str,Any])->bool:
    delivery=state["delivery"];frame=delivery["frame"];half_width=float(state["parcel"]["half_width"]);half_height=float(state["parcel"]["half_height"])
    def contained(sample):
        relative=_sub(sample["position"],frame["origin"]);right=_dot(relative,frame["right"]);up=_dot(relative,frame["up"]);normal=_dot(relative,frame["normal"])
        return sample["space"]==delivery["space"] and right-half_width>=float(delivery["local_right"][0])-1e-8 and right+half_width<=float(delivery["local_right"][1])+1e-8 and up-half_height>=float(delivery["local_up"][0])-1e-8 and up+half_height<=float(delivery["local_up"][1])+1e-8 and normal-half_width>=float(delivery["local_normal"][0])-1e-8 and normal+half_width<=float(delivery["local_normal"][1])+1e-8
    return abs(angle)<=float(state["qualification"]["maximum_final_angle_deg"])+1e-9 and bool(samples) and all(contained(sample) for sample in samples)


def grade(payload:dict[str,Any],ground_truth:dict[str,Any],public_state:dict[str,Any])->dict[str,Any]:
    challenge_id,task_id=str(ground_truth.get("challenge_id") or ""),str(ground_truth.get("task_id") or "")
    if str(payload.get("mechanic_id") or "")!=MECHANIC_ID or str(ground_truth.get("mechanic_id") or "")!=MECHANIC_ID:return _failure("mechanic mismatch")
    if not task_id or str(payload.get("task_id") or "")!=task_id:return _failure("task mismatch")
    if not challenge_id or str(payload.get("challenge_id") or "")!=challenge_id:return _failure("stale challenge")
    if str(public_state.get("mechanic_id") or "")!=MECHANIC_ID or str(public_state.get("challenge_id") or "")!=challenge_id or str(public_state.get("task_id") or "")!=task_id:return _failure("public freight identity mismatch")
    keys=("canvas","room","walls","tools","controls","parcel","delivery","qualification")
    if any(public_state.get(key)!=ground_truth.get(key) for key in keys):return _failure("public freight chamber disagrees with hidden state")
    events=payload.get("events")
    if not isinstance(events,list) or not events or len(events)>1600:return _failure("freight transcript is missing or too long")
    state=ground_truth;tools=copy.deepcopy(ground_truth["tools"]);portals={"blue":None,"orange":None};center=list(map(float,state["parcel"]["initial_center"]));angle=float(state["parcel"]["initial_angle_deg"]);initial,_blocker=_configuration(center,angle,portals,state,int(state["parcel"]["display_samples"]));samples=[{**item,"velocity":[0.0,0.0,0.0]} for item in initial]
    active_space="A";pending=None;active=False;terminal=False;previous_time=-1;placements=aim_turns=rotation_events=push_ticks=split_ticks=transformed_ticks=collisions=resets=0
    for sequence,event in enumerate(events,start=1):
        if terminal:return _failure(f"freight event {sequence} occurs after manifest close")
        if not isinstance(event,dict) or event.get("seq")!=sequence:return _failure(f"freight event {sequence} has invalid sequence")
        event_time=_number(event.get("t_ms"))
        if event_time is None or not 0<=event_time<=1_200_000 or event_time<previous_time:return _failure(f"freight event {sequence} has invalid timestamp")
        previous_time=event_time;kind=str(event.get("type") or "")
        if kind=="challenge_start":
            if active or sequence!=1:return _failure("freight challenge start is malformed")
            active=True;continue
        if not active:return _failure("freight operation occurred before chamber activation")
        if kind=="space_select":
            if pending or event.get("before")!=active_space or event.get("after") not in {"A","B"}:return _failure(f"space select {sequence} is malformed")
            active_space=event["after"];continue
        if kind=="aim":
            space=event.get("space");delta=_number(event.get("delta_deg"))
            if pending or space!=active_space or space not in {"A","B"} or delta is None or abs(abs(delta)-float(state["controls"]["aim_step_deg"]))>1e-9 or not _close(event.get("before_deg"),tools[space]["yaw_deg"]):return _failure(f"aim event {sequence} is malformed")
            tools[space]["yaw_deg"]=_round(tools[space]["yaw_deg"]+delta,2)
            if not _close(event.get("after_deg"),tools[space]["yaw_deg"]):return _failure(f"aim event {sequence} lies about yaw")
            aim_turns+=1;continue
        if kind=="portal_place":
            color,space=event.get("color"),event.get("space")
            if pending or color not in {"blue","orange"} or space!=active_space:return _failure(f"portal ray {sequence} is malformed")
            origin=list(map(float,tools[space]["origin"]));direction=_direction(float(tools[space]["yaw_deg"]));hit=_raycast(space,origin,direction,state["walls"],float(state["controls"]["maximum_ray_distance"]))
            if hit is None:return _failure(f"portal ray {sequence} cannot hit the claimed chamber")
            claim_hit=event.get("hit")
            if not _vec_claim(event.get("ray_origin"),origin) or not _vec_claim(event.get("ray_direction"),direction) or not isinstance(claim_hit,dict) or claim_hit.get("wall_id")!=hit["wall_id"] or not _vec_claim(claim_hit.get("point"),hit["point"]) or event.get("frame")!=hit["frame"]:return _failure(f"portal ray {sequence} fabricates hit geometry")
            blocker=_placement_blocker(hit,state["walls"],state["controls"]);accepted=blocker is None
            if event.get("accepted") is not accepted or event.get("blocker")!=(blocker or ""):return _failure(f"portal ray {sequence} fabricates panel clearance")
            if accepted:portals[color]={"color":color,"space":space,"wall_id":hit["wall_id"],"frame":hit["frame"]};placements+=1
            matrix=_portal_matrix(portals["blue"]["frame"],portals["orange"]["frame"]) if _linked(portals) else None
            if event.get("linked_matrix")!=matrix:return _failure(f"portal ray {sequence} lies about linked transform")
            continue
        if kind in {"parcel_rotate","parcel_push"}:
            if pending:return _failure(f"parcel control {sequence} overlaps pending physics")
            before_center=list(center);before_angle=angle
            if kind=="parcel_rotate":
                delta=_number(event.get("delta_deg"))
                if delta is None or abs(abs(delta)-float(state["controls"]["rotate_step_deg"]))>1e-9 or not _close(event.get("before_angle_deg"),angle):return _failure(f"parcel rotation {sequence} is malformed")
                after_center=list(center);after_angle=_round(angle+delta,2)
            else:
                delta=_number(event.get("delta"))
                if delta is None or abs(abs(delta)-float(state["controls"]["push_step"]))>1e-9 or not _vec_claim(event.get("before_center"),center):return _failure(f"parcel push {sequence} is malformed")
                axis=[math.cos(math.radians(angle)),0.0,math.sin(math.radians(angle))];after_center=[_round(center[i]+axis[i]*delta) for i in range(3)];after_angle=angle
            proposed,blocker=_proposal(before_center,before_angle,after_center,after_angle,portals,state);accepted=blocker is None
            if event.get("accepted") is not accepted or event.get("blocker")!=(blocker or "") or not _vec_claim(event.get("proposed_center"),after_center) or not _close(event.get("proposed_angle_deg"),after_angle):return _failure(f"parcel control {sequence} fabricates swept collision result")
            if not accepted:collisions+=1;continue
            pending={"source":"rotate" if kind=="parcel_rotate" else "push","center":after_center,"angle":after_angle,"samples":proposed};continue
        if kind=="freight_tick":
            if not pending or event.get("source")!=pending["source"] or not _vec_claim(event.get("center"),pending["center"]) or not _close(event.get("angle_deg"),pending["angle"]) or not _samples_claim(event.get("samples"),pending["samples"]):return _failure(f"freight tick {sequence} fabricates transformed parcel state")
            center=list(pending["center"]);angle=float(pending["angle"]);samples=pending["samples"]
            if pending["source"]=="push":push_ticks+=1
            else:rotation_events+=1
            spaces={sample["space"] for sample in samples}
            if spaces=={"A","B"}:split_ticks+=1
            if any(sample["space"]=="B" and math.sqrt(_dot(sample["velocity"],sample["velocity"]))>1e-7 for sample in samples):transformed_ticks+=1
            pending=None;continue
        if kind=="reset":
            if pending:return _failure("freight reset occurred during pending physics")
            tools=copy.deepcopy(ground_truth["tools"]);portals={"blue":None,"orange":None};center=list(map(float,state["parcel"]["initial_center"]));angle=float(state["parcel"]["initial_angle_deg"]);initial,_blocker=_configuration(center,angle,portals,state,int(state["parcel"]["display_samples"]));samples=[{**item,"velocity":[0.0,0.0,0.0]} for item in initial];active_space="A";placements=aim_turns=rotation_events=push_ticks=split_ticks=transformed_ticks=collisions=0;resets+=1;continue
        if kind=="verify":
            if pending:return _failure("manifest closed during pending freight physics")
            delivered=_delivered(samples,angle,state)
            if bool(event.get("claimed_delivered"))!=delivered:return _failure("manifest lies about receiver containment")
            terminal=True;continue
        return _failure(f"freight event {sequence} has invalid action {kind!r}")
    expected={"portals":portals,"center":[_round(value) for value in center],"angle_deg":_round(angle,2),"samples":samples,"placement_raycasts":placements,"aim_turns":aim_turns,"rotation_events":rotation_events,"push_ticks":push_ticks,"split_ticks":split_ticks,"transformed_velocity_ticks":transformed_ticks,"collisions":collisions,"resets":resets,"linked":_linked(portals),"delivered":_delivered(samples,angle,state)}
    claimed=payload.get("final_state");matches=isinstance(claimed,dict) and claimed.get("portals")==expected["portals"] and _vec_claim(claimed.get("center"),expected["center"]) and _close(claimed.get("angle_deg"),expected["angle_deg"]) and _samples_claim(claimed.get("samples"),samples) and all(claimed.get(key)==expected[key] for key in ("placement_raycasts","aim_turns","rotation_events","push_ticks","split_ticks","transformed_velocity_ticks","collisions","resets","linked","delivered"))
    if not matches:return _failure("claimed freight state does not match independent frame replay")
    q=state["qualification"];passed=terminal and expected["delivered"] and placements>=int(q["minimum_placement_raycasts"]) and aim_turns>=int(q["minimum_aim_turns"]) and rotation_events>=int(q["minimum_rotation_events"]) and push_ticks>=int(q["minimum_push_ticks"]) and split_ticks>=int(q["minimum_split_ticks"]) and transformed_ticks>=int(q["minimum_transformed_velocity_ticks"]) and collisions<=int(q["maximum_collisions"])
    return {"graded":True,"passed":passed,"score":100 if passed else 0,"feedback":f"replayed {placements} portal raycasts, {rotation_events} rotations, {push_ticks} swept pushes; split {split_ticks} ticks; transformed velocity {transformed_ticks}; collisions {collisions}; delivered {expected['delivered']}"}


def cheat(public_state:dict[str,Any],ground_truth:dict[str,Any])->dict[str,Any]:
    del public_state
    return {"solution":ground_truth.get("solution") or {},"answers":[]}
