"""Gemini Computer Use agent.

Uses Google's *official* Computer Use tool (`types.ComputerUse`) with
`gemini-3-flash-preview` (the only Flash model that supports Computer Use as of
2026-06; `gemini-3.5-flash` returns 400 "computer use capabilities" access error).

Design choices:
- **Full, untruncated history.** Every turn we append the model's content and a
  function_response (with the post-action screenshot) to `self.contents` and
  resend the whole list. The official docs show exactly this append-only loop; it
  also keeps the prefix stable so Gemini's implicit context caching is reused. We
  deliberately do NOT compact per turn.
- One Gemini call per env step. The model returns a single predefined UI action
  (click_at / type_text_at / key_combination / scroll / drag / ...); we translate
  it to the env's low-level action dicts (mouse pixel coords in 1920x1080,
  keyboard text/keys). Gemini coordinates are normalized 0-999 over the screenshot.
- Completion is signalled by the model returning no function_call (a plain text
  answer) -> we mark done.
"""
import json
import os
import pickle
from pathlib import Path

from PIL import Image
from dotenv import load_dotenv
from google import genai
from google.genai import types

from agents.agents.base import BaseAgent

load_dotenv()

SYSTEM_INSTRUCTION = (
    "You are operating a single desktop application that is ALREADY OPEN and fills "
    "the screen (1920x1080). Do not open a web browser, navigate to URLs, or use "
    "search — interact directly with what is on screen using clicks, typing, and "
    "keyboard shortcuts via the computer tool. Look carefully at each screenshot "
    "before acting. When the task is fully complete, stop calling the tool and "
    "reply with a short confirmation instead."
)

# Gemini key-combination names -> env (X11 keysym-ish) names used by the env layer.
_KEYMAP = {
    "control": "ctrl", "ctrl": "ctrl", "alt": "alt", "option": "alt",
    "shift": "shift", "meta": "super", "cmd": "super", "command": "super",
    "super": "super", "win": "super", "enter": "Return", "return": "Return",
    "tab": "Tab", "escape": "Escape", "esc": "Escape", "backspace": "BackSpace",
    "delete": "Delete", "del": "Delete", "space": "space", "spacebar": "space",
    "up": "Up", "down": "Down", "left": "Left", "right": "Right",
    "home": "Home", "end": "End", "pageup": "Prior", "pagedown": "Next",
}


