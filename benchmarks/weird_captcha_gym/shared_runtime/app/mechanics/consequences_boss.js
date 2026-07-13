(() => {
  "use strict";

  let model = null;
  const esc = (value) => String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function currentScene() {
    if (model.phase === "commit") return model.state.scenes[model.index];
    const id = model.state.boss_order[model.index];
    return model.state.scenes.find((scene) => scene.id === id);
  }

  function sceneMarkup(scene) {
    return `<div class="covenant-world world-${esc(scene.kind)} color-${esc(scene.color)}">
      <div class="covenant-moon"></div><div class="covenant-horizon"></div>
      <div class="covenant-figure"><i></i><b>${esc(scene.glyph)}</b></div>
      <div class="covenant-sockets">
        <div class="covenant-socket" data-socket="left"><i>${esc(scene.socket_glyphs[0])}</i></div>
        <div class="covenant-socket" data-socket="right"><i>${esc(scene.socket_glyphs[1])}</i></div>
      </div>
      <button class="covenant-relic" type="button" aria-label="Relic"><span>${esc(scene.glyph)}</span></button>
    </div>`;
  }

  function setSeal(value) {
    model.draft.seal = ((Number(value) % 4) + 4) % 4;
    const seal = document.querySelector(".covenant-seal");
    if (seal) seal.style.setProperty("--seal-angle", `${model.draft.seal * 90}deg`);
    updateCommitReady();
  }

  function updateCommitReady() {
    const button = document.querySelector(".covenant-bind");
    if (button) button.disabled = !model.draft.socket;
  }

  function installRelicDrag(scene) {
    const relic = document.querySelector(".covenant-relic");
    const world = document.querySelector(".covenant-world");
    if (!relic || !world) return;
    relic.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      relic.setPointerCapture(event.pointerId);
      const worldRect = world.getBoundingClientRect();
      const relicRect = relic.getBoundingClientRect();
      const dx = event.clientX - relicRect.left;
      const dy = event.clientY - relicRect.top;
      relic.dataset.dragging = "true";
      const move = (moveEvent) => {
        relic.style.left = `${moveEvent.clientX - worldRect.left - dx}px`;
        relic.style.top = `${moveEvent.clientY - worldRect.top - dy}px`;
      };
      const up = (upEvent) => {
        relic.removeEventListener("pointermove", move);
        relic.removeEventListener("pointerup", up);
        relic.dataset.dragging = "false";
        const rect = relic.getBoundingClientRect();
        const point = [rect.left + rect.width / 2, rect.top + rect.height / 2];
        let selected = null;
        document.querySelectorAll(".covenant-socket").forEach((socket) => {
          const target = socket.getBoundingClientRect();
          if (point[0] >= target.left && point[0] <= target.right && point[1] >= target.top && point[1] <= target.bottom) selected = socket;
        });
        if (!selected) {
          relic.removeAttribute("style");
          return;
        }
        model.draft.socket = selected.dataset.socket;
        document.querySelectorAll(".covenant-socket").forEach((socket) => socket.dataset.selected = String(socket === selected));
        const target = selected.getBoundingClientRect();
        relic.style.left = `${target.left - worldRect.left + target.width / 2 - rect.width / 2}px`;
        relic.style.top = `${target.top - worldRect.top + target.height / 2 - rect.height / 2}px`;
        record("place", {phase: model.phase, scene_id: scene.id, socket: model.draft.socket});
        updateCommitReady();
        void upEvent;
      };
      relic.addEventListener("pointermove", move);
      relic.addEventListener("pointerup", up);
    });
  }

  function installSealDrag(scene) {
    const seal = document.querySelector(".covenant-seal");
    if (!seal) return;
    seal.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      seal.setPointerCapture(event.pointerId);
      const update = (moveEvent) => {
        const rect = seal.getBoundingClientRect();
        const angle = Math.atan2(moveEvent.clientY - (rect.top + rect.height / 2), moveEvent.clientX - (rect.left + rect.width / 2));
        setSeal(Math.round((angle + Math.PI / 2) / (Math.PI / 2)));
      };
      const up = () => {
        seal.removeEventListener("pointermove", update);
        seal.removeEventListener("pointerup", up);
        record("seal", {phase: model.phase, scene_id: scene.id, seal: model.draft.seal});
      };
      update(event);
      seal.addEventListener("pointermove", update);
      seal.addEventListener("pointerup", up);
    });
  }

  async function submit() {
    if (model.submitting) return;
    model.submitting = true;
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({
        mechanic_id: model.state.mechanic_id,
        challenge_id: model.state.challenge_id,
        events: model.events,
      })});
      const outcome = await response.json();
      if (outcome.passed === true) {
        document.querySelector(".covenant-captcha")?.classList.add("is-passed");
        model.helpers.setReadout("PASS", "passed");
      } else {
        model.helpers.setReadout("FAIL", "error");
        window.setTimeout(() => outcome.state && model.helpers.render(outcome.state), 850);
      }
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("FAIL", "error");
    }
  }

  function bindDraft() {
    const scene = currentScene();
    if (!scene || !model.draft.socket) return;
    record(model.phase === "commit" ? "commit" : "reconstruct", {
      scene_id: scene.id,
      socket: model.draft.socket,
      seal: model.draft.seal,
      order_index: model.index,
    });
    model.index += 1;
    if (model.phase === "commit" && model.index >= model.state.scenes.length) {
      model.phase = "storm";
      renderStorm();
      return;
    }
    if (model.phase === "reconstruct" && model.index >= model.state.boss_order.length) {
      submit();
      return;
    }
    renderStep();
  }

  function renderStorm() {
    const stage = document.querySelector(".covenant-stage");
    record("storm", {duration_ms: Number(model.state.storm_ms)});
    stage.innerHTML = `<div class="covenant-storm"><i></i><i></i><i></i><strong>THE LEDGER CLOSES</strong></div>`;
    model.helpers.setReadout("", "idle");
    window.setTimeout(() => {
      model.phase = "reconstruct";
      model.index = 0;
      renderStep();
    }, Number(model.state.storm_ms));
  }

  function renderStep() {
    const scene = currentScene();
    model.draft = {socket: null, seal: Number(scene.initial_seal || 0)};
    const stage = document.querySelector(".covenant-stage");
    const label = model.phase === "commit" ? "THE MAKING" : "THE RECKONING";
    document.querySelector(".covenant-phase").textContent = `${String(model.index + 1).padStart(2, "0")} / 05 · ${label}`;
    stage.innerHTML = `${sceneMarkup(scene)}<aside class="covenant-control">
      <span>${model.phase === "commit" ? "PLACE / SEAL / BIND" : "REBUILD / SEAL / ANSWER"}</span>
      <div class="covenant-seal" style="--seal-angle:${model.draft.seal * 90}deg"><i>${esc(scene.glyph)}</i><b></b></div>
      <button class="covenant-bind" type="button" disabled>${model.phase === "commit" ? "BIND" : "ANSWER"}</button>
    </aside>`;
    installRelicDrag(scene);
    installSealDrag(scene);
    document.querySelector(".covenant-bind").addEventListener("click", bindDraft);
    model.helpers.setReadout("", "idle");
  }

  async function render(state, helpers) {
    document.body.dataset.mechanic = "consequences-boss-v2";
    model = {state, helpers, phase: "commit", index: 0, draft: null, events: [], submitting: false};
    helpers.app.innerHTML = `<section class="covenant-captcha" data-challenge-id="${esc(state.challenge_id)}">
      <header class="covenant-head"><span>CAUSAL LEDGER / COVENANT ENGINE</span><h1>${esc(state.prompt)}</h1><p class="covenant-phase"></p></header>
      <section class="covenant-stage"></section>
      <footer class="covenant-foot"><div class="readout" data-status="idle"></div><div class="covenant-orbit">◌　✦　◌</div></footer>
    </section>`;
    renderStep();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.consequences_boss = {render,rootSelector:".covenant-captcha"};
})();
