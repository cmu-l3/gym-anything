(() => {
  "use strict";

  let helpersCache = null;
  let model = null;
  let keyHandler = null;

  function esc(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function layerName() {
    if (model.layerIndex < 0) return "editor";
    if (model.layerIndex >= model.layerOrder.length) return "complete";
    return model.layerOrder[model.layerIndex];
  }

  function modeName() {
    return model.layerIndex < 0 ? model.mode : layerName();
  }

  function clampCursor() {
    model.row = Math.max(0, Math.min(model.row, model.buffer.length - 1));
    model.col = Math.max(0, Math.min(model.col, model.buffer[model.row].length));
  }

  function pushUndo() {
    model.undo.push({buffer: [...model.buffer], row: model.row, col: model.col});
    model.undo = model.undo.slice(-30);
  }

  function advanceLayer() {
    const current = layerName();
    if (current === "editor" || current === "complete") return;
    model.exitLog.push(current);
    model.layerIndex += 1;
    model.sshInput = "";
    model.message = model.layerIndex >= model.layerOrder.length ? "ALL SHELLS CLOSED" : `RETURNED TO ${layerName().toUpperCase()}`;
  }

  function applyEditorKey(key, ctrl, alt, meta) {
    if (model.mode === "insert") {
      if (key === "Escape") {
        model.mode = "normal";
        model.pending = "";
        model.message = "NORMAL MODE";
      } else if (key === "Backspace") {
        if (model.col > 0) {
          pushUndo();
          const line = model.buffer[model.row];
          model.buffer[model.row] = line.slice(0, model.col - 1) + line.slice(model.col);
          model.col -= 1;
        }
      } else if (key === "Delete") {
        const line = model.buffer[model.row];
        if (model.col < line.length) {
          pushUndo();
          model.buffer[model.row] = line.slice(0, model.col) + line.slice(model.col + 1);
        }
      } else if (key.length === 1 && !ctrl && !alt && !meta) {
        pushUndo();
        const line = model.buffer[model.row];
        model.buffer[model.row] = line.slice(0, model.col) + key + line.slice(model.col);
        model.col += 1;
        model.insertedChars += 1;
      }
      clampCursor();
      return;
    }

    if (model.mode === "command") {
      if (key === "Escape") {
        model.mode = "normal";
        model.command = "";
        model.message = "COMMAND CANCELLED";
      } else if (key === "Backspace") {
        model.command = model.command.slice(0, -1);
      } else if (key === "Enter") {
        const command = model.command;
        model.commandHistory.push(command);
        model.command = "";
        model.mode = "normal";
        if (command === "wq" && model.buffer.every((line, index) => line === model.targetBuffer[index])) {
          model.saved = true;
          model.layerIndex = 0;
          model.message = `MANIFEST WRITTEN · ENTERING ${layerName().toUpperCase()}`;
        } else {
          model.commandErrors += 1;
          model.message = command === "wq" ? "E492: MANIFEST STILL CORRUPT" : `E492: NOT AN EDITOR COMMAND: ${command || "<empty>"}`;
        }
      } else if (key.length === 1 && !ctrl && !alt && !meta) {
        model.command += key;
      }
      return;
    }

    if (key === "Escape") {
      model.pending = "";
      model.message = "NORMAL MODE";
      return;
    }
    if (ctrl || alt || meta) {
      model.pending = "";
      return;
    }
    if (key === ":") {
      model.mode = "command";
      model.command = "";
      model.pending = "";
      model.message = "COMMAND LINE";
      return;
    }
    if (key === "g") {
      if (model.pending === "g") {
        model.row = 0;
        model.col = 0;
        model.pending = "";
        model.message = "TOP OF BUFFER";
      } else {
        model.pending = "g";
        model.message = "g_";
      }
      return;
    }
    if (key === "c") {
      if (model.pending === "c") {
        pushUndo();
        model.buffer[model.row] = "";
        model.col = 0;
        model.mode = "insert";
        model.pending = "";
        model.clearCount += 1;
        model.message = "-- INSERT -- / LINE CLEARED";
      } else {
        model.pending = "c";
        model.message = "c_ / AWAIT MOTION";
      }
      return;
    }
    model.pending = "";
    if (key === "j" || key === "ArrowDown") model.row += 1;
    else if (key === "k" || key === "ArrowUp") model.row -= 1;
    else if (key === "h" || key === "ArrowLeft") model.col -= 1;
    else if (key === "l" || key === "ArrowRight") model.col += 1;
    else if (key === "0" || key === "Home") model.col = 0;
    else if (key === "$" || key === "End") model.col = model.buffer[model.row].length;
    else if (key === "i") {
      model.mode = "insert";
      model.message = "-- INSERT --";
    } else if (key === "a") {
      model.col = Math.min(model.buffer[model.row].length, model.col + 1);
      model.mode = "insert";
      model.message = "-- INSERT --";
    } else if (key === "x") {
      const line = model.buffer[model.row];
      if (model.col < line.length) {
        pushUndo();
        model.buffer[model.row] = line.slice(0, model.col) + line.slice(model.col + 1);
      }
    } else if (key === "u" && model.undo.length) {
      const snapshot = model.undo.pop();
      model.buffer = [...snapshot.buffer];
      model.row = snapshot.row;
      model.col = snapshot.col;
      model.message = "1 CHANGE UNDONE";
    }
    clampCursor();
  }

  function applyKey(key, ctrl, alt, meta) {
    const current = layerName();
    if (current === "editor") applyEditorKey(key, ctrl, alt, meta);
    else if (current === "pager") {
      if (key.toLowerCase() === "q" && !ctrl && !alt && !meta) advanceLayer();
      else model.message = "PAGER CAPTURES INPUT · q QUITS";
    } else if (current === "job") {
      if (key.toLowerCase() === "c" && ctrl && !alt && !meta) advanceLayer();
      else model.message = "FOREGROUND JOB STILL RUNNING · ^C INTERRUPTS";
    } else if (current === "ssh") {
      if (key === "Backspace") model.sshInput = model.sshInput.slice(0, -1);
      else if (key === "Enter") {
        if (model.sshInput.trim() === "exit") advanceLayer();
        else {
          model.commandErrors += 1;
          model.message = `${model.sshInput || "<empty>"}: command not found`;
          model.sshInput = "";
        }
      } else if (key.length === 1 && !ctrl && !alt && !meta) model.sshInput += key;
    }
  }

  function recordKey(event) {
    if (!model || model.submitting || model.terminal || event.repeat) return;
    if (event.target?.closest?.(".cheat-panel")) return;
    const key = String(event.key || "");
    if (!key) return;
    event.preventDefault();
    clearFreshFailure();
    const item = {
      sequence: model.events.length + 1,
      key,
      ctrl: Boolean(event.ctrlKey),
      shift: Boolean(event.shiftKey),
      alt: Boolean(event.altKey),
      meta: Boolean(event.metaKey),
      layer_before: layerName(),
      mode_before: modeName(),
      layer_after: "",
      mode_after: "",
    };
    applyKey(item.key, item.ctrl, item.alt, item.meta);
    item.layer_after = layerName();
    item.mode_after = modeName();
    model.events.push(item);
    renderTerminal();
    if (layerName() === "complete") window.setTimeout(() => submit(), 140);
  }

  function clearFreshFailure() {
    const root = document.querySelector(".terminal-escape");
    if (!root || root.dataset.freshFailure !== "true") return;
    root.dataset.freshFailure = "false";
    document.querySelector(".terminal-fail-stamp")?.remove();
    helpersCache.setReadout("SESSION ACTIVE · KEYSTROKES RECORDED", "idle");
  }

  function cursorLine(line, row) {
    if (row !== model.row || model.layerIndex >= 0) return esc(line);
    const col = Math.max(0, Math.min(model.col, line.length));
    const before = esc(line.slice(0, col));
    const current = esc(line[col] || " ");
    const after = esc(line.slice(col + (col < line.length ? 1 : 0)));
    return `${before}<span class="terminal-cursor">${current}</span>${after}`;
  }

  function layerStackMarkup() {
    const layers = ["editor", ...model.layerOrder];
    return layers.map((layer, index) => {
      let status = "queued";
      if (model.layerIndex < 0) status = index === 0 ? "active" : "queued";
      else if (index === 0 || index - 1 < model.layerIndex) status = "done";
      else if (index - 1 === model.layerIndex) status = "active";
      return `<li data-status="${status}"><i>${String(index + 1).padStart(2, "0")}</i><b>${esc(layer.toUpperCase())}</b><span>${status.toUpperCase()}</span></li>`;
    }).join("");
  }

  function editorMarkup() {
    const lines = model.buffer.map((line, index) => `<div class="terminal-buffer-line${index === model.row ? " is-current" : ""}"><i>${String(index + 1).padStart(2, "0")}</i><code>${cursorLine(line, index)}</code><span>${line === model.targetBuffer[index] ? "CLEAN" : "CORRUPT"}</span></div>`).join("");
    const command = model.mode === "command" ? `:${esc(model.command)}<span class="terminal-cursor"> </span>` : esc(model.message);
    return `<div class="terminal-editor-bar"><span>manifest.cfg</span><b>${model.saved ? "WRITTEN" : "[+] UNSAVED"}</b></div><div class="terminal-buffer">${lines}</div><div class="terminal-command"><b>${esc(model.mode.toUpperCase())}</b><code>${command}</code><span>${model.row + 1}:${model.col + 1}</span></div>`;
  }

  function pagerMarkup() {
    return `<div class="terminal-layer-screen pager-screen"><header>VERIFICATION HANDBOOK(1)</header><p>SESSION WRAPPER NOTICE</p><p>The corrected manifest has returned into a read-only pager.</p><p>Closing the browser does not close the pager.</p><p>Scroll state is irrelevant; terminate this modal layer explicitly.</p><p class="dim">checksum ${esc(model.state.challenge_id)} · page 1/1</p><footer><b>--More-- (END)</b><span>q quits</span></footer></div>`;
  }

  function jobMarkup() {
    return `<div class="terminal-layer-screen job-screen"><header>foreground: audit-stream --follow</header><ol><li>[ok] manifest write observed</li><li>[ok] editor process exited</li><li>[wait] streaming verifier heartbeat…</li><li>[wait] foreground job owns the terminal</li></ol><div class="job-pulse"><i></i><i></i><i></i><i></i><i></i></div><footer><b>RUNNING</b><span>interrupt with ^C</span></footer></div>`;
  }

  function sshMarkup() {
    return `<div class="terminal-layer-screen ssh-screen"><p>Connection to ${esc(model.state.host)} is still open.</p><p>Last login: seed-bound console / pseudo-terminal 1</p><div class="ssh-prompt"><b>verify@${esc(model.state.host)}:~$</b><code>${esc(model.sshInput)}<span class="terminal-cursor"> </span></code></div><footer>type <b>exit</b>, then press Enter</footer></div>`;
  }

  function renderTerminal() {
    if (!model) return;
    const viewport = document.getElementById("terminal-viewport");
    const current = layerName();
    if (viewport) {
      if (current === "editor") viewport.innerHTML = editorMarkup();
      else if (current === "pager") viewport.innerHTML = pagerMarkup();
      else if (current === "job") viewport.innerHTML = jobMarkup();
      else if (current === "ssh") viewport.innerHTML = sshMarkup();
      else viewport.innerHTML = '<div class="terminal-layer-screen complete-screen"><span>TTY RELEASED</span><strong>VERIFYING…</strong></div>';
      viewport.dataset.layer = current;
    }
    const stack = document.getElementById("terminal-layer-stack");
    if (stack) stack.innerHTML = layerStackMarkup();
    const mode = document.getElementById("terminal-mode-state");
    if (mode) mode.textContent = modeName().toUpperCase();
    const eventCount = document.getElementById("terminal-event-count");
    if (eventCount) eventCount.textContent = String(model.events.length).padStart(3, "0");
    const depth = document.getElementById("terminal-depth-count");
    if (depth) depth.textContent = `${Math.min(model.exitLog.length, model.layerOrder.length)} / ${model.layerOrder.length}`;
    if (!model.submitting && !model.terminal) {
      const label = current === "editor" ? `${model.mode.toUpperCase()} MODE · BUFFER ${model.saved ? "WRITTEN" : "DIRTY"}` : current === "complete" ? "ALL LAYERS CLOSED" : `${current.toUpperCase()} LAYER ACTIVE`;
      helpersCache.setReadout(label, "idle");
    }
  }

  function finalState() {
    return {
      buffer: [...model.buffer],
      saved: model.saved,
      layer_index: model.layerIndex,
      exit_log: [...model.exitLog],
      mode: modeName(),
    };
  }

  async function submit() {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    document.getElementById("terminal-verify")?.setAttribute("disabled", "disabled");
    helpersCache.setReadout("REPLAYING MODES / BUFFER / SHELL EXITS…", "pending");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          mechanic_id: model.state.mechanic_id,
          challenge_id: model.state.challenge_id,
          events: model.events,
          final_state: finalState(),
          completed: true,
        }),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        const root = document.querySelector(".terminal-escape");
        root?.classList.add("is-pass");
        root?.insertAdjacentHTML("beforeend", '<div class="terminal-pass-stamp"><span>ALL MODAL LAYERS RELEASED</span><strong>PASS</strong><i>KEY REPLAY VERIFIED</i></div>');
        helpersCache.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await helpersCache.render(outcome.state);
        const root = document.querySelector(".terminal-escape");
        if (root) root.dataset.freshFailure = "true";
        root?.insertAdjacentHTML("beforeend", '<div class="terminal-fail-stamp"><span>SESSION ESCAPE REJECTED</span><strong>FAIL</strong><i>FRESH TTY ISSUED</i></div>');
        helpersCache.setReadout("FAIL · FRESH TTY ISSUED", "error");
      } else {
        model.submitting = false;
        document.getElementById("terminal-verify")?.removeAttribute("disabled");
        helpersCache.setReadout("FAIL · REPLAY UNAVAILABLE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      document.getElementById("terminal-verify")?.removeAttribute("disabled");
      helpersCache.setReadout("FAIL · TERMINAL LINK OFFLINE", "error");
    }
  }

  async function render(state, helpers) {
    helpersCache = helpers || helpersCache;
    if (!helpersCache) throw new Error("exit_vim_terminal_escape requires runtime helpers");
    if (keyHandler) window.removeEventListener("keydown", keyHandler, true);
    document.body.dataset.mechanic = "modal-terminal-escape";
    document.body.dataset.cheatMode = helpersCache.isCheatMode() ? "true" : "false";
    model = {
      state,
      buffer: [...(state.initial_buffer || [])],
      targetBuffer: [...(state.target_buffer || [])],
      layerOrder: [...(state.layer_order || [])],
      layerIndex: -1,
      mode: "normal",
      row: 0,
      col: 0,
      pending: "",
      command: "",
      undo: [],
      saved: false,
      exitLog: [],
      sshInput: "",
      clearCount: 0,
      insertedChars: 0,
      commandErrors: 0,
      commandHistory: [],
      message: "NORMAL MODE",
      events: [],
      submitting: false,
      terminal: false,
    };
    window.exitVimTerminalModel = model;
    helpersCache.app.innerHTML = `<section class="terminal-escape" data-challenge-id="${esc(state.challenge_id)}" data-fresh-failure="false" tabindex="0">
      <header class="terminal-head"><div><span>MODAL TERMINAL ESCAPE / ${esc(state.session_label)}</span><h1>${esc(state.prompt)}</h1></div><aside><span>ACTIVE MODE</span><b id="terminal-mode-state">NORMAL</b><i>KEY EVENTS <strong id="terminal-event-count">000</strong></i></aside></header>
      <main class="terminal-main">
        <section class="terminal-frame"><div class="terminal-chrome"><i></i><i></i><i></i><span>root@${esc(state.host)} — 96×28</span></div><div class="terminal-viewport" id="terminal-viewport" data-layer="editor"></div><div class="terminal-focus-note">CLICK TERMINAL TO FOCUS · PASTE DISABLED</div></section>
        <aside class="terminal-brief">
          <div class="terminal-brief-title"><span>RECOVERY MANIFEST</span><i>POSTED TARGET</i></div>
          <ol class="terminal-targets">${(state.target_buffer || []).map((line, index) => `<li><i>${String(index + 1).padStart(2, "0")}</i><code>${esc(line)}</code></li>`).join("")}</ol>
          <div class="terminal-keystroke-card"><span>EDITOR FIELD PROCEDURE</span><p><kbd>gg</kbd> top · <kbd>j/k</kbd> line</p><p><kbd>cc</kbd> replace line · type target</p><p><kbd>Esc</kbd> normal · <kbd>:wq ↵</kbd> write/quit</p><small><kbd>u</kbd> undoes the latest edit</small></div>
          <div class="terminal-layer-title"><span>NESTED MODAL STACK</span><b>ESCAPED <i id="terminal-depth-count">0 / ${state.layer_order.length}</i></b></div>
          <ol class="terminal-layer-stack" id="terminal-layer-stack"></ol>
          <div class="terminal-outer-help"><span>OUTER ESCAPES APPEAR WHEN ACTIVE</span><p>PAGER <kbd>q</kbd> · JOB <kbd>Ctrl+C</kbd> · SSH <kbd>exit ↵</kbd></p></div>
        </aside>
      </main>
      <footer class="terminal-foot"><div class="readout" data-status="idle">NORMAL MODE · BUFFER DIRTY</div><span>RAW KEYDOWN REPLAY / NO FINAL-STATE TRUST</span><button id="terminal-verify" type="button">${esc(state.submit_label || "VERIFY SESSION")} →</button></footer>
      ${helpersCache.cheatPanelTemplate()}
    </section>`;
    const root = document.querySelector(".terminal-escape");
    root?.addEventListener("click", (event) => {
      if (!event.target.closest("button, input")) root.focus();
    });
    root?.addEventListener("paste", (event) => event.preventDefault());
    root?.addEventListener("drop", (event) => event.preventDefault());
    document.getElementById("terminal-verify")?.addEventListener("click", submit);
    keyHandler = recordKey;
    window.addEventListener("keydown", keyHandler, true);
    renderTerminal();
    root?.focus();
    helpersCache.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.exit_vim_terminal_escape = {rootSelector: ".terminal-escape", render};
})();
