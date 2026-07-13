const app = document.getElementById("app");
const gridModel = {
  selected: new Set(),
  order: [],
};
const lensModel = {
  state: null,
  pointer: null,
  cheatTarget: null,
};
const boardModel = {
  selectedCellId: null,
};
const dragModel = {
  placements: {},
};
const reloadModel = {
  step: 0,
  cleared: [],
  active: null,
  sequenceInput: [],
};
const rotateModel = {
  angle: 0,
};
const formModel = {
  tool: "sign",
  marks: [],
};
const temporalModel = {
  state: null,
  startedAt: 0,
  selectedObjectId: null,
  animationFrame: 0,
};
const ghostModel = {
  state: null,
  placements: {},
  frame: 0,
  animationFrame: 0,
};
const constellationModel = {
  state: null,
  pointer: null,
  pendingClick: null,
  animationFrame: 0,
};
const grillModel = {
  state: null,
  records: {},
  animationFrame: 0,
};
const rotatingKeyboardModel = {
  input: "",
};
const slotModel = {
  state: null,
  startedAt: 0,
  frozen: [],
  captured: "",
  wrongKeys: 0,
  submitting: false,
  animationFrame: 0,
  keyHandler: null,
};
const dominoModel = {
  state: null,
  engine: null,
  render: null,
  runner: null,
  bellBody: null,
  clapperBody: null,
  bellAnchor: null,
  bellInitial: null,
  bellPeakAngle: 0,
  bellAudioContext: null,
  bellSoundPlayed: false,
  bodiesById: {},
  dominoIds: [],
  looseIds: [],
  selectedId: null,
  initial: {},
  preRun: {},
  collisionPairs: new Set(),
  physicsPassed: false,
  bellHit: false,
  mode: "edit",
  runTimer: null,
};
const consequenceModel = {state: null, phase: "choices", sceneIndex: 0, bossIndex: 0, choices: {}, actions: {}};
const popupModel = {state: null, cleared: [], topZ: 20, submitting: false};
const funeralModel = {state: null, events: [], brushed: new Set(), gathered: new Set(), brushing: false, completed: false, pointerUpHandler: null};
const slimeModel = {state: null, startedAt: 0, player: {x: 0, y: 10}, deaths: 0, visited: new Set(), keyHandler: null, animationFrame: 0, completed: false, lastTick: -1};

function text(value) {
  return String(value == null ? "" : value);
}

function setReadout(message, status = "idle") {
  const node = document.querySelector(".readout");
  if (!node) return;
  node.dataset.status = status;
  node.textContent = message;
}

function isCheatMode() {
  return new URLSearchParams(window.location.search).get("cheat") === "1";
}

function renderWaiting(message) {
  document.body.dataset.mechanic = "waiting";
  app.innerHTML = `
    <section class="runtime-panel">
      <p>${text(message)}</p>
    </section>
  `;
}

function renderUnavailable() {
  document.body.dataset.mechanic = "waiting";
  app.innerHTML = `
    <section class="runtime-panel">
      <p>Not available.</p>
    </section>
  `;
}

async function renderExternalMechanic(state) {
  const mechanicId = text(state?.mechanic_id);
  if (!/^[a-z0-9_]+$/.test(mechanicId)) return false;
  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  if (!window.WeirdCaptchaMechanics[mechanicId]) {
    try {
      await new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = `/mechanics/${encodeURIComponent(mechanicId)}.js`;
        script.dataset.mechanicScript = mechanicId;
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    } catch (_error) {
      return false;
    }
  }
  const mechanic = window.WeirdCaptchaMechanics[mechanicId];
  if (!mechanic || typeof mechanic.render !== "function") return false;
  let style = document.querySelector(`link[data-mechanic-style="${mechanicId}"]`);
  if (!style) {
    style = document.createElement("link");
    style.rel = "stylesheet";
    style.href = `/mechanics/${encodeURIComponent(mechanicId)}.css`;
    style.dataset.mechanicStyle = mechanicId;
    await new Promise((resolve, reject) => {
      style.onload = resolve;
      style.onerror = reject;
      document.head.appendChild(style);
    });
  } else if (!style.sheet) {
    await new Promise((resolve, reject) => {
      style.addEventListener("load", resolve, {once: true});
      style.addEventListener("error", reject, {once: true});
    });
  }
  await mechanic.render(state, {
    app,
    text,
    setReadout,
    isCheatMode,
    cheatPanelTemplate,
    installCheatPanel,
    render: renderExternalMechanic,
  });
  return true;
}

function colorPalette(index) {
  const palettes = [
    ["#c7d0c8", "#7f948a", "#2f6544"],
    ["#d8c8ad", "#8b795f", "#2d633f"],
    ["#c5cdd8", "#748699", "#225d43"],
    ["#d2c4d2", "#80728f", "#285b3a"],
    ["#d7d3bd", "#828c68", "#306542"],
    ["#bdcfc4", "#6f8a80", "#24593a"],
    ["#decbb9", "#98795e", "#2f6137"],
    ["#ccd7d9", "#7d9098", "#265943"],
    ["#d1cab9", "#7d876f", "#315b3d"],
  ];
  return palettes[Math.abs(Number(index || 0)) % palettes.length];
}

function drawBackground(ctx, tile, width, height) {
  const palette = colorPalette(tile.frame?.palette);
  const grad = ctx.createLinearGradient(0, 0, width, height);
  grad.addColorStop(0, palette[0]);
  grad.addColorStop(1, palette[1]);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);

  ctx.fillStyle = "rgba(34, 58, 41, 0.13)";
  ctx.beginPath();
  ctx.ellipse(width * 0.52, height * 0.83, width * 0.66, height * 0.2, 0.02, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "rgba(255,255,255,0.18)";
  ctx.fillRect(0, height * 0.04, width, height * 0.32);

  ctx.save();
  ctx.rotate(-0.08);
  ctx.strokeStyle = "rgba(20, 20, 20, 0.22)";
  ctx.lineWidth = 1;
  for (let x = -height; x < width + height; x += 25) {
    ctx.beginPath();
    ctx.moveTo(x, -10);
    ctx.lineTo(x - 20, height + 16);
    ctx.stroke();
  }
  ctx.restore();

  const grain = Math.round(45 + Number(tile.frame?.grain || 0.2) * 160);
  ctx.fillStyle = "rgba(255,255,255,0.18)";
  for (let i = 0; i < grain; i += 1) {
    const n = (Math.sin((i + 1) * 91.7 + width) + 1) / 2;
    const m = (Math.sin((i + 1) * 37.3 + height) + 1) / 2;
    ctx.fillRect(n * width, m * height, 1.2 + (i % 3), 1.2 + (i % 2));
  }
}

function qcurve(ctx, x1, y1, cx, cy, x2, y2) {
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.quadraticCurveTo(cx, cy, x2, y2);
  ctx.stroke();
}

