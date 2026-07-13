from __future__ import annotations

import json
import time
from pathlib import Path

from playwright.sync_api import expect


MECHANIC_ID="portal_freight_oversized_parcel"


def _read(path:Path)->dict:return json.loads(path.read_text(encoding="utf-8"))
def _shot(page,out_dir:Path,mechanic:str,name:str)->None:out_dir.mkdir(parents=True,exist_ok=True);page.screenshot(path=str(out_dir/f"{mechanic}-{name}.png"),full_page=True)
def _wait_new(state_dir:Path,before:str)->None:
    deadline=time.time()+8
    while time.time()<deadline:
        if str(_read(state_dir/"ground_truth.json").get("challenge_id"))!=before:return
        time.sleep(.05)
    raise AssertionError("portal freight challenge did not regenerate")


def fail_once(page,state_dir:Path,out_dir:Path,mechanic:str)->None:
    if mechanic!=MECHANIC_ID:raise AssertionError(mechanic)
    before=str(_read(state_dir/"ground_truth.json")["challenge_id"]);page.locator("#freight-submit").click();_wait_new(state_dir,before)
    expect(page.locator(".portal-freight[data-fresh-failure='true']")).to_be_visible(timeout=8_000);expect(page.locator(".readout")).to_contain_text("FAIL");_shot(page,out_dir,mechanic,"fail-fresh-manifest")


def solve(page,state_dir:Path,out_dir:Path,mechanic:str)->None:
    if mechanic!=MECHANIC_ID:raise AssertionError(mechanic)
    expect(page.locator('.portal-freight[data-active="true"]')).to_be_visible(timeout=8_000);truth=_read(state_dir/"ground_truth.json")
    blue_aim=int(truth["solution"]["blue"]["aim_delta"])
    for _ in range(int(truth["solution"]["blue"]["aim_count"])):page.locator(f'[data-aim="{blue_aim}"]').click()
    page.locator('[data-fire="blue"]').click();page.locator('[data-portal-space="B"]').click();orange_aim=int(truth["solution"]["orange"]["aim_delta"])
    for _ in range(int(truth["solution"]["orange"]["aim_count"])):page.locator(f'[data-aim="{orange_aim}"]').click()
    page.locator('[data-fire="orange"]').click()
    root=page.locator(".portal-freight");expect(root).to_have_attribute("data-linked","true");expect(page.locator("#matrix-ledger")).to_contain_text("DET +1");_shot(page,out_dir,mechanic,"linked-right-handed-frames")
    delta=int(truth["solution"]["rotation_delta"])
    for _ in range(int(truth["solution"]["rotation_count"])):page.locator(f'[data-parcel-rotate="{delta}"]').click()
    _shot(page,out_dir,mechanic,"parcel-aligned-to-aperture")
    captured_split=False
    evidence_split_ticks=max(3,int(truth["qualification"]["minimum_split_ticks"]))
    for _ in range(int(truth["solution"]["push_count"])):
        page.locator('[data-parcel-push="0.25"]').click()
        split_ticks=int(page.locator("#split-ledger").text_content() or "0")
        if not captured_split and root.get_attribute("data-split")=="true" and split_ticks>=evidence_split_ticks:_shot(page,out_dir,mechanic,"parcel-spanning-both-frames");captured_split=True
    if not captured_split:raise AssertionError("parcel never visibly occupied both portal frames")
    expect(root).to_have_attribute("data-delivered","true");expect(root).to_have_attribute("data-collisions","0");expect(page.locator("#parcel-ledger")).to_have_text("RECEIVED")
    state=page.evaluate("() => ({linked:document.querySelector('.portal-freight').dataset.linked,delivered:document.querySelector('.portal-freight').dataset.delivered,split:Number(document.getElementById('split-ledger').textContent),collisions:Number(document.getElementById('collision-ledger').textContent)})")
    if state["linked"]!="true" or state["delivered"]!="true" or state["split"]<10 or state["collisions"]!=0:raise AssertionError(f"freight qualification incomplete: {state}")
    _shot(page,out_dir,mechanic,"receiver-containment-green");page.locator("#freight-submit").click();expect(page.locator(".readout")).to_have_text("PASS",timeout=8_000)
