from __future__ import annotations

import json
import math
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID = "forced_perspective_moving_day"


def _read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _shot(page, out_dir: Path, mechanic: str, name: str) -> None:
    out_dir.mkdir(parents=True, exist_ok=True); page.screenshot(path=str(out_dir / f"{mechanic}-{name}.png"), full_page=True)


def _wait_new(state_dir: Path, before: str) -> None:
    deadline = time.time() + 8
    while time.time() < deadline:
        if str(_read(state_dir / "ground_truth.json").get("challenge_id")) != before: return
        time.sleep(.05)
    raise AssertionError("perspective challenge did not regenerate")


def fail_once(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    before = str(_read(state_dir / "ground_truth.json")["challenge_id"]); page.locator(".persp-submit").click(); _wait_new(state_dir, before)
    expect(page.locator(".perspective-captcha[data-fresh-failure='true']")).to_be_visible(timeout=8_000); expect(page.locator(".readout")).to_contain_text("FAIL"); _shot(page, out_dir, mechanic, "fail-fresh-room")


def _camera_coords(point: list[float], camera: dict) -> tuple[float, float, float]:
    dx, dy, dz = point[0] - camera["x"], point[1] - camera["y"], point[2] - camera["z"]; c, s = math.cos(camera["yaw"]), math.sin(camera["yaw"])
    return c * dx - s * dz, dy, s * dx + c * dz


def _project(point: list[float], camera: dict) -> tuple[float, float, float]:
    x, y, depth = _camera_coords(point, camera); return camera["center"][0] + camera["focal"] * x / depth, camera["center"][1] - camera["focal"] * y / depth, depth


def _canvas_screen(box: dict, stage: dict, point: tuple[float, float]) -> tuple[float, float]:
    return box["x"] + point[0] / stage["width"] * box["width"], box["y"] + point[1] / stage["height"] * box["height"]


def _pick(page, truth: dict, box: dict, object_id: str) -> None:
    obj = next(item for item in truth["objects"] if item["id"] == object_id); projected = _project(obj["center"], truth["camera"]); page.mouse.move(*_canvas_screen(box, truth["stage"], truth["camera"]["center"]), steps=8); page.mouse.move(*_canvas_screen(box, truth["stage"], projected[:2]), steps=8); page.mouse.click(*_canvas_screen(box, truth["stage"], projected[:2])); expect(page.locator(".persp-held-value")).to_have_text(object_id.upper())


def _target_aim(truth: dict, object_id: str, target_xz: list[float], actual_depth: float, apparent: float) -> tuple[float, float]:
    camera = truth["camera"]; obj = next(item for item in truth["objects"] if item["id"] == object_id); target_point = [target_xz[0], 0, target_xz[1]]; camera_x, _camera_y, target_depth = _camera_coords(target_point, camera)
    # Preserve target camera-x while accepting the nearest legal 0.5-depth plane.
    c, s = math.cos(camera["yaw"]), math.sin(camera["yaw"]); world_x = camera["x"] + c * camera_x + s * actual_depth; world_z = camera["z"] - s * camera_x + c * actual_depth; scale = apparent * actual_depth / (camera["focal"] * obj["reference_size"]); vertical_size = obj["base_size"][2] if obj["role"] == "bridge" else obj["base_size"][1]; world_y = vertical_size * scale / 2
    screen = _project([world_x, world_y, world_z], camera); return screen[0], screen[1]


def _place(page, truth: dict, box: dict, object_id: str, target: list[float], use_wheel: bool, out_dir: Path | None = None) -> None:
    _pick(page, truth, box, object_id); held = page.evaluate("() => ({depth:window.forcedPerspectiveMovingDayModel.held.depth,apparent:window.forcedPerspectiveMovingDayModel.held.apparent})"); camera_target = _camera_coords([target[0], 0, target[1]], truth["camera"]); steps = round((camera_target[2] - held["depth"]) / truth["depth_controls"]["step"]); direction = 1 if steps > 0 else -1
    if use_wheel:
        canvas = page.locator(".persp-canvas"); canvas.hover()
        for _ in range(abs(steps)): page.mouse.wheel(0, 120 * direction); page.wait_for_timeout(18)
    else:
        button = page.locator(".persp-farther" if direction > 0 else ".persp-nearer")
        for _ in range(abs(steps)): button.click()
    actual_depth = page.evaluate("() => window.forcedPerspectiveMovingDayModel.held.depth"); aim = _target_aim(truth, object_id, target, actual_depth, held["apparent"]); page.mouse.move(*_canvas_screen(box, truth["stage"], aim), steps=10); page.wait_for_timeout(50)
    # Reconcile the floor-contact y coordinate against the live camera after CSS/canvas scaling.
    live_aim = page.evaluate("""() => { const m=window.forcedPerspectiveMovingDayModel,h=m.held,o=m.objects[h.id],c=m.camera,cx=(m.aim[0]-c.center[0])/c.focal*h.depth,co=Math.cos(c.yaw),si=Math.sin(c.yaw),x=c.x+co*cx+si*h.depth,z=c.z-si*cx+co*h.depth,scale=h.apparent*h.depth/(c.focal*o.reference_size),vertical=o.role==='bridge'?o.base_size[2]:o.base_size[1],y=vertical*scale/2,dx=x-c.x,dy=y-c.y,dz=z-c.z,camx=co*dx-si*dz,depth=si*dx+co*dz; return [m.aim[0],c.center[1]-c.focal*dy/depth]; }""")
    page.mouse.move(*_canvas_screen(box, truth["stage"], live_aim), steps=4); page.wait_for_timeout(60)
    if object_id == "sign" and out_dir is not None: _shot(page, out_dir, MECHANIC_ID, "active-perspective-depth")
    page.locator(".persp-release").click(); expect(page.locator(".persp-held-value")).to_have_text("NONE")


def solve(page, state_dir: Path, out_dir: Path, mechanic: str) -> None:
    if mechanic != MECHANIC_ID: raise AssertionError(mechanic)
    truth = _read(state_dir / "ground_truth.json")
    # Walk into the unbridged void to prove symmetric avatar/floor contact, then rewind.
    page.keyboard.down("w"); expect(page.locator(".persp-impact[data-visible='true']")).to_be_visible(timeout=5_000); page.keyboard.up("w"); _shot(page, out_dir, mechanic, "unbridged-void-collision"); page.locator(".persp-reset").click(); expect(page.locator(".readout")).to_contain_text("REWOUND")
    box = page.locator(".persp-canvas").bounding_box()
    if not box: raise AssertionError("perspective room canvas missing")
    _place(page, truth, box, "crate", truth["solver_targets"]["crate"], use_wheel=False, out_dir=out_dir); expect(page.locator(".persp-door-state")).to_have_text("UNLOCKED"); _shot(page, out_dir, mechanic, "shrunk-crate-key-slot")
    _place(page, truth, box, "sign", truth["solver_targets"]["sign"], use_wheel=True, out_dir=out_dir); expect(page.locator(".persp-bridge-state")).to_have_text("LOAD-BEARING"); _shot(page, out_dir, mechanic, "enlarged-sign-bridge")
    held: set[str] = set(); deadline = time.time() + 20; blocked_ticks = 0
    page.keyboard.down("w"); held.add("w")
    while time.time() < deadline:
        state = page.evaluate("() => ({x:window.forcedPerspectiveMovingDayModel.camera.x,z:window.forcedPerspectiveMovingDayModel.camera.z,done:window.forcedPerspectiveMovingDayModel.completed,blocked:window.forcedPerspectiveMovingDayModel.blocked})")
        if state["done"]: break
        if state["blocked"]:
            blocked_ticks += 1
            # A physical lip/door contact can occur between observation polls.
            # Explicitly strafe back toward the bridge/door centre and let the
            # collision resolver slide along the supported edge.
            correction = "a" if state["x"] > 0 else "d"
            opposite = "d" if correction == "a" else "a"
            if opposite in held: page.keyboard.up(opposite); held.remove(opposite)
            if correction not in held: page.keyboard.down(correction); held.add(correction)
            if blocked_ticks > 20: raise AssertionError(f"avatar could not recover from rigid contact: {state}")
            page.wait_for_timeout(45); continue
        blocked_ticks = 0
        if state["x"] > .18 and "a" not in held: page.keyboard.down("a"); held.add("a")
        if state["x"] <= .05 and "a" in held: page.keyboard.up("a"); held.remove("a")
        if state["x"] < -.18 and "d" not in held: page.keyboard.down("d"); held.add("d")
        if state["x"] >= -.05 and "d" in held: page.keyboard.up("d"); held.remove("d")
        page.wait_for_timeout(45)
    for key in list(held): page.keyboard.up(key)
    if not state["done"]:
        final_state = page.evaluate("() => ({x:window.forcedPerspectiveMovingDayModel.camera.x,z:window.forcedPerspectiveMovingDayModel.camera.z,done:window.forcedPerspectiveMovingDayModel.completed,blocked:window.forcedPerspectiveMovingDayModel.blocked,bridge:window.forcedPerspectiveMovingDayModel.bridgeReady,door:window.forcedPerspectiveMovingDayModel.doorOpen,tick:window.forcedPerspectiveMovingDayModel.tick})")
        raise AssertionError(f"avatar did not reach impossible-door exit: {final_state}")
    expect(page.locator(".persp-complete[data-visible='true']")).to_be_visible(timeout=3_000); state = page.evaluate("() => ({completed:window.forcedPerspectiveMovingDayModel.completed,bridge:window.forcedPerspectiveMovingDayModel.bridgeReady,door:window.forcedPerspectiveMovingDayModel.doorOpen,collisions:window.forcedPerspectiveMovingDayModel.collisions,resets:window.forcedPerspectiveMovingDayModel.resets,tick:window.forcedPerspectiveMovingDayModel.tick})")
    if not state["completed"] or not state["bridge"] or not state["door"] or state["collisions"] < 1 or state["resets"] < 1: raise AssertionError(f"perspective move incomplete: {state}")
    _shot(page, out_dir, mechanic, "solved-impossible-door"); page.locator(".persp-submit").click(); expect(page.locator(".readout")).to_have_text("PASS", timeout=8_000)
