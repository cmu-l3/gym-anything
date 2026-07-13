(() => {
  "use strict";
  let model = null;
  const esc = (value) => String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const COPY = {
    update:["OPTIONAL UPDATE","A component may be available."],coupon:["BONUS WINDOW","Terms continue elsewhere."],cleaner:["DESKTOP CARE","Several pixels require attention."],forecast:["LOCAL FORECAST","A strong chance of more windows."],player:["MEDIA HELPER","Playback has not been requested."],survey:["ONE QUESTION","Closing is also an answer."],prize:["CLAIM PENDING","No prize was actually described."]
  };
  function record(kind, details={}){const event={sequence:model.events.length+1,kind,...details};model.events.push(event);return event;}
  function windowMarkup(item, infected=false){const copy=COPY[item.theme]||COPY.update;return `<article class="parasite-window theme-${esc(item.theme)} ${infected?"is-infected":""}" data-window-id="${esc(item.id)}" data-behavior="${esc(item.runtime_behavior||"echo")}" style="left:${item.x}px;top:${item.y}px;width:${item.w}px;height:${item.h}px;z-index:${item.z}"><header><i></i><span>${esc(item.title)}</span><button type="button" class="parasite-close" aria-label="Close">×</button></header><div class="parasite-body"><b>${esc(copy[0])}</b><p>${esc(copy[1])}</p><div class="fake-progress"><i></i></div></div></article>`;}
  function liveWindows(){return Array.from(document.querySelectorAll(".parasite-window:not(.is-dead)"));}
  function updateCount(){const node=document.querySelector(".parasite-count b");if(node)node.textContent=String(liveWindows().length);}
  function focus(node){node.style.zIndex=String(++model.topZ);record("focus",{window_id:node.dataset.windowId});}
  function activateContainment(){model.provoked=true;document.querySelector(".containment-well").dataset.active="true";document.querySelector(".popup-field").classList.add("is-contaminated");}
  async function failDesktop(){
    if(model.submitting)return;
    model.submitting=true;
    try{
      const response=await fetch("/result",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({mechanic_id:model.state.mechanic_id,challenge_id:model.state.challenge_id,events:model.events})});
      const outcome=await response.json();
      model.helpers.setReadout("FAIL","error");
      setTimeout(()=>outcome.state&&model.helpers.render(outcome.state),850);
    }catch(_error){model.submitting=false;model.helpers.setReadout("FAIL","error");}
  }
  function spawnEchoes(parent){const field=document.querySelector(".popup-field");const base={x:parseFloat(parent.style.left),y:parseFloat(parent.style.top),w:parent.offsetWidth,h:parent.offsetHeight,theme:parent.dataset.theme||"update",title:"DESKTOP MESSAGE"};model.state.echo_ids.forEach((id,index)=>{const item={...base,id,x:Math.max(8,Math.min(690-base.w,base.x+(index?74:-58))),y:Math.max(10,Math.min(365-base.h,base.y+54+index*22)),z:++model.topZ,runtime_behavior:"echo"};field.insertAdjacentHTML("beforeend",windowMarkup(item,true));const node=field.querySelector(`[data-window-id="${CSS.escape(id)}"]`);installWindow(node);});record("spawn",{parent_id:parent.dataset.windowId,echo_ids:[...model.state.echo_ids]});updateCount();}
  async function submit(containedId){
    if(model.submitting)return;
    model.submitting=true;
    record("purge",{contained_id:containedId,remaining_before:liveWindows().map(node=>node.dataset.windowId)});
    document.querySelector(".popup-field").classList.add("is-purging");
    liveWindows().forEach((node,index)=>setTimeout(()=>node.classList.add("is-dead"),index*75));
    setTimeout(updateCount,650);
    await new Promise(resolve=>setTimeout(resolve,700));
    try{
      const response=await fetch("/result",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({mechanic_id:model.state.mechanic_id,challenge_id:model.state.challenge_id,events:model.events})});
      const outcome=await response.json();
      if(outcome.passed===true){
        model.helpers.setReadout("PASS","passed");
        document.querySelector(".parasite-captcha").classList.add("is-passed");
      }else{
        model.helpers.setReadout("FAIL","error");
        setTimeout(()=>outcome.state&&model.helpers.render(outcome.state),850);
      }
    }catch(_error){
      model.submitting=false;
      model.helpers.setReadout("FAIL","error");
    }
  }
  function tryContain(node){if(!model.provoked||!node.classList.contains("is-infected"))return false;const well=document.querySelector(".containment-well").getBoundingClientRect();const rect=node.getBoundingClientRect();const cx=rect.left+rect.width/2,cy=rect.top+rect.height/2;if(cx<well.left||cx>well.right||cy<well.top||cy>well.bottom)return false;record("contain",{window_id:node.dataset.windowId});node.classList.add("is-contained");submit(node.dataset.windowId);return true;}
  function installWindow(node){if(!node)return;node.dataset.theme=node.className.match(/theme-([^ ]+)/)?.[1]||"update";node.addEventListener("pointerdown",()=>focus(node));const header=node.querySelector("header");header.addEventListener("pointerdown",event=>{if(event.target.closest("button"))return;event.preventDefault();focus(node);header.setPointerCapture(event.pointerId);const field=document.querySelector(".popup-field").getBoundingClientRect();const start=[event.clientX,event.clientY],origin=[parseFloat(node.style.left),parseFloat(node.style.top)];const samples=[];const move=moveEvent=>{const x=Math.max(0,Math.min(700-node.offsetWidth,origin[0]+moveEvent.clientX-start[0]));const y=Math.max(0,Math.min(390-node.offsetHeight,origin[1]+moveEvent.clientY-start[1]));node.style.left=`${x}px`;node.style.top=`${y}px`;samples.push([Math.round(x),Math.round(y)]);};const up=()=>{header.removeEventListener("pointermove",move);header.removeEventListener("pointerup",up);record("drag",{window_id:node.dataset.windowId,samples:samples.slice(-80)});tryContain(node);};header.addEventListener("pointermove",move);header.addEventListener("pointerup",up);});node.querySelector(".parasite-close").addEventListener("click",()=>{if(model.submitting)return;focus(node);const behavior=node.dataset.behavior;record("close",{window_id:node.dataset.windowId});if(behavior==="replicate"&&!model.provoked){node.classList.add("is-infected");activateContainment();spawnEchoes(node);return;}if(node.classList.contains("is-infected")){node.classList.remove("pulse");void node.offsetWidth;node.classList.add("pulse");model.strikes+=1;record("resist",{window_id:node.dataset.windowId,strike:model.strikes});if(model.strikes>=3)failDesktop();return;}node.classList.add("is-dead");updateCount();});}
  async function render(state,helpers){document.body.dataset.mechanic="popup-exorcist-v2";model={state,helpers,events:[],topZ:20,provoked:false,strikes:0,submitting:false};helpers.app.innerHTML=`<section class="parasite-captcha"><header class="parasite-head"><div><span>DESKTOP CONTAINMENT / LIVE FIELD</span><h1>${esc(state.prompt)}</h1></div><div class="parasite-count">WINDOWS <b>${state.popups.length}</b></div></header><section class="popup-field"><div class="field-wallpaper"><i></i><span>LOCAL DESKTOP</span></div><div class="containment-well" data-active="false" style="left:${state.containment.x}px;top:${state.containment.y}px;width:${state.containment.w}px;height:${state.containment.h}px"><i></i><b>⌁</b></div>${state.popups.map(item=>windowMarkup(item)).join("")}</section><footer class="parasite-foot"><div class="readout" data-status="idle"></div><span class="field-signal">CONTAINMENT FIELD: DORMANT</span></footer></section>`;document.querySelectorAll(".parasite-window").forEach(installWindow);const observer=new MutationObserver(()=>{const signal=document.querySelector(".field-signal");if(signal)signal.textContent=model.provoked?"CONTAINMENT FIELD: RESONANT":"CONTAINMENT FIELD: DORMANT";});observer.observe(document.querySelector(".containment-well"),{attributes:true});}
  window.WeirdCaptchaMechanics=window.WeirdCaptchaMechanics||{};window.WeirdCaptchaMechanics.popup_exorcist={render,rootSelector:".parasite-captcha"};
})();
