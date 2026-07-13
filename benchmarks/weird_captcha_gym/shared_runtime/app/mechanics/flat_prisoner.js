(() => {
  "use strict";

  const model = {
    state: null, helpers: null, camera: null, events: [], mode: "camera", topology: null,
    prisoner: null, timer: 0, sessionStart: 0, dragMode: "orbit", drag: null,
    cameraEventCount: 0, freezeCount: 0, thawCount: 0, deathCount: 0,
    keyTransitionCount: 0, abandoned: false, busy: false, terminal: false,
    fallRecorded: false, canvas: null, context: null, freshTimer: 0, settleTimer: 0, lastCameraChangeAt: -Infinity,
  };

  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const clean = (value) => String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const elapsed = () => Math.max(0, Math.round(performance.now() - model.sessionStart));
  const dot = (a, b) => a.reduce((sum, value, index) => sum + value * b[index], 0);
  const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
  const normalize = (v) => { const length = Math.sqrt(dot(v,v)); return v.map((value) => value / Math.max(length, 1e-12)); };
  const record = (kind, details = {}) => { const event = {sequence:model.events.length+1,kind,elapsed_ms:elapsed(),...details}; model.events.push(event); return event; };

  function cameraBasis(camera) {
    const yaw=camera.yaw_deg*Math.PI/180,pitch=camera.pitch_deg*Math.PI/180,distance=camera.distance,target=camera.target;
    const eye=[target[0]+distance*Math.cos(pitch)*Math.sin(yaw),target[1]+distance*Math.sin(pitch),target[2]+distance*Math.cos(pitch)*Math.cos(yaw)];
    const forward=normalize(target.map((value,index)=>value-eye[index])),right=normalize(cross(forward,[0,1,0])),up=normalize(cross(right,forward));
    return {eye,forward,right,up};
  }

  function viewMatrix(camera) {
    const {eye,forward,right,up}=cameraBasis(camera);
    return [[right[0],right[1],right[2],-dot(right,eye)],[up[0],up[1],up[2],-dot(up,eye)],[-forward[0],-forward[1],-forward[2],dot(forward,eye)],[0,0,0,1]];
  }

  function projectionMatrix(viewport) {
    const aspect=viewport.width/viewport.height,focal=1/Math.tan(viewport.fov_deg*Math.PI/360),near=viewport.near,far=viewport.far;
    return [[focal/aspect,0,0,0],[0,focal,0,0],[0,0,(far+near)/(near-far),2*far*near/(near-far)],[0,0,-1,0]];
  }

  function matmul(a,b){return Array.from({length:4},(_,row)=>Array.from({length:4},(_,column)=>a[row].reduce((sum,value,index)=>sum+value*b[index][column],0)));}
  function matvec(matrix,vector){return matrix.map((row)=>dot(row,vector));}

  function project(point,camera=model.camera){
    const viewport=model.state.viewport,matrix=matmul(projectionMatrix(viewport),viewMatrix(camera)),clip=matvec(matrix,[point[0],point[1],point[2],1]);
    if(clip[3]<=1e-8)return{x:-9999,y:-9999,depth:9999,view_depth:clip[3],visible:false};
    const nx=clip[0]/clip[3],ny=clip[1]/clip[3],nz=clip[2]/clip[3];
    return{x:(nx*.5+.5)*viewport.width,y:(1-(ny*.5+.5))*viewport.height,depth:nz,view_depth:clip[3],visible:nx>=-1.2&&nx<=1.2&&ny>=-1.2&&ny<=1.2&&nz>=-1&&nz<=1};
  }

  function segmentsFor(camera=model.camera){
    return model.state.platforms.map((platform)=>{
      const first=project(platform.walk_edge[0],camera),second=project(platform.walk_edge[1],camera),left=first.x<=second.x?first:second,right=first.x<=second.x?second:first;
      return{id:platform.id,role:platform.role,left:left.x,right:right.x,left_y:left.y,right_y:right.y,visible:first.visible&&second.visible&&right.x-left.x>=42};
    });
  }
  function segmentY(segment,x){const amount=(x-segment.left)/Math.max(1e-9,segment.right-segment.left);return segment.left_y+(segment.right_y-segment.left_y)*amount;}

  function deriveTopology(camera=model.camera){
    const segments=segmentsFor(camera),directed=new Map(segments.map((segment)=>[segment.id,new Set()])),joins=[];
    segments.forEach((first,index)=>{if(!first.visible)return;segments.slice(index+1).forEach((second)=>{if(!second.visible)return;const left=Math.max(first.left,second.left),right=Math.min(first.right,second.right);if(right-left<10)return;const midpoint=(left+right)/2,separation=Math.abs(segmentY(first,midpoint)-segmentY(second,midpoint));if(separation<=10){directed.get(first.id).add(second.id);directed.get(second.id).add(first.id);joins.push({a:first.id,b:second.id,overlap:right-left,separation,left,right});}});});
    segments.forEach((first)=>{if(!first.visible)return;segments.forEach((second)=>{if(first===second||!second.visible)return;const gap=second.left-first.right;if(gap<4||gap>74)return;const rise=segmentY(first,first.right)-segmentY(second,second.left);if(rise>=-42&&rise<=78)directed.get(first.id).add(second.id);});});
    const startId=model.state.start_surface_id,exitId=model.state.exit_surface_id,reached=new Set([startId]),frontier=[startId];while(frontier.length){const current=frontier.pop();for(const next of directed.get(current)||[]){if(!reached.has(next)){reached.add(next);frontier.push(next);}}}
    const coreVisible=segments.filter((segment)=>!segment.id.startsWith("decoy-")).every((segment)=>segment.visible),valid=coreVisible&&joins.length>=2&&reached.has(exitId);
    return{segments,joins,directed,reached:[...reached],valid,start_id:startId,exit_id:exitId};
  }

  function copyCamera(value){return{yaw_deg:Number(value.yaw_deg),pitch_deg:Number(value.pitch_deg),distance:Number(value.distance),target:value.target.map(Number)};}
  function roundCamera(){model.camera.yaw_deg=Number(model.camera.yaw_deg.toFixed(6));model.camera.pitch_deg=Number(model.camera.pitch_deg.toFixed(6));model.camera.distance=Number(model.camera.distance.toFixed(6));model.camera.target=model.camera.target.map((value)=>Number(value.toFixed(6)));}

  function markCameraChanged(){model.lastCameraChangeAt=performance.now();clearTimeout(model.settleTimer);model.settleTimer=setTimeout(()=>{updatePanels();if(model.mode==="camera")model.helpers.setReadout(model.topology.valid?"CAMERA SETTLED · PROJECTION MAY BE FROZEN":"CAMERA SETTLED · ROUTE STILL DISCONNECTED","idle");},Number(model.state.requirements.minimum_freeze_settle_ms)+8);}
  function cameraSettled(){return performance.now()-model.lastCameraChangeAt>=Number(model.state.requirements.minimum_freeze_settle_ms);}
  function applyOrbit(yawDelta,pitchDelta){
    if(model.mode!=="camera"||model.busy)return;const c=model.state.controls;
    model.camera.yaw_deg=clamp(model.camera.yaw_deg+yawDelta,c.yaw_min,c.yaw_max);model.camera.pitch_deg=clamp(model.camera.pitch_deg+pitchDelta,c.pitch_min,c.pitch_max);roundCamera();record("orbit",{yaw_delta:yawDelta,pitch_delta:pitchDelta});model.cameraEventCount+=1;markCameraChanged();cameraChanged();
  }
  function applyPan(xDelta,yDelta){
    if(model.mode!=="camera"||model.busy)return;model.camera.target[0]=clamp(model.camera.target[0]+xDelta,-5,5);model.camera.target[1]=clamp(model.camera.target[1]+yDelta,-2,4);roundCamera();record("pan",{x_delta:xDelta,y_delta:yDelta});model.cameraEventCount+=1;markCameraChanged();cameraChanged();
  }
  function applyDolly(delta){
    if(model.mode!=="camera"||model.busy)return;const c=model.state.controls;model.camera.distance=clamp(model.camera.distance+delta,c.distance_min,c.distance_max);roundCamera();record("dolly",{delta});model.cameraEventCount+=1;markCameraChanged();cameraChanged();
  }
  function cameraChanged(){clearFreshFailure();model.topology=deriveTopology();draw();updatePanels();model.helpers.setReadout(model.topology.valid?"PROJECTION ROUTE DETECTED · CAMERA SETTLING":"CAMERA SETTLING · SEEK EDGE COINCIDENCES","pending");}
  function resetCamera(){if(model.mode!=="camera"||model.busy)return;model.camera=copyCamera(model.state.initial_camera);record("camera_reset");markCameraChanged();cameraChanged();model.helpers.setReadout("CAMERA RETURNED TO INTAKE VIEW · SETTLING","pending");}

  function platformFaces(){
    const faces=[];model.state.platforms.forEach((platform,platformIndex)=>{const projected=platform.vertices.map((vertex)=>project(vertex));platform.faces.forEach((indices,faceIndex)=>{const points=indices.map((index)=>projected[index]);if(points.some((point)=>point.view_depth<=0))return;faces.push({platform,platformIndex,faceIndex,points,depth:points.reduce((sum,point)=>sum+point.view_depth,0)/points.length});});});return faces.sort((a,b)=>b.depth-a.depth);
  }

  function draw3d(context){
    const viewport=model.state.viewport,palette=model.state.palette,gradient=context.createLinearGradient(0,0,0,viewport.height);gradient.addColorStop(0,palette.sky);gradient.addColorStop(.58,palette.haze);gradient.addColorStop(1,"#05090c");context.fillStyle=gradient;context.fillRect(0,0,viewport.width,viewport.height);
    context.save();context.lineWidth=1;for(let index=-8;index<=8;index+=1){const a=project([index,-2,-9]),b=project([index,-2,9]),c=project([-9,-2,index]),d=project([9,-2,index]);context.strokeStyle="rgba(132,195,207,.10)";for(const pair of [[a,b],[c,d]]){if(pair[0].view_depth>0&&pair[1].view_depth>0){context.beginPath();context.moveTo(pair[0].x,pair[0].y);context.lineTo(pair[1].x,pair[1].y);context.stroke();}}}context.restore();
    const tones=[palette.surface,"#365564","#4b445c","#57433b"];
    platformFaces().forEach((face)=>{context.beginPath();face.points.forEach((point,index)=>index?context.lineTo(point.x,point.y):context.moveTo(point.x,point.y));context.closePath();const decoy=face.platform.role==="decoy";context.fillStyle=face.faceIndex===0?tones[face.platform.tone%tones.length]:`${tones[face.platform.tone%tones.length]}${face.faceIndex===2?"dc":"aa"}`;context.globalAlpha=decoy?.38:.78;context.fill();context.strokeStyle=decoy?"rgba(149,167,171,.22)":"rgba(178,218,224,.32)";context.lineWidth=1;context.stroke();context.globalAlpha=1;});
    const topology=deriveTopology();model.state.platforms.forEach((platform,index)=>{const a=project(platform.walk_edge[0]),b=project(platform.walk_edge[1]);if(a.view_depth<=0||b.view_depth<=0)return;context.strokeStyle=platform.role==="decoy"?"rgba(152,173,178,.36)":palette.edge;context.lineWidth=platform.role==="decoy"?1.2:2.4;context.beginPath();context.moveTo(a.x,a.y);context.lineTo(b.x,b.y);context.stroke();if(platform.role!=="decoy"&&a.visible){context.fillStyle="rgba(218,244,246,.66)";context.font="700 8px ui-monospace,monospace";context.fillText(`S-${String(index+1).padStart(2,"0")}`,a.x+5,a.y-7);}});
    const start=topology.segments.find((segment)=>segment.id===model.state.start_surface_id),exit=topology.segments.find((segment)=>segment.id===model.state.exit_surface_id);if(start){const x=start.left+26,y=segmentY(start,x);drawMarker(context,x,y,"PRISONER",palette.signal,false);}if(exit){const x=exit.right-20,y=segmentY(exit,x);drawMarker(context,x,y,"EXIT",palette.edge,true);}
    context.fillStyle="rgba(231,243,239,.55)";context.font="800 8px ui-monospace,monospace";context.fillText("PERSPECTIVE MATRIX / LIVE WORLD SPACE",18,24);context.strokeStyle="rgba(118,232,255,.25)";context.strokeRect(viewport.width/2-21,viewport.height/2-21,42,42);context.beginPath();context.moveTo(viewport.width/2-31,viewport.height/2);context.lineTo(viewport.width/2+31,viewport.height/2);context.moveTo(viewport.width/2,viewport.height/2-31);context.lineTo(viewport.width/2,viewport.height/2+31);context.stroke();
  }

  function drawMarker(context,x,y,label,color,isExit){context.save();context.translate(x,y);context.strokeStyle=color;context.fillStyle=`${color}24`;context.lineWidth=2;if(isExit){context.fillRect(-14,-43,28,43);context.strokeRect(-14,-43,28,43);context.beginPath();context.arc(6,-21,2,0,Math.PI*2);context.fill();}else{context.beginPath();context.arc(0,-32,6,0,Math.PI*2);context.stroke();context.beginPath();context.moveTo(0,-26);context.lineTo(0,-8);context.moveTo(-9,-18);context.lineTo(9,-18);context.moveTo(0,-8);context.lineTo(-7,0);context.moveTo(0,-8);context.lineTo(7,0);context.stroke();}context.font="800 7px ui-monospace,monospace";context.textAlign="center";context.fillStyle=color;context.fillText(label,0,isExit?-49:-42);context.restore();}

  function makePhysics(topology){
    const start=topology.segments.find((segment)=>segment.id===topology.start_id),exit=topology.segments.find((segment)=>segment.id===topology.exit_id),x=start.left+26,exitX=exit.right-20;
    return{x,y:segmentY(start,x),vx:0,vy:0,grounded:Boolean(start.visible),alive:true,reached:false,left:false,right:false,jump_held:false,tick:0,jumps:0,transitions:0,exit_x:exitX,exit_y:segmentY(exit,exitX),segments:topology.segments};
  }
  function surfaceCandidates(player,x){const half=model.state.physics.player_width/2;return player.segments.filter((segment)=>segment.visible&&x>=segment.left-half&&x<=segment.right+half).map((segment)=>({y:segmentY(segment,clamp(x,segment.left,segment.right)),segment}));}

  function stepPhysicsState(p){
    if(!p)return;if(!p.alive||p.reached){p.tick+=1;return;}const physics=model.state.physics,dt=physics.tick_ms/1000,direction=(p.right?1:0)-(p.left?1:0),oldY=p.y;p.vx=direction*physics.move_speed;p.x+=p.vx*dt;
    if(p.grounded){const supports=surfaceCandidates(p,p.x).filter((item)=>Math.abs(item.y-oldY)<=5).sort((a,b)=>Math.abs(a.y-oldY)-Math.abs(b.y-oldY));if(supports.length){p.y=supports[0].y;p.vy=0;}else p.grounded=false;}
    if(!p.grounded){p.vy+=physics.gravity*dt;const nextY=p.y+p.vy*dt;if(p.vy>=0){const crossings=surfaceCandidates(p,p.x).filter((item)=>p.y<=item.y+1&&nextY>=item.y).sort((a,b)=>a.y-b.y);if(crossings.length){p.y=crossings[0].y;p.vy=0;p.grounded=true;}else p.y=nextY;}else p.y=nextY;}
    p.tick+=1;if(p.y>physics.death_y||p.x<-70||p.x>970)p.alive=false;if(p.alive&&p.grounded&&Math.abs(p.x-p.exit_x)<=physics.exit_radius&&Math.abs(p.y-p.exit_y)<=8)p.reached=true;
  }
  function stepPhysics(){stepPhysicsState(model.prisoner);}

  function drawFlat(context){
    const viewport=model.state.viewport,palette=model.state.palette;context.fillStyle="#070b0e";context.fillRect(0,0,viewport.width,viewport.height);context.strokeStyle="rgba(106,217,239,.08)";context.lineWidth=1;for(let x=0;x<=viewport.width;x+=30){context.beginPath();context.moveTo(x,0);context.lineTo(x,viewport.height);context.stroke();}for(let y=0;y<=viewport.height;y+=30){context.beginPath();context.moveTo(0,y);context.lineTo(viewport.width,y);context.stroke();}
    model.topology.segments.forEach((segment,index)=>{if(!segment.visible)return;context.beginPath();context.moveTo(segment.left,segment.left_y);context.lineTo(segment.right,segment.right_y);context.lineTo(segment.right,segment.right_y+25);context.lineTo(segment.left,segment.left_y+25);context.closePath();context.fillStyle=segment.role==="decoy"?"rgba(73,93,99,.3)":`${palette.surface}d8`;context.fill();context.strokeStyle=segment.role==="decoy"?"rgba(153,174,180,.3)":palette.edge;context.lineWidth=segment.role==="decoy"?1:3;context.beginPath();context.moveTo(segment.left,segment.left_y);context.lineTo(segment.right,segment.right_y);context.stroke();context.fillStyle="rgba(215,239,241,.48)";context.font="700 7px ui-monospace,monospace";context.fillText(String(index+1).padStart(2,"0"),segment.left+4,segment.left_y+17);});
    model.topology.joins.forEach((join)=>{const a=model.topology.segments.find((segment)=>segment.id===join.a),x=(join.left+join.right)/2,y=segmentY(a,x);context.fillStyle=palette.signal;context.beginPath();context.arc(x,y,4,0,Math.PI*2);context.fill();});
    const p=model.prisoner;if(!p)return;drawMarker(context,p.exit_x,p.exit_y,"EXIT",palette.edge,true);if(p.alive){context.save();context.translate(p.x,p.y);context.fillStyle=p.reached?palette.edge:palette.signal;context.strokeStyle="#091014";context.lineWidth=2;context.fillRect(-7,-24,14,24);context.strokeRect(-7,-24,14,24);context.beginPath();context.arc(0,-30,6,0,Math.PI*2);context.fill();context.stroke();context.restore();}else{context.fillStyle=palette.danger;context.font="900 44px Georgia,serif";context.textAlign="center";context.fillText("PROJECTION LOST",viewport.width/2,viewport.height/2);context.textAlign="left";}
    context.fillStyle="rgba(226,242,243,.58)";context.font="800 8px ui-monospace,monospace";context.fillText("FROZEN PROJECTION / COLLISION LEDGER ACTIVE",18,24);
  }

  function draw(){if(!model.context)return;model.context.clearRect(0,0,model.canvas.width,model.canvas.height);if(model.mode==="camera")draw3d(model.context);else drawFlat(model.context);}

  function updatePanels(){
    const topology=model.mode==="camera"?deriveTopology():model.topology;if(model.mode==="camera")model.topology=topology;
    document.querySelector(".flat-prisoner")?.setAttribute("data-mode",model.mode);const mode=document.getElementById("projection-mode");if(mode)mode.textContent=model.mode==="camera"?"3D / CAMERA LIVE":"2D / VIEW FROZEN";
    const joins=document.getElementById("flat-join-count");if(joins)joins.textContent=String(topology?.joins.length||0).padStart(2,"0");const route=document.getElementById("flat-route-state");if(route){route.textContent=topology?.valid?"ROUTE DETECTED":"DISCONNECTED";route.dataset.ready=topology?.valid?"true":"false";}
    const yaw=document.getElementById("camera-yaw"),pitch=document.getElementById("camera-pitch"),distance=document.getElementById("camera-distance"),pan=document.getElementById("camera-pan");if(yaw)yaw.textContent=`${model.camera.yaw_deg.toFixed(1)}°`;if(pitch)pitch.textContent=`${model.camera.pitch_deg.toFixed(1)}°`;if(distance)distance.textContent=model.camera.distance.toFixed(1);if(pan)pan.textContent=`${model.camera.target[0].toFixed(1)} / ${model.camera.target[1].toFixed(1)}`;
    const freeze=document.getElementById("freeze-view");if(freeze){const settling=model.mode==="camera"&&!cameraSettled();freeze.disabled=model.mode!=="camera"||model.busy||settling;freeze.textContent=settling?"CAMERA SETTLING…":"FREEZE VIEW → 2D";}document.querySelectorAll("[data-camera-control]").forEach((button)=>button.disabled=model.mode!=="camera"||model.busy);const thaw=document.getElementById("thaw-view");if(thaw)thaw.disabled=model.mode!=="flat"||model.busy;const certify=document.getElementById("certify-escape");if(certify)certify.disabled=!model.prisoner?.reached||model.busy;
    const status=document.getElementById("prisoner-status");if(status)status.textContent=model.mode!=="flat"?"AWAITING FREEZE":model.prisoner?.reached?"AT EXIT":model.prisoner?.alive?model.prisoner.grounded?"ON LEDGE":"AIRBORNE":"FELL INTO DEPTH";const tick=document.getElementById("physics-tick");if(tick)tick.textContent=String(model.prisoner?.tick||0).padStart(4,"0");
  }

  function freezeView(){if(model.mode!=="camera"||model.busy)return;if(!cameraSettled()){model.helpers.setReadout("CAMERA STILL SETTLING · FREEZE WILL UNLOCK SHORTLY","pending");updatePanels();return;}record("freeze");model.freezeCount+=1;model.topology=deriveTopology();model.prisoner=makePhysics(model.topology);model.mode="flat";model.fallRecorded=false;clearInterval(model.timer);model.timer=setInterval(()=>{stepPhysics();if(!model.prisoner.alive&&!model.fallRecorded){model.fallRecorded=true;model.deathCount+=1;model.helpers.setReadout("THE PRISONER FELL · THAW AND REFRAME","error");}if(model.prisoner.reached){model.helpers.setReadout("EXIT REACHED · CERTIFY THE FIXED-STEP ESCAPE","pending");}draw();updatePanels();},model.state.physics.tick_ms);draw();updatePanels();model.helpers.setReadout(model.topology.valid?"VIEW FROZEN · MOVE WITH A/D OR ARROWS · JUMP WITH SPACE":"VIEW FROZEN, BUT THE ROUTE LOOKS BROKEN · TEST OR THAW","pending");}

  function releaseHeldKeys(){if(!model.prisoner)return;for(const [key,field] of [["left","left"],["right","right"],["jump","jump_held"]]){if(model.prisoner[field]){record("key_up",{key,tick:model.prisoner.tick});model.prisoner[field]=false;model.prisoner.transitions+=1;model.keyTransitionCount+=1;}}}
  function thawView(){if(model.mode!=="flat"||model.busy)return;releaseHeldKeys();record("thaw",{tick:model.prisoner.tick});model.thawCount+=1;clearInterval(model.timer);model.timer=0;model.mode="camera";model.prisoner=null;model.topology=deriveTopology();draw();updatePanels();model.helpers.setReadout("WORLD RESTORED · REFRAME THE CAMERA","idle");}

  function keyName(event){if(event.code==="ArrowLeft"||event.code==="KeyA")return"left";if(event.code==="ArrowRight"||event.code==="KeyD")return"right";if(event.code==="Space"||event.code==="ArrowUp"||event.code==="KeyW")return"jump";return null;}
  function handleKey(event,down){const key=keyName(event);if(!key||model.mode!=="flat"||!model.prisoner||model.busy)return;event.preventDefault();const field={left:"left",right:"right",jump:"jump_held"}[key];if(Boolean(model.prisoner[field])===down)return;record(down?"key_down":"key_up",{key,tick:model.prisoner.tick});model.prisoner[field]=down;model.prisoner.transitions+=1;model.keyTransitionCount+=1;if(key==="jump"&&down&&model.prisoner.grounded&&model.prisoner.alive&&!model.prisoner.reached){model.prisoner.vy=model.state.physics.jump_velocity;model.prisoner.grounded=false;model.prisoner.jumps+=1;}updatePanels();}

  function canvasDown(event){if(model.mode!=="camera"||model.busy)return;event.preventDefault();model.drag={pointerId:event.pointerId,x:event.clientX,y:event.clientY,lastEvent:performance.now(),pendingX:0,pendingY:0};model.canvas.setPointerCapture?.(event.pointerId);}
  function canvasMove(event){if(!model.drag||event.pointerId!==model.drag.pointerId||model.mode!=="camera")return;model.drag.pendingX+=event.clientX-model.drag.x;model.drag.pendingY+=event.clientY-model.drag.y;model.drag.x=event.clientX;model.drag.y=event.clientY;if(performance.now()-model.drag.lastEvent<20)return;const dx=model.drag.pendingX,dy=model.drag.pendingY;model.drag.pendingX=model.drag.pendingY=0;model.drag.lastEvent=performance.now();if(model.dragMode==="orbit"){const step=model.state.controls.orbit_step_deg,yaw=clamp(dx*.12,-step,step),pitch=clamp(dy*.12,-step,step);if(Math.abs(yaw)+Math.abs(pitch)>.05)applyOrbit(yaw,pitch);}else{const step=model.state.controls.pan_step,x=clamp(-dx*.018,-step,step),y=clamp(dy*.018,-step,step);if(Math.abs(x)+Math.abs(y)>.02)applyPan(x,y);}}
  function canvasUp(event){if(model.drag&&event.pointerId===model.drag.pointerId)model.drag=null;}
  function wheel(event){if(model.mode!=="camera"||model.busy)return;event.preventDefault();applyDolly(Math.sign(event.deltaY)*model.state.controls.dolly_step);}

  function payload(completed){return{mechanic_id:model.state.mechanic_id,task_id:model.state.task_id,challenge_id:model.state.challenge_id,events:model.events,camera_event_count:model.cameraEventCount,freeze_count:model.freezeCount,thaw_count:model.thawCount,death_count:model.deathCount,key_transition_count:model.keyTransitionCount,abandoned:model.abandoned,accepted:Boolean(model.prisoner?.reached),completed,client_topology:model.topology?{valid:model.topology.valid,joins:model.topology.joins.length}:null};}
  async function certify(){if(!model.prisoner?.reached||model.busy)return;releaseHeldKeys();record("submit",{tick:model.prisoner.tick});await submit(true);}
  async function abandon(){if(model.busy)return;if(model.mode==="flat")releaseHeldKeys();record("abandon");model.abandoned=true;await submit(false);}
  async function submit(completed){if(model.busy)return;model.busy=true;model.terminal=true;clearInterval(model.timer);document.querySelectorAll("button").forEach((button)=>button.disabled=true);try{const response=await fetch("/result",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(payload(completed))}),outcome=await response.json();if(outcome.passed===true){document.querySelector(".flat-prisoner")?.insertAdjacentHTML("beforeend",'<div class="flat-prison-verdict is-pass"><small>MATRIX + PHYSICS REPLAY AGREES</small><strong>UNFLATTENED</strong><i>PASS</i></div>');model.helpers.setReadout("PASS","passed");}else if(outcome.passed===false&&outcome.state){await model.helpers.render(outcome.state);document.querySelector(".flat-prisoner")?.classList.add("is-fresh-fail");document.querySelector(".flat-prisoner")?.insertAdjacentHTML("beforeend",'<div class="flat-prison-verdict is-fail is-fresh"><small>THE VIEW COLLAPSED · FRESH CELLBLOCK READY</small><strong>RECAPTURED</strong><i>FAIL</i></div>');model.helpers.setReadout("FAIL · FRESH CELLBLOCK","error");model.freshTimer=setTimeout(()=>document.querySelector(".flat-prison-verdict.is-fresh")?.remove(),1350);}else{model.busy=false;model.terminal=false;document.querySelectorAll("button").forEach((button)=>button.disabled=false);model.helpers.setReadout("FAIL · NO MATRIX GRADE","error");}}catch(_error){model.busy=false;model.terminal=false;document.querySelectorAll("button").forEach((button)=>button.disabled=false);model.helpers.setReadout("FAIL · PROJECTION SERVER OFFLINE","error");}}
  function clearFreshFailure(){document.querySelector(".flat-prisoner")?.classList.remove("is-fresh-fail");document.querySelector(".flat-prison-verdict.is-fresh")?.remove();}

  async function render(state,helpers){
    clearInterval(model.timer);clearTimeout(model.freshTimer);clearTimeout(model.settleTimer);document.body.dataset.mechanic="flat-prisoner";document.body.style.setProperty("--flat-sky",state.palette.sky);document.body.style.setProperty("--flat-haze",state.palette.haze);document.body.style.setProperty("--flat-surface",state.palette.surface);document.body.style.setProperty("--flat-edge",state.palette.edge);document.body.style.setProperty("--flat-signal",state.palette.signal);document.body.style.setProperty("--flat-danger",state.palette.danger);document.body.dataset.cheatMode=helpers.isCheatMode()?"true":"false";
    Object.assign(model,{state,helpers,camera:copyCamera(state.initial_camera),events:[],mode:"camera",topology:null,prisoner:null,timer:0,sessionStart:performance.now(),dragMode:"orbit",drag:null,cameraEventCount:0,freezeCount:0,thawCount:0,deathCount:0,keyTransitionCount:0,abandoned:false,busy:false,terminal:false,fallRecorded:false,settleTimer:0,lastCameraChangeAt:-Infinity});
    helpers.app.innerHTML=`<section class="flat-prisoner" data-challenge-id="${clean(state.challenge_id)}" data-mode="camera"><header class="flat-prison-head"><div><span>PARALLAX CORRECTIONS / INMATE 02-D</span><h1>${clean(state.prompt)}</h1></div><aside><small id="projection-mode">3D / CAMERA LIVE</small><b>THE FLAT PRISONER</b><i>ROW-MAJOR VIEW × PROJECTION</i></aside></header><main class="flat-prison-main"><section class="flat-prison-stage"><canvas id="flat-prison-canvas" width="${state.viewport.width}" height="${state.viewport.height}" aria-label="procedural 3D prison and frozen 2D traversal"></canvas><div class="flat-stage-rail"><span>WORLD → VIEW → CLIP → SCREEN</span><b>DRAG CAMERA · WHEEL DOLLY · FREEZE PROJECTION</b><i>NO CAMERA PRESETS</i></div></section><aside class="flat-prison-console"><div class="camera-ledger"><small>LIVE CAMERA MATRIX</small><div><span>YAW <b id="camera-yaw">0°</b></span><span>PITCH <b id="camera-pitch">0°</b></span><span>DOLLY <b id="camera-distance">0</b></span><span>PAN X/Y <b id="camera-pan">0 / 0</b></span></div></div><div class="camera-mode-toggle"><button type="button" data-drag-mode="orbit" class="is-selected">ORBIT DRAG</button><button type="button" data-drag-mode="pan">PAN DRAG</button></div><div class="camera-pads"><section><small>ORBIT</small><button id="orbit-up" data-camera-control data-kind="orbit" data-pitch="-${state.controls.orbit_step_deg}">▲</button><button id="orbit-left" data-camera-control data-kind="orbit" data-yaw="-${state.controls.orbit_step_deg}">◀</button><i>◎</i><button id="orbit-right" data-camera-control data-kind="orbit" data-yaw="${state.controls.orbit_step_deg}">▶</button><button id="orbit-down" data-camera-control data-kind="orbit" data-pitch="${state.controls.orbit_step_deg}">▼</button></section><section><small>PAN</small><button id="pan-up" data-camera-control data-kind="pan" data-pan-y="${state.controls.pan_step}">▲</button><button id="pan-left" data-camera-control data-kind="pan" data-pan-x="-${state.controls.pan_step}">◀</button><i>✥</i><button id="pan-right" data-camera-control data-kind="pan" data-pan-x="${state.controls.pan_step}">▶</button><button id="pan-down" data-camera-control data-kind="pan" data-pan-y="-${state.controls.pan_step}">▼</button></section></div><div class="dolly-strip"><small>DOLLY</small><button id="dolly-in" data-camera-control data-kind="dolly" data-dolly="-${state.controls.dolly_step}">− NEAR</button><i></i><button id="dolly-out" data-camera-control data-kind="dolly" data-dolly="${state.controls.dolly_step}">+ FAR</button></div><div class="projection-audit"><div><small>REAL SCREEN JOINS</small><b id="flat-join-count">00</b></div><div><small>EXIT GRAPH</small><b id="flat-route-state" data-ready="false">DISCONNECTED</b></div><div><small>PRISONER</small><b id="prisoner-status">AWAITING FREEZE</b></div><div><small>PHYSICS TICK</small><b id="physics-tick">0000</b></div></div><div class="flat-actions"><button type="button" id="reset-camera" data-camera-control>RESET CAMERA</button><button type="button" id="freeze-view">FREEZE VIEW → 2D</button><button type="button" id="thaw-view" disabled>THAW / REFRAME</button><button type="button" id="certify-escape" disabled>${clean(state.submit_label)}</button></div><div class="flat-key-help"><span><b>A / D</b> CONTINUOUS MOVE</span><span><b>SPACE</b> JUMP</span></div></aside></main><footer class="flat-prison-foot"><div class="readout" data-status="idle">ORBIT, PAN, AND DOLLY UNTIL DISTANT EDGES COINCIDE</div><button type="button" id="abandon-flat">ABANDON / NEW CELLBLOCK</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    model.canvas=document.getElementById("flat-prison-canvas");model.context=model.canvas.getContext("2d");model.canvas.addEventListener("pointerdown",canvasDown);model.canvas.addEventListener("pointermove",canvasMove);model.canvas.addEventListener("pointerup",canvasUp);model.canvas.addEventListener("pointercancel",canvasUp);model.canvas.addEventListener("wheel",wheel,{passive:false});
    document.querySelectorAll("[data-camera-control][data-kind]").forEach((button)=>button.addEventListener("click",()=>{const kind=button.dataset.kind;if(kind==="orbit")applyOrbit(Number(button.dataset.yaw||0),Number(button.dataset.pitch||0));else if(kind==="pan")applyPan(Number(button.dataset.panX||0),Number(button.dataset.panY||0));else applyDolly(Number(button.dataset.dolly||0));}));document.querySelectorAll("[data-drag-mode]").forEach((button)=>button.addEventListener("click",()=>{model.dragMode=button.dataset.dragMode;document.querySelectorAll("[data-drag-mode]").forEach((item)=>item.classList.toggle("is-selected",item===button));}));
    document.getElementById("reset-camera")?.addEventListener("click",resetCamera);document.getElementById("freeze-view")?.addEventListener("click",freezeView);document.getElementById("thaw-view")?.addEventListener("click",thawView);document.getElementById("certify-escape")?.addEventListener("click",certify);document.getElementById("abandon-flat")?.addEventListener("click",abandon);window.onkeydown=(event)=>handleKey(event,true);window.onkeyup=(event)=>handleKey(event,false);helpers.installCheatPanel();window.flatPrisonerModel=model;window.flatPrisonerPublicMath={projectPoint:(point,camera)=>project(point,camera||model.camera),deriveTopology:(camera)=>deriveTopology(camera||model.camera),makePhysics:(camera)=>makePhysics(deriveTopology(camera||model.camera)),stepPhysics:(player)=>{stepPhysicsState(player);return player;},convention:"right-handed world; row-major matrices × column vectors; OpenGL clip; screen Y down"};model.topology=deriveTopology();draw();updatePanels();
  }

  window.WeirdCaptchaMechanics=window.WeirdCaptchaMechanics||{};window.WeirdCaptchaMechanics.flat_prisoner={rootSelector:".flat-prisoner",render};
})();
