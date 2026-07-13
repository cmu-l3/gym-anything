(() => {
  "use strict";

  const GRID = 24;
  const CLASSES = ["umbrella", "sailboat", "fish", "flower", "ladder", "bicycle", "lighthouse", "locomotive"];
  const model = {
    state: null, helpers: null, strokes: [], active: null, events: [], attempts: [],
    undoCount: 0, clearCount: 0, abandoned: false, busy: false, terminal: false,
    sessionStart: 0, canvas: null, context: null,
  };

  const clean = (value) => String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const distance = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);
  const now = () => Math.max(0, Math.round(performance.now() - model.sessionStart));

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function ellipse(cx, cy, rx, ry, count = 30) {
    const points = Array.from({length: count}, (_, index) => [cx + rx * Math.cos(index * Math.PI * 2 / count), cy + ry * Math.sin(index * Math.PI * 2 / count)]);
    points.push([cx + rx, cy]);
    return points;
  }

  function templates() {
    const canopy = [[.14,.51],[.17,.41],[.23,.31],[.32,.23],[.42,.19],[.50,.18],[.58,.19],[.68,.23],[.77,.31],[.83,.41],[.86,.51],[.78,.47],[.70,.53],[.62,.47],[.54,.53],[.46,.47],[.38,.53],[.30,.47],[.22,.53],[.14,.51]];
    const flower = [];
    for (let index = 0; index <= 70; index += 1) {
      const angle = index * Math.PI * 2 / 70;
      const radius = .18 + .075 * Math.cos(5 * angle);
      flower.push([.5 + radius * Math.cos(angle), .39 + radius * Math.sin(angle)]);
    }
    return {
      umbrella: [canopy, [[.50,.50],[.50,.62],[.50,.74],[.51,.84],[.56,.90],[.63,.89],[.67,.84]], [[.50,.19],[.22,.52]], [[.50,.19],[.38,.52]], [[.50,.19],[.62,.52]], [[.50,.19],[.78,.52]], [[.50,.18],[.50,.10]], [[.23,.63],[.18,.74]], [[.39,.69],[.34,.80]], [[.77,.63],[.72,.74]]],
      sailboat: [
        [[.17,.73],[.83,.73],[.70,.86],[.31,.86],[.17,.73]], [[.50,.72],[.50,.18]],
        [[.47,.23],[.25,.66],[.47,.66],[.47,.23]], [[.53,.29],[.77,.66],[.53,.66],[.53,.29]],
        [[.31,.69],[.69,.69]], [[.50,.20],[.20,.72]], [[.50,.20],[.82,.72]], [[.50,.18],[.65,.23],[.50,.29],[.50,.18]],
        [[.12,.88],[.34,.86],[.55,.89],[.78,.86],[.91,.88]], [[.16,.93],[.37,.91],[.60,.94],[.84,.91]], [[.23,.79],[.41,.77],[.59,.79],[.76,.77]],
      ],
      fish: [ellipse(.46,.52,.29,.20,34), [[.75,.52],[.91,.33],[.91,.71],[.75,.52]], ellipse(.35,.47,.035,.035,10), [[.18,.53],[.13,.56]], [[.48,.32],[.58,.18],[.66,.38]], [[.47,.71],[.58,.84],[.64,.67]], [[.27,.38],[.32,.52],[.27,.64]], [[.43,.46],[.48,.50],[.43,.54]], [[.54,.43],[.59,.48],[.54,.53]], [[.62,.48],[.67,.52],[.62,.56]]],
      flower: [flower, [[.50,.56],[.50,.66],[.50,.77],[.50,.89]], [[.50,.72],[.62,.65],[.70,.69],[.61,.78],[.50,.72]], [[.50,.78],[.39,.70],[.31,.74],[.39,.82],[.50,.78]], ellipse(.50,.39,.055,.055,14), [[.50,.39],[.50,.18]], [[.50,.39],[.68,.27]], [[.50,.39],[.72,.47]], [[.50,.39],[.57,.61]], [[.50,.39],[.31,.28]], [[.26,.90],[.74,.90]]],
      ladder: [
        [[.31,.14],[.31,.88]], [[.69,.14],[.69,.88]], [[.31,.22],[.69,.22]], [[.31,.34],[.69,.34]], [[.31,.46],[.69,.46]], [[.31,.58],[.69,.58]], [[.31,.70],[.69,.70]], [[.31,.82],[.69,.82]], [[.26,.91],[.34,.86]], [[.74,.91],[.66,.86]], [[.27,.14],[.73,.14]],
      ],
      bicycle: [ellipse(.27,.68,.18,.18,28), ellipse(.73,.68,.18,.18,28), [[.27,.68],[.43,.43],[.55,.68],[.27,.68],[.48,.68],[.64,.43],[.43,.43]], [[.64,.43],[.73,.68]], [[.62,.39],[.70,.36]], [[.39,.40],[.49,.40]], ellipse(.48,.68,.045,.045,14), [[.43,.68],[.54,.68]], [[.27,.68],[.48,.68]], [[.20,.45],[.38,.45],[.43,.43]], [[.72,.61],[.77,.58]]],
      lighthouse: [[[.34,.84],[.40,.35],[.60,.35],[.66,.84],[.34,.84]], [[.36,.28],[.50,.15],[.64,.28],[.36,.28]], [[.40,.28],[.60,.28],[.60,.40],[.40,.40],[.40,.28]], [[.46,.84],[.46,.70],[.54,.70],[.54,.84]], [[.38,.48],[.62,.48]], [[.37,.58],[.63,.58]], [[.36,.68],[.64,.68]], [[.40,.32],[.12,.23]], [[.60,.32],[.88,.23]], [[.20,.86],[.34,.81],[.43,.86]], [[.57,.86],[.68,.81],[.82,.86]], [[.12,.88],[.88,.88]]],
      locomotive: [[[.20,.42],[.69,.42],[.78,.58],[.78,.72],[.20,.72],[.20,.42]], [[.18,.31],[.38,.31],[.38,.61],[.18,.61],[.18,.31]], ellipse(.55,.52,.20,.12,24), [[.57,.40],[.57,.24],[.66,.24],[.69,.40]], [[.78,.60],[.91,.70],[.78,.70]], ellipse(.29,.75,.09,.09,20), ellipse(.51,.75,.09,.09,20), ellipse(.72,.75,.09,.09,20), [[.29,.75],[.72,.75]], [[.10,.84],[.90,.84]], [[.13,.89],[.87,.89]], ellipse(.63,.16,.055,.045,14), ellipse(.73,.10,.07,.05,14), [[.75,.49],[.83,.49]]],
    };
  }
  const TEMPLATES = templates();

  function transformTemplate(className, angleDeg, xScaleMilli) {
    const angle = angleDeg * Math.PI / 180;
    const cosine = Math.cos(angle), sine = Math.sin(angle), xScale = xScaleMilli / 1000;
    return TEMPLATES[className].map((stroke) => stroke.map(([x,y]) => {
      const dx = (x - .5) * xScale, dy = y - .5;
      return [.5 + dx * cosine - dy * sine, .5 + dx * sine + dy * cosine];
    }));
  }

  function normalize(strokes) {
    const points = strokes.flat();
    if (!points.length) return {strokes: [], bounds: {width:0,height:0,center_x:.5,center_y:.5,max_dim:0}};
    const xs = points.map((point) => point[0]), ys = points.map((point) => point[1]);
    const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys);
    const width = maxX - minX, height = maxY - minY, maxDim = Math.max(width, height, 1e-9), centerX = (minX + maxX)/2, centerY = (minY + maxY)/2;
    return {
      strokes: strokes.map((stroke) => stroke.map(([x,y]) => [.5 + (x-centerX)/maxDim*.82, .5 + (y-centerY)/maxDim*.82])),
      bounds: {width,height,center_x:centerX,center_y:centerY,max_dim:maxDim},
    };
  }

  function rasterize(strokes) {
    const raster = Array(GRID*GRID).fill(0);
    const mark = (x,y) => {
      const column = clamp(Math.round(x*(GRID-1)),0,GRID-1), row = clamp(Math.round(y*(GRID-1)),0,GRID-1);
      for (let dy=-1;dy<=1;dy+=1) for (let dx=-1;dx<=1;dx+=1) {
        const cx=column+dx, cy=row+dy; if(cx>=0&&cx<GRID&&cy>=0&&cy<GRID) raster[cy*GRID+cx]=1;
      }
    };
    for (const stroke of strokes) for (let segment=0;segment<stroke.length-1;segment+=1) {
      const first=stroke[segment], second=stroke[segment+1], steps=Math.max(1,Math.ceil(distance(first,second)*GRID*2.5));
      for(let index=0;index<=steps;index+=1){const amount=index/steps;mark(first[0]+(second[0]-first[0])*amount,first[1]+(second[1]-first[1])*amount);}
    }
    return raster;
  }

  function segmentsIntersect(a,b,c,d){
    const orient=(p,q,r)=>(q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]);
    const o1=orient(a,b,c),o2=orient(a,b,d),o3=orient(c,d,a),o4=orient(c,d,b);
    return o1*o2 < -1e-8 && o3*o4 < -1e-8;
  }

  function extractFeatures(inputStrokes) {
    const normalized=normalize(inputStrokes), strokes=normalized.strokes, raster=rasterize(strokes), occupied=[];
    raster.forEach((value,index)=>{if(value)occupied.push(index);});
    const coarse=[];
    for(let by=0;by<6;by+=1)for(let bx=0;bx<6;bx+=1){let sum=0;for(let row=by*4;row<by*4+4;row+=1)for(let col=bx*4;col<bx*4+4;col+=1)sum+=raster[row*GRID+col];coarse.push(sum/16);}
    let totalLength=0,turns=0,turnDen=0,closed=0;const direction=Array(8).fill(0),segments=[],endpoints=[];
    strokes.forEach((stroke,strokeIndex)=>{
      if(!stroke.length)return;endpoints.push(stroke[0],stroke.at(-1));
      let strokeLength=0;for(let index=0;index<stroke.length-1;index+=1){const first=stroke[index],second=stroke[index+1],length=distance(first,second);strokeLength+=length;if(length>1e-9){const angle=((Math.atan2(second[1]-first[1],second[0]-first[0])%Math.PI)+Math.PI)%Math.PI;direction[Math.min(7,Math.floor(angle/Math.PI*8))]+=length;segments.push([strokeIndex,index,first,second]);}}
      totalLength+=strokeLength;if(stroke.length>=3&&distance(stroke[0],stroke.at(-1))<=.055)closed+=1;
      for(let index=0;index<stroke.length-2;index+=1){const first=stroke[index],middle=stroke[index+1],last=stroke[index+2];if(distance(first,middle)>.005&&distance(middle,last)>.005){let delta=Math.abs(((Math.atan2(last[1]-middle[1],last[0]-middle[0])-Math.atan2(middle[1]-first[1],middle[0]-first[0])+Math.PI)%(2*Math.PI)+2*Math.PI)%(2*Math.PI)-Math.PI);turnDen+=1;if(delta>38*Math.PI/180)turns+=1;}}
    });
    if(totalLength)for(let index=0;index<8;index+=1)direction[index]/=totalLength;
    const endpointGrid=Array(16).fill(0);for(const [x,y] of endpoints)endpointGrid[Math.min(3,Math.floor(y*4))*4+Math.min(3,Math.floor(x*4))]+=1;if(endpoints.length)for(let i=0;i<16;i+=1)endpointGrid[i]/=endpoints.length;
    let intersections=0;for(let i=0;i<segments.length;i+=1)for(let j=i+1;j<segments.length;j+=1){const a=segments[i],b=segments[j];if(a[0]===b[0]&&Math.abs(a[1]-b[1])<=1)continue;if(segmentsIntersect(a[2],a[3],b[2],b[3]))intersections+=1;}
    let verticalDiff=0,horizontalDiff=0;for(let row=0;row<GRID;row+=1)for(let col=0;col<GRID;col+=1){verticalDiff+=Math.abs(raster[row*GRID+col]-raster[row*GRID+(GRID-1-col)]);horizontalDiff+=Math.abs(raster[row*GRID+col]-raster[(GRID-1-row)*GRID+col]);}
    const radial=Array(4).fill(0);for(const index of occupied){const x=(index%GRID)/(GRID-1),y=Math.floor(index/GRID)/(GRID-1),radius=Math.min(.707,Math.hypot(x-.5,y-.5));radial[Math.min(3,Math.floor(radius/.708*4))]+=1;}if(occupied.length)for(let i=0;i<4;i+=1)radial[i]/=occupied.length;
    const bounds=normalized.bounds;
    return {raster,coarse,direction,endpoint_grid:endpointGrid,stroke_count:strokes.length,closed_count:closed,intersections:Math.min(intersections,12),turn_rate:turns/Math.max(1,turnDen),aspect:bounds.width/Math.max(bounds.height,1e-9),symmetry:[1-verticalDiff/(GRID*GRID),1-horizontalDiff/(GRID*GRID)],radial,length:totalLength,density:occupied.length/(GRID*GRID),bounds};
  }

  const cosine=(a,b)=>{const numerator=a.reduce((sum,value,index)=>sum+value*b[index],0),denominator=Math.sqrt(a.reduce((sum,value)=>sum+value*value,0)*b.reduce((sum,value)=>sum+value*value,0));return denominator>1e-12?numerator/denominator:0;};
  const distributionSimilarity=(a,b)=>Math.max(0,1-a.reduce((sum,value,index)=>sum+Math.abs(value-b[index]),0)/2);
  function featureScore(f,p){
    const fi=f.raster.reduce((a,b)=>a+b,0),pi=p.raster.reduce((a,b)=>a+b,0),overlap=f.raster.reduce((sum,value,index)=>sum+(value&&p.raster[index]?1:0),0),dice=2*overlap/Math.max(1,fi+pi);
    const coarse=Math.max(0,1-f.coarse.reduce((sum,value,index)=>sum+Math.abs(value-p.coarse[index]),0)/f.coarse.length*2.3),direction=cosine(f.direction,p.direction),endpoints=distributionSimilarity(f.endpoint_grid,p.endpoint_grid);
    const topology=(Math.max(0,1-Math.abs(f.stroke_count-p.stroke_count)/5)+Math.max(0,1-Math.abs(f.closed_count-p.closed_count)/3)+Math.max(0,1-Math.abs(f.intersections-p.intersections)/5)+Math.max(0,1-Math.abs(f.turn_rate-p.turn_rate)*2))/4;
    const aspect=Math.exp(-Math.abs(Math.log(Math.max(f.aspect,.05)/Math.max(p.aspect,.05)))*1.1),symmetry=Math.max(0,1-f.symmetry.reduce((sum,value,index)=>sum+Math.abs(value-p.symmetry[index]),0)/2),radial=distributionSimilarity(f.radial,p.radial),length=Math.exp(-Math.abs(Math.log(Math.max(f.length,.05)/Math.max(p.length,.05)))*.65),density=Math.exp(-Math.abs(Math.log(Math.max(f.density,.01)/Math.max(p.density,.01)))*.65);
    return 100*(.39*dice+.10*coarse+.12*direction+.07*endpoints+.12*topology+.06*aspect+.035*symmetry+.045*radial+.035*length+.025*density);
  }

  function recognize(strokes) {
    const canvas=model.state.canvas,target=model.state.target,requirements=model.state.requirements;
    const floating=strokes.map((stroke)=>stroke.points.map(([x,y])=>[x/canvas.width,y/canvas.height])),features=extractFeatures(floating),scores={};
    for(const className of CLASSES)scores[className]=Math.round(featureScore(features,extractFeatures(transformTemplate(className,target.pose.angle_deg,target.style.x_scale_milli)))*10);
    const targetScore=scores[target.class_name],ordered=Object.entries(scores).sort((a,b)=>b[1]-a[1]||a[0].localeCompare(b[0])),bestClass=ordered[0][0],bestScore=ordered[0][1],bestOther=Math.max(...Object.entries(scores).filter(([name])=>name!==target.class_name).map(([,score])=>score)),margin=targetScore-bestOther,bounds=features.bounds,maxFraction=Math.max(bounds.width,bounds.height),centerOffset=Math.max(Math.abs(bounds.center_x-.5),Math.abs(bounds.center_y-.5)),minFraction=requirements.minimum_bbox_fraction_milli/1000,maxAllowed=requirements.maximum_bbox_fraction_milli/1000,maxCenter=requirements.maximum_center_offset_milli/1000;
    const compositionOk=maxFraction>=minFraction&&maxFraction<=maxAllowed&&centerOffset<=maxCenter;
    let accepted=strokes.length>0&&strokes.length<=requirements.stroke_budget&&compositionOk&&targetScore>=requirements.acceptance_score_milli&&margin>=requirements.minimum_margin_milli&&bestClass===target.class_name;
    if(strokes.some((stroke)=>!stroke.dense))accepted=false;
    let critique;
    if(!strokes.length||maxFraction<.08)critique="BLANK_OR_DOT";else if(strokes.some((stroke)=>!stroke.dense))critique="SPARSE_STROKE";else if(maxFraction<minFraction)critique="MAKE_LARGER";else if(maxFraction>maxAllowed)critique="GIVE_IT_AIR";else if(centerOffset>maxCenter)critique="CENTER_FORM";else if(Math.abs(features.stroke_count-target.expected_strokes)>=2)critique="CHECK_TOPOLOGY";else if(bestClass!==target.class_name)critique="WRONG_SILHOUETTE";else if(margin<requirements.minimum_margin_milli)critique="SIMPLIFY_SILHOUETTE";else if(targetScore<requirements.acceptance_score_milli)critique="REFINE_DIRECTIONS";else critique="ACCEPTED";
    return {scores,target_score_milli:targetScore,best_class:bestClass,best_score_milli:bestScore,margin_milli:margin,accepted,critique,composition:{bbox_fraction_milli:Math.round(maxFraction*1000),center_offset_milli:Math.round(centerOffset*1000),stroke_count:strokes.length,closed_count:features.closed_count,intersections:features.intersections}};
  }

  function summary(result,index){return {attempt_index:index,scores:result.scores,target_score_milli:result.target_score_milli,best_class:result.best_class,best_score_milli:result.best_score_milli,margin_milli:result.margin_milli,accepted:result.accepted,critique:result.critique,composition:result.composition};}
  const critiqueText={BLANK_OR_DOT:"I SEE NO COMMITTED FORM",SPARSE_STROKE:"KEEP EACH LINE CONTINUOUS",MAKE_LARGER:"MAKE THE SUBJECT LARGER",GIVE_IT_AIR:"GIVE THE FORM MORE AIR",CENTER_FORM:"CENTER THE COMPOSITION",CHECK_TOPOLOGY:"RETHINK THE STROKE TOPOLOGY",WRONG_SILHOUETTE:"THE SILHOUETTE READS AS ANOTHER OBJECT",SIMPLIFY_SILHOUETTE:"SIMPLIFY THE SILHOUETTE",REFINE_DIRECTIONS:"REFINE THE MAIN DIRECTIONS",ACCEPTED:"THE ROBOT RECOGNIZES YOUR SUBJECT"};

  function canvasPoint(event){const rect=model.canvas.getBoundingClientRect();return [clamp(Math.round((event.clientX-rect.left)/rect.width*model.state.canvas.width),0,model.state.canvas.width),clamp(Math.round((event.clientY-rect.top)/rect.height*model.state.canvas.height),0,model.state.canvas.height)];}
  function redraw(){
    const context=model.context,w=model.canvas.width,h=model.canvas.height,palette=model.state.palette;context.clearRect(0,0,w,h);context.fillStyle=palette.wall;context.fillRect(0,0,w,h);context.strokeStyle="rgba(27,45,56,.08)";context.lineWidth=1;for(let x=0;x<=w;x+=25){context.beginPath();context.moveTo(x,0);context.lineTo(x,h);context.stroke();}for(let y=0;y<=h;y+=25){context.beginPath();context.moveTo(0,y);context.lineTo(w,y);context.stroke();}
    context.strokeStyle=palette.ink;context.lineWidth=8;context.lineCap="round";context.lineJoin="round";for(const stroke of [...model.strokes,...(model.active?[model.active]:[])]){if(stroke.points.length<2)continue;context.beginPath();context.moveTo(...stroke.points[0]);for(const point of stroke.points.slice(1))context.lineTo(...point);context.stroke();}
  }

  function appendInterpolated(point,elapsed){
    const active=model.active,last=active.points.at(-1),lastTime=active.times.at(-1),gap=distance(last,point),delta=Math.max(0,elapsed-lastTime),steps=Math.max(1,Math.ceil(gap/18),Math.ceil(delta/95));
    for(let index=1;index<=steps;index+=1){const amount=index/steps,next=[Math.round(last[0]+(point[0]-last[0])*amount),Math.round(last[1]+(point[1]-last[1])*amount)],time=Math.round(lastTime+(elapsed-lastTime)*amount);if(next[0]===active.points.at(-1)[0]&&next[1]===active.points.at(-1)[1])continue;active.points.push(next);active.times.push(time);record("stroke_move",{stroke_id:active.id,point:next,elapsed_ms:time});}
  }
  function strokeDown(event){if(model.busy||model.terminal||model.active||model.strokes.length>=model.state.requirements.stroke_budget)return;clearFreshFailure();event.preventDefault();const point=canvasPoint(event),elapsed=now(),id=`stroke-${model.strokes.length+1}`;model.active={id,points:[point],times:[elapsed],start:elapsed,dense:false};record("stroke_down",{stroke_id:id,point,elapsed_ms:elapsed});model.canvas.setPointerCapture?.(event.pointerId);model.active.pointerId=event.pointerId;updatePanels();}
  function strokeMove(event){if(!model.active||event.pointerId!==model.active.pointerId)return;const point=canvasPoint(event),elapsed=now();if(point[0]===model.active.points.at(-1)[0]&&point[1]===model.active.points.at(-1)[1])return;appendInterpolated(point,elapsed);redraw();}
  function strokeUp(event){if(!model.active||event.pointerId!==model.active.pointerId)return;const point=canvasPoint(event),elapsed=now();if(point[0]!==model.active.points.at(-1)[0]||point[1]!==model.active.points.at(-1)[1])appendInterpolated(point,elapsed);const active=model.active,duration=elapsed-active.start;record("stroke_up",{stroke_id:active.id,point:active.points.at(-1),elapsed_ms:elapsed,duration_ms:duration,sample_count:active.points.length});active.dense=active.points.length>=model.state.requirements.minimum_points_per_stroke&&duration>=model.state.requirements.minimum_stroke_ms;delete active.pointerId;model.strokes.push(active);model.active=null;redraw();updatePanels();model.helpers.setReadout("STROKE RECORDED · CONTINUE OR ASK THE CRITIC","idle");}
  function undo(){if(model.busy||model.terminal||model.active||!model.strokes.length)return;const removed=model.strokes.pop();record("undo",{removed_stroke_id:removed.id});model.undoCount+=1;redraw();updatePanels();model.helpers.setReadout("LAST STROKE UNDONE","idle");}
  function clearCanvas(){if(model.busy||model.terminal||model.active)return;record("clear",{cleared_strokes:model.strokes.length});model.clearCount+=1;model.strokes=[];redraw();updatePanels();model.helpers.setReadout("CANVAS CLEARED · ATTEMPT HISTORY PRESERVED","idle");}

  function updateCritique(result){const panel=document.getElementById("critic-response");if(!panel)return;panel.dataset.status=result.accepted?"accepted":"rejected";panel.innerHTML=`<small>CRITIQUE ${String(model.attempts.length).padStart(2,"0")}</small><strong>${clean(critiqueText[result.critique]||result.critique)}</strong><div><span>IMPRESSION</span><i style="--confidence:${Math.min(1,result.target_score_milli/1000)}"></i><b>${result.target_score_milli>=850?"STRONG":result.target_score_milli>=700?"EMERGING":"WEAK"}</b></div><em>${result.best_class===model.state.target.class_name?"SUBJECT READS CLEARLY":`CURRENTLY READS: ${clean(result.best_class).toUpperCase()}`}</em>`;}
  function updatePanels(){const used=document.getElementById("stroke-used");if(used)used.textContent=`${model.strokes.length} / ${model.state.requirements.stroke_budget}`;const attempts=document.getElementById("attempt-used");if(attempts)attempts.textContent=`${model.attempts.length} / ${model.state.requirements.maximum_attempts}`;document.getElementById("undo-stroke")?.toggleAttribute("disabled",!model.strokes.length||model.busy);const tape=document.getElementById("critic-tape");if(tape)tape.innerHTML=model.attempts.length?model.attempts.slice().reverse().map((item)=>`<li><b>${String(item.attempt_index).padStart(2,"0")}</b><span>${clean(item.accepted?"ACCEPTED":critiqueText[item.critique])}</span><i>${clean(item.best_class).toUpperCase()}</i></li>`).join(""):'<li><b>00</b><span>NO REVIEWS YET</span><i>—</i></li>';}

  async function attempt(){if(model.busy||model.terminal||model.active)return;const result=recognize(model.strokes),item=summary(result,model.attempts.length+1);record("attempt",{attempt_index:item.attempt_index,client_score:item.target_score_milli,client_accepted:item.accepted,client_feedback:item.critique});model.attempts.push(item);updateCritique(result);updatePanels();if(result.accepted){model.helpers.setReadout("RECOGNIZED · REPLAYING THE DRAWING LEDGER…","pending");await submit(true);}else if(model.attempts.length>=model.state.requirements.maximum_attempts){model.helpers.setReadout("REVIEW LIMIT REACHED · FRESH BRIEF","error");await submit(false);}else model.helpers.setReadout(`${critiqueText[result.critique]} · REVISE AND TRY AGAIN`,"error");}
  async function abandon(){if(model.busy||model.terminal||model.active)return;record("abandon");model.abandoned=true;await submit(false);}
  function payload(completed){return {mechanic_id:model.state.mechanic_id,task_id:model.state.task_id,challenge_id:model.state.challenge_id,events:model.events,attempt_count:model.attempts.length,attempt_summaries:model.attempts,accepted:model.attempts.some((item)=>item.accepted),stroke_count:model.strokes.length,undo_count:model.undoCount,clear_count:model.clearCount,abandoned:model.abandoned,completed};}
  async function submit(completed){if(model.busy)return;model.busy=true;model.terminal=true;document.querySelectorAll("button").forEach((button)=>{button.disabled=true;});try{const response=await fetch("/result",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(payload(completed))}),outcome=await response.json();if(outcome.passed===true){const shell=document.querySelector(".art-critic-studio");shell?.classList.add("is-pass");shell?.insertAdjacentHTML("beforeend",'<div class="art-verdict art-verdict-pass"><small>SEMANTIC REPLAY AGREES</small><strong>MASTERPIECE</strong><i>PASS</i></div>');model.helpers.setReadout("PASS","passed");}else if(outcome.passed===false&&outcome.state){await model.helpers.render(outcome.state);const shell=document.querySelector(".art-critic-studio");shell?.classList.add("is-fresh-fail");shell?.insertAdjacentHTML("beforeend",'<div class="art-verdict art-verdict-fail art-verdict-fresh"><small>THE CRITIC CLOSED THE REVIEW · FRESH BRIEF</small><strong>REJECTED</strong><i>FAIL</i></div>');model.helpers.setReadout("FAIL · FRESH ROBOT BRIEF","error");setTimeout(()=>document.querySelector(".art-verdict-fresh")?.remove(),1200);}else{model.busy=false;model.terminal=false;document.querySelectorAll("button").forEach((button)=>{button.disabled=false;});model.helpers.setReadout("FAIL · NO CRITIC GRADE","error");}}catch(_error){model.busy=false;model.terminal=false;document.querySelectorAll("button").forEach((button)=>{button.disabled=false;});model.helpers.setReadout("FAIL · CRITIC OFFLINE","error");}}
  function clearFreshFailure(){document.querySelector(".art-critic-studio")?.classList.remove("is-fresh-fail");document.querySelector(".art-verdict-fresh")?.remove();}

  async function render(state,helpers){
    document.body.dataset.mechanic="robot-art-critic";document.body.style.setProperty("--art-wall",state.palette.wall);document.body.style.setProperty("--art-ink",state.palette.ink);document.body.style.setProperty("--art-robot",state.palette.robot);document.body.style.setProperty("--art-signal",state.palette.signal);document.body.style.setProperty("--art-warning",state.palette.warning);document.body.dataset.cheatMode=helpers.isCheatMode()?"true":"false";
    Object.assign(model,{state,helpers,strokes:[],active:null,events:[],attempts:[],undoCount:0,clearCount:0,abandoned:false,busy:false,terminal:false,sessionStart:performance.now()});
    helpers.app.innerHTML=`<section class="art-critic-studio" data-challenge-id="${clean(state.challenge_id)}"><header class="art-head"><div><span>ROBOT SALON / REVIEW BAY 05</span><h1>${clean(state.prompt)}</h1></div><aside><small>BRIEF</small><b>${clean(state.target.display_name)}</b><i>${clean(state.target.style.label)} · ${clean(state.target.pose.label)}</i></aside></header><main class="art-workbench"><section class="art-canvas-wrap"><canvas id="art-canvas" width="${state.canvas.width}" height="${state.canvas.height}" aria-label="limited stroke drawing canvas"></canvas><div class="art-canvas-caption"><span>DRAW WITH CONTINUOUS POINTER HOLDS</span><i>NO TEMPLATE</i><b>ROUGH LINES ARE WELCOME</b></div></section><aside class="critic-console"><div class="robot-face"><span><i></i><i></i></span><b>R-CRITIC 7</b><small>AWAITING ART</small></div><div class="brief-card"><small>DRAWING BRIEF</small><strong>${clean(state.target.display_name)}</strong><span>${clean(state.target.style.label)} / ${clean(state.target.pose.label)}</span><i>MAKE IT RECOGNIZABLE, NOT PERFECT.</i></div><div class="budget-grid"><div><small>STROKES</small><b id="stroke-used">0 / ${state.requirements.stroke_budget}</b></div><div><small>REVIEWS</small><b id="attempt-used">0 / ${state.requirements.maximum_attempts}</b></div></div><div class="critic-response" id="critic-response" data-status="idle"><small>CRITIQUE 00</small><strong>AWAITING A DRAWING</strong><em>YOU CAN REVISE AFTER A REVIEW</em></div><ol id="critic-tape"><li><b>00</b><span>NO REVIEWS YET</span><i>—</i></li></ol></aside></main><footer class="art-foot"><div><button type="button" id="undo-stroke">↶ UNDO STROKE</button><button type="button" id="clear-art">× CLEAR CANVAS</button></div><div class="readout" data-status="idle">DRAW THE NAMED SUBJECT · A VALID FIRST ATTEMPT MAY PASS</div><button type="button" id="ask-critic">${clean(state.submit_label)}</button><button type="button" id="abandon-art">ABANDON / NEW BRIEF</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    model.canvas=document.getElementById("art-canvas");model.context=model.canvas.getContext("2d");model.canvas.addEventListener("pointerdown",strokeDown);model.canvas.addEventListener("pointermove",strokeMove);model.canvas.addEventListener("pointerup",strokeUp);model.canvas.addEventListener("pointercancel",strokeUp);document.getElementById("undo-stroke")?.addEventListener("click",undo);document.getElementById("clear-art")?.addEventListener("click",clearCanvas);document.getElementById("ask-critic")?.addEventListener("click",attempt);document.getElementById("abandon-art")?.addEventListener("click",abandon);helpers.installCheatPanel();window.robotArtCriticModel=model;redraw();updatePanels();
  }
  window.WeirdCaptchaMechanics=window.WeirdCaptchaMechanics||{};window.WeirdCaptchaMechanics.robot_art_critic={rootSelector:".art-critic-studio",render};
})();
