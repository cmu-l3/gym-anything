(() => {
  "use strict";

  const HEIGHT = 5;
  const WIDTH = 5;
  const FORBIDDEN = "black_licorice";
  const model = {
    state: null,
    board: [],
    refillIndex: 0,
    score: 0,
    validMoves: 0,
    invalidSwaps: 0,
    swaps: [],
    receipt: [],
    selected: null,
    busy: false,
    terminal: false,
    ready: false,
    forbiddenActivated: false,
    helpers: null,
  };

  const sleep = (milliseconds) => new Promise((resolve) => window.setTimeout(resolve, milliseconds));
  const cloneBoard = (board) => (board || []).map((row) => [...row]);
  const coordKey = (coord) => `${coord[0]},${coord[1]}`;
  const sameCoord = (a, b) => a && b && a[0] === b[0] && a[1] === b[1];
  const adjacent = (a, b) => Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) === 1;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function findMatches(board) {
    const matched = new Set();
    for (let row = 0; row < HEIGHT; row += 1) {
      let start = 0;
      while (start < WIDTH) {
        const candy = board[row][start];
        let end = start + 1;
        while (end < WIDTH && board[row][end] === candy) end += 1;
        if (candy !== FORBIDDEN && end - start >= 3) {
          for (let column = start; column < end; column += 1) matched.add(`${row},${column}`);
        }
        start = end;
      }
    }
    for (let column = 0; column < WIDTH; column += 1) {
      let start = 0;
      while (start < HEIGHT) {
        const candy = board[start][column];
        let end = start + 1;
        while (end < HEIGHT && board[end][column] === candy) end += 1;
        if (candy !== FORBIDDEN && end - start >= 3) {
          for (let row = start; row < end; row += 1) matched.add(`${row},${column}`);
        }
        start = end;
      }
    }
    return matched;
  }

  function collapse(board, matched) {
    const next = cloneBoard(board);
    for (let column = 0; column < WIDTH; column += 1) {
      const survivors = [];
      for (let row = 0; row < HEIGHT; row += 1) {
        if (!matched.has(`${row},${column}`)) survivors.push(board[row][column]);
      }
      const holes = HEIGHT - survivors.length;
      const additions = model.state.refill_stream.slice(model.refillIndex, model.refillIndex + holes);
      if (additions.length !== holes) throw new Error("refill stream exhausted");
      model.refillIndex += holes;
      [...additions, ...survivors].forEach((candy, row) => { next[row][column] = candy; });
    }
    return next;
  }

  function candyMarkup(candy) {
    const symbols = {
      cherry: "●",
      lemon: "◆",
      mint: "✦",
      plum: "⬟",
      orange: "◎",
      black_licorice: "✕",
    };
    const names = {
      cherry: "CHERRY",
      lemon: "LEMON",
      mint: "MINT",
      plum: "PLUM",
      orange: "ORANGE",
      black_licorice: "DO NOT MOVE",
    };
    return `<span class="candy-piece candy-${clean(candy)}"><i>${symbols[candy] || "●"}</i><small>${names[candy] || candy}</small></span>`;
  }

  function boardMarkup() {
    return model.board.map((row, rowIndex) => row.map((candy, columnIndex) => {
      const selected = sameCoord(model.selected, [rowIndex, columnIndex]);
      return `<button type="button" draggable="true" class="candy-cell${selected ? " is-selected" : ""}" data-row="${rowIndex}" data-column="${columnIndex}" aria-label="${clean(candy)} row ${rowIndex + 1} column ${columnIndex + 1}">${candyMarkup(candy)}</button>`;
    }).join("")).join("");
  }

  function receiptMarkup() {
    if (!model.receipt.length) return '<li class="is-empty"><b>—</b><span>NO CASCADES YET</span><em>0</em></li>';
    return model.receipt.slice(-7).map((item) => `<li><b>W${item.wave}</b><span>${item.removed} CANDIES × ${item.wave}</span><em>+${item.points}</em></li>`).join("");
  }

  function refillMarkup() {
    return model.state.refill_stream.slice(model.refillIndex, model.refillIndex + 5)
      .map((candy) => `<i class="next-${clean(candy)}"></i>`).join("");
  }

  function updatePanels() {
    const score = document.getElementById("candy-score-current");
    const remaining = document.getElementById("candy-moves-left");
    const receipt = document.getElementById("candy-receipt");
    const refill = document.getElementById("candy-refill");
    const needle = document.querySelector(".candy-score-fill");
    const exact = document.getElementById("candy-exact-state");
    const stamp = document.getElementById("candy-certify");
    if (score) score.textContent = String(model.score).padStart(3, "0");
    if (remaining) remaining.textContent = String(Math.max(0, Number(model.state.move_budget) - model.validMoves));
    if (receipt) receipt.innerHTML = receiptMarkup();
    if (refill) refill.innerHTML = refillMarkup();
    if (needle) needle.style.height = `${Math.min(100, (model.score / Number(model.state.target_score)) * 100)}%`;
    if (exact) {
      exact.dataset.state = model.ready ? "exact" : model.score > Number(model.state.target_score) ? "over" : "under";
      exact.textContent = model.ready ? "EXACT CHANGE" : model.score > Number(model.state.target_score) ? "OVERPAID" : `${Number(model.state.target_score) - model.score} STILL OWED`;
    }
    if (stamp) stamp.classList.toggle("is-ready", model.ready);
  }

  function cellCoord(button) {
    return [Number(button.dataset.row), Number(button.dataset.column)];
  }

  function bindCells() {
    document.querySelectorAll(".candy-cell").forEach((button) => {
      button.addEventListener("click", () => selectCell(cellCoord(button)));
      button.addEventListener("dragstart", (event) => {
        if (model.busy || model.terminal) {
          event.preventDefault();
          return;
        }
        event.dataTransfer.setData("text/plain", coordKey(cellCoord(button)));
        event.dataTransfer.effectAllowed = "move";
        button.classList.add("is-dragging");
      });
      button.addEventListener("dragend", () => button.classList.remove("is-dragging"));
      button.addEventListener("dragover", (event) => event.preventDefault());
      button.addEventListener("drop", (event) => {
        event.preventDefault();
        const raw = event.dataTransfer.getData("text/plain").split(",").map(Number);
        const destination = cellCoord(button);
        if (raw.length === 2 && adjacent(raw, destination)) attemptSwap(raw, destination);
        else flashMessage("ADJACENT TILES ONLY", "error");
      });
    });
  }

  function renderBoard() {
    const board = document.getElementById("candy-board");
    if (!board) return;
    board.innerHTML = boardMarkup();
    bindCells();
  }

  function flashMessage(message, status = "idle") {
    model.helpers.setReadout(message, status);
    const shell = document.querySelector(".candy-cascade-captcha");
    shell?.classList.remove("is-jolt");
    void shell?.offsetWidth;
    shell?.classList.add("is-jolt");
  }

  function clearFreshFailure() {
    document.querySelector(".candy-verdict-fail")?.remove();
    document.querySelector(".candy-cascade-captcha")?.classList.remove("is-fresh-fail");
  }

  async function submit(completed) {
    if (!model.state || model.busy && !model.terminal) return;
    model.busy = true;
    document.querySelectorAll("button").forEach((button) => { button.disabled = true; });
    model.helpers.setReadout("AUDITING RECEIPT…", "pending");
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      swaps: model.swaps,
      final_board: cloneBoard(model.board),
      refill_index: model.refillIndex,
      score: model.score,
      valid_moves: model.validMoves,
      invalid_swaps: model.invalidSwaps,
      forbidden_activated: model.forbiddenActivated,
      completed,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        const shell = document.querySelector(".candy-cascade-captcha");
        shell?.classList.add("is-pass");
        shell?.insertAdjacentHTML("beforeend", '<div class="candy-verdict candy-verdict-pass"><small>RECEIPT BALANCED</small><strong>PASS</strong></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".candy-cascade-captcha");
        shell?.classList.add("is-fresh-fail");
        shell?.insertAdjacentHTML("beforeend", '<div class="candy-verdict candy-verdict-fail"><small>REGISTER VOID · FRESH BOARD</small><strong>FAIL</strong></div>');
        model.helpers.setReadout("FAIL · REGISTER RESET", "error");
        window.setTimeout(() => document.querySelector(".candy-verdict-fail")?.remove(), 1650);
      } else {
        model.busy = false;
        model.terminal = false;
        model.helpers.setReadout("FAIL · RECEIPT UNGRADED", "error");
        document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
      }
    } catch (_error) {
      model.busy = false;
      model.terminal = false;
      model.helpers.setReadout("FAIL · REGISTER OFFLINE", "error");
      document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
    }
  }

  async function forbiddenFailure(first, second) {
    model.forbiddenActivated = true;
    model.terminal = true;
    model.swaps.push({
      sequence: model.swaps.length + 1,
      from: [...first],
      to: [...second],
      outcome: "forbidden",
      score_after: model.score,
      wave_count: 0,
    });
    const shell = document.querySelector(".candy-cascade-captcha");
    shell?.classList.add("is-licorice-fail");
    shell?.insertAdjacentHTML("beforeend", '<div class="candy-verdict candy-verdict-fail"><small>BLACK LICORICE DISTURBED</small><strong>VOID</strong></div>');
    flashMessage("LICORICE ALARM · RECEIPT VOID", "error");
    await sleep(650);
    await submit(false);
  }

  async function attemptSwap(first, second) {
    if (model.busy || model.terminal || !adjacent(first, second)) return;
    clearFreshFailure();
    model.busy = true;
    model.selected = null;
    const firstCandy = model.board[first[0]][first[1]];
    const secondCandy = model.board[second[0]][second[1]];
    if (firstCandy === FORBIDDEN || secondCandy === FORBIDDEN) {
      model.busy = false;
      await forbiddenFailure(first, second);
      return;
    }

    const before = cloneBoard(model.board);
    model.board[first[0]][first[1]] = secondCandy;
    model.board[second[0]][second[1]] = firstCandy;
    renderBoard();
    const matches = findMatches(model.board);
    if (!matches.size) {
      model.invalidSwaps += 1;
      model.swaps.push({
        sequence: model.swaps.length + 1,
        from: [...first],
        to: [...second],
        outcome: "invalid",
        score_after: model.score,
        wave_count: 0,
      });
      document.getElementById("candy-board")?.classList.add("is-invalid");
      flashMessage("NO MATCH · SWAP RETURNED", "error");
      await sleep(230);
      model.board = before;
      renderBoard();
      document.getElementById("candy-board")?.classList.remove("is-invalid");
      model.busy = false;
      updatePanels();
      return;
    }

    model.validMoves += 1;
    let wave = 0;
    let moveScore = 0;
    while (true) {
      const currentMatches = findMatches(model.board);
      if (!currentMatches.size) break;
      wave += 1;
      const points = currentMatches.size * 10 * wave;
      moveScore += points;
      model.score += points;
      model.receipt.push({move: model.validMoves, wave, removed: currentMatches.size, points});
      currentMatches.forEach((key) => document.querySelector(`.candy-cell[data-row="${key.split(",")[0]}"][data-column="${key.split(",")[1]}"]`)?.classList.add("is-matched"));
      updatePanels();
      flashMessage(`CASCADE ${wave}× · +${points}`, "idle");
      await sleep(210);
      model.board = collapse(model.board, currentMatches);
      renderBoard();
      updatePanels();
      await sleep(205);
      if (wave > 20) throw new Error("cascade exceeded safety limit");
    }
    model.swaps.push({
      sequence: model.swaps.length + 1,
      from: [...first],
      to: [...second],
      outcome: "valid",
      score_after: model.score,
      wave_count: wave,
    });
    model.ready = model.validMoves === Number(model.state.move_budget) && model.score === Number(model.state.target_score);
    model.busy = false;
    updatePanels();
    if (model.ready) {
      flashMessage(`EXACT · ${model.score} / ${model.state.target_score} · STAMP IT`, "passed");
      document.querySelector(".candy-cascade-captcha")?.classList.add("is-exact");
      return;
    }
    if (model.score > Number(model.state.target_score) || model.validMoves >= Number(model.state.move_budget)) {
      model.terminal = true;
      const reason = model.score > Number(model.state.target_score) ? "OVERPAID" : "SHORT CHANGE";
      document.querySelector(".candy-cascade-captcha")?.insertAdjacentHTML("beforeend", `<div class="candy-verdict candy-verdict-fail"><small>${reason}</small><strong>VOID</strong></div>`);
      flashMessage(`${reason} · RECEIPT VOID`, "error");
      await sleep(700);
      await submit(false);
    } else {
      flashMessage(`MOVE ${model.validMoves} PAID +${moveScore} · ONE SWAP LEFT`, "idle");
    }
  }

  function selectCell(coord) {
    if (model.busy || model.terminal) return;
    clearFreshFailure();
    if (!model.selected) {
      model.selected = coord;
      renderBoard();
      flashMessage("FIRST CANDY HELD · CHOOSE A NEIGHBOR", "idle");
      return;
    }
    if (sameCoord(model.selected, coord)) {
      model.selected = null;
      renderBoard();
      return;
    }
    if (!adjacent(model.selected, coord)) {
      model.selected = coord;
      renderBoard();
      flashMessage("ADJACENT TILES ONLY", "error");
      return;
    }
    const first = model.selected;
    model.selected = null;
    attemptSwap(first, coord);
  }

  function resetBoard() {
    if (model.busy) return;
    model.board = cloneBoard(model.state.board);
    model.refillIndex = 0;
    model.score = 0;
    model.validMoves = 0;
    model.invalidSwaps = 0;
    model.swaps = [];
    model.receipt = [];
    model.selected = null;
    model.ready = false;
    model.terminal = false;
    model.forbiddenActivated = false;
    document.querySelector(".candy-cascade-captcha")?.classList.remove("is-exact", "is-licorice-fail");
    document.querySelectorAll(".candy-verdict").forEach((node) => node.remove());
    renderBoard();
    updatePanels();
    model.helpers.setReadout("REGISTER RESET · RECEIPT EMPTY", "idle");
  }

  async function render(state, helpers) {
    document.body.dataset.mechanic = "exact-change-candy-cascade";
    document.body.dataset.candyPalette = String(state.palette || "soda-pop");
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    Object.assign(model, {
      state,
      board: cloneBoard(state.board),
      refillIndex: 0,
      score: 0,
      validMoves: 0,
      invalidSwaps: 0,
      swaps: [],
      receipt: [],
      selected: null,
      busy: false,
      terminal: false,
      ready: false,
      forbiddenActivated: false,
      helpers,
    });
    helpers.app.innerHTML = `
      <section class="candy-cascade-captcha" data-challenge-id="${clean(state.challenge_id)}">
        <header class="candy-head">
          <div class="candy-brand"><span>NO. 36 / CONFECTIONERY CASHIER TEST</span><h1>${clean(state.prompt)}</h1></div>
          <div class="candy-target-ticket"><small>EXACT TOTAL</small><strong>${Number(state.target_score)}</strong><i>POINTS</i></div>
        </header>
        <main class="candy-workbench">
          <aside class="candy-score-column">
            <div class="candy-register-label">REGISTER</div>
            <div class="candy-score-window"><small>CURRENT</small><strong id="candy-score-current">000</strong></div>
            <div class="candy-score-gauge"><div class="candy-score-fill"></div><span>${Number(state.target_score)}</span></div>
            <div class="candy-moves"><small>VALID SWAPS LEFT</small><b id="candy-moves-left">${Number(state.move_budget)}</b></div>
            <div class="candy-exact-state" id="candy-exact-state" data-state="under">${Number(state.target_score)} STILL OWED</div>
          </aside>
          <section class="candy-board-case">
            <div class="candy-board-top"><span>SWAP NEIGHBORS · CASCADES PAY MORE</span><b>5 × 5</b></div>
            <div class="candy-board" id="candy-board">${boardMarkup()}</div>
            <div class="candy-danger-strip"><i>${candyMarkup(FORBIDDEN)}</i><p><b>BLACK LICORICE</b><span>TOUCHING IT VOIDS THE RUN</span></p></div>
          </section>
          <aside class="candy-receipt-column">
            <header><span>CASCADE RECEIPT</span><b>× WAVE</b></header>
            <ol id="candy-receipt">${receiptMarkup()}</ol>
            <div class="candy-next"><span>NEXT DROP</span><div id="candy-refill">${refillMarkup()}</div></div>
            <p>10 points per candy.<br>Wave 2 doubles. Wave 3 triples.</p>
          </aside>
        </main>
        <footer class="candy-foot">
          <button type="button" class="candy-reset" id="candy-reset">↺ RESET BOARD</button>
          <div class="readout" data-status="idle">REGISTER OPEN · TWO EXACT SWAPS</div>
          <button type="button" class="candy-certify" id="candy-certify">${clean(state.submit_label || "STAMP EXACT")}</button>
        </footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    bindCells();
    updatePanels();
    document.getElementById("candy-reset")?.addEventListener("click", resetBoard);
    document.getElementById("candy-certify")?.addEventListener("click", () => submit(model.ready));
    helpers.installCheatPanel();
    window.exactChangeCandyModel = model;
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.exact_change_candy_cascade = {
    rootSelector: ".candy-cascade-captcha",
    render,
  };
})();
