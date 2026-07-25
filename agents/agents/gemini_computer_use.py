"""Gemini Computer Use agent.

Uses Google's official Computer Use tool (`types.ComputerUse`) and supports
both current model generations:

- `gemini-3-flash-preview` / `gemini-2.5-computer-use-preview*` emit the
  legacy action set (click_at, type_text_at, key_combination, scroll_at, ...)
  and are browser-environment models.
- `gemini-3.5-flash` emits the newer action set (click, type, hotkey,
  press_key, scroll, take_screenshot, ...) and supports
  ENVIRONMENT_DESKTOP (google-genai >= 2.x), which is what this harness
  actually shows the model.

The translator dispatches on the action *name*, so both vocabularies work
regardless of which model produced them. Unknown actions are never silently
swallowed: they are logged, recorded in the transcript, reported back to the
model as an error in the next function response, and after
`_MAX_CONSECUTIVE_UNSUPPORTED` in a row the episode is marked done.

Design choices:
- **Full, untruncated history.** Every turn we append the model's content and a
  function_response (with the post-action screenshot) to `self.contents` and
  resend the whole list. The official docs show exactly this append-only loop; it
  also keeps the prefix stable so Gemini's implicit context caching is reused. We
  deliberately do NOT compact per turn.
- One Gemini call per env step. The model returns a single predefined UI action;
  we translate it to the env's low-level action dicts (mouse pixel coords at the
  native resolution, keyboard text/keys). Gemini coordinates are normalized
  0-999 over the screenshot.
- Browser-navigation actions (open_web_browser, search, navigate, ...) are
  excluded via `excluded_predefined_functions` instead of being begged away in
  the system prompt.
- Completion is signalled by the model returning no function_call (a plain text
  answer): we mark done.
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
    "the screen. Interact directly with what is on screen using clicks, typing, and "
    "keyboard shortcuts via the computer tool. Look carefully at each screenshot "
    "before acting. When the task is fully complete, stop calling the tool and "
    "reply with a short confirmation instead."
)

# Gemini key names -> env (X11 keysym-ish) names used by the env layer.
_KEYMAP = {
    "control": "ctrl", "ctrl": "ctrl", "alt": "alt", "option": "alt",
    "shift": "shift", "meta": "super", "cmd": "super", "command": "super",
    "super": "super", "win": "super", "enter": "Return", "return": "Return",
    "tab": "Tab", "escape": "Escape", "esc": "Escape", "backspace": "BackSpace",
    "delete": "Delete", "del": "Delete", "space": "space", "spacebar": "space",
    "up": "Up", "down": "Down", "left": "Left", "right": "Right",
    "home": "Home", "end": "End", "pageup": "Prior", "pagedown": "Next",
}

# Models that emit the legacy (browser-only) action vocabulary.
_LEGACY_MODEL_PREFIXES = ("gemini-2.5-computer-use", "gemini-3-flash")

# Browser-navigation actions this harness can never execute (single desktop
# app, no browser chrome). Excluded per vocabulary so the model cannot emit
# them at all.
_LEGACY_BROWSER_FUNCTIONS = ["open_web_browser", "search", "navigate", "go_back", "go_forward"]
_NEW_BROWSER_FUNCTIONS = ["navigate", "go_back", "go_forward"]

_MAX_CONSECUTIVE_UNSUPPORTED = 3


def _uses_legacy_actions(model: str) -> bool:
    return model.startswith(_LEGACY_MODEL_PREFIXES)


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
        self.pending_error = None   # error text to report for the previous action
        self.consecutive_unsupported = 0
        self._last_unsupported = False
        self.transcript = []        # human-readable record for inspection

        self.setup_custom_logger()

        self.legacy_actions = _uses_legacy_actions(self.model)
        self.environment = self._resolve_environment()
        excluded = self.agent_args.get("excluded_functions")
        if excluded is None:
            excluded = _LEGACY_BROWSER_FUNCTIONS if self.legacy_actions else _NEW_BROWSER_FUNCTIONS

        self.client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
        self.tool = types.Tool(
            computer_use=types.ComputerUse(
                environment=self.environment,
                excluded_predefined_functions=list(excluded),
            )
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

    def _resolve_environment(self):
        """Pick the ComputerUse environment.

        Legacy models are browser-only. Newer models default to
        ENVIRONMENT_DESKTOP, which is what this harness actually shows the
        model, falling back to browser (with a warning) when the installed
        google-genai predates the desktop enum. Override with
        agent_args["environment"] = "browser" | "desktop" | "mobile".
        """
        requested = self.agent_args.get("environment")
        if requested is None:
            requested = "browser" if self.legacy_actions else "desktop"
        enum_name = f"ENVIRONMENT_{requested.upper()}"
        env = getattr(types.Environment, enum_name, None)
        if env is None:
            print(f"[gemini-cu] google-genai has no {enum_name} (SDK too old?); "
                  "falling back to ENVIRONMENT_BROWSER")
            return types.Environment.ENVIRONMENT_BROWSER
        return env

    @property
    def _is_browser_env(self):
        return self.environment == types.Environment.ENVIRONMENT_BROWSER

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
            resp = {}
            if self._is_browser_env:
                # The browser protocol expects a current-URL field; a desktop
                # app has none, so report a stable placeholder.
                resp["url"] = f"app://{self.agent_args.get('task_name', 'desktop')}"
            if self.pending_error:
                resp["error"] = self.pending_error
            if self.pending_safety:
                resp["safety_acknowledgement"] = "true"
            fr = self._function_response(self.pending_name, self.pending_id, resp, shot)
            self.contents.append(types.Content(role="user", parts=[types.Part(function_response=fr)]))
            self.pending_safety = False
            self.pending_error = None

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
                                "args": {k: v for k, v in args.items()
                                         if k not in ("safety_decision", "intent")},
                                "intent": args.get("intent"),
                                "env_actions": actions,
                                "error": self.pending_error,
                                "reasoning": reasoning_text})
        self._dump_transcript()
        if self.verbose:
            print(f"[gemini-cu] step {self.step_idx}: {fc.name}({args}) -> {actions}")
        if self.consecutive_unsupported >= _MAX_CONSECUTIVE_UNSUPPORTED:
            print(f"[gemini-cu] {self.consecutive_unsupported} unsupported actions "
                  "in a row; ending episode")
            self.done = True
            self._dump_transcript()
        return [{"tool_id": f"gem_{self.step_idx}", "actions": actions}]

    # ---- action translation ----------------------------------------------
    def _unsupported(self, name, detail):
        """Loud no-op: warn, report the error back to the model, count it."""
        self.pending_error = f"Action '{name}' is not supported here: {detail}"
        self.consecutive_unsupported += 1
        self._last_unsupported = True
        print(f"[gemini-cu] UNSUPPORTED action {name}: {detail}")
        return [{"action": "wait", "time": 0.5}]

    def _translate(self, name, args):
        W, H = self.display_resolution

        def px(x, y):
            return [int(round(float(x) / 1000.0 * W)), int(round(float(y) / 1000.0 * H))]

        self._last_unsupported = False
        known = self._translate_known(name, args, px)
        if known is not None:
            if not self._last_unsupported:
                self.consecutive_unsupported = 0
            return known

        if name in ("open_app", "list_apps"):
            return self._unsupported(name, "mobile-only action; this is a desktop app")
        if name in _LEGACY_BROWSER_FUNCTIONS or name in _NEW_BROWSER_FUNCTIONS:
            return self._unsupported(name, "browser navigation is unavailable in a single desktop app")
        return self._unsupported(name, "unknown predefined function for this harness")

    def _translate_known(self, name, args, px):
        """Return env actions for a recognized action name, else None.

        Handles BOTH Gemini action vocabularies: legacy (gemini-3-flash-preview,
        gemini-2.5-computer-use-preview) and current (gemini-3.5-flash).
        """
        # --- clicks (legacy: click_at / hover_at; new: click family + move) ---
        if name in ("click_at", "click"):
            return [{"mouse": {"left_click": px(args["x"], args["y"])}}]
        if name == "right_click":
            return [{"mouse": {"right_click": px(args["x"], args["y"])}}]
        if name == "middle_click":
            return [{"mouse": {"middle_click": px(args["x"], args["y"])}}]
        if name == "double_click":
            return [{"mouse": {"double_click": px(args["x"], args["y"])}}]
        if name == "triple_click":
            return [{"mouse": {"triple_click": px(args["x"], args["y"])}}]
        if name in ("hover_at", "move"):
            return [{"mouse": {"move": px(args["x"], args["y"])}}]
        if name == "mouse_down":
            return [{"mouse": {"move": px(args["x"], args["y"])}},
                    {"mouse": {"buttons": {"left_down": True}}}]
        if name == "mouse_up":
            return [{"mouse": {"move": px(args["x"], args["y"])}},
                    {"mouse": {"buttons": {"left_up": True}}}]
        if name == "long_press":
            return [{"mouse": {"move": px(args["x"], args["y"])}},
                    {"mouse": {"buttons": {"left_down": True}}},
                    {"action": "wait", "time": float(args.get("seconds", 2))},
                    {"mouse": {"buttons": {"left_up": True}}}]

        # --- typing (legacy: type_text_at clicks first; new: type at focus) ---
        if name == "type_text_at":
            out = [{"mouse": {"left_click": px(args["x"], args["y"])}}]
            if args.get("clear_before_typing"):
                out.append({"keyboard": {"keys": ["ctrl", "a"]}})
            out.append({"keyboard": {"text": args.get("text", "")}})
            if args.get("press_enter"):
                out.append({"keyboard": {"keys": ["Return"]}})
            return out
        if name == "type":
            out = []
            if args.get("clear_before_typing"):
                out.append({"keyboard": {"keys": ["ctrl", "a"]}})
            out.append({"keyboard": {"text": args.get("text", "")}})
            if args.get("press_enter"):
                out.append({"keyboard": {"keys": ["Return"]}})
            return out

        # --- keys ---
        if name == "key_combination":
            return self._key_combo_actions(str(args.get("keys", "")))
        if name == "press_key":
            return self._key_combo_actions(str(args.get("key", "")))
        if name == "hotkey":
            keys = args.get("keys", [])
            if isinstance(keys, str):
                return self._key_combo_actions(keys)
            return [{"keyboard": {"keys": [_KEYMAP.get(str(k).lower(), str(k)) for k in keys]}}]
        if name == "key_down":
            return [{"keyboard": {"keys_down": [_KEYMAP.get(str(args.get("key", "")).lower(),
                                                            str(args.get("key", "")))]}}]
        if name == "key_up":
            return [{"keyboard": {"keys_up": [_KEYMAP.get(str(args.get("key", "")).lower(),
                                                          str(args.get("key", "")))]}}]

        # --- scrolling ---
        if name == "scroll_document":
            amt = self._scroll_amount(args.get("direction", "down"), 600)
            return [{"mouse": {"scroll": amt}}]
        if name in ("scroll_at", "scroll"):
            magnitude = int(args.get("magnitude", args.get("magnitude_in_pixels", 600)) or 600)
            direction = str(args.get("direction", "down")).lower()
            if direction in ("left", "right"):
                return self._unsupported(name, "horizontal scroll is not modeled by the env")
            amt = self._scroll_amount(direction, magnitude)
            out = []
            if "x" in args and "y" in args:
                out.append({"mouse": {"move": px(args["x"], args["y"])}})
            out.append({"mouse": {"scroll": amt}})
            return out

        # --- drags (legacy: destination_x/y; new: end_x/y or destination_x/y) ---
        if name == "drag_and_drop":
            sx = args.get("x", args.get("start_x"))
            sy = args.get("y", args.get("start_y"))
            dx = args.get("destination_x", args.get("end_x"))
            dy = args.get("destination_y", args.get("end_y"))
            if None in (sx, sy, dx, dy):
                return self._unsupported(name, f"missing drag coordinates in {sorted(args)}")
            return [{"mouse": {"left_click_drag": [px(sx, sy), px(dx, dy)]}}]

        # --- waiting / observation ---
        if name == "wait_5_seconds":
            return [{"action": "wait", "time": 5}]
        if name == "wait":
            return [{"action": "wait", "time": float(args.get("seconds", 1))}]
        if name == "take_screenshot":
            return [{"action": "screenshot"}]

        return None

    @staticmethod
    def _scroll_amount(direction, magnitude):
        d = str(direction).lower()
        if d == "down":
            return -abs(magnitude)
        if d == "up":
            return abs(magnitude)
        return 0  # left/right scroll not modeled

    def _key_combo_actions(self, combo):
        """Translate a key combination / single key into env keyboard actions.

        A single character (letters, digits, punctuation like + ~ < > # * &) is
        *typed*, not sent as an xdotool keysym — `xdotool key +` is
        ambiguous/invalid, whereas typing it yields the right JS event.key.
        Named keys (Enter/Escape/Tab/arrows) and modifier chords (Ctrl+A,
        Shift+Equals) use xdotool key.
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
