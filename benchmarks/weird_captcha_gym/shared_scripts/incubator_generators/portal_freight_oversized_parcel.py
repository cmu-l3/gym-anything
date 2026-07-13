from __future__ import annotations

import hashlib
import math
import random
from typing import Any


MECHANIC_ID = "portal_freight_oversized_parcel"
PALETTES = ("aperture-ivory", "test-chamber-cyan", "hazard-amber", "freight-oxide")
# 3 source lanes × 3 destination lanes × 2 parcel angles × 2 apertures ×
# 4 destination walls × 2 blue aim offsets × 2 orange aim offsets × 4 palettes.
VARIANT_COUNT = 3 * 3 * 2 * 2 * 4 * 2 * 2 * 4


def _seed_int(seed: str, salt: str) -> int:
    return int(hashlib.sha256(f"{seed}|{salt}".encode()).hexdigest()[:16], 16)


def _round(value: float, digits: int = 5) -> float:
    return round(float(value) + 1e-12, digits)


def _dot(first: list[float], second: list[float]) -> float:
    return sum(first[index] * second[index] for index in range(3))


def _cross(first: list[float], second: list[float]) -> list[float]:
    return [first[1]*second[2]-first[2]*second[1], first[2]*second[0]-first[0]*second[2], first[0]*second[1]-first[1]*second[0]]


def _frame(origin: list[float], normal: list[float], wall_id: str) -> dict[str, Any]:
    up=[0.0,1.0,0.0];right=_cross(up,normal)
    return {"origin":[_round(value) for value in origin],"right":[_round(value) for value in right],"up":up,"normal":normal,"wall_id":wall_id}


def _portal_matrix(source: dict[str, Any], destination: dict[str, Any]) -> list[list[float]]:
    # Frame columns are (right, up, normal).  diag(-1,1,-1) has determinant +1,
    # so the linked transform remains a proper right-handed rigid transform.
    source_basis=[[source[key][row] for key in ("right","up","normal")] for row in range(3)]
    destination_basis=[[destination[key][row] for key in ("right","up","normal")] for row in range(3)]
    flip=[[-1.0,0.0,0.0],[0.0,1.0,0.0],[0.0,0.0,-1.0]]
    rotation=[[sum(destination_basis[row][k]*flip[k][k]*source_basis[col][k] for k in range(3)) for col in range(3)] for row in range(3)]
    translation=[destination["origin"][row]-sum(rotation[row][col]*source["origin"][col] for col in range(3)) for row in range(3)]
    return [[_round(rotation[row][col]) for col in range(3)]+[_round(translation[row])] for row in range(3)]+[[0.0,0.0,0.0,1.0]]


def _transform(matrix: list[list[float]], point: list[float], vector: bool = False) -> list[float]:
    return [_round(sum(matrix[row][col]*point[col] for col in range(3))+(0.0 if vector else matrix[row][3])) for row in range(3)]


