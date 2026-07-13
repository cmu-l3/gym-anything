(() => {
  "use strict";

  const model = {
    state: null,
    tick: -1,
    cash: 0,
    position: 0,
    selected: "hold",
    orders: [],
    ledger: [],
    quotes: [],
    timer: 0,
    frame: 0,
    deadline: 0,
    running: false,
    submitting: false,
  };
  window.insiderTradingCaptchaModel = model;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function money(cents, signed = false) {
    const value = Number(cents || 0);
    const sign = value < 0 ? "−" : signed && value > 0 ? "+" : "";
    return `${sign}$${(Math.abs(value) / 100).toFixed(2)}`;
  }

  function clearClock() {
    if (model.timer) window.clearTimeout(model.timer);
    if (model.frame) window.cancelAnimationFrame(model.frame);
    model.timer = 0;
    model.frame = 0;
  }

  function orderGlyph(side) {
    if (side === "buy") return "B";
    if (side === "sell") return "S";
    return "—";
  }

  function visiblePrice() {
    return Number(model.state?.runtime_price_stream_cents?.[model.tick] || 0);
  }

  function projectedPosition(candidate = model.selected) {
    const delay = Number(model.state.order_delay_ticks || 2);
    let projected = model.position;
    model.orders.forEach((order) => {
      if (Number(order.tick) + delay > model.tick) {
        if (order.side === "buy") projected += 1;
        if (order.side === "sell") projected -= 1;
      }
    });
    if (candidate === "buy") projected += 1;
    if (candidate === "sell") projected -= 1;
    return projected;
  }

  function chartMarkup() {
    const values = model.quotes.map((quote) => Number(quote.price));
    if (!values.length) return "";
    const minimum = Math.min(...values) - 80;
    const maximum = Math.max(...values) + 80;
    const spread = Math.max(1, maximum - minimum);
    const width = 650;
    const height = 250;
    const points = values.map((value, index) => {
      const x = values.length === 1 ? 24 : 24 + index * (width - 48) / Math.max(1, Number(model.state.tick_count) - 1);
      const y = height - 24 - (value - minimum) * (height - 48) / spread;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    }).join(" ");
    const last = points.split(" ").at(-1).split(",");
    return `<polyline class="market-trace-shadow" points="${points}"></polyline>
      <polyline class="market-trace" points="${points}"></polyline>
      <circle class="market-last-dot" cx="${last[0]}" cy="${last[1]}" r="5"></circle>`;
  }

  function renderTape() {
    const tape = document.querySelector(".market-tape-list");
    if (tape) {
      tape.innerHTML = model.quotes.slice(-7).reverse().map((quote) => {
        const change = quote.index ? quote.price - model.quotes[quote.index - 1].price : 0;
        const movement = change > 0 ? "up" : change < 0 ? "down" : "flat";
        return `<li data-move="${movement}"><span>T${String(quote.index + 1).padStart(2, "0")}</span><b>${money(quote.price)}</b><i>${money(change, true)}</i></li>`;
      }).join("");
    }
    const ledger = document.querySelector(".market-ledger-list");
    if (ledger) {
      ledger.innerHTML = model.ledger.slice(-6).reverse().map((row) =>
        `<li data-side="${row.side}"><b>${row.side.toUpperCase()}</b><span>T${String(row.placed_tick + 1).padStart(2, "0")} → T${String(row.settle_tick + 1).padStart(2, "0")}</span><i>${money(row.price_cents)}</i></li>`
      ).join("") || '<li class="market-empty">NO SETTLEMENTS</li>';
    }
  }

  function renderOrders() {
    const strip = document.querySelector(".market-order-strip");
    if (!strip) return;
    const count = Number(model.state.tick_count || 0);
    strip.innerHTML = Array.from({length: count}, (_, index) => {
      const order = model.orders[index];
      const side = order?.side || (index === model.tick && model.running ? model.selected : "waiting");
      const status = index < model.orders.length ? "committed" : index === model.tick && model.running ? "live" : "future";
      return `<i data-side="${side}" data-status="${status}" title="Tick ${index + 1}: ${side}">${orderGlyph(side)}</i>`;
    }).join("");
  }

  function updateDashboard() {
    const price = visiblePrice();
    const equity = model.cash + model.position * price;
    const profit = equity - Number(model.state.initial_cash_cents || 0);
    const set = (selector, value) => {
      const node = document.querySelector(selector);
      if (node) node.textContent = value;
    };
    set(".market-current-price", money(price));
    set(".market-tick-number", String(model.tick + 1).padStart(2, "0"));
    set(".market-cash-value", money(model.cash));
    set(".market-position-value", `${model.position} LOT${model.position === 1 ? "" : "S"}`);
    set(".market-equity-value", money(equity));
    set(".market-profit-value", money(profit, true));
    const profitNode = document.querySelector(".market-profit-value");
    if (profitNode) profitNode.dataset.sign = profit > 0 ? "up" : profit < 0 ? "down" : "flat";
    const chart = document.querySelector(".market-chart-lines");
    if (chart) chart.innerHTML = chartMarkup();
    renderTape();
    renderOrders();
    updateControls();
  }

  function updateControls() {
    const locked = !model.running || model.tick >= Number(model.state.tick_count) - Number(model.state.order_delay_ticks);
    document.querySelectorAll(".market-order-button").forEach((button) => {
      const side = String(button.dataset.side);
      let disabled = locked || model.submitting;
      const projected = projectedPosition(side);
      if (side !== "hold" && (projected < 0 || projected > Number(model.state.max_position))) disabled = true;
      button.disabled = disabled;
      button.dataset.selected = side === model.selected ? "true" : "false";
    });
    const badge = document.querySelector(".market-queued-badge");
    if (badge) badge.textContent = locked ? "BOOK LOCKED" : `${model.selected.toUpperCase()} @ T${String(model.tick + 1).padStart(2, "0")}`;
  }

  function animateClock(helpers) {
    if (!model.running) return;
    const remaining = Math.max(0, model.deadline - performance.now());
    const meter = document.querySelector(".market-tick-meter i");
    if (meter) meter.style.transform = `scaleX(${remaining / Number(model.state.tick_ms)})`;
    const clock = document.querySelector(".market-clock");
    if (clock) clock.textContent = `${(remaining / 1000).toFixed(1)}s`;
    if (remaining > 0) model.frame = requestAnimationFrame(() => animateClock(helpers));
  }

  function settleAtTick(tick) {
    const delay = Number(model.state.order_delay_ticks || 2);
    const placedTick = tick - delay;
    if (placedTick < 0) return true;
    const order = model.orders[placedTick];
    if (!order || order.side === "hold") return true;
    const price = Number(model.state.runtime_price_stream_cents[tick]);
    const fee = Number(model.state.fee_cents);
    if (order.side === "buy") {
      if (model.position >= Number(model.state.max_position) || model.cash < price + fee) return false;
      model.cash -= price + fee;
      model.position += 1;
    } else if (order.side === "sell") {
      if (model.position <= 0) return false;
      model.cash += price - fee;
      model.position -= 1;
    }
    model.ledger.push({
      placed_tick: placedTick,
      settle_tick: tick,
      side: order.side,
      price_cents: price,
      fee_cents: fee,
      cash_after_cents: model.cash,
      position_after: model.position,
    });
    const flash = document.querySelector(".market-settlement-flash");
    if (flash) {
      flash.dataset.side = order.side;
      flash.innerHTML = `<span>${order.side.toUpperCase()} SETTLED</span><b>${money(price)}</b><i>FEE ${money(fee)}</i>`;
      flash.classList.remove("is-visible");
      void flash.offsetWidth;
      flash.classList.add("is-visible");
    }
    return true;
  }

  function arriveTick(tick, helpers) {
    model.tick = tick;
    if (!settleAtTick(tick)) {
      submitBook(helpers, true);
      return;
    }
    model.selected = "hold";
    model.quotes.push({index: tick, price: Number(model.state.runtime_price_stream_cents[tick])});
    model.deadline = performance.now() + Number(model.state.tick_ms);
    updateDashboard();
    helpers.setReadout(`LIVE · ORDER NOW SETTLES AT T${String(tick + Number(model.state.order_delay_ticks) + 1).padStart(2, "0")}`, "idle");
    if (tick >= Number(model.state.tick_count) - Number(model.state.order_delay_ticks)) {
      helpers.setReadout("SETTLEMENT WINDOW · NEW ORDERS LOCKED", "pending");
    }
    animateClock(helpers);
    model.timer = window.setTimeout(() => commitTick(helpers), Number(model.state.tick_ms));
  }

  function commitTick(helpers) {
    if (!model.running || model.submitting) return;
    if (model.frame) cancelAnimationFrame(model.frame);
    model.orders.push({tick: model.tick, side: model.selected});
    renderOrders();
    const next = model.tick + 1;
    if (next < Number(model.state.tick_count)) {
      arriveTick(next, helpers);
    } else {
      model.running = false;
      submitBook(helpers, false);
    }
  }

  async function submitBook(helpers, forced) {
    if (model.submitting || !model.state) return;
    clearClock();
    model.running = false;
    model.submitting = true;
    updateControls();
    helpers.setReadout(forced ? "FORCED CLOSE · AUDITING…" : "CLOSING TAPE · AUDITING…", "pending");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          mechanic_id: model.state.mechanic_id,
          task_id: model.state.task_id,
          challenge_id: model.state.challenge_id,
          orders: model.orders,
          settlement_ledger: model.ledger,
          final: {cash_cents: model.cash, position: model.position},
        }),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        const shell = document.querySelector(".insider-market-captcha");
        if (shell) shell.dataset.terminal = "pass";
        const profit = model.cash - Number(model.state.initial_cash_cents);
        document.querySelector(".market-terminal-stamp")?.replaceChildren();
        document.querySelector(".market-terminal-stamp")?.insertAdjacentHTML("beforeend", `<span>BOOK CLEARED</span><strong>PASS</strong><i>${money(profit, true)} · FLAT</i>`);
        helpers.setReadout("PASS · DELAYED BOOK VERIFIED", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await helpers.render(outcome.state);
        const shell = document.querySelector(".insider-market-captcha");
        if (shell) shell.dataset.freshFailure = "true";
        helpers.setReadout("FAIL · MARKET REOPENED ON A FRESH TAPE", "error");
      } else {
        model.submitting = false;
        helpers.setReadout("FAIL · NO MARKET GRADE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      helpers.setReadout("FAIL · CLEARING HOUSE OFFLINE", "error");
    }
  }

  function startMarket(helpers) {
    if (model.running || model.submitting) return;
    model.cash = Number(model.state.initial_cash_cents);
    model.position = 0;
    model.tick = -1;
    model.selected = "hold";
    model.orders = [];
    model.ledger = [];
    model.quotes = [];
    model.running = true;
    document.querySelector(".market-start-curtain")?.setAttribute("data-open", "true");
    document.querySelector(".insider-market-captcha")?.setAttribute("data-started", "true");
    arriveTick(0, helpers);
  }

  async function render(state, helpers) {
    clearClock();
    document.body.dataset.mechanic = "insider-trading-captcha";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model.state = state;
    model.tick = -1;
    model.cash = Number(state.initial_cash_cents);
    model.position = 0;
    model.selected = "hold";
    model.orders = [];
    model.ledger = [];
    model.quotes = [];
    model.running = false;
    model.submitting = false;
    helpers.app.innerHTML = `
      <section class="insider-market-captcha" data-challenge-id="${clean(state.challenge_id)}">
        <div class="market-grain"></div>
        <header class="market-head">
          <div class="market-brand"><span>AFTERHOURS CLEARING OFFICE</span><h1>${clean(state.prompt)}</h1></div>
          <div class="market-contract"><span>CONTRACT</span><b>${clean(state.symbol)} / DELAY-${state.order_delay_ticks}</b><i>${state.tick_count} TICKS · ${money(state.fee_cents)} FEE</i></div>
        </header>
        <main class="market-workbench">
          <section class="market-chart-card">
            <div class="market-price-ribbon">
              <span>${clean(state.symbol)} <i>LIVE</i></span>
              <strong class="market-current-price">—</strong>
              <small>TICK <b class="market-tick-number">00</b> / ${String(state.tick_count).padStart(2, "0")}</small>
            </div>
            <div class="market-chart-wrap">
              <svg viewBox="0 0 650 250" preserveAspectRatio="none" aria-label="Price chart">
                <defs><pattern id="market-grid" width="54" height="42" patternUnits="userSpaceOnUse"><path d="M 54 0 L 0 0 0 42" fill="none" stroke="currentColor" stroke-width="1"/></pattern></defs>
                <rect width="650" height="250" fill="url(#market-grid)" class="market-grid"></rect>
                <g class="market-chart-lines"></g>
              </svg>
              <div class="market-settlement-flash"></div>
              <div class="market-terminal-stamp"></div>
            </div>
            <div class="market-order-strip"></div>
          </section>
          <aside class="market-side-column">
            <section class="market-balance-card">
              <header><span>ACCOUNT / ${clean(state.symbol)}</span><i>LIVE EQUITY</i></header>
              <dl>
                <div><dt>CASH</dt><dd class="market-cash-value">${money(state.initial_cash_cents)}</dd></div>
                <div><dt>POSITION</dt><dd class="market-position-value">0 LOTS</dd></div>
                <div><dt>EQUITY</dt><dd class="market-equity-value">${money(state.initial_cash_cents)}</dd></div>
                <div class="market-profit-row"><dt>PROFIT / TARGET ${money(state.target_profit_cents, true)}</dt><dd class="market-profit-value">$0.00</dd></div>
              </dl>
            </section>
            <section class="market-tape-card"><header>QUOTE TAPE <i>PAST ONLY</i></header><ol class="market-tape-list"><li class="market-empty">AWAITING OPEN</li></ol></section>
            <section class="market-ledger-card"><header>SETTLEMENT LEDGER <i>T+${state.order_delay_ticks}</i></header><ol class="market-ledger-list"><li class="market-empty">NO SETTLEMENTS</li></ol></section>
          </aside>
        </main>
        <section class="market-dealing-desk">
          <div class="market-rule-plate"><b>THE CATCH</b><span>Every order executes exactly <strong>${state.order_delay_ticks} market ticks later</strong> at that future quote.</span></div>
          <div class="market-order-controls">
            <button type="button" class="market-order-button" data-side="buy"><span>▲</span><b>BUY 1</b><i>B</i></button>
            <button type="button" class="market-order-button" data-side="hold"><span>•</span><b>HOLD</b><i>H</i></button>
            <button type="button" class="market-order-button" data-side="sell"><span>▼</span><b>SELL 1</b><i>S</i></button>
          </div>
          <div class="market-queue-status"><span class="market-queued-badge">BOOK CLOSED</span><div class="market-tick-meter"><i></i></div><b class="market-clock">—</b></div>
          <button type="button" class="market-force-close">FORCE CLOSE</button>
        </section>
        <footer class="market-foot"><div class="readout" data-status="idle">PRESS START · FINISH FLAT ABOVE ${money(state.target_profit_cents, true)}</div><span>NO SHORTS · MAX ${state.max_position} LOTS · ONE ORDER / TICK</span></footer>
        <div class="market-start-curtain">
          <div><span>DELAYED MARKET CLEARANCE</span><strong>${clean(state.symbol)}</strong><p>Watch the tape. Queue buys and sells. Each order lands ${state.order_delay_ticks} ticks after you place it.</p><ul><li>Reach ${money(state.target_profit_cents, true)} profit after fees</li><li>Finish with zero open lots</li><li>The last ${state.order_delay_ticks} ticks settle only</li></ul><button type="button" class="market-start">OPEN THE TAPE</button></div>
        </div>
        ${helpers.cheatPanelTemplate()}
      </section>`;

    document.querySelector(".market-start").addEventListener("click", () => startMarket(helpers));
    document.querySelector(".market-force-close").addEventListener("click", () => submitBook(helpers, true));
    document.querySelectorAll(".market-order-button").forEach((button) => {
      button.addEventListener("click", () => {
        if (button.disabled || !model.running) return;
        model.selected = String(button.dataset.side);
        updateControls();
        renderOrders();
      });
    });
    const keyHandler = (event) => {
      if (event.repeat || !model.running) return;
      const map = {b: "buy", h: "hold", s: "sell"};
      const side = map[String(event.key).toLowerCase()];
      if (!side) return;
      const button = document.querySelector(`.market-order-button[data-side="${side}"]`);
      if (button && !button.disabled) {
        event.preventDefault();
        button.click();
      }
    };
    document.querySelector(".insider-market-captcha").addEventListener("keydown", keyHandler);
    document.querySelector(".insider-market-captcha").setAttribute("tabindex", "0");
    updateDashboard();
    helpers.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.insider_trading_captcha = {rootSelector: ".insider-market-captcha", render};
})();
