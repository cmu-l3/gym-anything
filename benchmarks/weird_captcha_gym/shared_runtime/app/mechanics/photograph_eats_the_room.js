(() => {
  "use strict";

  let model = null;
  let activeCleanup = null;
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const round2 = (value) => Math.round(Number(value) * 100) / 100;
  const angleError = (first, second) => Math.abs(((first - second + 180) % 360 + 360) % 360 - 180);
  const cameraCopy = () => ({x: round2(model.camera.x), y: round2(model.camera.y), yaw_deg: round2(model.camera.yaw_deg)});
  const planeCopy = () => ({lateral: round2(model.plane.lateral), depth: round2(model.plane.depth), rotation_deg: round2(model.plane.rotation_deg), scale: round2(model.plane.scale)});
  const nowMs = () => Math.round(performance.now() - model.startedAt);
  function pushEvent(event) { const item = {seq: model.events.length + 1, t_ms: nowMs(), ...event}; model.events.push(item); return item; }

  function projectSource(camera, source) {
    const yaw = camera.yaw_deg * Math.PI / 180;
    const cosine = Math.cos(yaw), sine = Math.sin(yaw), halfFov = Math.tan(Number(model.state.controls.fov_deg) * Math.PI / 360);
    const endpoints = [];
    for (const endpoint of source.endpoints) {
      const dx = Number(endpoint.x) - camera.x, dy = Number(endpoint.y) - camera.y;
      const forward = dx * cosine + dy * sine, side = -dx * sine + dy * cosine;
      if (forward <= .2) return null;
      endpoints.push({u: Math.round((.5 + side / (2 * forward * halfFov)) * 10000) / 10000, depth: Math.round(forward * 10000) / 10000});
    }
    const distance = Math.hypot(Number(source.midpoint.x) - camera.x, Number(source.midpoint.y) - camera.y);
    if (distance > Number(model.state.qualification.capture_range) || endpoints.some((item) => item.u < .04 || item.u > .96)) return null;
    return {endpoints, distance: Math.round(distance * 10000) / 10000};
  }

  function sourceOccluded(source) {
    const wallX=Number(model.state.room.divider.x),targetX=Number(source.midpoint.x),targetY=Number(source.midpoint.y);
    if((model.camera.x-wallX)*(targetX-wallX)>=0||Math.abs(targetX-model.camera.x)<1e-9)return false;
    const amount=(wallX-model.camera.x)/(targetX-model.camera.x),crossingY=model.camera.y+(targetY-model.camera.y)*amount;
    const opening=model.operations.find((item)=>item.operation==="carve_opening");
    return !opening||!nearSegment({x:wallX,y:crossingY},opening,.45);
  }

  function nearSegment(pointValue, operation, halfWidth) {
    const radians = Number(operation.angle_deg) * Math.PI / 180;
    const dx = pointValue.x - Number(operation.center.x), dy = pointValue.y - Number(operation.center.y);
    const along = dx * Math.cos(radians) + dy * Math.sin(radians);
    const across = -dx * Math.sin(radians) + dy * Math.cos(radians);
    return Math.abs(along) <= Number(operation.length) / 2 + .12 + 1e-9 && Math.abs(across) <= halfWidth + 1e-9;
  }

  function collisionMove(dx, dy) {
    const room = model.state.room, radius = Number(model.state.qualification.collision_radius);
    const bridge = model.operations.find((item) => item.operation === "add_walkway");
    const opening = model.operations.find((item) => item.operation === "carve_opening");
    const old = {x: model.camera.x, y: model.camera.y};
    function valid(x, y, previous) {
      if (x < radius || x > Number(room.width) - radius || y < radius || y > Number(room.height) - radius) return false;
      const voidArea = room.void;
      if (x >= Number(voidArea.x1) && x <= Number(voidArea.x2) && y >= Number(voidArea.y1) && y <= Number(voidArea.y2)) {
        if (!bridge || !nearSegment({x, y}, bridge, Number(model.state.qualification.bridge_half_width))) return false;
      }
      const wallX = Number(room.divider.x);
      const crosses = (previous.x - wallX) * (x - wallX) <= 0 && Math.abs(x - previous.x) > 1e-9;
      if (crosses || Math.abs(x - wallX) < radius) {
        if (!opening || !nearSegment({x: wallX, y}, opening, .45)) return false;
      }
      return true;
    }
    const full = {x: old.x + dx, y: old.y + dy};
    if (valid(full.x, full.y, old)) return {x: round2(full.x), y: round2(full.y)};
    const onlyX = {x: old.x + dx, y: old.y}; if (valid(onlyX.x, onlyX.y, old)) return {x: round2(onlyX.x), y: round2(onlyX.y)};
    const onlyY = {x: old.x, y: old.y + dy}; if (valid(onlyY.x, onlyY.y, old)) return {x: round2(onlyY.x), y: round2(onlyY.y)};
    return old;
  }

  function mappedGeometry() {
    const yaw = model.camera.yaw_deg * Math.PI / 180;
    return {
      center: {x: round2(model.camera.x + Math.cos(yaw) * model.plane.depth - Math.sin(yaw) * model.plane.lateral), y: round2(model.camera.y + Math.sin(yaw) * model.plane.depth + Math.cos(yaw) * model.plane.lateral)},
      angle_deg: round2((model.camera.yaw_deg + model.plane.rotation_deg) % 360),
      length: round2(Number(model.carrying.length) * model.plane.scale),
    };
  }

  function worldToCamera(pointValue) {
    const yaw = model.camera.yaw_deg * Math.PI / 180;
    const dx = Number(pointValue.x) - model.camera.x, dy = Number(pointValue.y) - model.camera.y;
    return {forward: dx * Math.cos(yaw) + dy * Math.sin(yaw), side: -dx * Math.sin(yaw) + dy * Math.cos(yaw)};
  }

  function projectFloor(pointValue, canvas) {
    const local = worldToCamera(pointValue); if (local.forward <= .12) return null;
    const focal = canvas.width / (2 * Math.tan(Number(model.state.controls.fov_deg) * Math.PI / 360));
    return {x: canvas.width / 2 + local.side / local.forward * focal, y: canvas.height * .46 + 1.45 / local.forward * focal, depth: local.forward};
  }

  function drawFloor(context, canvas) {
    const gradient = context.createLinearGradient(0, 0, 0, canvas.height);
    gradient.addColorStop(0, "#16192b"); gradient.addColorStop(.46, "#25233b"); gradient.addColorStop(1, "#735164");
    context.fillStyle = gradient; context.fillRect(0, 0, canvas.width, canvas.height);
    context.strokeStyle = "rgba(255,234,212,.16)"; context.lineWidth = 1;
    for (let x = 0; x <= Number(model.state.room.width); x += 1) {
      const a = projectFloor({x, y: .1}, canvas), b = projectFloor({x, y: Number(model.state.room.height) - .1}, canvas);
      if (a && b) { context.beginPath(); context.moveTo(a.x, a.y); context.lineTo(b.x, b.y); context.stroke(); }
    }
    for (let y = 0; y <= Number(model.state.room.height); y += 1) {
      const a = projectFloor({x: .1, y}, canvas), b = projectFloor({x: Number(model.state.room.width) - .1, y}, canvas);
      if (a && b) { context.beginPath(); context.moveTo(a.x, a.y); context.lineTo(b.x, b.y); context.stroke(); }
    }
  }

  function drawFloorQuad(context, canvas, corners, fill, stroke) {
    const points = corners.map((item) => projectFloor(item, canvas)); if (points.some((item) => !item)) return;
    context.beginPath(); context.moveTo(points[0].x, points[0].y); points.slice(1).forEach((item) => context.lineTo(item.x, item.y)); context.closePath();
    context.fillStyle = fill; context.fill(); context.strokeStyle = stroke; context.lineWidth = 2; context.stroke();
  }

  function drawWallSegment(context, canvas, first, second, color = "#e4c8b7") {
    const a = projectFloor(first, canvas), b = projectFloor(second, canvas); if (!a || !b) return;
    const topA = a.y - 2.55 / a.depth * canvas.width * .65, topB = b.y - 2.55 / b.depth * canvas.width * .65;
    context.beginPath(); context.moveTo(a.x, a.y); context.lineTo(b.x, b.y); context.lineTo(b.x, topB); context.lineTo(a.x, topA); context.closePath();
    context.fillStyle = color; context.fill(); context.strokeStyle = "#301f34"; context.lineWidth = 2; context.stroke();
  }

  function drawSource(context, canvas, source) {
    if (model.usedSources.includes(source.id)) return;
    const first = projectFloor(source.endpoints[0], canvas), second = projectFloor(source.endpoints[1], canvas); if (!first || !second) return;
    const liftA = first.y - Number(source.height) / first.depth * canvas.width * .65, liftB = second.y - Number(source.height) / second.depth * canvas.width * .65;
    context.beginPath(); context.moveTo(first.x, liftA); context.lineTo(second.x, liftB); context.strokeStyle = source.kind === "beam" ? "#ff896e" : "#8ef1de"; context.lineWidth = Math.max(4, 16 / Math.min(first.depth, second.depth)); context.stroke();
    context.strokeStyle = "rgba(255,255,255,.7)"; context.lineWidth = 1; context.stroke();
  }

  function drawPhotoPlane(context, canvas) {
    if (!model.carrying) return;
    const mapped = mappedGeometry(), radians = mapped.angle_deg * Math.PI / 180, half = mapped.length / 2;
    const first = {x: mapped.center.x - Math.cos(radians) * half, y: mapped.center.y - Math.sin(radians) * half};
    const second = {x: mapped.center.x + Math.cos(radians) * half, y: mapped.center.y + Math.sin(radians) * half};
    const a = projectFloor(first, canvas), b = projectFloor(second, canvas); if (!a || !b) return;
    const topA = a.y - 1.65 / a.depth * canvas.width * .65, topB = b.y - 1.65 / b.depth * canvas.width * .65;
    context.beginPath(); context.moveTo(a.x, a.y); context.lineTo(b.x, b.y); context.lineTo(b.x, topB); context.lineTo(a.x, topA); context.closePath();
    context.fillStyle = "rgba(246,235,210,.74)"; context.fill(); context.strokeStyle = "#ff7f66"; context.lineWidth = 4; context.stroke();
    context.strokeStyle = "rgba(45,30,52,.72)"; context.setLineDash([6, 5]); context.beginPath(); context.moveTo(a.x, (a.y + topA) / 2); context.lineTo(b.x, (b.y + topB) / 2); context.stroke(); context.setLineDash([]);
  }

  function drawScene() {
    const canvas = document.getElementById("photo-room-canvas"), context = canvas?.getContext("2d"); if (!canvas || !context || !model) return;
    drawFloor(context, canvas);
    const room = model.state.room, voidArea = room.void;
    drawFloorQuad(context, canvas, [{x:voidArea.x1,y:voidArea.y1},{x:voidArea.x2,y:voidArea.y1},{x:voidArea.x2,y:voidArea.y2},{x:voidArea.x1,y:voidArea.y2}], "rgba(10,7,19,.94)", "#ff846b");
    const bridge = model.operations.find((item) => item.operation === "add_walkway");
    if (bridge) {
      const half = bridge.length / 2, width = .48; drawFloorQuad(context, canvas, [{x:bridge.center.x-half,y:bridge.center.y-width},{x:bridge.center.x+half,y:bridge.center.y-width},{x:bridge.center.x+half,y:bridge.center.y+width},{x:bridge.center.x-half,y:bridge.center.y+width}], "#f4d7bd", "#ff8066");
    }
    const wallX = Number(room.divider.x), opening = model.operations.find((item) => item.operation === "carve_opening");
    if (opening) {
      const half = opening.length / 2; drawWallSegment(context, canvas, {x:wallX,y:.35}, {x:wallX,y:opening.center.y-half}); drawWallSegment(context, canvas, {x:wallX,y:opening.center.y+half}, {x:wallX,y:Number(room.height)-.35});
    } else drawWallSegment(context, canvas, {x:wallX,y:.35}, {x:wallX,y:Number(room.height)-.35});
    model.state.sources.forEach((source) => drawSource(context, canvas, source));
    const terminal = projectFloor(room.terminal, canvas); if (terminal) { const size = clamp(110 / terminal.depth, 12, 55); context.fillStyle = "#91f1dc"; context.fillRect(terminal.x-size/2, terminal.y-size*1.7, size, size*1.7); context.strokeStyle="#112b32";context.lineWidth=3;context.strokeRect(terminal.x-size/2,terminal.y-size*1.7,size,size*1.7); }
    drawPhotoPlane(context, canvas);
    context.strokeStyle = "rgba(255,245,226,.84)"; context.lineWidth = 1.5; context.beginPath(); context.arc(canvas.width/2, canvas.height*.46, 25, 0, Math.PI*2); context.moveTo(canvas.width/2-38,canvas.height*.46);context.lineTo(canvas.width/2-12,canvas.height*.46);context.moveTo(canvas.width/2+12,canvas.height*.46);context.lineTo(canvas.width/2+38,canvas.height*.46);context.stroke();
    context.fillStyle="#fff0dc";context.font="800 9px Courier New";context.fillText(`${model.camera.x.toFixed(1)},${model.camera.y.toFixed(1)} / ${Math.round(model.camera.yaw_deg)}°`,14,20);
  }

  function drawMap() {
    const canvas = document.getElementById("photo-room-map"), context = canvas?.getContext("2d"); if (!canvas || !context || !model) return;
    const sx = canvas.width / Number(model.state.room.width), sy = canvas.height / Number(model.state.room.height), room = model.state.room;
    context.fillStyle="#201e31";context.fillRect(0,0,canvas.width,canvas.height);
    const v=room.void;context.fillStyle="#080813";context.fillRect(v.x1*sx,v.y1*sy,(v.x2-v.x1)*sx,(v.y2-v.y1)*sy);
    context.strokeStyle="#d1b9a9";context.lineWidth=2;context.beginPath();context.moveTo(room.divider.x*sx,0);context.lineTo(room.divider.x*sx,canvas.height);context.stroke();
    model.state.sockets.forEach((socket)=>{context.strokeStyle=socket.operation==="add_walkway"?"#ff8067":"#7ee3d4";context.lineWidth=3;context.beginPath();context.arc(socket.center.x*sx,socket.center.y*sy,6,0,Math.PI*2);context.stroke();});
    model.operations.forEach((item)=>{context.fillStyle="#f2d7bd";context.beginPath();context.arc(item.center.x*sx,item.center.y*sy,4,0,Math.PI*2);context.fill();});
    context.fillStyle="#ffecdd";context.beginPath();context.arc(model.camera.x*sx,model.camera.y*sy,4,0,Math.PI*2);context.fill();const yaw=model.camera.yaw_deg*Math.PI/180;context.strokeStyle="#ff8067";context.beginPath();context.moveTo(model.camera.x*sx,model.camera.y*sy);context.lineTo(model.camera.x*sx+Math.cos(yaw)*13,model.camera.y*sy+Math.sin(yaw)*13);context.stroke();
  }

  function updateInterface() {
    if (!model) return; const root=document.querySelector(".photo-room"); if(!root)return;
    root.dataset.active=String(model.active);root.dataset.cameraX=String(round2(model.camera.x));root.dataset.cameraY=String(round2(model.camera.y));root.dataset.yaw=String(round2(model.camera.yaw_deg));root.dataset.carrying=model.carrying?.kind||"";root.dataset.operationCount=String(model.operations.length);
    const coord=document.getElementById("photo-coord");if(coord)coord.textContent=`${model.camera.x.toFixed(1)} / ${model.camera.y.toFixed(1)} / ${Math.round(model.camera.yaw_deg)}°`;
    const plate=document.getElementById("photo-carry-status");if(plate)plate.textContent=model.carrying?`${model.carrying.kind.toUpperCase()} NEGATIVE LOADED`:"CAMERA EMPTY";
    const lateral=document.getElementById("photo-lateral"),depth=document.getElementById("photo-depth"),rotation=document.getElementById("photo-rotation"),scale=document.getElementById("photo-scale");
    if(lateral)lateral.textContent=model.plane.lateral.toFixed(2);if(depth)depth.textContent=model.plane.depth.toFixed(2);if(rotation)rotation.textContent=`${Math.round(model.plane.rotation_deg)}°`;if(scale)scale.textContent=`${model.plane.scale.toFixed(1)}×`;
    const planeMarker=document.querySelector("#photo-plane-pad i");if(planeMarker){planeMarker.style.left=`${(model.plane.lateral-Number(model.state.controls.plane_lateral_min))/(Number(model.state.controls.plane_lateral_max)-Number(model.state.controls.plane_lateral_min))*100}%`;planeMarker.style.top=`${(1-(model.plane.depth-Number(model.state.controls.plane_depth_min))/(Number(model.state.controls.plane_depth_max)-Number(model.state.controls.plane_depth_min)))*100}%`;}
    document.querySelectorAll(".photo-carry-control").forEach((button)=>{button.disabled=!model.active||!model.carrying||model.moving||model.planeDragging||model.submitting;});
    document.querySelectorAll(".photo-nav-control,#photo-capture,#photo-room-reset").forEach((button)=>{button.disabled=!model.active||model.planeDragging||model.submitting||model.completed;});
    const submit=document.getElementById("photo-submit");if(submit)submit.disabled=!model.active||model.moving||model.planeDragging||model.submitting||model.completed;
    drawScene();drawMap();
  }

  function tickMove() {
    if(!model?.moving)return;const current=performance.now(),dt=Math.round(current-model.lastMoveAt);if(dt<25)return;if(dt>Number(model.state.qualification.maximum_move_sample_gap_ms)){pushEvent({type:"move_stall",gap_ms:dt,camera:cameraCopy()});model.lastMoveAt=current;return;}
    const before=cameraCopy(),yaw=model.camera.yaw_deg*Math.PI/180,forward=[Math.cos(yaw),Math.sin(yaw)],right=[-Math.sin(yaw),Math.cos(yaw)];const direction={forward,right,back:[-forward[0],-forward[1]],left:[-right[0],-right[1]]}[model.moving];const distance=Number(model.state.controls.move_speed)*dt/1000,next=collisionMove(direction[0]*distance,direction[1]*distance);
    model.camera.x=next.x;model.camera.y=next.y;model.moveSamples+=1;model.travel+=Math.hypot(next.x-before.x,next.y-before.y);pushEvent({type:"move_tick",code:model.moving,dt_ms:dt,from:before,to:cameraCopy()});model.lastMoveAt=current;updateInterface();
  }
  function startMove(code){if(!model?.active||model.moving||model.planeDragging||model.submitting||model.completed)return;model.moving=code;model.lastMoveAt=performance.now();pushEvent({type:"move_start",code,camera:cameraCopy()});model.moveTimer=setInterval(tickMove,Number(model.state.controls.move_tick_ms));updateInterface();}
  function endMove(code=model?.moving){if(!model?.moving||code!==model.moving)return;clearInterval(model.moveTimer);model.moveTimer=null;pushEvent({type:"move_end",code:model.moving,camera:cameraCopy()});model.moving=null;updateInterface();}
  function turn(delta){if(!model?.active||model.moving||model.planeDragging||model.submitting||model.completed)return;const before=cameraCopy();model.camera.yaw_deg=(model.camera.yaw_deg+delta+360)%360;pushEvent({type:"turn",delta_deg:delta,before,after:cameraCopy()});updateInterface();}

  function captureGeometry(){if(!model?.active||model.moving||model.planeDragging||model.carrying||model.submitting)return;const candidates=model.state.sources.filter((source)=>!model.usedSources.includes(source.id)&&!sourceOccluded(source)).map((source)=>({source,projection:projectSource(model.camera,source)})).filter((item)=>item.projection).sort((a,b)=>a.projection.distance-b.projection.distance);if(!candidates.length){model.localStamp="NO GEOMETRY IN FRUSTUM";model.helpers.setReadout("CAPTURE FAILED / MOVE, TURN, AND FRAME THE ENTIRE SOURCE","error");updateStamp();return;}const selected=candidates[0];model.carrying=selected.source;model.plane={lateral:0,depth:1.2,rotation_deg:0,scale:1};model.adjustments={drag_moves:0,rotations:0,scales:0};model.captures+=1;pushEvent({type:"capture",camera:cameraCopy(),captured_source_id:selected.source.id,projection:selected.projection});model.localStamp="CAPTURED";model.helpers.setReadout("NEGATIVE LOADED / CARRY IT TO A SOCKET","idle");updateStamp();updateInterface();}

  function planePointer(event){const pad=document.getElementById("photo-plane-pad"),rect=pad.getBoundingClientRect();return{x:round2(clamp((event.clientX-rect.left)/rect.width,0,1)),y:round2(clamp((event.clientY-rect.top)/rect.height,0,1))};}
  function planeDragStart(event){if(!model?.active||!model.carrying||model.moving||model.planeDragging)return;model.planeDragging=true;model.lastPlanePointer=planePointer(event);pushEvent({type:"plane_drag_start",pointer:model.lastPlanePointer,plane:planeCopy()});event.currentTarget.setPointerCapture?.(event.pointerId);updateInterface();}
  function planeDragMove(event){if(!model?.planeDragging)return;const pointer=planePointer(event),before=planeCopy();model.plane.lateral=round2(Number(model.state.controls.plane_lateral_min)+pointer.x*(Number(model.state.controls.plane_lateral_max)-Number(model.state.controls.plane_lateral_min)));model.plane.depth=round2(Number(model.state.controls.plane_depth_min)+(1-pointer.y)*(Number(model.state.controls.plane_depth_max)-Number(model.state.controls.plane_depth_min)));model.lastPlanePointer=pointer;model.adjustments.drag_moves+=1;pushEvent({type:"plane_drag_move",pointer,from:before,to:planeCopy()});updateInterface();}
  function planeDragEnd(event){if(!model?.planeDragging)return;pushEvent({type:"plane_drag_end",plane:planeCopy()});model.planeDragging=false;event.currentTarget.releasePointerCapture?.(event.pointerId);updateInterface();}
  function planeRotate(delta){if(!model?.carrying||model.moving||model.planeDragging)return;const before=model.plane.rotation_deg;model.plane.rotation_deg=(before+delta+360)%360;model.adjustments.rotations+=1;pushEvent({type:"plane_rotate",delta_deg:delta,before,after:model.plane.rotation_deg});updateInterface();}
  function planeScale(delta){if(!model?.carrying||model.moving||model.planeDragging)return;const before=model.plane.scale,after=round2(clamp(before+delta,Number(model.state.controls.plane_scale_min),Number(model.state.controls.plane_scale_max)));if(after===before)return;model.plane.scale=after;model.adjustments.scales+=1;pushEvent({type:"plane_scale",delta:round2(delta),before,after});updateInterface();}
  function planeReset(){if(!model?.carrying||model.moving||model.planeDragging)return;model.plane={lateral:0,depth:1.2,rotation_deg:0,scale:1};model.adjustments={drag_moves:0,rotations:0,scales:0};model.planeResets+=1;pushEvent({type:"plane_reset",plane:planeCopy()});model.localStamp="PRINT RESET";model.helpers.setReadout("PRINT RESTORED / GEOMETRY UNCHANGED","idle");updateStamp();updateInterface();}
  function develop(){if(!model?.carrying||model.moving||model.planeDragging)return;const mapped=mappedGeometry(),socket=model.state.sockets.find((item)=>item.source_kind===model.carrying.kind);const qualified=Math.hypot(mapped.center.x-Number(socket.center.x),mapped.center.y-Number(socket.center.y))<=Number(socket.tolerance)&&angleError(mapped.angle_deg,Number(socket.angle_deg))<=10&&mapped.length>=Number(socket.minimum_length)&&model.adjustments.drag_moves>=Number(model.state.qualification.minimum_plane_drag_moves)&&model.adjustments.scales>=Number(model.state.qualification.minimum_scale_changes);pushEvent({type:"develop",camera:cameraCopy(),plane:planeCopy(),mapped,developed:qualified});if(qualified){model.operations.push({source_id:model.carrying.id,operation:socket.operation,...mapped});model.usedSources.push(model.carrying.id);model.carrying=null;model.localStamp=socket.operation==="add_walkway"?"BRIDGE REAL":"DOOR REAL";model.helpers.setReadout(socket.operation==="add_walkway"?"REALITY OVERWRITTEN / BRIDGE COLLISION ACTIVE":"REALITY OVERWRITTEN / DOOR COLLISION REMOVED","idle");}else{model.localFailures+=1;model.localStamp="DEVELOPMENT REJECTED";model.helpers.setReadout("DEVELOPMENT REJECTED / ALIGN SOCKET, ANGLE, AND SCALE","error");}updateStamp();updateInterface();}
  function updateStamp(){const stamp=document.getElementById("photo-local-stamp");if(stamp){stamp.textContent=model.localStamp||"";stamp.dataset.visible=String(Boolean(model.localStamp));}}
  function resetRoom(){if(!model?.active||model.moving||model.planeDragging)return;const initial=model.state.initial_camera;model.camera={x:Number(initial.x),y:Number(initial.y),yaw_deg:Number(initial.yaw_deg)};model.operations=[];model.usedSources=[];model.carrying=null;model.plane={lateral:0,depth:1.2,rotation_deg:0,scale:1};model.moveSamples=0;model.travel=0;model.captures=0;model.localFailures=0;model.planeResets=0;model.roomResets+=1;pushEvent({type:"room_reset",camera:cameraCopy()});model.localStamp="ROOM REWOUND";model.helpers.setReadout("ROOM REWOUND / SOURCES RESTORED","idle");updateStamp();updateInterface();}

  function finalState(){const terminal=model.state.room.terminal;return{camera:cameraCopy(),operations:model.operations,carrying_source_id:model.carrying?.id||null,captures:model.captures,move_samples:model.moveSamples,travel:round2(model.travel),local_failures:model.localFailures,plane_resets:model.planeResets,room_resets:model.roomResets,terminal_contact:Math.hypot(model.camera.x-Number(terminal.x),model.camera.y-Number(terminal.y))<=Number(terminal.radius)};}
  function showVerdict(kind){const root=document.querySelector(".photo-room"),verdict=root?.querySelector(".photo-verdict");if(!root||!verdict)return;root.classList.toggle("is-passed",kind==="pass");root.classList.toggle("is-failed",kind==="fail");verdict.innerHTML=`<b>${kind==="pass"?"PASS":"FAIL"}</b><span>${kind==="pass"?"ROOM ACCEPTED THE PHOTOGRAPHS":"FRESH ROOM / CAMERA AT STANDBY"}</span>`;if(kind==="fail"){const timer=setTimeout(()=>root.classList.remove("is-failed"),1600);model.timers.add(timer);}}
  async function submitRoom(){if(!model?.active||model.moving||model.planeDragging||model.submitting||model.completed)return;const current=model;pushEvent({type:"verify",claimed_terminal:true});current.submitting=true;updateInterface();try{const response=await fetch("/result",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({mechanic_id:current.state.mechanic_id,task_id:current.state.task_id,challenge_id:current.state.challenge_id,events:current.events,final_state:finalState(),completed:true})});const outcome=await response.json();if(outcome.passed===true){current.completed=true;current.helpers.setReadout("PASS","passed");showVerdict("pass");updateInterface();}else if(outcome.passed===false){const helpers=current.helpers;if(outcome.state)await render(outcome.state,helpers,{freshFailure:true});model.helpers.setReadout("FAIL","error");showVerdict("fail");}}catch(_error){if(model===current){current.submitting=false;current.helpers.setReadout("DARKROOM LINK LOST","error");updateInterface();}}}
  function installDeveloperReveal(){const form=document.getElementById("cheat-form"),input=document.getElementById("cheat-password"),output=document.getElementById("cheat-output");if(!form||!input||!output)return;form.addEventListener("submit",async(event)=>{event.preventDefault();output.textContent="";try{const response=await fetch("/cheat",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({password:input.value})});if(!response.ok){output.textContent=response.status===404?"Disabled.":"Denied.";return;}const data=await response.json();output.textContent=(data.solution?.placements||[]).map((item)=>`${item.socket_id} ${item.rotation_deg}° ${item.scale}×`).join(" · ");}catch(_error){output.textContent="Unavailable.";}});}
  function startChallenge(){if(!model||model.active)return;model.active=true;pushEvent({type:"challenge_start",camera:cameraCopy()});model.helpers.setReadout("CAMERA LIVE / EXPLORE THE ROOM","idle");updateInterface();}

  async function render(state,helpers,options={}){
    if(activeCleanup)activeCleanup();document.body.dataset.mechanic="photograph-eats-the-room";document.body.dataset.cheatMode=helpers.isCheatMode()?"true":"false";const initial=state.initial_camera;
    model={state,helpers,startedAt:performance.now(),events:[],camera:{x:Number(initial.x),y:Number(initial.y),yaw_deg:Number(initial.yaw_deg)},operations:[],usedSources:[],carrying:null,plane:{lateral:0,depth:1.2,rotation_deg:0,scale:1},adjustments:{drag_moves:0,rotations:0,scales:0},moving:null,moveTimer:null,lastMoveAt:0,moveSamples:0,travel:0,captures:0,localFailures:0,planeResets:0,roomResets:0,planeDragging:false,lastPlanePointer:{x:.5,y:.82},localStamp:"",active:false,submitting:false,completed:false,timers:new Set()};
    helpers.app.innerHTML=`<section class="photo-room palette-${helpers.text(state.palette)}" data-fresh-failure="${options.freshFailure?"true":"false"}" data-active="false" tabindex="0"><div class="photo-verdict" aria-live="assertive"></div><header class="photo-head"><div><span>APPLIED PERSPECTIVE LAB / ${helpers.text(state.plate_id)}</span><h1>${helpers.text(state.prompt)}</h1></div><div class="photo-seal"><i>▣</i><span>ROOM<br><b>NEGATIVE</b></span></div></header><main class="photo-workbench"><section class="photo-stage"><canvas id="photo-room-canvas" width="880" height="450" aria-label="navigable perspective room"></canvas><div class="photo-stage-rail"><span>WASD MOVE · ← → TURN · C CAPTURE</span><b>PERSPECTIVE GEOMETRY / COLLISION LIVE</b></div><div id="photo-local-stamp" data-visible="false"></div></section><aside class="photo-console"><div class="photo-map-card"><header><span>ROOM CONTACT SHEET</span><b id="photo-coord"></b></header><canvas id="photo-room-map" width="250" height="92"></canvas></div><div class="photo-nav"><button class="photo-nav-control" data-turn="-15">↶</button><button class="photo-nav-control" data-move="forward">W</button><button class="photo-nav-control" data-turn="15">↷</button><button class="photo-nav-control" data-move="left">A</button><button class="photo-nav-control" data-move="back">S</button><button class="photo-nav-control" data-move="right">D</button></div><button id="photo-capture">CAPTURE FRUSTUM</button><div class="photo-carry"><header><span id="photo-carry-status">CAMERA EMPTY</span><b><i id="photo-lateral">0.00</i>L / <i id="photo-depth">1.20</i>D</b></header><div id="photo-plane-pad" class="photo-carry-control"><i></i><span>DRAG PHOTO / LATERAL + DEPTH</span></div><div class="photo-transform"><button class="photo-carry-control" id="photo-rotate-left">−15°</button><b id="photo-rotation">0°</b><button class="photo-carry-control" id="photo-rotate-right">+15°</button><button class="photo-carry-control" id="photo-scale-down">−</button><b id="photo-scale">1.0×</b><button class="photo-carry-control" id="photo-scale-up">+</button></div><div class="photo-develop"><button class="photo-carry-control" id="photo-plane-reset">RESET PRINT</button><button class="photo-carry-control" id="photo-develop">DEVELOP INTO ROOM</button></div></div><button id="photo-room-reset">REWIND ROOM</button></aside></main><footer class="photo-foot"><div class="readout" data-status="idle">CAMERA STANDBY</div><button id="photo-submit">${helpers.text(state.submit_label||"VERIFY ROOM")}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    const root=document.querySelector(".photo-room"),pad=document.getElementById("photo-plane-pad");pad.addEventListener("pointerdown",planeDragStart);pad.addEventListener("pointermove",planeDragMove);pad.addEventListener("pointerup",planeDragEnd);pad.addEventListener("pointercancel",planeDragEnd);
    document.querySelectorAll("[data-move]").forEach((button)=>{button.addEventListener("pointerdown",()=>startMove(button.dataset.move));button.addEventListener("pointerup",()=>endMove(button.dataset.move));button.addEventListener("pointercancel",()=>endMove(button.dataset.move));});document.querySelectorAll("[data-turn]").forEach((button)=>button.addEventListener("click",()=>turn(Number(button.dataset.turn))));
    document.getElementById("photo-capture").addEventListener("click",captureGeometry);document.getElementById("photo-rotate-left").addEventListener("click",()=>planeRotate(-15));document.getElementById("photo-rotate-right").addEventListener("click",()=>planeRotate(15));document.getElementById("photo-scale-down").addEventListener("click",()=>planeScale(-.1));document.getElementById("photo-scale-up").addEventListener("click",()=>planeScale(.1));document.getElementById("photo-plane-reset").addEventListener("click",planeReset);document.getElementById("photo-develop").addEventListener("click",develop);document.getElementById("photo-room-reset").addEventListener("click",resetRoom);document.getElementById("photo-submit").addEventListener("click",submitRoom);
    const held=new Map();const keyDown=(event)=>{if(event.repeat)return;const movement={w:"forward",s:"back",a:"left",d:"right"}[event.key.toLowerCase()];if(movement){event.preventDefault();held.set(event.code,movement);startMove(movement);}else if(event.key==="ArrowLeft"){event.preventDefault();turn(-15);}else if(event.key==="ArrowRight"){event.preventDefault();turn(15);}else if(event.key.toLowerCase()==="c"){event.preventDefault();captureGeometry();}};const keyUp=(event)=>{const movement=held.get(event.code);if(movement){held.delete(event.code);endMove(movement);}};window.addEventListener("keydown",keyDown);window.addEventListener("keyup",keyUp);installDeveloperReveal();
    activeCleanup=()=>{clearInterval(model?.moveTimer);model?.timers.forEach((timer)=>clearTimeout(timer));window.removeEventListener("keydown",keyDown);window.removeEventListener("keyup",keyUp);pad.removeEventListener("pointerdown",planeDragStart);pad.removeEventListener("pointermove",planeDragMove);pad.removeEventListener("pointerup",planeDragEnd);pad.removeEventListener("pointercancel",planeDragEnd);};updateInterface();root?.focus();if(options.freshFailure){const fresh=model,timer=setTimeout(()=>{if(model===fresh)startChallenge();},1650);model.timers.add(timer);}else startChallenge();
  }
  window.WeirdCaptchaMechanics=window.WeirdCaptchaMechanics||{};window.WeirdCaptchaMechanics.photograph_eats_the_room={rootSelector:".photo-room",render};
})();