def generate(task: dict[str, Any], seed: str) -> tuple[dict[str, Any], dict[str, Any]]:
    rng=random.Random(_seed_int(seed,MECHANIC_ID));challenge_id=hashlib.sha256(f"{seed}|{MECHANIC_ID}".encode()).hexdigest()[:12];task_id=str(task.get("id") or "portal_freight_oversized_parcel_seed_0001@0.1")
    source_lane=rng.choice((2.25,3.2,4.15));destination_lane=rng.choice((2.15,3.2,4.25));initial_angle=rng.choice((-20.0,20.0));aperture_half_width=rng.choice((0.82,0.9));destination_wall=rng.choice(("B-west","B-east","B-north","B-south"));blue_offset=rng.choice((-30.0,30.0));orange_offset=rng.choice((-30.0,30.0));palette=rng.choice(PALETTES)
    room={"width":8.0,"depth":6.4,"height":3.0}
    walls=[]
    for space in ("A","B"):
        walls.extend([
            {"id":f"{space}-west","space":space,"axis":"x","value":0.0,"range":[0.0,room["depth"]],"normal":[1.0,0.0,0.0]},
            {"id":f"{space}-east","space":space,"axis":"x","value":room["width"],"range":[0.0,room["depth"]],"normal":[-1.0,0.0,0.0]},
            {"id":f"{space}-north","space":space,"axis":"z","value":0.0,"range":[0.0,room["width"]],"normal":[0.0,0.0,1.0]},
            {"id":f"{space}-south","space":space,"axis":"z","value":room["depth"],"range":[0.0,room["width"]],"normal":[0.0,0.0,-1.0]},
        ])
    destination_specs={
        "B-west":{"origin":[0.0,1.2,destination_lane],"normal":[1.0,0.0,0.0],"tool_origin":[4.0,1.2,destination_lane],"target_yaw":180.0},
        "B-east":{"origin":[room["width"],1.2,destination_lane],"normal":[-1.0,0.0,0.0],"tool_origin":[4.0,1.2,destination_lane],"target_yaw":0.0},
        "B-north":{"origin":[destination_lane,1.2,0.0],"normal":[0.0,0.0,1.0],"tool_origin":[destination_lane,1.2,room["depth"]/2],"target_yaw":-90.0},
        "B-south":{"origin":[destination_lane,1.2,room["depth"]],"normal":[0.0,0.0,-1.0],"tool_origin":[destination_lane,1.2,room["depth"]/2],"target_yaw":90.0},
    };destination_spec=destination_specs[destination_wall]
    tools={"A":{"origin":[4.0,1.2,source_lane],"yaw_deg":blue_offset},"B":{"origin":destination_spec["tool_origin"],"yaw_deg":destination_spec["target_yaw"]+orange_offset}}
    controls={"aim_step_deg":15.0,"rotate_step_deg":5.0,"push_step":0.25,"maximum_ray_distance":12.0,"portal_half_width":aperture_half_width,"portal_half_height":1.05,"simulation_samples":49}
    parcel={"initial_center":[3.2,1.2,source_lane],"initial_angle_deg":initial_angle,"length":5.2,"half_width":0.18,"half_height":0.18,"display_samples":13}
    source_frame=_frame([room["width"],1.2,source_lane],[-1.0,0.0,0.0],"A-east");destination_frame=_frame(destination_spec["origin"],destination_spec["normal"],destination_wall);expected_matrix=_portal_matrix(source_frame,destination_frame)
    delivery={"space":"B","frame":destination_frame,"local_right":[-.42,.42],"local_up":[-.3,.3],"local_normal":[0.0,5.85],"label":"ORIENTED OVERSIZE RECEIVER"}
    qualification={"minimum_placement_raycasts":2,"minimum_aim_turns":4,"minimum_rotation_events":4,"minimum_push_ticks":25,"minimum_split_ticks":10,"minimum_transformed_velocity_ticks":10,"maximum_final_angle_deg":0.1,"maximum_collisions":0}
    push_count=int(math.ceil((room["width"]+parcel["length"]/2+parcel["half_width"]-parcel["initial_center"][0])/controls["push_step"]))
    public_state={
        "benchmark":"weird_captcha_gym","mechanic_id":MECHANIC_ID,"task_id":task_id,"challenge_id":challenge_id,"asset_manifest":"shared_runtime/assets/provenance/incubator_full_build_v1.json",
        "prompt":task.get("natural_language") or "Place BLUE at the Chamber A source and ORANGE at the Chamber B receiver. Deliver the oversized parcel intact.","generator":{"name":"right_handed_portal_freight_v1","variant_count":VARIANT_COUNT,"variant_count_kind":"discrete_geometry_and_palette"},
        "manifest_id":f"PF-{challenge_id[:5].upper()}-{rng.randint(100,999)}","palette":palette,"canvas":{"width":900,"height":468},"room":room,"walls":walls,"tools":tools,"controls":controls,"parcel":parcel,"delivery":delivery,"qualification":qualification,"submit_label":"CLOSE MANIFEST",
    }
    ground_truth={
        "mechanic_id":MECHANIC_ID,"task_id":task_id,"seed":seed,"challenge_id":challenge_id,"canvas":public_state["canvas"],"room":room,"walls":walls,"tools":tools,"controls":controls,"parcel":parcel,"delivery":delivery,"qualification":qualification,"variant_count":VARIANT_COUNT,
        "solution":{"blue":{"space":"A","frame":source_frame,"aim_delta":-15.0 if blue_offset>0 else 15.0,"aim_count":2},"orange":{"space":"B","frame":destination_frame,"aim_delta":-15.0 if orange_offset>0 else 15.0,"aim_count":2},"matrix":expected_matrix,"rotation_delta":-5.0 if initial_angle>0 else 5.0,"rotation_count":int(abs(initial_angle)/controls["rotate_step_deg"]),"push_count":push_count},
    }
    rotation=[row[:3] for row in expected_matrix[:3]];det=(rotation[0][0]*(rotation[1][1]*rotation[2][2]-rotation[1][2]*rotation[2][1])-rotation[0][1]*(rotation[1][0]*rotation[2][2]-rotation[1][2]*rotation[2][0])+rotation[0][2]*(rotation[1][0]*rotation[2][1]-rotation[1][1]*rotation[2][0]))
    assert abs(det-1.0)<1e-9
    mapped=_transform(expected_matrix,[room["width"]+.5,1.2,source_lane]);velocity=_transform(expected_matrix,[.25,0.0,0.0],vector=True);expected_mapped=[_round(destination_frame["origin"][i]+destination_frame["normal"][i]*.5) for i in range(3)];expected_velocity=[_round(destination_frame["normal"][i]*.25) for i in range(3)];inverse=_portal_matrix(destination_frame,source_frame)
    assert mapped==expected_mapped and velocity==expected_velocity and _transform(inverse,mapped)==[room["width"]+.5,1.2,source_lane]
    assert push_count>=qualification["minimum_push_ticks"]
    return public_state,ground_truth