class GeminiComputerUseAgent(BaseAgent):

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get("agent_args", {})
        self.model = self.agent_args.get("model", "gemini-3-flash-preview")
        self.decoding_params = self.agent_args.get("decoding_params", {})
        self.exp_name = self.agent_args.get("exp_name", "exp")
        self.debug = kwargs.get("debug", False)
        self.verbose = kwargs.get("verbose", False)

        self.done = False
        self.step_idx = -1
        self.display_resolution = (1920, 1080)

        self.contents = []          # full Gemini conversation (never compacted)
        self.pending_name = None    # name of the function_call awaiting a screenshot
        self.pending_id = None
        self.pending_safety = False
        self.transcript = []        # human-readable record for inspection

        self.setup_custom_logger()

        self.client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
        self.tool = types.Tool(
            computer_use=types.ComputerUse(environment=types.Environment.ENVIRONMENT_BROWSER)
        )
        self.config = types.GenerateContentConfig(
            tools=[self.tool],
            system_instruction=SYSTEM_INSTRUCTION,
            temperature=self.decoding_params.get("temperature", 1.0),
            # Return the model's thought summaries (part.thought == True). The
            # accompanying thought_signature is preserved automatically because we
            # append the whole candidate.content to history each turn.
            thinking_config=types.ThinkingConfig(
                include_thoughts=True,
                thinking_level=self.decoding_params.get("thinking_level", "high"),
            ),
        )

    # ---- bookkeeping (mirrors the other agents) ---------------------------
    def setup_custom_logger(self):
        task_name = self.agent_args.get("task_name", "task")
        base = f"all_runs/{self.exp_name}/{self.model}/{task_name}"
        self.save_folder_custom = base
        for run_number in range(0, 100):
            if os.path.exists(f"{base}/run_{run_number}"):
                continue
            self.save_folder_custom = f"{base}/run_{run_number}"
            break
        os.makedirs(self.save_folder_custom, exist_ok=True)

    def save_observation(self, obs):
        try:
            Image.open(obs["screen"]["path"]).save(
                f"{self.save_folder_custom}/observation_{self.step_idx}.png")
        except Exception as exc:
            print(f"[gemini-cu] save_observation failed: {exc}")

    def init(self, task_description, display_resolution, save_path):
        self.task_description = task_description
        self.display_resolution = tuple(display_resolution) or (1920, 1080)
        self.save_path = save_path

    # ---- main loop --------------------------------------------------------
    def step(self, obs, action_outputs):
        self.save_observation(obs)
        self.step_idx += 1
        shot = Path(obs["screen"]["path"]).read_bytes()

        if not self.contents:
            self.contents.append(types.Content(role="user", parts=[
                types.Part(text=self.task_description),
                types.Part.from_bytes(data=shot, mime_type="image/png"),
            ]))
        else:
            resp = {"url": "app://gridsmith"}
            if self.pending_safety:
                resp["safety_acknowledgement"] = "true"
            fr = self._function_response(self.pending_name, self.pending_id, resp, shot)
            self.contents.append(types.Content(role="user", parts=[types.Part(function_response=fr)]))
            self.pending_safety = False

        try:
            response = self.client.models.generate_content(
                model=self.model, contents=self.contents, config=self.config)
        except Exception as exc:
            print(f"[gemini-cu] generate_content error: {exc}")
            self.done = True
            self._dump_transcript()
            return []

        candidate = response.candidates[0]
        self.contents.append(candidate.content)  # keep full history

        fc, reasoning = None, []
        for part in (candidate.content.parts or []):
            # thought summaries come back as text parts flagged thought=True
            if getattr(part, "thought", False) and getattr(part, "text", None):
                reasoning.append(part.text)
                continue
            if getattr(part, "function_call", None):
                fc = part.function_call
                break
            if getattr(part, "text", None):
                reasoning.append(part.text)
        reasoning_text = "\n".join(r.strip() for r in reasoning if r and r.strip())
        if reasoning_text and self.verbose:
            print(f"[gemini-cu] thinking: {reasoning_text[:400]}")

        if fc is None:
            # No tool call -> the model considers the task finished.
            self.done = True
            self.transcript.append({"step": self.step_idx, "action": "DONE",
                                     "reasoning": reasoning_text})
            self._dump_transcript()
            return []

        args = dict(fc.args or {})
        if isinstance(args.get("safety_decision"), dict):
            self.pending_safety = True  # auto-acknowledge in this authorized sandbox
        self.pending_name = fc.name
        self.pending_id = getattr(fc, "id", None)

        actions = self._translate(fc.name, args)
        self.transcript.append({"step": self.step_idx, "action": fc.name,
                                "args": {k: v for k, v in args.items() if k != "safety_decision"},
                                "env_actions": actions, "reasoning": reasoning_text})
        self._dump_transcript()
        if self.verbose:
            print(f"[gemini-cu] step {self.step_idx}: {fc.name}({args}) -> {actions}")
        return [{"tool_id": f"gem_{self.step_idx}", "actions": actions}]

    # ---- action translation ----------------------------------------------
    def _translate(self, name, args):
        W, H = self.display_resolution

        def px(x, y):
            return [int(round(float(x) / 1000.0 * W)), int(round(float(y) / 1000.0 * H))]

        if name == "click_at":
            return [{"mouse": {"left_click": px(args["x"], args["y"])}}]
        if name == "hover_at":
            return [{"mouse": {"move": px(args["x"], args["y"])}}]
        if name == "type_text_at":
            out = [{"mouse": {"left_click": px(args["x"], args["y"])}}]
            if args.get("clear_before_typing"):
                out.append({"keyboard": {"keys": ["ctrl", "a"]}})
            out.append({"keyboard": {"text": args.get("text", "")}})
            if args.get("press_enter"):
                out.append({"keyboard": {"keys": ["Return"]}})
            return out
        if name == "key_combination":
            return self._key_combo_actions(str(args.get("keys", "")))
        if name == "scroll_document":
            amt = self._scroll_amount(args.get("direction", "down"), 600)
            return [{"mouse": {"scroll": amt}}]
        if name == "scroll_at":
            amt = self._scroll_amount(args.get("direction", "down"), int(args.get("magnitude", 600)))
            return [{"mouse": {"move": px(args["x"], args["y"])}}, {"mouse": {"scroll": amt}}]
        if name == "drag_and_drop":
            s = px(args["x"], args["y"])
            d = px(args["destination_x"], args["destination_y"])
            return [{"mouse": {"move": s}}, {"mouse": {"buttons": {"left_down": True}}},
                    {"mouse": {"move": d}}, {"mouse": {"buttons": {"left_up": True}}}]
        if name == "wait_5_seconds":
            return [{"action": "wait", "time": 5}]
        # open_web_browser / navigate / search / go_back / go_forward: irrelevant to
        # a single already-open app -> just re-observe so the loop continues.
        return [{"action": "wait", "time": 0.5}]

    @staticmethod
    def _scroll_amount(direction, magnitude):
        d = str(direction).lower()
        if d == "down":
            return -abs(magnitude)
        if d == "up":
            return abs(magnitude)
        return 0  # left/right scroll not modeled

    def _key_combo_actions(self, combo):
        """Translate a Gemini key_combination into env keyboard actions.

        Crucially, a single character (incl. GRIDSMITH's aggregator keys
        + ~ < > # * & and ordinary letters/digits) is *typed*, not sent as an
        xdotool keysym — `xdotool key +` is ambiguous/invalid, whereas typing it
        yields the right JS event.key. Named keys (Enter/Escape/Tab/arrows) and
        modifier chords (Ctrl+A, Shift+Equals) use xdotool key.
        """
        c = combo.strip()
        if not c:
            return [{"action": "wait", "time": 0.1}]
        if len(c) == 1:
            return [{"keyboard": {"text": c}}]
        if c.lower() in _KEYMAP:
            return [{"keyboard": {"keys": [_KEYMAP[c.lower()]]}}]
        if "+" in c or "-" in c:
            return [{"keyboard": {"keys": self._keys(c)}}]
        # multi-char, no separator, not a named key (e.g. a count prefix "4j")
        # -> type the characters so the app sees each keypress.
        return [{"keyboard": {"text": c}}]

    @staticmethod
    def _keys(combo):
        out = []
        for k in str(combo).replace("-", "+").split("+"):
            k = k.strip()
            if k:
                out.append(_KEYMAP.get(k.lower(), k))
        return out

    def _function_response(self, name, fid, resp, shot):
        blob = types.FunctionResponseBlob(mime_type="image/png", data=shot)
        part = types.FunctionResponsePart(inline_data=blob)
        try:
            return types.FunctionResponse(id=fid, name=name or "computer", response=resp, parts=[part])
        except Exception:
            return types.FunctionResponse(name=name or "computer", response=resp, parts=[part])

    # ---- persistence ------------------------------------------------------
    def _dump_transcript(self):
        try:
            with open(f"{self.save_folder_custom}/trajectory.json", "w") as fh:
                json.dump({"model": self.model, "task": getattr(self, "task_description", ""),
                           "steps": self.transcript}, fh, indent=2)
        except Exception as exc:
            print(f"[gemini-cu] trajectory dump failed: {exc}")

    def finish(self, *args, **kwargs):
        self._dump_transcript()
        try:
            pickle.dump(self.transcript, open(f"{self.save_path}/messages.pkl", "wb"))
            pickle.dump(self.transcript, open(f"{self.save_folder_custom}/messages.pkl", "wb"))
        except Exception as exc:
            print(f"[gemini-cu] finish dump failed: {exc}")
        if "info" in kwargs:
            try:
                pickle.dump(kwargs["info"], open(f"{self.save_folder_custom}/info.pkl", "wb"))
            except Exception:
                pass