function drawTree(ctx, tree) {
  if (!tree) return;
  const trunk = tree.trunk || {};
  const crown = tree.crown || {};
  ctx.save();

  const lobes = Number(crown.lobes || 4);
  const crownColors = ["#1e5b32", "#2d7040", "#3f8051", "#245f37"];
  for (let i = 0; i < lobes; i += 1) {
    const t = lobes === 1 ? 0.5 : i / (lobes - 1);
    const x = Number(crown.x || 110) + (t - 0.5) * Number(crown.rx || 56);
    const y = Number(crown.y || 48) + Math.sin(t * Math.PI) * -8;
    ctx.fillStyle = "rgba(17, 52, 29, 0.42)";
    ctx.beginPath();
    ctx.ellipse(x + 2, y + 4, Number(crown.rx || 56) / (lobes + 0.2), Number(crown.ry || 20) * 1.1, -0.18 + t * 0.34, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = crownColors[i % crownColors.length];
    ctx.beginPath();
    ctx.ellipse(x, y, Number(crown.rx || 56) / (lobes + 0.35), Number(crown.ry || 20), -0.18 + t * 0.34, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.strokeStyle = "rgba(44, 24, 9, 0.55)";
  ctx.lineWidth = Number(trunk.width || 15) + 6;
  qcurve(
    ctx,
    Number(trunk.base_x || 110),
    Number(trunk.base_y || 138),
    Number(trunk.base_x || 110) + Number(trunk.bend || 0),
    96,
    Number(trunk.top_x || 110),
    Number(trunk.top_y || 58),
  );
  ctx.strokeStyle = "#72451f";
  ctx.lineWidth = Number(trunk.width || 15);
  qcurve(
    ctx,
    Number(trunk.base_x || 110),
    Number(trunk.base_y || 138),
    Number(trunk.base_x || 110) + Number(trunk.bend || 0),
    96,
    Number(trunk.top_x || 110),
    Number(trunk.top_y || 58),
  );

  (tree.branches || []).forEach((branch) => {
    ctx.strokeStyle = "rgba(45, 24, 9, 0.58)";
    ctx.lineWidth = Number(branch.width || 7) + 4;
    qcurve(
      ctx,
      Number(branch.x1),
      Number(branch.y1),
      Number(branch.cx),
      Number(branch.cy),
      Number(branch.x2),
      Number(branch.y2),
    );
    ctx.strokeStyle = "#673813";
    ctx.lineWidth = Number(branch.width || 7);
    qcurve(
      ctx,
      Number(branch.x1),
      Number(branch.y1),
      Number(branch.cx),
      Number(branch.cy),
      Number(branch.x2),
      Number(branch.y2),
    );
  });

  ctx.fillStyle = "rgba(156, 201, 138, 0.28)";
  for (let i = 0; i < lobes; i += 1) {
    const t = lobes === 1 ? 0.5 : i / (lobes - 1);
    const x = Number(crown.x || 110) + (t - 0.5) * Number(crown.rx || 48) + 8;
    const y = Number(crown.y || 48) + Math.sin(t * Math.PI) * -7 - 4;
    ctx.beginPath();
    ctx.ellipse(x, y, 11, 5, -0.2, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function appleColor(hue) {
  return ["#d71920", "#c91f2b", "#e02b24", "#b81224"][Math.abs(Number(hue || 0)) % 4];
}

function drawApple(ctx, apple) {
  if (!apple) return;
  const r = Number(apple.r || 11);
  ctx.save();
  ctx.globalAlpha = Number(apple.opacity || 1);
  ctx.translate(Number(apple.x || 110), Number(apple.y || 80));
  ctx.rotate(Number(apple.tilt || 0));
  ctx.fillStyle = appleColor(apple.hue);
  ctx.beginPath();
  ctx.ellipse(-r * 0.24, 0, r * 0.64, r * 0.82, -0.18, 0, Math.PI * 2);
  ctx.ellipse(r * 0.24, 0, r * 0.64, r * 0.82, 0.18, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "#6a3b16";
  ctx.fillRect(-1.4, -r * 1.18, 3.8, r * 0.58);
  ctx.fillStyle = "#2c8b36";
  ctx.beginPath();
  ctx.ellipse(r * 0.34, -r * 1.02, r * 0.32, r * 0.15, -0.35, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = "rgba(255,255,255,0.62)";
  ctx.beginPath();
  ctx.ellipse(-r * 0.33, -r * 0.28, r * 0.15, r * 0.22, -0.7, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawSign(ctx, p) {
  const w = Number(p.w || 60);
  const h = Number(p.h || 38);
  const x = Number(p.x || 110);
  const y = Number(p.y || 80);
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate((Number(p.j || 0.4) - 0.5) * 0.25);
  ctx.fillStyle = "#f4ead3";
  ctx.strokeStyle = "#25211b";
  ctx.lineWidth = 4;
  ctx.fillRect(-w / 2, -h / 2, w, h);
  ctx.strokeRect(-w / 2, -h / 2, w, h);
  ctx.restore();
}

function propRenderLayer(kind) {
  if (["foreground_hand", "foreground_leaf", "leaf_overlay", "scratch", "fog_band"].includes(kind)) return "foreground";
  if (kind === "stem_line") return "mid";
  if (
    kind === "sign" ||
    kind.includes("stump") ||
    kind.includes("crate") ||
    kind.includes("basket") ||
    kind.includes("bench") ||
    kind.includes("table") ||
    kind.includes("bucket") ||
    kind.includes("stone") ||
    kind.includes("window") ||
    kind.includes("poster") ||
    kind.includes("label") ||
    kind.includes("mirror") ||
    kind.includes("hole") ||
    kind.includes("mushroom") ||
    kind.includes("lantern") ||
    kind.includes("sack") ||
    kind.includes("wheel") ||
    kind === "plate"
  ) {
    return "mid";
  }
  return "base";
}

function drawProp(ctx, p, layer = "base") {
  const kind = p.kind || "";
  const x = Number(p.x || 110);
  const y = Number(p.y || 80);
  if (propRenderLayer(kind) !== layer) return;

  ctx.save();
  if (kind === "pond") {
    ctx.fillStyle = "rgba(83, 135, 157, 0.62)";
    ctx.beginPath();
    ctx.ellipse(x, y + 8, 50, 18, -0.05, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.35)";
    ctx.lineWidth = 2;
    qcurve(ctx, x - 32, y + 7, x, y + 1, x + 35, y + 8);
  } else if (kind === "sign") {
    drawSign(ctx, p);
  } else if (kind.includes("stump")) {
    ctx.fillStyle = "#7f4c22";
    ctx.fillRect(x - 25, y - 2, 50, 25);
    ctx.fillStyle = "#b78345";
    ctx.beginPath();
    ctx.ellipse(x, y - 2, 28, 10, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "rgba(72, 38, 14, 0.45)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.ellipse(x, y - 2, 16, 5, 0, 0, Math.PI * 2);
    ctx.stroke();
  } else if (kind.includes("crate") || kind.includes("basket")) {
    ctx.fillStyle = "#a86b2f";
    ctx.fillRect(x - 32, y - 12, 64, 31);
    ctx.strokeStyle = "rgba(54, 31, 13, 0.6)";
    ctx.lineWidth = 4;
    ctx.strokeRect(x - 32, y - 12, 64, 31);
    qcurve(ctx, x - 30, y + 2, x, y - 9, x + 30, y + 2);
  } else if (kind.includes("bucket")) {
    ctx.fillStyle = "#8c897f";
    ctx.beginPath();
    ctx.ellipse(x, y - 12, 27, 9, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillRect(x - 25, y - 12, 50, 32);
    ctx.fillStyle = "rgba(255,255,255,0.22)";
    ctx.fillRect(x - 15, y - 9, 9, 27);
    ctx.strokeStyle = "#3d3a34";
    ctx.lineWidth = 3;
    qcurve(ctx, x - 20, y - 14, x, y - 31, x + 20, y - 14);
  } else if (kind.includes("bench") || kind.includes("table")) {
    ctx.fillStyle = "#8c5a2b";
    ctx.fillRect(x - 43, y - 7, 86, 13);
    ctx.fillRect(x - 35, y + 11, 10, 23);
    ctx.fillRect(x + 25, y + 11, 10, 23);
    ctx.strokeStyle = "rgba(48, 30, 16, 0.7)";
    ctx.lineWidth = 3;
    qcurve(ctx, x - 46, y - 11, x, y - 17, x + 46, y - 11);
  } else if (kind.includes("stone")) {
    ctx.fillStyle = "#737970";
    ctx.beginPath();
    ctx.ellipse(x, y, 40, 19, -0.08, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.16)";
    ctx.beginPath();
    ctx.ellipse(x - 12, y - 7, 15, 5, -0.2, 0, Math.PI * 2);
    ctx.fill();
  } else if (kind === "bird") {
    ctx.strokeStyle = "#25211b";
    ctx.lineWidth = 3;
    qcurve(ctx, x - 14, y, x - 4, y - 9, x + 5, y);
    qcurve(ctx, x + 5, y, x + 14, y - 8, x + 22, y + 1);
  } else if (kind.includes("fence") || kind.includes("ladder")) {
    ctx.strokeStyle = "rgba(50, 42, 28, 0.72)";
    ctx.lineWidth = 5;
    for (let i = -2; i <= 2; i += 1) {
      qcurve(ctx, x - 54, y + i * 12, x, y + i * 5, x + 54, y + i * 12);
    }
  } else if (kind === "distant_tree") {
    ctx.strokeStyle = "rgba(80, 64, 38, 0.55)";
    ctx.lineWidth = 5;
    qcurve(ctx, x, y + 34, x - 2, y + 15, x, y);
    ctx.strokeStyle = "rgba(42, 94, 52, 0.5)";
    ctx.lineWidth = 12;
    qcurve(ctx, x - 28, y, x, y - 16, x + 30, y);
  } else if (kind.includes("rope")) {
    ctx.strokeStyle = "rgba(60, 43, 25, 0.72)";
    ctx.lineWidth = 4;
    qcurve(ctx, x, y - 48, x + 16, y - 8, x - 2, y + 34);
    ctx.strokeStyle = "rgba(40, 31, 21, 0.54)";
    qcurve(ctx, x + 14, y - 42, x + 28, y - 8, x + 12, y + 32);
  } else if (kind.includes("cloud")) {
    ctx.fillStyle = "rgba(239,244,240,0.75)";
    for (let i = 0; i < 3; i += 1) {
      ctx.beginPath();
      ctx.ellipse(x + i * 18 - 18, y + (i % 2) * 4, 24, 13, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (kind.includes("paint") || kind.includes("flag") || kind.includes("kite")) {
    ctx.fillStyle = "rgba(205, 38, 38, 0.76)";
    ctx.beginPath();
    ctx.moveTo(x - 16, y - 16);
    ctx.lineTo(x + 19, y - 7);
    ctx.lineTo(x + 7, y + 18);
    ctx.lineTo(x - 21, y + 11);
    ctx.closePath();
    ctx.fill();
  } else if (kind.includes("window") || kind.includes("poster") || kind.includes("label") || kind.includes("mirror")) {
    ctx.fillStyle = kind.includes("mirror") ? "rgba(214,232,236,0.72)" : "#efe6d0";
    ctx.strokeStyle = "#2f2a22";
    ctx.lineWidth = 4;
    ctx.fillRect(x - 34, y - 24, 68, 48);
    ctx.strokeRect(x - 34, y - 24, 68, 48);
    ctx.strokeStyle = "rgba(255,255,255,0.45)";
    ctx.lineWidth = 2;
    qcurve(ctx, x - 25, y + 10, x - 2, y - 20, x + 28, y - 8);
  } else if (kind.includes("hole")) {
    ctx.fillStyle = "rgba(28, 23, 20, 0.76)";
    ctx.beginPath();
    ctx.ellipse(x, y, 36, 14, 0.05, 0, Math.PI * 2);
    ctx.fill();
  } else if (kind.includes("mushroom")) {
    ctx.fillStyle = "#f3dfc2";
    ctx.fillRect(x - 5, y, 10, 24);
    ctx.fillStyle = "#bd2630";
    ctx.beginPath();
    ctx.ellipse(x, y, 28, 14, 0, Math.PI, 0);
    ctx.fill();
  } else if (kind.includes("lantern")) {
    ctx.fillStyle = "rgba(241, 177, 60, 0.38)";
    ctx.beginPath();
    ctx.ellipse(x, y, 38, 35, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#6a4323";
    ctx.fillRect(x - 9, y - 12, 18, 26);
  } else if (kind.includes("sack")) {
    ctx.fillStyle = "#b89261";
    ctx.beginPath();
    ctx.ellipse(x, y + 8, 30, 28, -0.08, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#72502d";
    ctx.lineWidth = 4;
    qcurve(ctx, x - 19, y - 11, x, y - 22, x + 18, y - 11);
  } else if (kind.includes("wheel")) {
    ctx.strokeStyle = "#50351d";
    ctx.lineWidth = 8;
    ctx.beginPath();
    ctx.arc(x, y, 28, 0, Math.PI * 2);
    ctx.stroke();
    ctx.lineWidth = 3;
    for (let i = 0; i < 6; i += 1) {
      const a = (i / 6) * Math.PI * 2;
      qcurve(ctx, x, y, x + Math.cos(a) * 10, y + Math.sin(a) * 10, x + Math.cos(a) * 25, y + Math.sin(a) * 25);
    }
  } else if (kind === "plate") {
    ctx.fillStyle = "rgba(235, 228, 211, 0.88)";
    ctx.beginPath();
    ctx.ellipse(x, y, 42, 13, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "rgba(80, 74, 63, 0.45)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.ellipse(x, y, 31, 8, 0, 0, Math.PI * 2);
    ctx.stroke();
  } else if (kind === "stem_line") {
    ctx.strokeStyle = "#4a2a12";
    ctx.lineWidth = 4;
    qcurve(ctx, x, Number(p.y1 || y - 18), x + 2, y - 8, x, Number(p.y2 || y - 5));
  } else if (kind === "bark_shadow") {
    ctx.fillStyle = "rgba(20, 10, 4, 0.42)";
    ctx.beginPath();
    ctx.ellipse(x, y, 16, 20, 0.15, 0, Math.PI * 2);
    ctx.fill();
  } else if (kind === "foreground_leaf" || kind === "leaf_overlay") {
    ctx.fillStyle = "rgba(36, 93, 43, 0.88)";
    ctx.beginPath();
    ctx.ellipse(x, y, 25, 10, -0.35, 0, Math.PI * 2);
    ctx.fill();
  } else if (kind === "foreground_hand") {
    ctx.fillStyle = "rgba(191, 151, 114, 0.78)";
    ctx.beginPath();
    ctx.ellipse(x, y, 24, 16, -0.2, 0, Math.PI * 2);
    ctx.fill();
    for (let i = 0; i < 4; i += 1) {
      ctx.fillRect(x - 18 + i * 10, y - 22, 7, 22);
    }
  } else if (kind === "ground_shadow" || kind === "gap_marker") {
    ctx.fillStyle = "rgba(22, 18, 12, 0.24)";
    ctx.beginPath();
    ctx.ellipse(x, y + 9, 24, 8, 0, 0, Math.PI * 2);
    ctx.fill();
  } else if (kind === "scratch") {
    ctx.strokeStyle = "rgba(255, 255, 255, 0.2)";
    ctx.lineWidth = 2;
    qcurve(ctx, x - Number(p.w || 40) / 2, y, x, y - 9, x + Number(p.w || 40) / 2, y + 3);
  } else if (kind === "fog_band") {
    ctx.fillStyle = "rgba(225, 231, 226, 0.28)";
    ctx.beginPath();
    ctx.ellipse(x, y, Number(p.w || 80) / 2, 15, -0.08, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.fillStyle = "rgba(85, 73, 58, 0.35)";
    ctx.beginPath();
    ctx.ellipse(x, y, 22, 10, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
}

function drawTile(canvas, tile) {
  const ctx = canvas.getContext("2d");
  if (!ctx) return;
  const width = canvas.width;
  const height = canvas.height;
  ctx.clearRect(0, 0, width, height);
  drawBackground(ctx, tile, width, height);
  ctx.save();
  ctx.translate(width / 2, height / 2);
  ctx.rotate((Number(tile.frame?.tilt || 0) * Math.PI) / 180);
  ctx.scale(Number(tile.frame?.crop || 1), Number(tile.frame?.crop || 1));
  ctx.translate(-width / 2, -height / 2);
  (tile.props || []).forEach((p) => drawProp(ctx, p, "base"));
  drawTree(ctx, tile.tree);
  (tile.props || []).forEach((p) => drawProp(ctx, p, "mid"));
  (tile.apples || []).forEach((apple) => drawApple(ctx, apple));
  (tile.props || []).forEach((p) => drawProp(ctx, p, "foreground"));
  (tile.occluders || []).forEach((p) => drawProp(ctx, p, "foreground"));
  ctx.restore();
  ctx.strokeStyle = "rgba(0,0,0,0.34)";
  ctx.lineWidth = 8;
  ctx.strokeRect(4, 4, width - 8, height - 8);
}

function modifierTheme(index) {
  const themes = [
    ["#d5c9b6", "#8a8170", "#2a2e2f"],
    ["#c8d3d1", "#6f8386", "#202a2d"],
    ["#d7c6cf", "#88717d", "#2d2228"],
    ["#cbd0b8", "#7f8762", "#272b1e"],
    ["#d8cbbb", "#947b5d", "#2e2720"],
    ["#c9d3dc", "#718596", "#202934"],
    ["#d7d0be", "#827c69", "#28251f"],
    ["#c7d4c7", "#6f876f", "#1f2b21"],
  ];
  return themes[Math.abs(Number(index || 0)) % themes.length];
}

function modifierObjectColor(index) {
  return ["#b6332d", "#235f8d", "#20725b", "#7a4b8d", "#b06f1f", "#303a42", "#b74765", "#5d6f24"][Math.abs(Number(index || 0)) % 8];
}

function drawModifierObject(ctx, kind, color) {
  ctx.save();
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = 7;
  if (kind === "key") {
    ctx.beginPath();
    ctx.arc(-22, -2, 15, 0, Math.PI * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-7, -2);
    ctx.lineTo(35, -2);
    ctx.lineTo(35, 12);
    ctx.moveTo(16, -2);
    ctx.lineTo(16, 9);
    ctx.stroke();
  } else if (kind === "lock") {
    ctx.lineWidth = 8;
    ctx.beginPath();
    ctx.arc(0, -13, 21, Math.PI, Math.PI * 2);
    ctx.stroke();
    ctx.fillRect(-28, -8, 56, 45);
    ctx.fillStyle = "rgba(255,255,255,0.28)";
    ctx.fillRect(-8, 7, 16, 18);
  } else if (kind === "wrench") {
    ctx.lineWidth = 10;
    ctx.beginPath();
    ctx.moveTo(-33, 31);
    ctx.lineTo(18, -20);
    ctx.stroke();
    ctx.lineWidth = 7;
    ctx.beginPath();
    ctx.arc(27, -29, 18, 0.35, Math.PI * 1.45);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(-38, 36, 9, 0, Math.PI * 2);
    ctx.stroke();
  } else if (kind === "anchor") {
    ctx.lineWidth = 7;
    ctx.beginPath();
    ctx.arc(0, -34, 9, 0, Math.PI * 2);
    ctx.moveTo(0, -24);
    ctx.lineTo(0, 31);
    ctx.moveTo(-26, -2);
    ctx.lineTo(26, -2);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(0, 13, 35, 0.25, Math.PI - 0.25);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-35, 13);
    ctx.lineTo(-22, 4);
    ctx.moveTo(35, 13);
    ctx.lineTo(22, 4);
    ctx.stroke();
  } else if (kind === "crown") {
    ctx.beginPath();
    ctx.moveTo(-36, 28);
    ctx.lineTo(-30, -20);
    ctx.lineTo(-9, 8);
    ctx.lineTo(0, -27);
    ctx.lineTo(10, 8);
    ctx.lineTo(31, -20);
    ctx.lineTo(36, 28);
    ctx.closePath();
    ctx.fill();
  } else if (kind === "hourglass") {
    ctx.lineWidth = 6;
    ctx.strokeRect(-27, -34, 54, 68);
    ctx.beginPath();
    ctx.moveTo(-22, -28);
    ctx.lineTo(22, -28);
    ctx.lineTo(0, 0);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(-22, 28);
    ctx.lineTo(22, 28);
    ctx.lineTo(0, 0);
    ctx.closePath();
    ctx.fill();
  } else if (kind === "bolt") {
    ctx.beginPath();
    ctx.moveTo(5, -40);
    ctx.lineTo(-24, 4);
    ctx.lineTo(0, 4);
    ctx.lineTo(-8, 40);
    ctx.lineTo(28, -10);
    ctx.lineTo(5, -10);
    ctx.closePath();
    ctx.fill();
  } else if (kind === "cup") {
    ctx.lineWidth = 7;
    ctx.beginPath();
    ctx.moveTo(-28, -27);
    ctx.lineTo(-19, 30);
    ctx.lineTo(18, 30);
    ctx.lineTo(28, -27);
    ctx.closePath();
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(31, -3, 17, -Math.PI / 2, Math.PI / 2);
    ctx.stroke();
    ctx.fillRect(-20, 33, 40, 6);
  }
  ctx.restore();
}

function modifierByName(tile, name) {
  return (tile.modifiers || []).find((item) => item.name === name);
}

function drawModifierObjectAt(ctx, tile, dx = 0, dy = 0, alpha = 1) {
  const obj = tile.object || {};
  ctx.save();
  ctx.globalAlpha *= alpha;
  ctx.translate(Number(obj.x || 80) + dx, Number(obj.y || 60) + dy);
  ctx.scale(Number(obj.scale || 1), Number(obj.scale || 1));
  drawModifierObject(ctx, tile.kind, modifierObjectColor(obj.color));
  ctx.restore();
}

function drawModifierTile(canvas, tile) {
  const ctx = canvas.getContext("2d");
  const width = canvas.width;
  const height = canvas.height;
  const theme = modifierTheme(tile.frame?.theme);
  ctx.clearRect(0, 0, width, height);
  const grad = ctx.createLinearGradient(0, 0, width, height);
  grad.addColorStop(0, theme[0]);
  grad.addColorStop(1, theme[1]);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);

  ctx.save();
  ctx.strokeStyle = "rgba(20,20,20,0.16)";
  ctx.lineWidth = 1;
  for (let x = -20; x < width + 30; x += 18) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x + 18, height);
    ctx.stroke();
  }
  (tile.noise || []).forEach((item, index) => {
    ctx.save();
    ctx.translate(Number(item.x || 0), Number(item.y || 0));
    ctx.rotate(Number(item.a || 0));
    ctx.strokeStyle = index % 3 ? "rgba(255,255,255,0.22)" : "rgba(0,0,0,0.16)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(-Number(item.w || 20) / 2, 0);
    ctx.lineTo(Number(item.w || 20) / 2, 0);
    ctx.stroke();
    ctx.restore();
  });
  ctx.restore();

  ctx.save();
  ctx.translate(width / 2, height / 2);
  ctx.rotate((Number(tile.frame?.tilt || 0) * Math.PI) / 180);
  ctx.translate(-width / 2, -height / 2);
  const crop = modifierByName(tile, "crop");
  const offset = modifierByName(tile, "tile_offset");
  const rotate = modifierByName(tile, "rotate");
  const mirror = modifierByName(tile, "mirror");
  ctx.translate(Number(offset?.dx || 0) + Number(crop?.x || 0), Number(offset?.dy || 0) + Number(crop?.y || 0));
  ctx.translate(width / 2, height / 2);
  if (rotate) ctx.rotate(Number(rotate.angle || 0));
  ctx.scale(mirror ? -1 : 1, 1);
  ctx.scale(Number(crop?.scale || 1), Number(crop?.scale || 1));
  ctx.translate(-width / 2, -height / 2);

  const shadow = modifierByName(tile, "jitter_shadow");
  if (shadow) drawModifierObjectAt(ctx, tile, Number(shadow.dx || 0), Number(shadow.dy || 0), 0.28);
  const split = modifierByName(tile, "split");
  if (split) {
    const axis = split.axis || "x";
    const amount = Number(split.offset || 10);
    ctx.save();
    if (axis === "x") {
      ctx.beginPath();
      ctx.rect(0, 0, width / 2, height);
      ctx.clip();
      drawModifierObjectAt(ctx, tile, -amount, 0, 1);
      ctx.restore();
      ctx.save();
      ctx.beginPath();
      ctx.rect(width / 2, 0, width / 2, height);
      ctx.clip();
      drawModifierObjectAt(ctx, tile, amount, 0, 1);
    } else {
      ctx.beginPath();
      ctx.rect(0, 0, width, height / 2);
      ctx.clip();
      drawModifierObjectAt(ctx, tile, 0, -amount, 1);
      ctx.restore();
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, height / 2, width, height / 2);
      ctx.clip();
      drawModifierObjectAt(ctx, tile, 0, amount, 1);
    }
    ctx.restore();
  } else {
    drawModifierObjectAt(ctx, tile);
  }
  ctx.restore();

  if (modifierByName(tile, "invert")) {
    ctx.save();
    ctx.globalCompositeOperation = "difference";
    ctx.fillStyle = "rgba(255,255,255,0.82)";
    ctx.fillRect(0, 0, width, height);
    ctx.restore();
  }
  const stripe = modifierByName(tile, "stripe_occlusion");
  if (stripe) {
    ctx.save();
    ctx.translate(width / 2, height / 2);
    ctx.rotate(Number(stripe.angle || 0));
    ctx.fillStyle = "rgba(28, 33, 38, 0.52)";
    const count = Number(stripe.count || 3);
    for (let i = -count; i <= count; i += 1) {
      ctx.fillRect(-width, i * 24 - 4, width * 2, 8);
    }
    ctx.restore();
  }
  const fog = modifierByName(tile, "fog");
  if (fog) {
    ctx.fillStyle = "rgba(242,245,238,0.34)";
    ctx.beginPath();
    ctx.ellipse(Number(fog.x || 80), Number(fog.y || 60), 54, 20, -0.18, 0, Math.PI * 2);
    ctx.fill();
  }
  const loader = modifierByName(tile, "fake_loader");
  if (loader) {
    ctx.fillStyle = "rgba(12, 16, 19, 0.58)";
    ctx.fillRect(12, height - 22, width - 24, 9);
    ctx.fillStyle = "#f3c742";
    ctx.fillRect(12, height - 22, (width - 24) * Number(loader.progress || 0.5), 9);
  }
  ctx.strokeStyle = "rgba(0,0,0,0.38)";
  ctx.lineWidth = 7;
  ctx.strokeRect(3.5, 3.5, width - 7, height - 7);
}

function lensTheme(index) {
  const themes = [
    ["#172126", "#24363b", "#89a5a7", "#ffbf3c"],
    ["#211d22", "#372c35", "#a89aa4", "#ffbf3c"],
    ["#182219", "#2d3c2f", "#9aa98f", "#ffbf3c"],
    ["#241f16", "#40351f", "#b0a17c", "#ffbf3c"],
    ["#171b27", "#283247", "#95a4bd", "#ffbf3c"],
    ["#201b18", "#3b3029", "#ad9a84", "#ffbf3c"],
    ["#142026", "#25353e", "#8fb2c1", "#ffbf3c"],
  ];
  return themes[Math.abs(Number(index || 0)) % themes.length];
}

function drawLensBackground(ctx, state, width, height) {
  const theme = lensTheme(state.surface?.theme);
  const grad = ctx.createLinearGradient(0, 0, width, height);
  grad.addColorStop(0, theme[0]);
  grad.addColorStop(1, theme[1]);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, width, height);

  ctx.save();
  ctx.strokeStyle = "rgba(255,255,255,0.055)";
  ctx.lineWidth = 1;
  for (let x = 18; x < width; x += 24) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x - 18, height);
    ctx.stroke();
  }
  for (let y = 16; y < height; y += 22) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y + 14);
    ctx.stroke();
  }
  ctx.restore();

  (state.clutter || []).forEach((item, index) => {
    const x = Number(item.x || 0);
    const y = Number(item.y || 0);
    ctx.save();
    ctx.globalAlpha = Number(item.alpha || 0.12);
    ctx.translate(x, y);
    ctx.rotate(Number(item.rot || 0));
    if (item.kind === "cell") {
      ctx.fillStyle = index % 3 === 0 ? theme[2] : "rgba(255,255,255,0.72)";
      ctx.beginPath();
      ctx.ellipse(0, 0, Number(item.r || 8), Number(item.r || 8) * 0.55, 0, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.strokeStyle = index % 4 === 0 ? theme[2] : "rgba(255,255,255,0.76)";
      ctx.lineWidth = item.kind === "dash" ? 3 : 1.6;
      ctx.beginPath();
      ctx.moveTo(-Number(item.w || 20) / 2, 0);
      ctx.quadraticCurveTo(0, -7, Number(item.w || 20) / 2, 2);
      ctx.stroke();
    }
    ctx.restore();
  });

  const grain = Math.round(600 + Number(state.surface?.grain || 0.22) * 1200);
  ctx.fillStyle = "rgba(255,255,255,0.09)";
  for (let i = 0; i < grain; i += 1) {
    const n = (Math.sin((i + 3) * 74.31 + width) + 1) / 2;
    const m = (Math.sin((i + 7) * 39.17 + height) + 1) / 2;
    const px = Math.floor(n * width);
    const py = Math.floor(m * height);
    ctx.fillRect(px, py, 1, 1);
  }
}

function drawLensGlyph(ctx, mark, theme) {
  const r = Number(mark.r || 14) * Number(mark.scale || 1);
  ctx.save();
  ctx.translate(Number(mark.x || 0), Number(mark.y || 0));
  ctx.rotate(Number(mark.rot || 0));
  ctx.globalAlpha = mark.kind === "target" ? 1 : Number(mark.alpha || 0.62);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  if (mark.kind === "target") {
    ctx.strokeStyle = theme[3];
    ctx.fillStyle = "rgba(255, 191, 60, 0.2)";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(0, 0, r * 0.52, 0, Math.PI * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(-r * 1.45, 0);
    ctx.lineTo(-r * 0.48, 0);
    ctx.moveTo(r * 0.48, 0);
    ctx.lineTo(r * 1.45, 0);
    ctx.moveTo(0, -r * 1.45);
    ctx.lineTo(0, -r * 0.48);
    ctx.moveTo(0, r * 0.48);
    ctx.lineTo(0, r * 1.45);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(0, 0, 3.4, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
    return;
  }

  const palette = {
    blue_ring: "#70a8d8",
    green_cross: "#84b876",
    red_square: "#d36d65",
    gray_spiral: "#b8b8b0",
    yellow_slash: "#d1b75c",
    black_ticks: "#1c1c1c",
    cyan_lozenge: "#75c7c8",
    pink_arc: "#d48caf",
    tiny_grid: "#d6d1c5",
    white_chip: "#ece8d8",
    orange_dot: "#e28d3f",
    violet_hook: "#b090d4",
  };
  ctx.strokeStyle = palette[mark.symbol] || "rgba(230,230,230,0.8)";
  ctx.fillStyle = palette[mark.symbol] || "rgba(230,230,230,0.8)";
  ctx.lineWidth = 3;
  if (mark.symbol?.includes("ring")) {
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, Math.PI * 1.6);
    ctx.stroke();
  } else if (mark.symbol?.includes("cross")) {
    ctx.beginPath();
    ctx.moveTo(-r, 0);
    ctx.lineTo(r, 0);
    ctx.moveTo(0, -r);
    ctx.lineTo(0, r);
    ctx.stroke();
  } else if (mark.symbol?.includes("square") || mark.symbol?.includes("chip")) {
    ctx.strokeRect(-r, -r, r * 2, r * 2);
  } else if (mark.symbol?.includes("spiral") || mark.symbol?.includes("arc") || mark.symbol?.includes("hook")) {
    ctx.beginPath();
    ctx.arc(0, 0, r, 0.2, Math.PI * 1.4);
    ctx.lineTo(r * 0.25, r * 0.45);
    ctx.stroke();
  } else if (mark.symbol?.includes("lozenge")) {
    ctx.beginPath();
    ctx.moveTo(0, -r);
    ctx.lineTo(r * 1.25, 0);
    ctx.lineTo(0, r);
    ctx.lineTo(-r * 1.25, 0);
    ctx.closePath();
    ctx.stroke();
  } else if (mark.symbol?.includes("grid")) {
    for (let i = -1; i <= 1; i += 1) {
      ctx.beginPath();
      ctx.moveTo(-r, i * r * 0.45);
      ctx.lineTo(r, i * r * 0.45);
      ctx.moveTo(i * r * 0.45, -r);
      ctx.lineTo(i * r * 0.45, r);
      ctx.stroke();
    }
  } else {
    ctx.beginPath();
    ctx.moveTo(-r, r * 0.75);
    ctx.lineTo(r, -r * 0.75);
    ctx.stroke();
  }
  ctx.restore();
}

function drawLensCanvas(canvas) {
  const state = lensModel.state;
  if (!state) return;
  const ctx = canvas.getContext("2d");
  const width = canvas.width;
  const height = canvas.height;
  const theme = lensTheme(state.surface?.theme);
  drawLensBackground(ctx, state, width, height);

  if (lensModel.pointer) {
    const radius = Number(state.surface?.lens_radius || 58);
    ctx.save();
    ctx.beginPath();
    ctx.arc(lensModel.pointer.x, lensModel.pointer.y, radius, 0, Math.PI * 2);
    ctx.clip();
    ctx.fillStyle = "rgba(238, 244, 238, 0.16)";
    ctx.fillRect(0, 0, width, height);
    (state.hidden_marks || []).forEach((mark) => drawLensGlyph(ctx, mark, theme));
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.78)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(lensModel.pointer.x, lensModel.pointer.y, radius, 0, Math.PI * 2);
    ctx.stroke();
    ctx.strokeStyle = "rgba(0, 0, 0, 0.42)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.arc(lensModel.pointer.x, lensModel.pointer.y, radius + 4, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  if (lensModel.cheatTarget) {
    const target = lensModel.cheatTarget;
    ctx.save();
    ctx.strokeStyle = "#f3c742";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(Number(target.x), Number(target.y), Number(target.radius || 18) + 7, 0, Math.PI * 2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(Number(target.x) - 24, Number(target.y));
    ctx.lineTo(Number(target.x) + 24, Number(target.y));
    ctx.moveTo(Number(target.x), Number(target.y) - 24);
    ctx.lineTo(Number(target.x), Number(target.y) + 24);
    ctx.stroke();
    ctx.restore();
  }

  ctx.strokeStyle = "rgba(0,0,0,0.42)";
  ctx.lineWidth = 8;
  ctx.strokeRect(4, 4, width - 8, height - 8);
}

function canvasPointFromEvent(canvas, event) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: ((event.clientX - rect.left) / rect.width) * canvas.width,
    y: ((event.clientY - rect.top) / rect.height) * canvas.height,
  };
}

function cheatPanelTemplate() {
  if (!isCheatMode()) return "";
  return `
    <section class="cheat-panel" aria-label="developer answer reveal">
      <form id="cheat-form" class="cheat-form">
        <input class="cheat-input" id="cheat-password" type="password" autocomplete="off" placeholder="Password">
        <button class="cheat-submit" type="submit">Reveal</button>
      </form>
      <p class="cheat-output" id="cheat-output"></p>
    </section>
  `;
}

function clearCheatMarks() {
  document.querySelectorAll(".apple-tile[data-cheat-answer], .modifier-tile[data-cheat-answer]").forEach((tile) => {
    tile.removeAttribute("data-cheat-answer");
    tile.removeAttribute("data-cheat-position");
  });
}

function applyCheatAnswers(answers) {
  clearCheatMarks();
  const positions = [];
  (answers || []).forEach((answer) => {
    const tileId = text(answer.tile_id);
    const tile = document.querySelector(`.apple-tile[data-tile-id="${CSS.escape(tileId)}"], .modifier-tile[data-tile-id="${CSS.escape(tileId)}"]`);
    if (!tile) return;
    const position = answer.position == null ? "?" : text(answer.position);
    tile.dataset.cheatAnswer = "true";
    tile.dataset.cheatPosition = position;
    positions.push(position);
  });
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = positions.length ? `Answers: ${positions.join(", ")}` : "No answers found.";
}

function applyCursorLensCheat(target) {
  lensModel.cheatTarget = target || null;
  const canvas = document.querySelector(".lens-canvas");
  if (canvas) drawLensCanvas(canvas);
  const output = document.getElementById("cheat-output");
  if (!output) return;
  if (!target) {
    output.textContent = "No target found.";
    return;
  }
  output.textContent = `Target: ${Math.round(Number(target.x))}, ${Math.round(Number(target.y))}`;
}

function applyBoardGameCheat(move) {
  document.querySelectorAll(".board-cell[data-cheat-answer]").forEach((cell) => {
    cell.removeAttribute("data-cheat-answer");
  });
  const cellId = text(move?.cell_id);
  const cell = document.querySelector(`.board-cell[data-cell-id="${CSS.escape(cellId)}"]`);
  if (cell) cell.dataset.cheatAnswer = "true";
  const output = document.getElementById("cheat-output");
  if (!output) return;
  if (!move) {
    output.textContent = "No move found.";
    return;
  }
  const row = Number(move.row) + 1;
  const col = Number(move.col) + 1;
  output.textContent = `Move: row ${row}, col ${col}`;
}

function applySemanticCheat(assignments) {
  Object.entries(assignments || {}).forEach(([objectId, zoneId]) => {
    const obj = document.querySelector(`.drag-object[data-object-id="${CSS.escape(objectId)}"]`);
    const zone = document.querySelector(`.drop-zone[data-zone-id="${CSS.escape(zoneId)}"]`);
    if (obj) obj.dataset.cheatAnswer = "true";
    if (zone) zone.dataset.cheatAnswer = "true";
  });
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = `Assignments: ${Object.keys(assignments || {}).length}`;
}

function applyReloadCheat(data) {
  const output = document.getElementById("cheat-output");
  if (!output) return;
  output.textContent = `Interruptions: ${Object.entries(data || {}).map(([key, value]) => `${key}=${Array.isArray(value) ? value.join(" ") : value}`).join("; ")}`;
}

function applyRotateCheat(rotation) {
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = `Target angle: ${Math.round(Number(rotation?.target_angle || 0))}`;
  const marker = document.querySelector(".rotate-target-mark");
  if (marker) marker.textContent = `${Math.round(Number(rotation?.target_angle || 0))} deg`;
}

function applyFormCheat(requiredMarks) {
  (requiredMarks || []).forEach((mark) => {
    const field = document.querySelector(`.form-field[data-field-id="${CSS.escape(text(mark.field_id))}"]`);
    if (field) field.dataset.cheatAnswer = "true";
  });
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = (requiredMarks || []).map((mark) => `${mark.mark_type} ${mark.field_label}`).join("; ");
}

function applyWonkyCheat(token) {
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = `Token: ${text(token)}`;
}

function applyTemporalCheat(target) {
  const objectId = text(target?.object_id);
  const button = document.querySelector(`.temporal-hit[data-object-id="${CSS.escape(objectId)}"]`);
  if (button) button.dataset.cheatAnswer = "true";
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = `First change: ${text(target?.kind)} at ${text(target?.first_change_ms)} ms`;
}

function applyInteractionCheat(label, value) {
  const output = document.getElementById("cheat-output");
  if (output) output.textContent = `${label}: ${typeof value === "string" ? value : JSON.stringify(value)}`;
}

function installCheatPanel() {
  if (!isCheatMode()) return;
  const form = document.getElementById("cheat-form");
  const input = document.getElementById("cheat-password");
  const output = document.getElementById("cheat-output");
  if (!form || !input || !output) return;
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    clearCheatMarks();
    output.textContent = "";
    try {
      const response = await fetch("/cheat", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({password: input.value}),
      });
      if (!response.ok) {
        output.textContent = response.status === 404 ? "Disabled." : "Denied.";
        return;
      }
      const data = await response.json();
      if (data.mechanic_id === "cursor_lens_reveal") {
        applyCursorLensCheat(data.target);
      } else if (data.mechanic_id === "board_game_captcha") {
        applyBoardGameCheat(data.move);
      } else if (data.mechanic_id === "semantic_drag_drop_absurdity") {
        applySemanticCheat(data.assignments);
      } else if (data.mechanic_id === "reload_interruption") {
        applyReloadCheat(data.answers);
      } else if (data.mechanic_id === "rotate_wrong_thing_upright") {
        applyRotateCheat(data.rotation);
      } else if (data.mechanic_id === "bureaucratic_signature_trap") {
        applyFormCheat(data.required_marks);
      } else if (data.mechanic_id === "wonky_text_hostile_rendering") {
        applyWonkyCheat(data.token);
      } else if (data.mechanic_id === "temporal_memory_first_change") {
        applyTemporalCheat(data.target);
      } else if (data.mechanic_id === "motion_only_ghost_jigsaw") {
        applyInteractionCheat("Positions", data.positions);
      } else if (data.mechanic_id === "cursor_constellation_hunt") {
        applyInteractionCheat("Target", {shape: data.shape, ...data.target});
      } else if (data.mechanic_id === "parallel_grillmaster") {
        applyInteractionCheat("Cook windows", data.targets);
      } else if (data.mechanic_id === "rotating_keyboard") {
        applyInteractionCheat("Code", data.target);
      } else if (data.mechanic_id === "slot_reel_capture") {
        applyInteractionCheat("Sequence", data.sequence);
      } else {
        applyCheatAnswers(data.answers);
      }
    } catch (_error) {
      output.textContent = "Unavailable.";
    }
  });
}

function renderAppleGrid(state) {
  document.body.dataset.mechanic = "apple-grid";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  gridModel.selected = new Set();
  gridModel.order = [];
  const tiles = state.tiles || [];
  app.innerHTML = `
    <section class="apple-captcha" data-mechanic="${text(state.mechanic_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Select every image where the apple is visibly attached to the tree.")}</h1>
      </header>
      <section class="apple-grid" aria-label="${text(state.prompt || "image grid")}">
        ${tiles.map((tile, index) => `
          <button class="apple-tile" type="button" data-tile-id="${text(tile.id)}" aria-pressed="false">
            <canvas width="260" height="182" aria-label="image ${index + 1}"></canvas>
            <span class="tile-selected"></span>
          </button>
        `).join("")}
      </section>
      <footer class="apple-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-apple-grid">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;

  document.querySelectorAll(".apple-tile").forEach((button, index) => {
    drawTile(button.querySelector("canvas"), tiles[index]);
    button.addEventListener("click", () => {
      const tileId = button.dataset.tileId;
      if (gridModel.selected.has(tileId)) {
        gridModel.selected.delete(tileId);
        button.setAttribute("aria-pressed", "false");
      } else {
        gridModel.selected.add(tileId);
        gridModel.order.push(tileId);
        button.setAttribute("aria-pressed", "true");
      }
    });
  });

  document.getElementById("submit-apple-grid").addEventListener("click", async () => {
    const payload = {
      mechanic_id: document.querySelector(".apple-captcha").dataset.mechanic,
      selected_tile_ids: Array.from(gridModel.selected),
      selection_order: gridModel.order,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const outcome = await response.json();
      if (outcome.passed === true) {
        setReadout("PASS", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) renderAppleGrid(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });

  installCheatPanel();
}

function renderModifierGrid(state) {
  document.body.dataset.mechanic = "modifier-grid";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  gridModel.selected = new Set();
  gridModel.order = [];
  const tiles = state.tiles || [];
  app.innerHTML = `
    <section class="modifier-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head modifier-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Select every corrupted target.")}</h1>
      </header>
      <section class="modifier-grid" aria-label="${text(state.prompt || "corrupted image grid")}">
        ${tiles.map((tile, index) => `
          <button class="modifier-tile" type="button" data-tile-id="${text(tile.id)}" aria-pressed="false">
            <canvas width="176" height="130" aria-label="image ${index + 1}"></canvas>
            <span class="tile-selected"></span>
          </button>
        `).join("")}
      </section>
      <footer class="apple-captcha-foot modifier-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-modifier-grid">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;

  document.querySelectorAll(".modifier-tile").forEach((button, index) => {
    drawModifierTile(button.querySelector("canvas"), tiles[index]);
    button.addEventListener("click", () => {
      setReadout("", "idle");
      const tileId = button.dataset.tileId;
      if (gridModel.selected.has(tileId)) {
        gridModel.selected.delete(tileId);
        button.setAttribute("aria-pressed", "false");
      } else {
        gridModel.selected.add(tileId);
        gridModel.order.push(tileId);
        button.setAttribute("aria-pressed", "true");
      }
    });
  });

  document.getElementById("submit-modifier-grid").addEventListener("click", async () => {
    const payload = {
      mechanic_id: document.querySelector(".modifier-captcha").dataset.mechanic,
      challenge_id: document.querySelector(".modifier-captcha").dataset.challengeId,
      selected_tile_ids: Array.from(gridModel.selected),
      selection_order: gridModel.order,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const outcome = await response.json();
      if (outcome.passed === true) {
        setReadout("PASS", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) renderModifierGrid(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });

  installCheatPanel();
}

function boardTheme(index) {
  const themes = [
    ["#f4efe2", "#1e2a33", "#cf3f2f", "#2d6d8e"],
    ["#efe7d7", "#221e1a", "#b93532", "#2e6575"],
    ["#edf0e5", "#1f2b20", "#b8492f", "#355f91"],
    ["#e9edf0", "#20262c", "#c74731", "#286b5f"],
    ["#f2e8db", "#2a211d", "#b7422c", "#2d5e8b"],
    ["#e7eadf", "#1f2524", "#c13d32", "#336b76"],
  ];
  return themes[Math.abs(Number(index || 0)) % themes.length];
}

function pieceMarkup(value) {
  if (value === "X") return `<span class="board-piece board-piece-x" aria-label="X">X</span>`;
  if (value === "O") return `<span class="board-piece board-piece-o" aria-label="O">O</span>`;
  return `<span class="board-empty" aria-hidden="true"></span>`;
}

function renderBoardGame(state) {
  document.body.dataset.mechanic = "board-game";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  boardModel.selectedCellId = null;
  const game = state.game || {};
  const cells = game.cells || [];
  const theme = boardTheme(game.theme);
  app.innerHTML = `
    <section class="board-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}" style="--board-paper:${theme[0]};--board-ink:${theme[1]};--board-x:${theme[2]};--board-o:${theme[3]};">
      <header class="apple-captcha-head board-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Play X on the correct square.")}</h1>
      </header>
      <section class="board-stage" aria-label="${text(state.prompt || "tic tac toe board")}">
        <div class="board-grid">
          ${cells.map((cell) => `
            <button class="board-cell" type="button" data-cell-id="${text(cell.id)}" data-row="${text(cell.row)}" data-col="${text(cell.col)}" data-value="${text(cell.value)}" aria-pressed="false" ${cell.value ? "disabled" : ""}>
              ${pieceMarkup(cell.value)}
            </button>
          `).join("")}
        </div>
      </section>
      <footer class="apple-captcha-foot board-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-board-move">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;

  document.querySelectorAll(".board-cell:not([disabled])").forEach((button) => {
    button.addEventListener("click", () => {
      setReadout("", "idle");
      document.querySelectorAll(".board-cell[aria-pressed='true']").forEach((cell) => {
        cell.setAttribute("aria-pressed", "false");
        const ghost = cell.querySelector(".board-ghost");
        if (ghost) ghost.remove();
      });
      boardModel.selectedCellId = button.dataset.cellId;
      button.setAttribute("aria-pressed", "true");
      button.insertAdjacentHTML("beforeend", `<span class="board-ghost">X</span>`);
    });
  });

  document.getElementById("submit-board-move").addEventListener("click", async () => {
    if (!boardModel.selectedCellId) {
      setReadout("FAIL", "error");
      return;
    }
    const selected = document.querySelector(`.board-cell[data-cell-id="${CSS.escape(boardModel.selectedCellId)}"]`);
    const payload = {
      mechanic_id: document.querySelector(".board-captcha").dataset.mechanic,
      challenge_id: document.querySelector(".board-captcha").dataset.challengeId,
      selected_cell_id: boardModel.selectedCellId,
      selected: {
        row: selected ? Number(selected.dataset.row) : null,
        col: selected ? Number(selected.dataset.col) : null,
      },
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const outcome = await response.json();
      if (outcome.passed === true) {
        setReadout("PASS", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) renderBoardGame(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });

  installCheatPanel();
}

function renderCursorLens(state) {
  document.body.dataset.mechanic = "cursor-lens";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  lensModel.state = state;
  lensModel.pointer = null;
  lensModel.cheatTarget = null;
  const surface = state.surface || {};
  const width = Number(surface.width || 660);
  const height = Number(surface.height || 390);
  app.innerHTML = `
    <section class="lens-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head lens-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Use the cursor lens to find the amber target mark and click its center.")}</h1>
      </header>
      <section class="lens-stage" aria-label="${text(state.prompt || "hidden marker canvas")}">
        <canvas class="lens-canvas" width="${width}" height="${height}"></canvas>
      </section>
      <footer class="apple-captcha-foot lens-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-lens-click">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;

  let pendingClick = null;
  const canvas = document.querySelector(".lens-canvas");
  drawLensCanvas(canvas);

  canvas.addEventListener("mousemove", (event) => {
    lensModel.pointer = canvasPointFromEvent(canvas, event);
    drawLensCanvas(canvas);
  });
  canvas.addEventListener("mouseleave", () => {
    lensModel.pointer = null;
    drawLensCanvas(canvas);
  });
  canvas.addEventListener("click", (event) => {
    pendingClick = canvasPointFromEvent(canvas, event);
    lensModel.pointer = pendingClick;
    drawLensCanvas(canvas);
  });

  document.getElementById("submit-lens-click").addEventListener("click", async () => {
    if (!pendingClick) {
      setReadout("FAIL", "error");
      return;
    }
    const payload = {
      mechanic_id: document.querySelector(".lens-captcha").dataset.mechanic,
      challenge_id: document.querySelector(".lens-captcha").dataset.challengeId,
      click: {
        x: Number(pendingClick.x.toFixed(2)),
        y: Number(pendingClick.y.toFixed(2)),
      },
      canvas: {width, height},
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const outcome = await response.json();
      if (outcome.passed === true) {
        setReadout("PASS", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) renderCursorLens(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });

  installCheatPanel();
}

function objectGlyph(label) {
  const key = label.toLowerCase();
  if (key.includes("key")) return "key";
  if (key.includes("fuse")) return "fuse";
  if (key.includes("stamp")) return "stamp";
  if (key.includes("ice")) return "ice";
  if (key.includes("gear")) return "gear";
  if (key.includes("thread")) return "thread";
  if (key.includes("lens")) return "lens";
  if (key.includes("plug")) return "plug";
  if (key.includes("ticket")) return "ticket";
  if (key.includes("seal")) return "seal";
  return "object";
}

function renderSemanticDragDrop(state) {
  document.body.dataset.mechanic = "semantic-drag";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  dragModel.placements = {};
  const surface = state.surface || {};
  app.innerHTML = `
    <section class="wide-captcha semantic-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Drag each object where it belongs.")}</h1>
      </header>
      <section class="semantic-stage" style="--stage-w:${Number(surface.width || 690)};--stage-h:${Number(surface.height || 330)}">
        ${(state.zones || []).map((zone) => `
          <div class="drop-zone" data-zone-id="${text(zone.id)}" style="left:${Number(zone.x)}px;top:${Number(zone.y)}px">
            <span>${text(zone.label)}</span>
            <small>${text(zone.relation)}</small>
          </div>
        `).join("")}
        ${(state.objects || []).map((object) => `
          <button class="drag-object object-${text(objectGlyph(object.label))}" type="button" data-object-id="${text(object.id)}" style="left:${Number(object.x)}px;top:${Number(object.y)}px;--object-color:${Number(object.color || 0)}">
            <span class="object-symbol"></span>
            <span class="object-label">${text(object.label)}</span>
          </button>
        `).join("")}
      </section>
      <footer class="apple-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-semantic">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;

  const stage = document.querySelector(".semantic-stage");
  let active = null;
  document.querySelectorAll(".drag-object").forEach((object) => {
    object.addEventListener("pointerdown", (event) => {
      active = {
        node: object,
        dx: event.clientX - object.getBoundingClientRect().left,
        dy: event.clientY - object.getBoundingClientRect().top,
      };
      object.setPointerCapture(event.pointerId);
      object.classList.add("dragging");
      setReadout("", "idle");
    });
    object.addEventListener("pointermove", (event) => {
      if (!active || active.node !== object) return;
      const rect = stage.getBoundingClientRect();
      object.style.left = `${event.clientX - rect.left - active.dx}px`;
      object.style.top = `${event.clientY - rect.top - active.dy}px`;
    });
    object.addEventListener("pointerup", (event) => {
      if (!active || active.node !== object) return;
      object.releasePointerCapture(event.pointerId);
      object.classList.remove("dragging");
      const objectRect = object.getBoundingClientRect();
      const cx = objectRect.left + objectRect.width / 2;
      const cy = objectRect.top + objectRect.height / 2;
      let matched = null;
      document.querySelectorAll(".drop-zone").forEach((zone) => {
        const rect = zone.getBoundingClientRect();
        if (cx >= rect.left && cx <= rect.right && cy >= rect.top && cy <= rect.bottom) matched = zone;
      });
      if (matched) {
        const stageRect = stage.getBoundingClientRect();
        const zr = matched.getBoundingClientRect();
        object.style.left = `${zr.left - stageRect.left + 12}px`;
        object.style.top = `${zr.top - stageRect.top + zr.height - objectRect.height - 10}px`;
        dragModel.placements[object.dataset.objectId] = matched.dataset.zoneId;
        object.dataset.placed = "true";
      }
      active = null;
    });
  });

  document.getElementById("submit-semantic").addEventListener("click", async () => {
    const payload = {
      mechanic_id: document.querySelector(".semantic-captcha").dataset.mechanic,
      challenge_id: document.querySelector(".semantic-captcha").dataset.challengeId,
      placements: dragModel.placements,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else {
        if (outcome.state) renderSemanticDragDrop(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });

  installCheatPanel();
}

function reloadProgressWidth(required) {
  return `${Math.min(100, Math.round((reloadModel.step / required) * 100))}%`;
}

async function submitReloadFailure(state, interruptionId) {
  const payload = {
    mechanic_id: state.mechanic_id,
    challenge_id: state.challenge_id,
    completed: false,
    cleared_interruptions: reloadModel.cleared,
    failed_interruption_id: interruptionId,
    user_agent: navigator.userAgent,
  };
  const response = await fetch("/result", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify(payload),
  });
  const outcome = await response.json();
  if (outcome.state) renderReloadInterruption(outcome.state);
  setReadout("FAIL", "error");
}

function showReloadOverlay(state, overlay) {
  reloadModel.active = overlay;
  reloadModel.sequenceInput = [];
  const modal = document.querySelector(".reload-modal");
  modal.hidden = false;
  if (overlay.type === "type_code") {
    modal.innerHTML = `
      <div class="reload-card">
        <h2>${text(overlay.prompt)}</h2>
        <div class="reload-code">${text(overlay.code)}</div>
        <input class="reload-input" id="reload-code-input" autocomplete="off">
        <button class="apple-submit" type="button" id="reload-overlay-submit">VERIFY</button>
      </div>
    `;
    document.getElementById("reload-overlay-submit").addEventListener("click", async () => {
      const value = document.getElementById("reload-code-input").value.trim().toUpperCase();
      if (value === text(overlay.answer).toUpperCase()) {
        reloadModel.cleared.push(overlay.id);
        modal.hidden = true;
        reloadModel.active = null;
      } else {
        await submitReloadFailure(state, overlay.id);
      }
    });
  } else if (overlay.type === "press_lit") {
    modal.innerHTML = `
      <div class="reload-card">
        <h2>${text(overlay.prompt)}</h2>
        <div class="reload-buttons">${(overlay.buttons || []).map((button) => `<button class="reload-choice" type="button" data-value="${text(button)}">${text(button)}</button>`).join("")}</div>
      </div>
    `;
    modal.querySelectorAll(".reload-choice").forEach((button) => {
      button.addEventListener("click", async () => {
        if (button.dataset.value === text(overlay.answer)) {
          reloadModel.cleared.push(overlay.id);
          modal.hidden = true;
          reloadModel.active = null;
        } else {
          await submitReloadFailure(state, overlay.id);
        }
      });
    });
  } else {
    modal.innerHTML = `
      <div class="reload-card">
        <h2>${text(overlay.prompt)}</h2>
        <div class="reload-sequence">${(overlay.sequence || []).map((item) => `<span>${text(item)}</span>`).join("")}</div>
        <div class="reload-buttons">${(overlay.buttons || []).map((button) => `<button class="reload-choice" type="button" data-value="${text(button)}">${text(button)}</button>`).join("")}</div>
      </div>
    `;
    modal.querySelectorAll(".reload-choice").forEach((button) => {
      button.addEventListener("click", async () => {
        reloadModel.sequenceInput.push(button.dataset.value);
        const expected = overlay.sequence || [];
        const index = reloadModel.sequenceInput.length - 1;
        if (reloadModel.sequenceInput[index] !== expected[index]) {
          await submitReloadFailure(state, overlay.id);
          return;
        }
        if (reloadModel.sequenceInput.length === expected.length) {
          reloadModel.cleared.push(overlay.id);
          modal.hidden = true;
          reloadModel.active = null;
        }
      });
    });
  }
}

function renderReloadInterruption(state) {
  document.body.dataset.mechanic = "reload";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  reloadModel.step = 0;
  reloadModel.cleared = [];
  reloadModel.active = null;
  const required = Number(state.base_task?.steps_required || 6);
  app.innerHTML = `
    <section class="wide-captcha reload-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Finish the base task. Clear any verification interruptions.")}</h1>
      </header>
      <section class="reload-stage">
        <div class="reload-panel">
          <div class="reload-meter"><span></span></div>
          <button class="reload-lever" type="button" id="reload-lever">${text(state.base_task?.label || "RELOAD")}</button>
          <div class="reload-bolts"><span></span><span></span><span></span></div>
        </div>
        <div class="reload-modal" hidden></div>
      </section>
      <footer class="apple-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-reload">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;
  const meter = document.querySelector(".reload-meter span");
  const interruptions = state.interruptions || [];
  document.getElementById("reload-lever").addEventListener("click", () => {
    if (reloadModel.active || reloadModel.step >= required) return;
    reloadModel.step += 1;
    meter.style.width = reloadProgressWidth(required);
    const overlay = interruptions.find((item) => Number(item.step) === reloadModel.step && !reloadModel.cleared.includes(item.id));
    if (overlay) showReloadOverlay(state, overlay);
  });
  document.getElementById("submit-reload").addEventListener("click", async () => {
    const payload = {
      mechanic_id: state.mechanic_id,
      challenge_id: state.challenge_id,
      completed: reloadModel.step >= required,
      cleared_interruptions: reloadModel.cleared,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else {
        if (outcome.state) renderReloadInterruption(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });
  installCheatPanel();
}

function renderRotateWrongThing(state) {
  document.body.dataset.mechanic = "rotate";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  rotateModel.angle = Number(state.rotation?.initial_angle || 0);
  const offsets = state.rotation?.cue_offsets || {};
  app.innerHTML = `
    <section class="rotate-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Rotate the label upright.")}</h1>
      </header>
      <section class="rotate-stage">
        <div class="rotate-target-mark"></div>
        <div class="rotate-object" style="--angle:${rotateModel.angle}deg;--label-offset:${Number(offsets.label || 0)}deg;--icon-offset:${Number(offsets.icon || 0)}deg;--shadow-offset:${Number(offsets.shadow || 0)}deg">
          <div class="rotate-shadow">SHADOW</div>
          <div class="rotate-body">
            <span class="rotate-label">UP</span>
            <span class="rotate-icon"></span>
          </div>
        </div>
      </section>
      <footer class="apple-captcha-foot rotate-foot">
        <div class="rotate-controls">
          <button type="button" id="rotate-left">-15</button>
          <input id="rotate-slider" type="range" min="0" max="345" step="15" value="${rotateModel.angle}">
          <button type="button" id="rotate-right">+15</button>
        </div>
        <button class="apple-submit" type="button" id="submit-rotate">${text(state.submit_label || "VERIFY")}</button>
        <div class="apple-status readout" data-status="idle"></div>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;
  const object = document.querySelector(".rotate-object");
  const slider = document.getElementById("rotate-slider");
  const update = () => {
    rotateModel.angle = ((rotateModel.angle % 360) + 360) % 360;
    object.style.setProperty("--angle", `${rotateModel.angle}deg`);
    slider.value = String(rotateModel.angle);
  };
  slider.addEventListener("input", () => {
    rotateModel.angle = Number(slider.value);
    update();
  });
  document.getElementById("rotate-left").addEventListener("click", () => {
    rotateModel.angle -= 15;
    update();
  });
  document.getElementById("rotate-right").addEventListener("click", () => {
    rotateModel.angle += 15;
    update();
  });
  document.getElementById("submit-rotate").addEventListener("click", async () => {
    const payload = {
      mechanic_id: state.mechanic_id,
      challenge_id: state.challenge_id,
      angle: rotateModel.angle,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else {
        if (outcome.state) renderRotateWrongThing(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });
  installCheatPanel();
}

function markText(type) {
  if (type === "initial") return "PR";
  if (type === "stamp") return "OK";
  return "sig";
}

function renderBureaucraticSignatureTrap(state) {
  document.body.dataset.mechanic = "form";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  formModel.tool = "sign";
  formModel.marks = [];
  const form = state.form || {};
  app.innerHTML = `
    <section class="wide-captcha form-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Sign exactly where requested.")}</h1>
      </header>
      <section class="form-stage">
        <div class="form-paper">
          <h2>${text(form.title || "Verification Form")}</h2>
          ${(form.fields || []).map((field) => `
            <button class="form-field" type="button" data-field-id="${text(field.id)}" style="left:${Number(field.x)}px;top:${Number(field.y)}px;width:${Number(field.w)}px;height:${Number(field.h)}px">
              <span>${text(field.label)}</span>
            </button>
          `).join("")}
        </div>
      </section>
      <footer class="form-foot">
        <div class="form-tools">${(form.tools || ["sign", "initial", "stamp"]).map((tool, index) => `<button type="button" class="form-tool" data-tool="${text(tool)}" aria-pressed="${index === 0 ? "true" : "false"}">${text(tool).toUpperCase()}</button>`).join("")}</div>
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-form">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;
  document.querySelectorAll(".form-tool").forEach((button) => {
    button.addEventListener("click", () => {
      formModel.tool = button.dataset.tool;
      document.querySelectorAll(".form-tool").forEach((tool) => tool.setAttribute("aria-pressed", "false"));
      button.setAttribute("aria-pressed", "true");
    });
  });
  document.querySelectorAll(".form-field").forEach((field) => {
    field.addEventListener("click", () => {
      setReadout("", "idle");
      field.querySelectorAll(".form-mark").forEach((node) => node.remove());
      field.insertAdjacentHTML("beforeend", `<span class="form-mark mark-${text(formModel.tool)}">${markText(formModel.tool)}</span>`);
      formModel.marks = formModel.marks.filter((mark) => mark.field_id !== field.dataset.fieldId);
      formModel.marks.push({field_id: field.dataset.fieldId, mark_type: formModel.tool});
    });
  });
  document.getElementById("submit-form").addEventListener("click", async () => {
    const payload = {
      mechanic_id: state.mechanic_id,
      challenge_id: state.challenge_id,
      marks: formModel.marks,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else {
        if (outcome.state) renderBureaucraticSignatureTrap(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });
  installCheatPanel();
}

function drawWonkyText(canvas, challenge) {
  const ctx = canvas.getContext("2d");
  const width = canvas.width;
  const height = canvas.height;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#e8ece8";
  ctx.fillRect(0, 0, width, height);
  ctx.fillStyle = "rgba(38,45,48,0.08)";
  for (let x = 0; x < width; x += 18) ctx.fillRect(x, 0, 1, height);
  (challenge.noise || []).forEach((n) => {
    ctx.save();
    ctx.translate(Number(n.x), Number(n.y));
    ctx.rotate(Number(n.angle || 0));
    ctx.strokeStyle = "rgba(28,35,37,0.22)";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(-Number(n.w) / 2, 0);
    ctx.lineTo(Number(n.w) / 2, 0);
    ctx.stroke();
    ctx.restore();
  });
  ctx.font = "700 54px Georgia, serif";
  ctx.textBaseline = "middle";
  const token = text(challenge.token);
  const start = 54;
  [...token].forEach((ch, index) => {
    const meta = (challenge.char_offsets || [])[index] || {};
    const x = start + index * 72 + Number(meta.dx || 0);
    const y = height / 2 + Number(meta.dy || 0);
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(Number(meta.angle || 0));
    ctx.fillStyle = index % 2 ? "#253d56" : "#3d2d36";
    ctx.shadowColor = "rgba(198,78,70,0.45)";
    ctx.shadowBlur = 2;
    ctx.shadowOffsetX = 5;
    ctx.fillText(ch, 0, 0);
    if (meta.split) {
      ctx.fillStyle = "rgba(232,236,232,0.78)";
      ctx.fillRect(-4, -8, 48, 9);
      ctx.fillStyle = "rgba(31,37,40,0.7)";
      ctx.fillText(ch, 2, -3);
    }
    ctx.restore();
  });
  ctx.fillStyle = "rgba(190,52,50,0.22)";
  (challenge.decoys || []).forEach((decoy, index) => {
    ctx.save();
    ctx.translate(28 + index * 118, 24 + (index % 2) * 142);
    ctx.rotate(index % 2 ? -0.12 : 0.1);
    ctx.font = "700 19px Tahoma, sans-serif";
    ctx.fillText(decoy, 0, 0);
    ctx.restore();
  });
}

function renderWonkyText(state) {
  document.body.dataset.mechanic = "wonky-text";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  const challenge = state.text_challenge || {};
  app.innerHTML = `
    <section class="wide-captcha wonky-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Enter the warped word.")}</h1>
      </header>
      <section class="wonky-stage">
        <canvas class="wonky-canvas" width="640" height="190"></canvas>
        <input class="wonky-input" id="wonky-input" autocomplete="off" spellcheck="false">
      </section>
      <footer class="apple-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-wonky">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;
  drawWonkyText(document.querySelector(".wonky-canvas"), challenge);
  document.getElementById("submit-wonky").addEventListener("click", async () => {
    const payload = {
      mechanic_id: state.mechanic_id,
      challenge_id: state.challenge_id,
      text: document.getElementById("wonky-input").value,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else {
        if (outcome.state) renderWonkyText(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });
  installCheatPanel();
}

function temporalColor(index, changed) {
  const colors = ["#cf3f37", "#2f6d9b", "#3e7b47", "#8060a8", "#bd8b26", "#2e3742"];
  const changedColors = ["#f2d14b", "#42d3c8", "#ff6f91", "#9be15d", "#ffffff", "#e1a7ff"];
  return (changed ? changedColors : colors)[Math.abs(Number(index || 0)) % 6];
}

function temporalPosition(object, elapsed) {
  const t = elapsed / 1000;
  return {
    x: Number(object.x) + Math.sin(t * 1.4 + Number(object.color || 0)) * Number(object.vx || 0),
    y: Number(object.y) + Math.cos(t * 1.2 + Number(object.color || 0)) * Number(object.vy || 0),
  };
}

function drawTemporalObject(ctx, object, elapsed, selected) {
  const changed = elapsed >= Number(object.change_ms || 999999);
  const p = temporalPosition(object, elapsed);
  ctx.save();
  ctx.translate(p.x, p.y);
  ctx.strokeStyle = selected ? "#2f7df6" : "rgba(0,0,0,0.34)";
  ctx.lineWidth = selected ? 6 : 3;
  ctx.fillStyle = temporalColor(object.color, changed);
  const kind = object.kind;
  if (kind === "ring") {
    ctx.beginPath();
    ctx.arc(0, 0, changed ? 24 : 18, 0, Math.PI * 2);
    ctx.stroke();
  } else if (kind === "box") {
    ctx.fillRect(-21, -21, changed ? 50 : 42, changed ? 34 : 42);
    ctx.strokeRect(-21, -21, changed ? 50 : 42, changed ? 34 : 42);
  } else if (kind === "flag") {
    ctx.fillRect(-3, -28, 6, 56);
    ctx.beginPath();
    ctx.moveTo(3, -25);
    ctx.lineTo(changed ? 36 : 28, -14);
    ctx.lineTo(3, -3);
    ctx.closePath();
    ctx.fill();
  } else if (kind === "needle") {
    ctx.rotate(changed ? 1.2 : -0.4);
    ctx.fillRect(-3, -31, 6, 62);
    ctx.beginPath();
    ctx.arc(0, 0, 9, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.beginPath();
    ctx.moveTo(0, -25);
    ctx.lineTo(24, 0);
    ctx.lineTo(0, 25);
    ctx.lineTo(-24, 0);
    ctx.closePath();
    ctx.fill();
    if (changed) {
      ctx.fillStyle = "rgba(0,0,0,0.35)";
      ctx.fillRect(-18, -4, 36, 8);
    }
  }
  ctx.restore();
}

function drawTemporalCanvas(canvas) {
  const state = temporalModel.state;
  if (!state) return;
  const timeline = state.timeline || {};
  const now = performance.now();
  const elapsed = ((now - temporalModel.startedAt) % Number(timeline.duration_ms || 5200));
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = "#172126";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.strokeStyle = "rgba(255,255,255,0.13)";
  ctx.lineWidth = 1;
  for (let x = 24; x < canvas.width; x += 42) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x - 28, canvas.height);
    ctx.stroke();
  }
  (timeline.objects || []).forEach((object) => {
    drawTemporalObject(ctx, object, elapsed, temporalModel.selectedObjectId === object.id);
  });
  temporalModel.animationFrame = requestAnimationFrame(() => drawTemporalCanvas(canvas));
}

function renderTemporalMemory(state) {
  document.body.dataset.mechanic = "temporal";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  if (temporalModel.animationFrame) cancelAnimationFrame(temporalModel.animationFrame);
  temporalModel.state = state;
  temporalModel.startedAt = performance.now();
  temporalModel.selectedObjectId = null;
  app.innerHTML = `
    <section class="wide-captcha temporal-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="apple-captcha-head">
        <p>Weird CAPTCHA</p>
        <h1>${text(state.prompt || "Click the first object that changed.")}</h1>
      </header>
      <section class="temporal-stage">
        <canvas class="temporal-canvas" width="680" height="300"></canvas>
        ${(state.timeline?.objects || []).map((object) => `<button class="temporal-hit" type="button" data-object-id="${text(object.id)}"></button>`).join("")}
      </section>
      <footer class="apple-captcha-foot">
        <div class="apple-status readout" data-status="idle"></div>
        <button class="apple-submit" type="button" id="submit-temporal">${text(state.submit_label || "VERIFY")}</button>
      </footer>
      ${cheatPanelTemplate()}
    </section>
  `;
  const canvas = document.querySelector(".temporal-canvas");
  drawTemporalCanvas(canvas);
  canvas.addEventListener("click", (event) => {
    const p = canvasPointFromEvent(canvas, event);
    const elapsed = ((performance.now() - temporalModel.startedAt) % Number(state.timeline?.duration_ms || 5200));
    let best = null;
    let bestDistance = 9999;
    (state.timeline?.objects || []).forEach((object) => {
      const pos = temporalPosition(object, elapsed);
      const distance = Math.hypot(p.x - pos.x, p.y - pos.y);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = object;
      }
    });
    if (best && bestDistance <= 42) {
      temporalModel.selectedObjectId = best.id;
      setReadout("", "idle");
    }
  });
  document.getElementById("submit-temporal").addEventListener("click", async () => {
    const payload = {
      mechanic_id: state.mechanic_id,
      challenge_id: state.challenge_id,
      selected_object_id: temporalModel.selectedObjectId,
      user_agent: navigator.userAgent,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else {
        if (outcome.state) renderTemporalMemory(outcome.state);
        setReadout("FAIL", "error");
      }
    } catch (_error) {
      setReadout("FAIL", "error");
    }
  });
  installCheatPanel();
}

function ghostNoise(x, y, seed) {
  const a = Math.sin(x * 0.42 + y * 0.31 + seed * 0.013);
  const b = Math.sin(x * 0.17 - y * 0.53 + seed * 0.029);
  const c = Math.sin((x + y) * 0.71 + seed * 0.007);
  return Math.max(0, Math.min(1, 0.5 + a * 0.23 + b * 0.17 + c * 0.1));
}

function ghostPatternMask(theme, x, y) {
  const nx = x / 216 - 0.5;
  const ny = y / 216 - 0.5;
  const ring = (cx, cy, radius, thickness) => Math.abs(Math.hypot(nx - cx, ny - cy) - radius) < thickness;
  const line = (x1, y1, x2, y2, width) => {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const length2 = dx * dx + dy * dy;
    const t = Math.max(0, Math.min(1, ((nx - x1) * dx + (ny - y1) * dy) / length2));
    return Math.hypot(nx - (x1 + t * dx), ny - (y1 + t * dy)) < width;
  };
  if (theme === "orbit") {
    return ring(0, 0, 0.28, 0.045) || ring(0, 0, 0.1, 0.045) || line(-0.45, 0.26, 0.45, -0.22, 0.035);
  }
  if (theme === "signal") {
    return line(-0.34, 0.36, -0.12, -0.35, 0.045) || line(-0.12, -0.35, 0.1, 0.36, 0.045) || line(0.1, 0.36, 0.34, -0.35, 0.045) || ring(0, 0.28, 0.1, 0.035);
  }
  if (theme === "totem") {
    return ring(0, -0.03, 0.34, 0.05) || ring(-0.13, -0.08, 0.045, 0.03) || ring(0.13, -0.08, 0.045, 0.03) || line(-0.15, 0.15, 0.15, 0.15, 0.035);
  }
  if (theme === "constellation") {
    return line(-0.4, 0.24, -0.08, -0.32, 0.04) || line(-0.08, -0.32, 0.32, 0.28, 0.04) || line(0.32, 0.28, -0.32, -0.02, 0.04) || ring(-0.4, 0.24, 0.05, 0.035) || ring(0.32, 0.28, 0.05, 0.035);
  }
  if (theme === "hourglass") {
    return line(-0.3, -0.35, 0.3, -0.35, 0.04) || line(-0.3, 0.35, 0.3, 0.35, 0.04) || line(-0.3, -0.35, 0.3, 0.35, 0.04) || line(0.3, -0.35, -0.3, 0.35, 0.04);
  }
  return line(-0.38, 0.2, -0.28, -0.24, 0.045) || line(-0.28, -0.24, 0, 0.02, 0.045) || line(0, 0.02, 0.28, -0.24, 0.045) || line(0.28, -0.24, 0.38, 0.2, 0.045) || line(-0.38, 0.2, 0.38, 0.2, 0.045);
}

function drawGhostCanvas(canvas, sourceIndex, frame, visual, full = false, pieceSeed = null) {
  const ctx = canvas.getContext("2d");
  const width = canvas.width;
  const height = canvas.height;
  const image = ctx.createImageData(width, height);
  const tileRow = Math.floor(sourceIndex / 3);
  const tileCol = sourceIndex % 3;
  const offset = frame * Number(visual.scroll_speed || 1.8);
  const seed = full ? Number(visual.global_seed || 1) : Number(pieceSeed || visual.global_seed || 1);
  for (let py = 0; py < height; py += 1) {
    for (let px = 0; px < width; px += 1) {
      const gx = full ? (px / width) * 216 : ((tileCol + px / width) / 3) * 216;
      const gy = full ? (py / height) * 216 : ((tileRow + py / height) / 3) * 216;
      const inside = ghostPatternMask(visual.theme, gx, gy);
      const sampleY = inside ? gy - offset : gy + offset;
      const value = ghostNoise(gx, sampleY, seed);
      const gray = Math.round(55 + value * 170);
      const index = (py * width + px) * 4;
      image.data[index] = gray;
      image.data[index + 1] = gray + 2;
      image.data[index + 2] = gray + 4;
      image.data[index + 3] = 255;
    }
  }
  ctx.putImageData(image, 0, 0);
}

function animateGhostJigsaw() {
  if (!ghostModel.state || document.body.dataset.mechanic !== "ghost-jigsaw") return;
  ghostModel.frame += 0.48;
  const visual = ghostModel.state.visual || {};
  const reference = document.querySelector(".ghost-reference");
  if (reference) drawGhostCanvas(reference, 0, ghostModel.frame, visual, true);
  document.querySelectorAll(".ghost-piece").forEach((piece) => {
    const source = Number(piece.dataset.sourceIndex);
    const canvas = piece.querySelector("canvas");
    if (canvas) drawGhostCanvas(canvas, source, ghostModel.frame + Number(piece.dataset.phase || 0), visual, false, Number(piece.dataset.noiseSeed));
  });
  ghostModel.animationFrame = requestAnimationFrame(animateGhostJigsaw);
}

function ghostDropTarget(target, pieceId) {
  const piece = document.querySelector(`.ghost-piece[data-piece-id="${CSS.escape(pieceId)}"]`);
  const bank = document.querySelector(".ghost-piece-bank");
  if (!piece || !bank) return;
  if (target.classList.contains("ghost-slot")) {
    const existing = target.querySelector(".ghost-piece");
    if (existing && existing !== piece) {
      delete ghostModel.placements[existing.dataset.pieceId];
      bank.appendChild(existing);
    }
    target.appendChild(piece);
    ghostModel.placements[pieceId] = Number(target.dataset.slotIndex);
  } else {
    bank.appendChild(piece);
    delete ghostModel.placements[pieceId];
  }
  setReadout("", "idle");
}

function renderMotionOnlyGhostJigsaw(state) {
  if (ghostModel.animationFrame) cancelAnimationFrame(ghostModel.animationFrame);
  document.body.dataset.mechanic = "ghost-jigsaw";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  ghostModel.state = state;
  ghostModel.placements = {};
  ghostModel.frame = 0;
  app.innerHTML = `
    <section class="interaction-captcha ghost-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="interaction-head ghost-head"><p>MOTION CHECK / 01</p><h1>${text(state.prompt)}</h1></header>
      <section class="ghost-stage">
        <div class="ghost-reference-wrap"><span>LIVE REFERENCE</span><canvas class="ghost-reference" width="168" height="168"></canvas></div>
        <div class="ghost-board" aria-label="jigsaw destination">
          ${Array.from({length: 9}, (_, index) => `<div class="ghost-slot" data-slot-index="${index}" aria-label="position ${index + 1}"></div>`).join("")}
        </div>
        <div class="ghost-piece-bank" aria-label="moving jigsaw pieces">
          ${(state.pieces || []).map((piece) => `<div class="ghost-piece" draggable="true" data-piece-id="${text(piece.id)}" data-source-index="${text(piece.source_index)}" data-noise-seed="${text(piece.noise_seed)}" data-phase="${text(piece.phase)}"><canvas width="58" height="58"></canvas></div>`).join("")}
        </div>
      </section>
      <footer class="interaction-foot"><div class="readout" data-status="idle"></div><button class="interaction-submit" id="submit-ghost" type="button">${text(state.submit_label || "VERIFY")}</button></footer>
      ${cheatPanelTemplate()}
    </section>`;
  document.querySelectorAll(".ghost-piece").forEach((piece) => {
    piece.addEventListener("dragstart", (event) => event.dataTransfer.setData("text/plain", piece.dataset.pieceId));
  });
  document.querySelectorAll(".ghost-slot, .ghost-piece-bank").forEach((target) => {
    target.addEventListener("dragover", (event) => event.preventDefault());
    target.addEventListener("drop", (event) => {
      event.preventDefault();
      ghostDropTarget(target, event.dataTransfer.getData("text/plain"));
    });
  });
  document.getElementById("submit-ghost").addEventListener("click", async () => {
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, placements: ghostModel.placements})});
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else if (outcome.passed === false) { if (outcome.state) renderMotionOnlyGhostJigsaw(outcome.state); setReadout("FAIL", "error"); }
    } catch (_error) { setReadout("FAIL", "error"); }
  });
  animateGhostJigsaw();
  installCheatPanel();
}

function constellationPoint(canvas, event) {
  const box = canvas.getBoundingClientRect();
  return {x: (event.clientX - box.left) * canvas.width / box.width, y: (event.clientY - box.top) * canvas.height / box.height};
}

function drawConstellationCanvas(canvas, now = performance.now()) {
  const state = constellationModel.state;
  if (!state) return;
  const surface = state.surface || {};
  const ctx = canvas.getContext("2d");
  const pointer = constellationModel.pointer || constellationModel.pendingClick;
  const solution = surface.solution || {x: 0, y: 0};
  const bg = ctx.createRadialGradient(canvas.width * 0.52, canvas.height * 0.42, 20, canvas.width * 0.5, canvas.height * 0.5, canvas.width * 0.65);
  bg.addColorStop(0, "#112b30"); bg.addColorStop(0.55, "#061418"); bg.addColorStop(1, "#020608");
  ctx.fillStyle = bg; ctx.fillRect(0, 0, canvas.width, canvas.height);
  let progress = 0;
  let falseProgress = 0;
  if (pointer) {
    const distance = Math.hypot(pointer.x - solution.x, pointer.y - solution.y);
    progress = Math.exp(-(distance * distance) / (2 * 112 * 112));
    (surface.decoys || []).forEach((decoy) => {
      const d = Math.hypot(pointer.x - decoy.x, pointer.y - decoy.y);
      falseProgress = Math.max(falseProgress, 0.34 * Math.exp(-(d * d) / (2 * 72 * 72)));
    });
  }
  const plotted = [];
  (surface.stars || []).forEach((star, index) => {
    const twinkle = Math.sin(now / 410 + Number(star.twinkle || 0));
    let x = Number(star.base_x);
    let y = Number(star.base_y);
    if (!star.noise) {
      const targetX = Number(star.target_x);
      const targetY = Number(star.target_y);
      x += (targetX - x) * progress;
      y += (targetY - y) * progress;
      if (falseProgress > progress) {
        x += ((canvas.width - targetX) - x) * falseProgress;
        y += ((targetY + Math.sin(index * 1.7) * 28) - y) * falseProgress;
      }
    } else {
      x += Math.sin(now / 900 + index) * 3;
      y += Math.cos(now / 760 + index * 0.7) * 3;
    }
    plotted.push({x, y, noise: star.noise});
    ctx.fillStyle = star.noise ? `rgba(130,169,158,${0.3 + twinkle * 0.08})` : `rgba(198,255,214,${0.72 + twinkle * 0.18})`;
    ctx.beginPath(); ctx.arc(x, y, star.noise ? 1.25 : 1.8 + progress * 0.55, 0, Math.PI * 2); ctx.fill();
  });
  if (progress > 0.78) {
    ctx.strokeStyle = `rgba(104,255,165,${(progress - 0.78) * 1.8})`;
    ctx.lineWidth = 0.7;
    ctx.beginPath();
    plotted.filter((point) => !point.noise).forEach((point, index) => index ? ctx.lineTo(point.x, point.y) : ctx.moveTo(point.x, point.y));
    ctx.stroke();
  }
  if (constellationModel.pendingClick) {
    ctx.strokeStyle = "#e9ff8f"; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(constellationModel.pendingClick.x, constellationModel.pendingClick.y, 11, 0, Math.PI * 2); ctx.stroke();
  }
  constellationModel.animationFrame = requestAnimationFrame((time) => drawConstellationCanvas(canvas, time));
}

function renderCursorConstellationHunt(state) {
  if (constellationModel.animationFrame) cancelAnimationFrame(constellationModel.animationFrame);
  document.body.dataset.mechanic = "constellation-hunt";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  constellationModel.state = state; constellationModel.pointer = null; constellationModel.pendingClick = null;
  const surface = state.surface || {};
  app.innerHTML = `
    <section class="interaction-captcha constellation-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="interaction-head constellation-head"><p>ACTIVE VISION / 02</p><h1>${text(state.prompt)}</h1></header>
      <section class="constellation-stage"><canvas class="constellation-canvas" width="${text(surface.width || 680)}" height="${text(surface.height || 410)}"></canvas><div class="constellation-reticle"></div></section>
      <footer class="interaction-foot"><div class="readout" data-status="idle"></div><button class="interaction-submit" id="submit-constellation" type="button">${text(state.submit_label || "VERIFY")}</button></footer>
      ${cheatPanelTemplate()}
    </section>`;
  const canvas = document.querySelector(".constellation-canvas");
  canvas.addEventListener("mousemove", (event) => { constellationModel.pointer = constellationPoint(canvas, event); });
  canvas.addEventListener("mouseleave", () => { constellationModel.pointer = null; });
  canvas.addEventListener("click", (event) => { constellationModel.pendingClick = constellationPoint(canvas, event); setReadout("", "idle"); });
  drawConstellationCanvas(canvas);
  document.getElementById("submit-constellation").addEventListener("click", async () => {
    const click = constellationModel.pendingClick || {x: -999, y: -999};
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, click: {x: Number(click.x.toFixed(2)), y: Number(click.y.toFixed(2))}})});
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else if (outcome.passed === false) { if (outcome.state) renderCursorConstellationHunt(outcome.state); setReadout("FAIL", "error"); }
    } catch (_error) { setReadout("FAIL", "error"); }
  });
  installCheatPanel();
}

function foodArt(kind) {
  return `<span class="food-art food-art-${text(kind)}"><i></i><b></b></span><span class="food-name">${text(kind)}</span>`;
}

function grillFoodState(food, record, now) {
  if (!record || record.place === "prep") return "raw";
  if (record.place === "tray") return record.duration >= food.target_ms - food.tolerance_ms && record.duration <= food.target_ms + food.tolerance_ms ? "served" : "spoiled";
  const elapsed = now - record.startedAt;
  if (elapsed < food.target_ms - food.tolerance_ms) return elapsed < food.target_ms * 0.45 ? "raw" : "warming";
  if (elapsed <= food.target_ms + food.tolerance_ms) return "ready";
  if (elapsed <= food.target_ms + food.tolerance_ms * 2.2) return "burning";
  return "burnt";
}

function animateGrillmaster(now = performance.now()) {
  if (!grillModel.state || document.body.dataset.mechanic !== "grillmaster") return;
  (grillModel.state.foods || []).forEach((food) => {
    const node = document.querySelector(`.grill-food[data-food-id="${CSS.escape(food.id)}"]`);
    if (node) node.dataset.cookState = grillFoodState(food, grillModel.records[food.id], now);
  });
  grillModel.animationFrame = requestAnimationFrame(animateGrillmaster);
}

function renderParallelGrillmaster(state) {
  if (grillModel.animationFrame) cancelAnimationFrame(grillModel.animationFrame);
  document.body.dataset.mechanic = "grillmaster";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  grillModel.state = state; grillModel.records = {};
  (state.foods || []).forEach((food) => { grillModel.records[food.id] = {place: "prep", startedAt: null, duration: null}; });
  app.innerHTML = `
    <section class="interaction-captcha grill-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="interaction-head grill-head"><p>DINNER RUSH / 03</p><h1>${text(state.prompt)}</h1></header>
      <section class="grill-stage">
        <div class="grill-zone grill-prep" data-drop-zone="prep"><span class="zone-label">RAW ORDER</span>${(state.foods || []).map((food) => `<div class="grill-food" draggable="true" data-food-id="${text(food.id)}" data-kind="${text(food.kind)}" data-cook-state="raw">${foodArt(food.kind)}</div>`).join("")}</div>
        <div class="grill-zone grill-fire" data-drop-zone="grill"><span class="zone-label">LIVE FIRE</span><div class="grill-bars"></div><div class="heat-wave heat-wave-a"></div><div class="heat-wave heat-wave-b"></div></div>
        <div class="grill-zone grill-tray" data-drop-zone="tray"><span class="zone-label">SERVING TRAY</span></div>
      </section>
      <footer class="interaction-foot"><div class="readout" data-status="idle"></div><button class="interaction-submit grill-submit" id="submit-grill" type="button">${text(state.submit_label || "SERVE")}</button></footer>
      ${cheatPanelTemplate()}
    </section>`;
  document.querySelectorAll(".grill-food").forEach((foodNode) => {
    foodNode.addEventListener("dragstart", (event) => event.dataTransfer.setData("text/plain", foodNode.dataset.foodId));
  });
  document.querySelectorAll(".grill-zone").forEach((zone) => {
    zone.addEventListener("dragover", (event) => event.preventDefault());
    zone.addEventListener("drop", (event) => {
      event.preventDefault();
      const id = event.dataTransfer.getData("text/plain");
      const node = document.querySelector(`.grill-food[data-food-id="${CSS.escape(id)}"]`);
      const record = grillModel.records[id];
      const destination = zone.dataset.dropZone;
      if (!node || !record) return;
      if (destination === "grill" && record.place === "prep") {
        record.place = "grill"; record.startedAt = performance.now(); zone.appendChild(node);
      } else if (destination === "tray" && record.place === "grill") {
        record.duration = performance.now() - record.startedAt; record.place = "tray"; zone.appendChild(node);
      }
      setReadout("", "idle");
    });
  });
  document.getElementById("submit-grill").addEventListener("click", async () => {
    const durations = {};
    Object.entries(grillModel.records).forEach(([id, record]) => { if (record.place === "tray" && record.duration != null) durations[id] = Math.round(record.duration); });
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, durations_ms: durations})});
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else if (outcome.passed === false) { if (outcome.state) renderParallelGrillmaster(outcome.state); setReadout("FAIL", "error"); }
    } catch (_error) { setReadout("FAIL", "error"); }
  });
  animateGrillmaster();
  installCheatPanel();
}

function updateRotatingKeyboardDisplay(target) {
  const display = document.querySelector(".rotating-entry");
  if (!display) return;
  display.innerHTML = target.split("").map((_, index) => `<span data-filled="${index < rotatingKeyboardModel.input.length ? "true" : "false"}">${index < rotatingKeyboardModel.input.length ? text(rotatingKeyboardModel.input[index]) : "·"}</span>`).join("");
}

function renderRotatingKeyboard(state) {
  document.body.dataset.mechanic = "rotating-keyboard";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  rotatingKeyboardModel.input = "";
  const keyboard = state.keyboard || {};
  app.innerHTML = `
    <section class="interaction-captcha rotating-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}">
      <header class="interaction-head rotating-head"><p>COORDINATE CHECK / 04</p><h1>${text(state.prompt)}</h1></header>
      <section class="rotating-stage">
        <div class="rotating-fixed"><span>CONFIRM</span><strong>${text(keyboard.target)}</strong><div class="rotating-entry"></div></div>
        <div class="rotating-perspective"><div class="rotating-deck" style="--spin-direction:${Number(keyboard.direction || 1)};--spin-duration:${Number(keyboard.duration_ms || 9400)}ms">
          ${(keyboard.rows || []).map((row) => `<div class="rotating-row">${row.split("").map((key) => `<button type="button" class="rotating-key" data-key="${text(key)}">${text(key)}</button>`).join("")}</div>`).join("")}
          <div class="rotating-row rotating-row-short"><button type="button" class="rotating-key rotating-delete" data-key="BACKSPACE">ERASE</button></div>
        </div></div>
      </section>
      <footer class="interaction-foot"><div class="readout" data-status="idle"></div><button class="interaction-submit rotating-submit" id="submit-rotating" type="button">${text(state.submit_label || "CONFIRM")}</button></footer>
      ${cheatPanelTemplate()}
    </section>`;
  const deck = document.querySelector(".rotating-deck");
  updateRotatingKeyboardDisplay(keyboard.target || "");
  document.querySelectorAll(".rotating-key").forEach((button) => {
    button.addEventListener("click", () => {
      const key = button.dataset.key;
      if (key === "BACKSPACE") rotatingKeyboardModel.input = rotatingKeyboardModel.input.slice(0, -1);
      else if (rotatingKeyboardModel.input.length < String(keyboard.target || "").length) rotatingKeyboardModel.input += key;
      if (rotatingKeyboardModel.input.length > 0) deck.classList.add("is-spinning");
      updateRotatingKeyboardDisplay(keyboard.target || "");
      setReadout("", "idle");
    });
  });
  document.getElementById("submit-rotating").addEventListener("click", async () => {
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, text: rotatingKeyboardModel.input})});
      const outcome = await response.json();
      if (outcome.passed === true) setReadout("PASS", "passed");
      else if (outcome.passed === false) { if (outcome.state) renderRotatingKeyboard(outcome.state); setReadout("FAIL", "error"); }
    } catch (_error) { setReadout("FAIL", "error"); }
  });
  installCheatPanel();
}

function animateSlotReels(now = performance.now()) {
  if (!slotModel.state || document.body.dataset.mechanic !== "slot-reel") return;
  const elapsed = now - slotModel.startedAt;
  (slotModel.state.reels || []).forEach((reel, index) => {
    const node = document.querySelector(`.slot-reel[data-reel-id="${CSS.escape(reel.id)}"]`);
    if (!node) return;
    const frozen = slotModel.frozen.includes(reel.id);
    const tokenIndex = frozen ? reel.tokens.indexOf(reel.target) : (Math.floor(elapsed / reel.interval_ms) + Number(reel.phase || 0)) % reel.tokens.length;
    node.dataset.tokenIndex = String(tokenIndex);
    node.dataset.active = String(index === slotModel.frozen.length && !frozen);
    node.dataset.frozen = String(frozen);
    const symbol = node.querySelector(".slot-symbol");
    if (symbol) symbol.textContent = reel.tokens[tokenIndex];
  });
  slotModel.animationFrame = requestAnimationFrame(animateSlotReels);
}

function updateSlotStrikes(maxStrikes) {
  const counter = document.querySelector(".slot-strikes-count");
  if (counter) counter.textContent = `${slotModel.wrongKeys}/${maxStrikes}`;
  document.querySelectorAll(".slot-strike-pip").forEach((pip, index) => {
    pip.dataset.active = String(index < slotModel.wrongKeys);
  });
}

async function submitSlotAttempt(state) {
  if (slotModel.submitting) return;
  slotModel.submitting = true;
  try {
    const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, captured_sequence: slotModel.captured, frozen_reel_ids: slotModel.frozen, wrong_keys: slotModel.wrongKeys})});
    const outcome = await response.json();
    if (outcome.passed === true) {
      setReadout("PASS", "passed");
    } else if (outcome.passed === false) {
      if (outcome.state) renderSlotReelCapture(outcome.state);
      setReadout("FAIL", "error");
    }
  } catch (_error) {
    slotModel.submitting = false;
    setReadout("FAIL", "error");
  }
}

function renderSlotReelCapture(state) {
  if (slotModel.animationFrame) cancelAnimationFrame(slotModel.animationFrame);
  if (slotModel.keyHandler) window.removeEventListener("keydown", slotModel.keyHandler);
  document.body.dataset.mechanic = "slot-reel";
  document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  const maxStrikes = Number(state.max_strikes || 3);
  slotModel.state = state; slotModel.startedAt = performance.now(); slotModel.frozen = []; slotModel.captured = ""; slotModel.wrongKeys = 0; slotModel.submitting = false;
  app.innerHTML = `
    <section class="interaction-captcha slot-captcha" data-mechanic="${text(state.mechanic_id)}" data-challenge-id="${text(state.challenge_id)}" tabindex="0">
      <header class="interaction-head slot-head"><p>LIVE CAPTURE / 05</p><h1>${text(state.prompt)}</h1></header>
      <section class="slot-stage"><div class="slot-machine-top"><span>CAPTURE</span><div class="slot-status-rail"><div class="slot-lights"></div><div class="slot-strikes" aria-live="polite"><span>STRIKES</span><strong class="slot-strikes-count">0/${maxStrikes}</strong>${Array.from({length: maxStrikes}, () => '<i class="slot-strike-pip" data-active="false"></i>').join("")}</div></div></div><div class="slot-reels">
        ${(state.reels || []).map((reel, index) => `<div class="slot-reel" data-reel-id="${text(reel.id)}" data-active="${index === 0}" data-frozen="false"><span class="slot-arrow">▼</span><div class="slot-window"><span class="slot-symbol">◆</span></div><span class="slot-index">0${index + 1}</span></div>`).join("")}
      </div><div class="slot-captured">${(state.reels || []).map(() => "<span>·</span>").join("")}</div></section>
      <footer class="interaction-foot slot-foot"><div class="readout" data-status="idle"></div><button class="interaction-submit slot-submit" id="submit-slot" type="button">${text(state.submit_label || "VERIFY")}</button></footer>
      ${cheatPanelTemplate()}
    </section>`;
  slotModel.keyHandler = (event) => {
    if (event.repeat || slotModel.submitting || !/^[a-z0-9]$/i.test(event.key)) return;
    const index = slotModel.frozen.length;
    const reel = (state.reels || [])[index];
    if (!reel) return;
    const node = document.querySelector(`.slot-reel[data-reel-id="${CSS.escape(reel.id)}"]`);
    const token = reel.tokens[Number(node?.dataset.tokenIndex || -1)];
    if (token === reel.target && event.key.toUpperCase() === reel.target) {
      slotModel.frozen.push(reel.id); slotModel.captured += reel.target;
      const cells = document.querySelectorAll(".slot-captured span");
      if (cells[index]) cells[index].textContent = reel.target;
      document.querySelector(".slot-captcha")?.classList.remove("slot-shock");
      setReadout("", "idle");
    } else {
      slotModel.wrongKeys += 1;
      updateSlotStrikes(maxStrikes);
      setReadout("", "idle");
      const panel = document.querySelector(".slot-captcha");
      panel?.classList.remove("slot-shock"); void panel?.offsetWidth; panel?.classList.add("slot-shock");
      if (slotModel.wrongKeys >= maxStrikes) {
        window.removeEventListener("keydown", slotModel.keyHandler);
        setTimeout(() => submitSlotAttempt(state), 260);
      }
    }
  };
  window.addEventListener("keydown", slotModel.keyHandler);
  document.querySelector(".slot-captcha").focus();
  animateSlotReels();
  document.getElementById("submit-slot").addEventListener("click", () => submitSlotAttempt(state));
  installCheatPanel();
}

function dominoAxisAngle(angleDegrees) {
  return ((Number(angleDegrees || 0) + 90) % 180 + 180) % 180 - 90;
}

function destroyDominoPhysics() {
  if (dominoModel.runTimer) clearTimeout(dominoModel.runTimer);
  if (dominoModel.runner && window.Matter) Matter.Runner.stop(dominoModel.runner);
  if (dominoModel.render && window.Matter) Matter.Render.stop(dominoModel.render);
  if (dominoModel.bellAudioContext && dominoModel.bellAudioContext.state !== "closed") dominoModel.bellAudioContext.close().catch(() => {});
  dominoModel.runTimer = null; dominoModel.runner = null; dominoModel.render = null; dominoModel.engine = null;
  dominoModel.bellBody = null; dominoModel.clapperBody = null; dominoModel.bellAnchor = null; dominoModel.bellInitial = null; dominoModel.bellAudioContext = null;
}

function snapshotDominoBodies() {
  const snapshot = {};
  dominoModel.dominoIds.forEach((id) => {
    const body = dominoModel.bodiesById[id];
    snapshot[id] = {x: body.position.x, y: body.position.y, angle: body.angle};
  });
  return snapshot;
}

function setDominoControls() {
  const editing = dominoModel.mode === "edit";
  const hasSelection = editing && Boolean(dominoModel.selectedId);
  ["domino-rotate-left", "domino-flip", "domino-rotate-right"].forEach((id) => { const button = document.getElementById(id); if (button) button.disabled = !hasSelection; });
  const run = document.getElementById("domino-run"); if (run) run.disabled = !editing;
  const reset = document.getElementById("domino-reset"); if (reset) reset.disabled = editing && !Object.keys(dominoModel.preRun).length;
  const submit = document.getElementById("domino-submit");
  if (submit) {
    const ready = dominoModel.mode === "result" && dominoRunPassed();
    submit.disabled = !ready; submit.classList.toggle("is-ready", ready); submit.textContent = ready ? "CERTIFY PASS →" : String(dominoModel.state?.submit_label || "CERTIFY");
  }
  const selected = document.querySelector(".domino-selected");
  if (selected) {
    if (!dominoModel.selectedId) selected.textContent = "SELECT A COLORED DOMINO";
    else {
      const body = dominoModel.bodiesById[dominoModel.selectedId];
      selected.textContent = `SELECTED / ${String(body?.plugin?.domino?.color || "piece").toUpperCase()} / AXIS ${dominoAxisAngle((body?.angle || 0) * 180 / Math.PI).toFixed(0)}°`;
    }
  }
}

function dominoBellId() {
  return String(dominoModel.state?.board?.bell_body_id || "bell-body");
}

function dominoRunPassed() {
  return dominoModel.physicsPassed && dominoModel.bellPeakAngle >= 0.03;
}

function setDominoVerdict(outcome = "", title = "", detail = "") {
  const verdict = document.querySelector(".domino-verdict"); if (!verdict) return;
  verdict.className = `domino-verdict${outcome ? ` is-${outcome}` : ""}`;
  verdict.innerHTML = outcome ? `<strong>${text(title)}</strong><span>${text(detail)}</span>` : "";
}

function armDominoBellAudio() {
  try {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;
    if (!dominoModel.bellAudioContext || dominoModel.bellAudioContext.state === "closed") dominoModel.bellAudioContext = new AudioContext();
    if (dominoModel.bellAudioContext.state === "suspended") dominoModel.bellAudioContext.resume().catch(() => {});
  } catch (_error) {
    dominoModel.bellAudioContext = null;
  }
}

function ringDominoBellSound() {
  if (dominoModel.bellSoundPlayed) return;
  dominoModel.bellSoundPlayed = true;
  const audio = dominoModel.bellAudioContext; if (!audio || audio.state === "closed") return;
  const now = audio.currentTime;
  const gain = audio.createGain(); gain.gain.setValueAtTime(0.0001, now); gain.gain.exponentialRampToValueAtTime(0.18, now + 0.012); gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.25); gain.connect(audio.destination);
  [[740, 1], [1113, 0.38], [1487, 0.19]].forEach(([frequency, level]) => {
    const oscillator = audio.createOscillator(); const partial = audio.createGain();
    oscillator.type = "sine"; oscillator.frequency.setValueAtTime(frequency, now); oscillator.frequency.exponentialRampToValueAtTime(frequency * 0.994, now + 1.15);
    partial.gain.value = level; oscillator.connect(partial); partial.connect(gain); oscillator.start(now); oscillator.stop(now + 1.3);
  });
}

function dominoConnectedToBell() {
  const first = String(dominoModel.state?.board?.first_body_id || "");
  if (!first) return false;
  const graph = new Map();
  dominoModel.collisionPairs.forEach((key) => {
    const [left, right] = key.split("|");
    if (!graph.has(left)) graph.set(left, new Set());
    if (!graph.has(right)) graph.set(right, new Set());
    graph.get(left).add(right); graph.get(right).add(left);
  });
  const seen = new Set([first]); const queue = [first];
  while (queue.length) {
    const current = queue.shift();
    (graph.get(current) || []).forEach((neighbor) => { if (!seen.has(neighbor)) { seen.add(neighbor); queue.push(neighbor); } });
  }
  return dominoModel.dominoIds.every((id) => seen.has(id)) && seen.has(dominoBellId());
}

function recordDominoCollisions(event) {
  const bellId = dominoBellId(); const allowed = new Set([...dominoModel.dominoIds, bellId]);
  event.pairs.forEach((pair) => {
    const left = pair.bodyA.label; const right = pair.bodyB.label;
    if (!allowed.has(left) || !allowed.has(right)) return;
    dominoModel.collisionPairs.add([left, right].sort().join("|"));
    if (left === bellId || right === bellId) {
      dominoModel.bellHit = true;
      ringDominoBellSound();
    }
  });
  if (!dominoModel.physicsPassed && dominoModel.bellHit && dominoConnectedToBell()) {
    dominoModel.physicsPassed = true;
    const trace = document.querySelector(".domino-trace"); if (trace) trace.textContent = "BELL CONTACT / VALIDATING PHYSICAL SWING…";
    setReadout("BELL HIT — VALIDATING…", "pending");
    if (dominoModel.runTimer) clearTimeout(dominoModel.runTimer);
    dominoModel.runTimer = setTimeout(finishDominoRun, 1200);
    setDominoControls();
  }
}

function drawDominoDetails() {
  const render = dominoModel.render; if (!render) return;
  const context = render.context;
  dominoModel.dominoIds.forEach((id) => {
    const body = dominoModel.bodiesById[id]; const meta = body.plugin.domino;
    context.save(); context.translate(body.position.x, body.position.y); context.rotate(body.angle);
    if (id === dominoModel.selectedId && dominoModel.mode === "edit") {
      context.strokeStyle = "#fff4b5"; context.lineWidth = 2; context.setLineDash([4, 3]); context.strokeRect(-12, -42, 24, 84); context.setLineDash([]);
    }
    context.fillStyle = meta.loose ? (meta.color === "saffron" ? "#30230a" : "#f8ead2") : "#443d30";
    context.textAlign = "center"; context.textBaseline = "middle";
    if (meta.loose) {
      context.beginPath(); context.arc(0, -17, 3.2, 0, Math.PI * 2); context.fill(); context.beginPath(); context.arc(0, 17, 3.2, 0, Math.PI * 2); context.fill();
    } else {
      context.font = "700 9px Courier New"; context.fillText(String(meta.index + 1).padStart(2, "0"), 0, 0);
    }
    context.restore();
  });
  const bell = dominoModel.bellBody; const clapper = dominoModel.clapperBody; const anchor = dominoModel.bellAnchor;
  if (!bell || !clapper || !anchor) return;
  const initialAngle = Number(dominoModel.bellInitial?.body?.angle || 0);
  const swingAngle = Math.atan2(Math.sin(bell.angle - initialAngle), Math.cos(bell.angle - initialAngle));
  if (dominoModel.mode !== "edit") dominoModel.bellPeakAngle = Math.max(dominoModel.bellPeakAngle, Math.abs(swingAngle));
  const top = Matter.Vector.add(bell.position, Matter.Vector.rotate({x: 0, y: -22}, bell.angle));
  const clapperJoint = Matter.Vector.add(bell.position, Matter.Vector.rotate({x: 0, y: 7}, bell.angle));
  context.save();
  context.strokeStyle = "#5a411e"; context.lineWidth = 3; context.lineCap = "round";
  context.beginPath(); context.moveTo(anchor.x - 13, anchor.y - 3); context.lineTo(anchor.x + 13, anchor.y - 3); context.stroke();
  context.lineWidth = 2; context.beginPath(); context.moveTo(anchor.x, anchor.y); context.lineTo(top.x, top.y); context.stroke();
  context.restore();
  context.save(); context.translate(bell.position.x, bell.position.y); context.rotate(bell.angle);
  if (dominoModel.bellHit) { context.shadowColor = "#f7cb55"; context.shadowBlur = 13; }
  const bellGradient = context.createLinearGradient(-26, 0, 26, 0); bellGradient.addColorStop(0, "#714317"); bellGradient.addColorStop(0.48, "#f0c64e"); bellGradient.addColorStop(1, "#8b571c");
  context.beginPath(); context.moveTo(-13, -22); context.quadraticCurveTo(-20, -2, -26, 21); context.lineTo(26, 21); context.quadraticCurveTo(20, -2, 13, -22); context.closePath();
  context.fillStyle = bellGradient; context.fill(); context.strokeStyle = "#4f3215"; context.lineWidth = 2.3; context.stroke();
  context.beginPath(); context.moveTo(-28, 21); context.quadraticCurveTo(0, 26, 28, 21); context.strokeStyle = "#553515"; context.lineWidth = 5; context.stroke();
  context.beginPath(); context.moveTo(-11, -23); context.lineTo(11, -23); context.strokeStyle = "#5b3917"; context.lineWidth = 5; context.stroke();
  context.restore();
  context.save(); context.strokeStyle = "#5d3917"; context.lineWidth = 2.2; context.beginPath(); context.moveTo(clapperJoint.x, clapperJoint.y); context.lineTo(clapper.position.x, clapper.position.y); context.stroke();
  context.beginPath(); context.arc(clapper.position.x, clapper.position.y, 6.5, 0, Math.PI * 2); context.fillStyle = "#6c4019"; context.fill(); context.strokeStyle = "#3f2813"; context.lineWidth = 1.5; context.stroke(); context.restore();
}

function finishDominoRun() {
  if (dominoModel.runner) Matter.Runner.stop(dominoModel.runner);
  if (dominoModel.runTimer) clearTimeout(dominoModel.runTimer);
  dominoModel.runTimer = null; dominoModel.runner = null; dominoModel.mode = "result";
  const trace = document.querySelector(".domino-trace");
  const swingDegrees = dominoModel.bellPeakAngle * 180 / Math.PI;
  if (dominoRunPassed()) {
    if (trace) trace.textContent = `PHYSICS PASS / BELL SWING ${swingDegrees.toFixed(1)}° / CERTIFY BELOW`;
    setReadout("PHYSICS PASS", "passed"); setDominoVerdict("pass", "PHYSICS PASS", `CONTINUOUS IMPULSE · BELL ${swingDegrees.toFixed(1)}°`);
  } else {
    if (trace) trace.textContent = "PHYSICS FAIL / NO CONTINUOUS BELL STRIKE / REWIND";
    setReadout("PHYSICS FAIL", "error"); setDominoVerdict("fail", "PHYSICS FAIL", "CHAIN BROKEN · REWIND AND REPAIR");
  }
  setDominoControls();
}

function rewindDominoPhysics() {
  if (dominoModel.runTimer) clearTimeout(dominoModel.runTimer);
  if (dominoModel.runner) Matter.Runner.stop(dominoModel.runner);
  dominoModel.runTimer = null; dominoModel.runner = null;
  const source = Object.keys(dominoModel.preRun).length ? dominoModel.preRun : dominoModel.initial;
  dominoModel.dominoIds.forEach((id) => {
    const body = dominoModel.bodiesById[id]; const pose = source[id];
    Matter.Body.setStatic(body, true); Matter.Body.setPosition(body, {x: pose.x, y: pose.y}); Matter.Body.setAngle(body, pose.angle);
    Matter.Body.setVelocity(body, {x: 0, y: 0}); Matter.Body.setAngularVelocity(body, 0);
  });
  const resetBody = (body, pose) => {
    if (!body || !pose) return;
    Matter.Body.setPosition(body, {x: pose.x, y: pose.y}); Matter.Body.setAngle(body, pose.angle); Matter.Body.setVelocity(body, {x: 0, y: 0}); Matter.Body.setAngularVelocity(body, 0); Matter.Sleeping.set(body, false);
  };
  resetBody(dominoModel.bellBody, dominoModel.bellInitial?.body); resetBody(dominoModel.clapperBody, dominoModel.bellInitial?.clapper);
  dominoModel.mode = "edit"; dominoModel.physicsPassed = false; dominoModel.bellHit = false; dominoModel.bellPeakAngle = 0; dominoModel.bellSoundPlayed = false; dominoModel.collisionPairs = new Set(); dominoModel.selectedId = null;
  const trace = document.querySelector(".domino-trace"); if (trace) trace.textContent = "PHYSICS READY / DRAG, ROTATE, RUN";
  setDominoVerdict(); setReadout("", "idle"); setDominoControls();
}

function runDominoSimulation() {
  if (dominoModel.mode !== "edit") return;
  armDominoBellAudio();
  setReadout("", "idle"); dominoModel.preRun = snapshotDominoBodies(); dominoModel.collisionPairs = new Set(); dominoModel.physicsPassed = false; dominoModel.bellHit = false; dominoModel.bellPeakAngle = 0; dominoModel.bellSoundPlayed = false; dominoModel.selectedId = null; dominoModel.mode = "running";
  setDominoVerdict();
  const trace = document.querySelector(".domino-trace"); if (trace) trace.textContent = "LIVE RIGID-BODY RUN / GRAVITY ON";
  dominoModel.dominoIds.forEach((id) => {
    const body = dominoModel.bodiesById[id]; Matter.Body.setStatic(body, false); Matter.Body.setVelocity(body, {x: 0, y: 0}); Matter.Body.setAngularVelocity(body, 0); Matter.Sleeping.set(body, false);
  });
  Matter.Sleeping.set(dominoModel.bellBody, false); Matter.Sleeping.set(dominoModel.clapperBody, false);
  dominoModel.runner = Matter.Runner.create({delta: 1000 / 60, isFixed: true}); Matter.Runner.run(dominoModel.runner, dominoModel.engine);
  const first = dominoModel.bodiesById[String(dominoModel.state.board.first_body_id)];
  setTimeout(() => {
    if (dominoModel.mode !== "running" || !first) return;
    Matter.Body.setAngularVelocity(first, 0.2);
    Matter.Body.applyForce(first, {x: first.position.x, y: first.position.y - 30}, {x: 0.008, y: 0});
  }, 180);
  dominoModel.runTimer = setTimeout(finishDominoRun, 8500); setDominoControls();
}

function setupDominoPhysics(state, board) {
  if (!window.Matter) throw new Error("Matter.js physics engine did not load");
  const {Engine, Render, Bodies, Body, Composite, Constraint, Events} = Matter;
  const engine = Engine.create({enableSleeping: true}); engine.gravity.y = 1; engine.gravity.scale = 0.001;
  engine.positionIterations = 12; engine.velocityIterations = 10; engine.constraintIterations = 4;
  dominoModel.engine = engine; dominoModel.bodiesById = {}; dominoModel.dominoIds = []; dominoModel.looseIds = [];
  const floor = Bodies.rectangle(360, 360, 760, 40, {isStatic: true, label: "table-floor", friction: 0.9, render: {fillStyle: "#756547", strokeStyle: "#443923", lineWidth: 1}});
  const bellX = Number(state.board?.bell?.x || 575); const bellY = Number(state.board?.bell?.y || 294); const bellId = String(state.board?.bell_body_id || "bell-body"); const bellGroup = Matter.Body.nextGroup(true);
  const bellBody = Bodies.trapezoid(bellX, bellY, 52, 48, 0.3, {label: bellId, density: 0.0027, friction: 0.42, frictionAir: 0.014, restitution: 0.12, collisionFilter: {group: bellGroup}, render: {visible: false}});
  const clapperBody = Bodies.circle(bellX, bellY + 32, 6.5, {label: "bell-clapper", density: 0.0034, frictionAir: 0.008, restitution: 0.24, collisionFilter: {group: bellGroup}, render: {visible: false}});
  const bellAnchor = {x: bellX, y: bellY - 46};
  const bellPivot = Constraint.create({label: "bell-pivot", pointA: bellAnchor, bodyB: bellBody, pointB: {x: 0, y: -22}, length: 24, stiffness: 0.92, damping: 0.09, render: {visible: false}});
  const clapperLink = Constraint.create({label: "clapper-link", bodyA: bellBody, pointA: {x: 0, y: 7}, bodyB: clapperBody, length: 25, stiffness: 0.82, damping: 0.025, render: {visible: false}});
  dominoModel.bellBody = bellBody; dominoModel.clapperBody = clapperBody; dominoModel.bellAnchor = bellAnchor;
  dominoModel.bellInitial = {body: {x: bellBody.position.x, y: bellBody.position.y, angle: bellBody.angle}, clapper: {x: clapperBody.position.x, y: clapperBody.position.y, angle: clapperBody.angle}};
  const createDomino = (item, meta) => {
    const color = meta.loose ? ({vermilion: "#b83b30", saffron: "#d7a82f", cobalt: "#315f82"}[item.color] || "#b83b30") : "#eee5cc";
    const body = Bodies.rectangle(Number(item.x), Number(item.y), 14, 72, {label: String(item.id), density: 0.0048, friction: 0.48, frictionStatic: 0.76, frictionAir: 0, restitution: 0.04, chamfer: {radius: 1.5}, render: {fillStyle: color, strokeStyle: "#1e1b16", lineWidth: 2}});
    Body.setAngle(body, Number(item.angle || 0) * Math.PI / 180); Body.setStatic(body, true); body.plugin.domino = {...meta, color: item.color || "ivory"};
    dominoModel.bodiesById[item.id] = body; dominoModel.dominoIds.push(item.id); if (meta.loose) dominoModel.looseIds.push(item.id); return body;
  };
  const bodies = [floor, bellBody, clapperBody, bellPivot, clapperLink];
  (state.board?.fixed || []).forEach((item, index) => bodies.push(createDomino(item, {loose: false, index})));
  (state.board?.loose || []).forEach((item, index) => bodies.push(createDomino(item, {loose: true, index})));
  Composite.add(engine.world, bodies); dominoModel.initial = snapshotDominoBodies(); dominoModel.preRun = {};
  const render = Render.create({element: board, engine, options: {width: 720, height: 410, wireframes: false, background: "transparent", pixelRatio: 1}});
  dominoModel.render = render; Render.run(render); Events.on(render, "afterRender", drawDominoDetails); Events.on(engine, "collisionStart", recordDominoCollisions);
  const canvas = render.canvas; canvas.className = "domino-physics-canvas";
  const point = (event) => { const rect = canvas.getBoundingClientRect(); return {x: (event.clientX - rect.left) * 720 / rect.width, y: (event.clientY - rect.top) * 410 / rect.height}; };
  let dragging = null;
  canvas.addEventListener("pointerdown", (event) => {
    if (dominoModel.mode !== "edit") return; event.preventDefault(); const p = point(event);
    const hits = Matter.Query.point(dominoModel.looseIds.map((id) => dominoModel.bodiesById[id]), p); dragging = hits[hits.length - 1] || null; dominoModel.selectedId = dragging?.label || null;
    if (dragging) canvas.setPointerCapture(event.pointerId); setReadout("", "idle"); setDominoControls();
  });
  canvas.addEventListener("pointermove", (event) => {
    if (!dragging || dominoModel.mode !== "edit") return; const p = point(event); Matter.Body.setPosition(dragging, {x: Math.max(18, Math.min(702, p.x)), y: Math.max(45, Math.min(392, p.y))});
  });
  const release = (event) => { if (dragging && canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId); dragging = null; };
  canvas.addEventListener("pointerup", release); canvas.addEventListener("pointercancel", release);
  canvas.addEventListener("dblclick", () => { if (!dominoModel.selectedId || dominoModel.mode !== "edit") return; const selected = dominoModel.bodiesById[dominoModel.selectedId]; Matter.Body.rotate(selected, 15 * Math.PI / 180); setDominoControls(); });
}

function rotateSelectedDomino(degrees) {
  if (!dominoModel.selectedId || dominoModel.mode !== "edit") return;
  Matter.Body.rotate(dominoModel.bodiesById[dominoModel.selectedId], degrees * Math.PI / 180); setReadout("", "idle"); setDominoControls();
}

function renderDominoAutopsy(state) {
  destroyDominoPhysics(); document.body.dataset.mechanic = "domino-autopsy"; document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  dominoModel.state = state; dominoModel.selectedId = null; dominoModel.collisionPairs = new Set(); dominoModel.physicsPassed = false; dominoModel.bellHit = false; dominoModel.bellPeakAngle = 0; dominoModel.bellSoundPlayed = false; dominoModel.mode = "edit";
  app.innerHTML = `
    <section class="domino-captcha" data-challenge-id="${text(state.challenge_id)}">
      <header class="domino-head"><div><span>RIGID-BODY LAB № 06</span><h1>${text(state.prompt)}</h1></div><div class="domino-scope"><i></i><i></i><i></i></div></header>
      <section class="domino-board">
        <div class="domino-ruler"></div><div class="domino-gap-label">BUILD THE BRIDGE</div><div class="domino-trace">PHYSICS READY / DRAG, ROTATE, RUN</div><div class="domino-selected">SELECT A COLORED DOMINO</div>
        <div class="domino-verdict" aria-live="polite" aria-atomic="true"></div>
      </section>
      <footer class="domino-controls"><div class="readout" data-status="idle"></div><button id="domino-rotate-left" type="button">↺ 15°</button><button id="domino-flip" type="button">FLIP 180°</button><button id="domino-rotate-right" type="button">15° ↻</button><button id="domino-reset" type="button">REWIND RUN</button><button id="domino-run" class="domino-run" type="button">▶ RUN PHYSICS</button><button id="domino-submit" class="domino-certify" type="button">${text(state.submit_label || "CERTIFY")}</button></footer>
      ${cheatPanelTemplate()}
    </section>`;
  const board = document.querySelector(".domino-board"); setupDominoPhysics(state, board);
  document.getElementById("domino-rotate-left").addEventListener("click", () => rotateSelectedDomino(-15));
  document.getElementById("domino-flip").addEventListener("click", () => rotateSelectedDomino(180));
  document.getElementById("domino-rotate-right").addEventListener("click", () => rotateSelectedDomino(15));
  document.getElementById("domino-reset").addEventListener("click", rewindDominoPhysics);
  document.getElementById("domino-run").addEventListener("click", runDominoSimulation);
  document.getElementById("domino-submit").addEventListener("click", async () => {
    const placements = {}; dominoModel.looseIds.forEach((id) => { const pose = dominoModel.preRun[id]; placements[id] = {x: Number(pose.x.toFixed(2)), y: Number(pose.y.toFixed(2)), angle: Number((pose.angle * 180 / Math.PI).toFixed(2))}; });
    const collisionPairs = Array.from(dominoModel.collisionPairs).map((key) => key.split("|"));
    try { const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, placements, physics_engine: "matter-js@0.20.0", bell_hit: dominoModel.bellHit, bell_peak_angle: Number(dominoModel.bellPeakAngle.toFixed(5)), run_completed: dominoModel.mode === "result", collision_pairs: collisionPairs})}); const outcome = await response.json(); if (outcome.passed === true) { setReadout("PASS", "passed"); } else if (outcome.passed === false) { if (outcome.state) renderDominoAutopsy(outcome.state); setReadout("FAIL", "error"); } } catch (_error) { setReadout("FAIL", "error"); }
  });
  setDominoControls(); installCheatPanel();
}

function consequenceSceneArt(kind) {
  return `<div class="consequence-art consequence-${text(kind)}"><div class="art-moon"></div><div class="art-figure"><i></i><b></b></div><div class="art-object"></div><div class="art-ground"></div></div>`;
}

function consequenceChoiceIcon(choice) {
  const icons = {release: "🜁", jar: "◈", share: "◒", hoard: "●", free: "⌁", trap: "⌗", water: "♒", salt: "✣", protect: "◉", exploit: "⌁"};
  return icons[choice] || "◆";
}

function renderConsequenceStep() {
  const state = consequenceModel.state; if (!state) return;
  const chamber = document.querySelector(".consequence-chamber"); const progress = document.querySelector(".consequence-progress");
  if (consequenceModel.phase === "choices") {
    const scene = state.scenes[consequenceModel.sceneIndex];
    progress.textContent = `${String(consequenceModel.sceneIndex + 1).padStart(2, "0")} / 04 — THE MAKING`;
    chamber.innerHTML = `${consequenceSceneArt(scene.kind)}<div class="consequence-rune">${text(scene.kind)}</div><div class="consequence-choices">${scene.choices.map((choice) => `<button type="button" data-choice="${text(choice)}"><span>${consequenceChoiceIcon(choice)}</span><b>${text(choice)}</b></button>`).join("")}</div>`;
    chamber.querySelectorAll("[data-choice]").forEach((button) => button.addEventListener("click", () => {
      setReadout("", "idle");
      consequenceModel.choices[scene.id] = button.dataset.choice; chamber.classList.add("is-choosing");
      setTimeout(() => { consequenceModel.sceneIndex += 1; chamber.classList.remove("is-choosing"); if (consequenceModel.sceneIndex >= state.scenes.length) consequenceModel.phase = "boss"; renderConsequenceStep(); }, 360);
    }));
    return;
  }
  const sceneId = state.boss_order[consequenceModel.bossIndex]; const scene = state.scenes.find((item) => item.id === sceneId);
  progress.textContent = `${String(consequenceModel.bossIndex + 1).padStart(2, "0")} / 04 — THE RECKONING`;
  chamber.innerHTML = `<div class="boss-halo"><i></i><i></i><i></i><strong>JUDGMENT</strong></div>${consequenceSceneArt(scene.kind)}<div class="consequence-memory"><span>YOU CHOSE</span><b>${consequenceChoiceIcon(consequenceModel.choices[sceneId])}</b></div><div class="consequence-choices boss-choices"><button type="button" data-action="protect"><span>${consequenceChoiceIcon("protect")}</span><b>PROTECT</b></button><button type="button" data-action="exploit"><span>${consequenceChoiceIcon("exploit")}</span><b>EXPLOIT</b></button></div>`;
  chamber.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", async () => {
    setReadout("", "idle");
    consequenceModel.actions[sceneId] = button.dataset.action; consequenceModel.bossIndex += 1;
    if (consequenceModel.bossIndex < state.boss_order.length) { chamber.classList.add("is-choosing"); setTimeout(() => { chamber.classList.remove("is-choosing"); renderConsequenceStep(); }, 300); return; }
    try { const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, choices: consequenceModel.choices, boss_actions: consequenceModel.actions})}); const outcome = await response.json(); if (outcome.passed === true) { chamber.classList.add("is-absolved"); setReadout("PASS", "passed"); } else if (outcome.passed === false) { if (outcome.state) renderConsequencesBoss(outcome.state); setReadout("FAIL", "error"); } } catch (_error) { setReadout("FAIL", "error"); }
  }));
}

function renderConsequencesBoss(state) {
  document.body.dataset.mechanic = "consequences-boss"; document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  consequenceModel.state = state; consequenceModel.phase = "choices"; consequenceModel.sceneIndex = 0; consequenceModel.bossIndex = 0; consequenceModel.choices = {}; consequenceModel.actions = {};
  app.innerHTML = `<section class="consequence-captcha"><header class="consequence-head"><span>THE LEDGER REMEMBERS</span><h1>${text(state.prompt)}</h1><p class="consequence-progress"></p></header><section class="consequence-chamber"></section><footer class="consequence-foot"><div class="readout" data-status="idle"></div><div class="ledger-dots">${state.scenes.map(() => "<i></i>").join("")}</div></footer>${cheatPanelTemplate()}</section>`;
  renderConsequenceStep(); installCheatPanel();
}

function popupBody(theme) {
  const bodies = {miracle: ["ONE WEIRD MIRACLE", "Doctors hate this window."], warning: ["⚠ DRIVE FAILURE", "Your files may be lonely."], coupon: ["97% OFF", "Expires before you blink."], romance: ["3 GHOSTS NEARBY", "They want to meet you."], system: ["MEMORY CLEANER", "Download more memory now."], horoscope: ["YOUR FUTURE", "contains another popup."], winner: ["YOU WON", "A suspicious amount of nothing."], download: ["FAST PLAYER", "Required to close this ad."], seal: ["☠ KILL SWITCH ☠", "One click ends every process."]};
  const copy = bodies[theme] || bodies.warning; return `<strong>${copy[0]}</strong><p>${copy[1]}</p><div class="popup-fake-button">CONTINUE »</div>`;
}

async function submitPopupResult(state, mode, trigger) {
  if (popupModel.submitting) return; popupModel.submitting = true;
  try { const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, cleared_popup_ids: popupModel.cleared, mode, trigger_popup_id: trigger || null})}); const outcome = await response.json(); if (outcome.passed === true) setReadout("PASS", "passed"); else if (outcome.passed === false) { if (outcome.state) renderPopupExorcist(outcome.state); setReadout("FAIL", "error"); } } catch (_error) { popupModel.submitting = false; setReadout("FAIL", "error"); }
}

function renderPopupExorcist(state) {
  document.body.dataset.mechanic = "popup-exorcist"; document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  popupModel.state = state; popupModel.cleared = []; popupModel.topZ = 20; popupModel.submitting = false;
  app.innerHTML = `<section class="popup-captcha"><header class="popup-head"><div><span>DESKTOP HYGIENE CHECK</span><h1>${text(state.prompt)}</h1></div><div class="popup-counter">THREATS <b>${state.popups.length}</b></div></header><section class="popup-desktop"><div class="desktop-wallpaper"><i></i><strong>Everything is fine.</strong></div>${state.popups.map((popup) => `<article class="chaos-popup popup-theme-${text(popup.theme)}" data-popup-id="${text(popup.id)}" data-special="${popup.special}" style="left:${popup.x}px;top:${popup.y}px;width:${popup.w}px;height:${popup.h}px;z-index:${popup.z}"><header><span>${text(popup.title)}</span><button type="button" class="popup-close" aria-label="Close">${popup.special ? "☠" : "×"}</button></header><div class="chaos-popup-body">${popupBody(popup.theme)}</div></article>`).join("")}<div class="purge-crosshair"><i></i><b></b></div></section><footer class="popup-foot"><div class="readout" data-status="idle"></div><span>Drag windows. Close them. Or find something worse.</span></footer>${cheatPanelTemplate()}</section>`;
  const desktop = document.querySelector(".popup-desktop"); const counter = document.querySelector(".popup-counter b");
  document.querySelectorAll(".chaos-popup").forEach((popup) => {
    popup.addEventListener("pointerdown", () => { popup.style.zIndex = String(++popupModel.topZ); });
    const header = popup.querySelector("header"); header.addEventListener("pointerdown", (event) => {
      if (event.target.closest("button")) return; event.preventDefault(); header.setPointerCapture(event.pointerId);
      const startX = event.clientX; const startY = event.clientY; const left = parseFloat(popup.style.left); const top = parseFloat(popup.style.top);
      const move = (moveEvent) => { popup.style.left = `${Math.max(0, Math.min(690 - popup.offsetWidth, left + moveEvent.clientX - startX))}px`; popup.style.top = `${Math.max(0, Math.min(390 - popup.offsetHeight, top + moveEvent.clientY - startY))}px`; };
      const up = () => { header.removeEventListener("pointermove", move); header.removeEventListener("pointerup", up); };
      header.addEventListener("pointermove", move); header.addEventListener("pointerup", up);
    });
    popup.querySelector(".popup-close").addEventListener("click", () => {
      setReadout("", "idle");
      const id = popup.dataset.popupId;
      if (popup.dataset.special === "true") {
        popupModel.cleared = state.popups.map((item) => item.id); desktop.classList.add("is-purging");
        Array.from(document.querySelectorAll(".chaos-popup")).forEach((node, index) => setTimeout(() => node.classList.add("is-exorcised"), index * 95));
        counter.textContent = "0"; setTimeout(() => submitPopupResult(state, "purge", id), 900); return;
      }
      popupModel.cleared.push(id); popup.classList.add("is-closed"); counter.textContent = String(state.popups.length - popupModel.cleared.length);
      if (popupModel.cleared.length === state.popups.length) submitPopupResult(state, "manual", null);
    });
  }); installCheatPanel();
}

function ritualPush(eventName) {
  setReadout("", "idle");
  if (!funeralModel.events.includes(eventName)) funeralModel.events.push(eventName);
}

function updateFuneralState() {
  const stage = document.querySelector(".funeral-stage"); if (!stage) return;
  stage.dataset.inspected = String(funeralModel.events.includes("inspect")); stage.dataset.brushed = String(funeralModel.events.includes("brush")); stage.dataset.lit = String(funeralModel.events.includes("light")); stage.dataset.gathered = String(funeralModel.events.includes("gather")); stage.dataset.offered = String(funeralModel.events.includes("offer"));
  const progress = document.querySelector(".moss-progress"); if (progress) progress.style.setProperty("--ritual-progress", `${Math.min(100, funeralModel.brushed.size / Number(funeralModel.state.brush_threshold || 17) * 100)}%`);
}

async function submitFuneral(state) {
  if (funeralModel.completed) return; funeralModel.completed = true;
  try { const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, events: funeralModel.events, brushed_cells: Array.from(funeralModel.brushed), gathered_flower_ids: Array.from(funeralModel.gathered), completed: funeralModel.events.includes("offer")})}); const outcome = await response.json(); if (outcome.passed === true) setReadout("PASS", "passed"); else if (outcome.passed === false) { if (outcome.state) renderFuneralRitual(outcome.state); setReadout("FAIL", "error"); } } catch (_error) { funeralModel.completed = false; setReadout("FAIL", "error"); }
}

function brushMossCell(cell) {
  if (!funeralModel.events.includes("inspect")) return;
  const index = Number(cell.dataset.mossIndex); funeralModel.brushed.add(index); cell.dataset.cleared = "true";
  if (funeralModel.brushed.size >= Number(funeralModel.state.brush_threshold || 17) && !funeralModel.events.includes("brush")) ritualPush("brush");
  updateFuneralState();
}

function renderFuneralRitual(state) {
  if (funeralModel.pointerUpHandler) window.removeEventListener("pointerup", funeralModel.pointerUpHandler);
  document.body.dataset.mechanic = "funeral-ritual"; document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  funeralModel.state = state; funeralModel.events = []; funeralModel.brushed = new Set(); funeralModel.gathered = new Set(); funeralModel.brushing = false; funeralModel.completed = false;
  app.innerHTML = `<section class="funeral-captcha"><header class="funeral-head"><span>MEMORIAL № 10</span><h1>${text(state.prompt)}</h1></header><section class="funeral-stage" data-inspected="false" data-brushed="false" data-lit="false" data-gathered="false" data-offered="false"><div class="rain rain-a"></div><div class="rain rain-b"></div><div class="grave-moon"></div><div class="grave-hill"></div><button type="button" class="tombstone"><span class="epitaph">${text(state.epitaph)}</span><div class="moss-grid">${Array.from({length: state.moss_cells || 24}, (_, index) => `<i class="moss-cell" data-moss-index="${index}" data-cleared="false"></i>`).join("")}</div><div class="moss-progress"></div></button><button type="button" class="grave-candle" aria-label="Candle"><i></i><b></b></button><div class="flower-field">${(state.flowers || []).map((flower) => `<button type="button" class="ritual-flower flower-${text(flower.kind)}" data-flower-id="${text(flower.id)}" style="left:${flower.x}%;top:${flower.y}%" aria-label="${text(flower.kind)}"><i></i><b></b></button>`).join("")}</div><div class="ritual-brush"><i></i><b></b></div><div class="grave-bed"></div><div class="ritual-bouquet" draggable="true"><i></i><i></i><i></i><b></b></div><div class="ritual-whisper">look closer</div></section><footer class="funeral-foot"><div class="readout" data-status="idle"></div><div class="ritual-stars">✦　·　✦</div></footer>${cheatPanelTemplate()}</section>`;
  const tombstone = document.querySelector(".tombstone"); tombstone.addEventListener("click", () => { ritualPush("inspect"); updateFuneralState(); });
  document.querySelectorAll(".moss-cell").forEach((cell) => { cell.addEventListener("pointerdown", (event) => { event.preventDefault(); funeralModel.brushing = true; brushMossCell(cell); }); cell.addEventListener("pointerenter", () => { if (funeralModel.brushing) brushMossCell(cell); }); });
  funeralModel.pointerUpHandler = () => { funeralModel.brushing = false; };
  window.addEventListener("pointerup", funeralModel.pointerUpHandler);
  document.querySelector(".grave-candle").addEventListener("click", () => { if (!funeralModel.events.includes("brush")) return; ritualPush("light"); updateFuneralState(); });
  document.querySelectorAll(".ritual-flower").forEach((flower) => flower.addEventListener("click", () => { if (!funeralModel.events.includes("light")) return; funeralModel.gathered.add(flower.dataset.flowerId); flower.dataset.picked = "true"; if (funeralModel.gathered.size === state.flowers.length) ritualPush("gather"); updateFuneralState(); }));
  const bouquet = document.querySelector(".ritual-bouquet"); bouquet.addEventListener("dragstart", (event) => event.dataTransfer.setData("text/plain", "bouquet"));
  const bed = document.querySelector(".grave-bed"); bed.addEventListener("dragover", (event) => event.preventDefault()); bed.addEventListener("drop", (event) => { event.preventDefault(); if (!funeralModel.events.includes("gather")) return; ritualPush("offer"); updateFuneralState(); setTimeout(() => submitFuneral(state), 700); });
  updateFuneralState(); installCheatPanel();
}

function slimeLaneAt(row) {
  return (slimeModel.state?.board?.lanes || []).find((lane) => Number(lane.row) === Number(row));
}

function slimeLanePositions(lane, elapsed = performance.now() - slimeModel.startedAt) {
  const columns = Number(slimeModel.state?.board?.columns || 9); const step = Math.floor(elapsed / Number(lane.step_ms || 600)); const positions = new Set();
  (lane.offsets || []).forEach((offset) => { const head = ((Number(offset) + Number(lane.phase || 0) + step * Number(lane.direction || 1)) % columns + columns) % columns; for (let part = 0; part < Number(lane.length || 1); part += 1) positions.add(((head + part * Number(lane.direction || 1)) % columns + columns) % columns); });
  return positions;
}

function slimeLaneSafe(x, row, elapsed = performance.now() - slimeModel.startedAt) {
  const lane = slimeLaneAt(row); if (!lane) return true; const occupied = slimeLanePositions(lane, elapsed).has(Number(x)); return lane.kind === "water" ? occupied : !occupied;
}

function drawSlimeBoard() {
  if (!slimeModel.state || document.body.dataset.mechanic !== "slime-commute") return;
  const elapsed = performance.now() - slimeModel.startedAt; const tick = Math.floor(elapsed / 80);
  if (tick !== slimeModel.lastTick) {
    slimeModel.lastTick = tick;
    document.querySelectorAll(".slime-cell").forEach((cell) => { cell.querySelectorAll(".lane-entity,.slime-avatar").forEach((node) => node.remove()); });
    (slimeModel.state.board.lanes || []).forEach((lane) => { slimeLanePositions(lane, elapsed).forEach((x) => { const cell = document.querySelector(`.slime-cell[data-x="${x}"][data-y="${lane.row}"]`); if (cell) cell.insertAdjacentHTML("beforeend", `<span class="lane-entity entity-${text(lane.kind)}" data-direction="${lane.direction}"><i></i></span>`); }); });
    const playerCell = document.querySelector(`.slime-cell[data-x="${slimeModel.player.x}"][data-y="${slimeModel.player.y}"]`); if (playerCell) playerCell.insertAdjacentHTML("beforeend", `<span class="slime-avatar"><i></i><b></b></span>`);
  }
  slimeModel.animationFrame = requestAnimationFrame(drawSlimeBoard);
}

async function submitSlime(state, completed) {
  if (slimeModel.completed) return; slimeModel.completed = true;
  try { const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: state.mechanic_id, challenge_id: state.challenge_id, completed, final: slimeModel.player, deaths: slimeModel.deaths, visited_rows: Array.from(slimeModel.visited)})}); const outcome = await response.json(); if (outcome.passed === true) { document.querySelector(".slime-board")?.classList.add("is-home"); setReadout("PASS", "passed"); } else if (outcome.passed === false) { if (outcome.state) renderSlimeCommute(outcome.state); setReadout("FAIL", "error"); } } catch (_error) { slimeModel.completed = false; setReadout("FAIL", "error"); }
}

function renderSlimeCommute(state) {
  if (slimeModel.animationFrame) cancelAnimationFrame(slimeModel.animationFrame); if (slimeModel.keyHandler) window.removeEventListener("keydown", slimeModel.keyHandler);
  document.body.dataset.mechanic = "slime-commute"; document.body.dataset.cheatMode = isCheatMode() ? "true" : "false";
  slimeModel.state = state; slimeModel.startedAt = performance.now(); slimeModel.player = {x: Number(state.board.start_x), y: 10}; slimeModel.deaths = 0; slimeModel.visited = new Set([10]); slimeModel.completed = false; slimeModel.lastTick = -1;
  const laneMap = new Map((state.board.lanes || []).map((lane) => [Number(lane.row), lane.kind]));
  app.innerHTML = `<section class="slime-captcha" tabindex="0"><header class="slime-head"><div><span>CROSSING LICENSE / 11</span><h1>${text(state.prompt)}</h1></div><div class="slime-lives">WIPES <b>0</b> / ${state.board.max_deaths}</div></header><section class="slime-frame"><div class="slime-board">${Array.from({length: state.board.rows}, (_, row) => `<div class="slime-row row-${laneMap.get(row) || "safe"}" data-row="${row}">${Array.from({length: state.board.columns}, (_, x) => `<div class="slime-cell" data-x="${x}" data-y="${row}">${row === 0 && x === state.board.goal_x ? '<span class="slime-home">⌂</span>' : ""}</div>`).join("")}</div>`).join("")}</div><aside class="slime-instructions"><div class="wasd"><span></span><b>W</b><b>A</b><b>S</b><b>D</b></div><p>HOP<br>WAIT<br>HOP</p></aside></section><footer class="slime-foot"><div class="readout" data-status="idle"></div><div class="slime-meter"><i></i></div></footer>${cheatPanelTemplate()}</section>`;
  const shell = document.querySelector(".slime-captcha"); const wipeCounter = document.querySelector(".slime-lives b");
  slimeModel.keyHandler = (event) => {
    if (event.repeat || slimeModel.completed || !["w", "a", "s", "d", "arrowup", "arrowleft", "arrowdown", "arrowright"].includes(event.key.toLowerCase())) return;
    event.preventDefault(); setReadout("", "idle"); const key = event.key.toLowerCase(); const dx = key === "a" || key === "arrowleft" ? -1 : key === "d" || key === "arrowright" ? 1 : 0; const dy = key === "w" || key === "arrowup" ? -1 : key === "s" || key === "arrowdown" ? 1 : 0;
    const next = {x: Math.max(0, Math.min(state.board.columns - 1, slimeModel.player.x + dx)), y: Math.max(0, Math.min(state.board.rows - 1, slimeModel.player.y + dy))}; if (next.x === slimeModel.player.x && next.y === slimeModel.player.y) return;
    if (!slimeLaneSafe(next.x, next.y)) {
      slimeModel.deaths += 1; wipeCounter.textContent = String(slimeModel.deaths); shell.classList.remove("slime-splat"); void shell.offsetWidth; shell.classList.add("slime-splat"); slimeModel.player = {x: Number(state.board.start_x), y: 10}; slimeModel.visited = new Set([10]);
      if (slimeModel.deaths >= Number(state.board.max_deaths || 4)) setTimeout(() => submitSlime(state, false), 280); return;
    }
    slimeModel.player = next; slimeModel.visited.add(next.y); document.querySelector(".slime-meter i").style.width = `${(10 - next.y) * 10}%`; slimeModel.lastTick = -1;
    if (next.y === 0 && next.x === Number(state.board.goal_x)) { window.removeEventListener("keydown", slimeModel.keyHandler); setTimeout(() => submitSlime(state, true), 420); }
  };
  window.addEventListener("keydown", slimeModel.keyHandler); shell.focus(); drawSlimeBoard(); installCheatPanel();
}

async function main() {
  try {
    const response = await fetch(`/state?ts=${Date.now()}`, {cache: "no-store"});
    if (!response.ok) {
      renderWaiting("Loading.");
      return;
    }
    const state = await response.json();
    const reviewedOverhauls = new Set([
      "surreal_apple_on_tree_grid",
      "cursor_lens_reveal",
      "modifier_stack_image_grid",
      "board_game_captcha",
      "consequences_boss",
      "popup_exorcist",
      "slime_commute",
      "semantic_drag_drop_absurdity",
      "reload_interruption",
      "rotate_wrong_thing_upright",
      "bureaucratic_signature_trap",
      "wonky_text_hostile_rendering",
      "temporal_memory_first_change",
    ]);
    if (reviewedOverhauls.has(state.mechanic_id) && await renderExternalMechanic(state)) {
      return;
    }
    if (state.mechanic_id === "surreal_apple_on_tree_grid") {
      renderAppleGrid(state);
      return;
    }
    if (state.mechanic_id === "cursor_lens_reveal") {
      renderCursorLens(state);
      return;
    }
    if (state.mechanic_id === "board_game_captcha") {
      renderBoardGame(state);
      return;
    }
    if (state.mechanic_id === "modifier_stack_image_grid") {
      renderModifierGrid(state);
      return;
    }
    if (state.mechanic_id === "semantic_drag_drop_absurdity") {
      renderSemanticDragDrop(state);
      return;
    }
    if (state.mechanic_id === "reload_interruption") {
      renderReloadInterruption(state);
      return;
    }
    if (state.mechanic_id === "rotate_wrong_thing_upright") {
      renderRotateWrongThing(state);
      return;
    }
    if (state.mechanic_id === "bureaucratic_signature_trap") {
      renderBureaucraticSignatureTrap(state);
      return;
    }
    if (state.mechanic_id === "wonky_text_hostile_rendering") {
      renderWonkyText(state);
      return;
    }
    if (state.mechanic_id === "temporal_memory_first_change") {
      renderTemporalMemory(state);
      return;
    }
    if (state.mechanic_id === "motion_only_ghost_jigsaw") {
      renderMotionOnlyGhostJigsaw(state);
      return;
    }
    if (state.mechanic_id === "cursor_constellation_hunt") {
      renderCursorConstellationHunt(state);
      return;
    }
    if (state.mechanic_id === "parallel_grillmaster") {
      renderParallelGrillmaster(state);
      return;
    }
    if (state.mechanic_id === "rotating_keyboard") {
      renderRotatingKeyboard(state);
      return;
    }
    if (state.mechanic_id === "slot_reel_capture") {
      renderSlotReelCapture(state);
      return;
    }
    if (state.mechanic_id === "domino_autopsy") {
      renderDominoAutopsy(state);
      return;
    }
    if (state.mechanic_id === "consequences_boss") {
      renderConsequencesBoss(state);
      return;
    }
    if (state.mechanic_id === "popup_exorcist") {
      renderPopupExorcist(state);
      return;
    }
    if (state.mechanic_id === "funeral_ritual") {
      renderFuneralRitual(state);
      return;
    }
    if (state.mechanic_id === "slime_commute") {
      renderSlimeCommute(state);
      return;
    }
    if (state.status !== "not_benchmark_ready" && await renderExternalMechanic(state)) {
      return;
    }
    renderUnavailable();
  } catch (_error) {
    renderWaiting("Loading.");
  }
}

main();
