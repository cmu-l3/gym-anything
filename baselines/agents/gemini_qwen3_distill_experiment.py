from baselines.agents.base import BaseAgent
from baselines.agents.claude_gemini_qwen3 import GeminiQwen3Agent
from baselines.common.llm_clients import call_gemini_with_retry, smart_resize, parse_qwen3vl_response
from PIL import Image
import json
import os
from io import BytesIO
import base64
import numpy as np


class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        return json.JSONEncoder.default(self, obj)


class GeminiQwen3DistillAgentExperiment(GeminiQwen3Agent):
    """
    Experimental agent that prompts Gemini 3 Flash to produce Claude-style
    structured thinking traces for better distillation into smaller models.

    Key differences from GeminiQwen3Agent:
    - Overrides get_system_prompt() with Claude-style thinking instructions + examples
    - Configurable reasoning_effort (default 'none' to disable implicit reasoning)
    - All <think> content comes from explicit model output, not implicit reasoning_content

    Usage:
        python -m baselines.evaluation.run_single --env_dir benchmarks/environments/gimp_env_all_fast --task saturation_increase \
            --agent 'GeminiQwen3DistillAgentExperiment' \
            --agent_args '{"model":"gemini-3-flash-preview", "exp_name":"gemini-claude-style-exp0", "task_name":"saturation_increase", "reasoning_effort":"none"}'
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Configurable reasoning effort: 'none', 'low', 'high'
        # 'none' = no implicit reasoning, model must produce <think> explicitly
        # 'low'/'high' = implicit reasoning present, may cause double-think
        self.reasoning_effort = self.agent_args.get('reasoning_effort', 'none')
        self.resize_to = tuple(self.agent_args.get('resize_to', [1920, 1080]))
        # Response prefix forces Gemini to produce <think> blocks
        # by starting the assistant response with '<think>\nLooking at the screenshot,'
        self.use_response_prefix = self.agent_args.get('use_response_prefix', True)
        self.response_prefix = '<think>\nLooking at the screenshot,'

    def get_system_prompt(self):
        """
        Override system prompt to instruct Gemini to produce Claude-style
        structured thinking traces.

        The Claude thinking style is characterized by:
        - Observe-Reason-Act (ORA) flow
        - No bold headers, no "Okay"/"Alright" fillers, no markdown inside <think>
        - Concise: 30-120 words for most steps
        - Predictable vocabulary: "I can see", "I need to", "Let me"
        - Last sentence telegraphs the action
        - Clinical tone, no emotional language
        """
        width, height = self.display_resolution

        tools_def = {
            "type": "function",
            "function": {
                "name": "computer_use",
                "description": f"""Use a mouse and keyboard to interact with a computer, and take screenshots.
* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.
* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions. E.g. if you click on Firefox and a window doesn't open, try wait and taking another screenshot.
* The screen's resolution is {width}x{height}.
* Whenever you intend to move the cursor to click on an element like an icon, you should consult a screenshot to determine the coordinates of the element before moving the cursor.
* If you tried clicking on a program or link but it failed to load even after waiting, try adjusting your cursor position so that the tip of the cursor visually falls on the element that you want to click.
* Make sure to click any buttons, links, icons, etc with the cursor tip in the center of the element. Don't click boxes on their edges unless asked.""",
                "parameters": {
                    "properties": {
                        "action": {
                            "description": """The action to perform. The available actions are:
* `key`: Performs key down presses on the arguments passed in order, then performs key releases in reverse order.
* `type`: Type a string of text on the keyboard.
* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.
* `click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `left_click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `drag`: Click and drag the cursor to a specified (x, y) pixel coordinate on the screen.
* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate on the screen.
* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate on the screen.
* `double_click`: Double-click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `scroll`: Performs a scroll of the mouse scroll wheel.
* `wait`: Wait specified seconds for the change to happen.
* `terminate`: Terminate the current task and report its completion status.""",
                            "enum": ["key", "type", "mouse_move", "click", "left_click", "drag",
                                     "right_click", "middle_click", "double_click", "scroll", "wait", "terminate"],
                            "type": "string"
                        },
                        "keys": {"description": "Required only by `action=key`.", "type": "array"},
                        "text": {"description": "Required only by `action=type`.", "type": "string"},
                        "coordinate": {"description": "The x,y coordinates for mouse actions.", "type": "array"},
                        "coordinate2": {"description": "The x2,y2 coordinates for drag end position. Required only by `action=drag`.", "type": "array"},
                        "pixels": {"description": "The amount of scrolling.", "type": "number"},
                        "time": {"description": "The seconds to wait.", "type": "number"},
                        "status": {
                            "description": "The status of the task.",
                            "type": "string",
                            "enum": ["success", "failure"]
                        }
                    },
                    "required": ["action"],
                    "type": "object"
                }
            }
        }

        system_prompt = """# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
""" + json.dumps(tools_def) + """
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>

# Response format

For every step, respond in exactly this format:
1) A <think>...</think> block with your reasoning.
2) Action: a short imperative sentence describing what to do.
3) A single <tool_call>...</tool_call> block with the JSON.

# Thinking style rules

Your <think> block MUST follow these rules strictly:

Structure — use the Observe-Reason-Act pattern:
- FIRST, state what you see on screen. Start with "I can see...", "Looking at...", or "The [element] is now...".
- THEN, connect the observation to the task. Use "I need to..." or "I should...".
- FINALLY, state your intended action. End with "Let me..." or "I'll...".

Length — calibrate to the situation:
- Simple confirmation (a field is focused, a menu opened): 20-40 words.
- Standard navigation (click a button, type text): 40-80 words.
- Multi-step planning (need 3+ actions): 80-150 words. Use a numbered list.

Vocabulary — use these phrases consistently:
- For observations: "I can see", "is now", "Looking at", "appears to"
- For planning: "I need to", "I should", "The next step is"
- For intent: "Let me click on", "Let me type", "I'll scroll"
- For self-correction: "Actually," or "Wait —" (never "Hmm", "Oops", "No big deal")

Strictly FORBIDDEN inside <think>:
- Bold headers like **Title** or markdown formatting
- Starting with "Okay", "Alright", "Right", "So"
- Emotional language: exclamation marks, "Rookie mistake!", "damn", "Aha!"
- Meta-narration: "Here's my interpretation...", "tailored for an expert audience"
- Unnecessary repetition or going back and forth on the same point
- Speculation about frontend frameworks, event listeners, or implementation details
- Filler phrases: "No big deal", "these things happen", "the damn thing"

The Action line must be:
- A single imperative sentence, 8-15 words
- Starts with a verb: Click, Type, Scroll, Press, Drag, Wait
- Includes target and purpose: "Click on the Apply button to apply the filter"

# Examples

Example 1 (simple confirmation):
<think>
The Colors menu is now open. I can see the Desaturate option in the dropdown list. I need to click on it to convert the image to grayscale.
</think>
Action: Click on "Desaturate" in the Colors menu.
<tool_call>
{"name": "computer_use", "arguments": {"action": "click", "coordinate": [334, 245]}}
</tool_call>

Example 2 (standard navigation with context):
<think>
I can see the search box is active with a cursor blinking. I need to type the patient's name "Jayson Fadel" to search for their record. After typing, I should press Enter or click the search button to find the patient.

Let me type the patient's name in the search field.
</think>
Action: Type "Jayson Fadel" in the search field.
<tool_call>
{"name": "computer_use", "arguments": {"action": "type", "text": "Jayson Fadel"}}
</tool_call>

Example 3 (multi-step planning):
<think>
Looking at the current screenshot, the image has been loaded in the editor. The task requires applying a vintage sepia tone effect.

The steps to achieve this are:
1. First, desaturate the image to convert it to grayscale
2. Then, use the Colorize tool to add a brownish sepia tone

I need to start by accessing the Colors menu to find the Desaturate option. The Colors menu is visible in the menu bar at the top of the screen.

Let me click on the Colors menu to begin.
</think>
Action: Click on the Colors menu to access color adjustment tools.
<tool_call>
{"name": "computer_use", "arguments": {"action": "click", "coordinate": [334, 110]}}
</tool_call>

Example 4 (self-correction):
<think>
I can see that the search returned "No matching records found" with "Fadel" in the search field. There are 46 total entries in the system but the filter is not finding results.

Actually, I should try searching by Date of Birth instead. The patient's DOB is 1992-06-30. Let me clear the current field and try the Date of Birth search field.
</think>
Action: Clear the search field by triple-clicking to select all text.
<tool_call>
{"name": "computer_use", "arguments": {"action": "triple_click", "coordinate": [178, 333]}}
</tool_call>

Example 5 (task completion):
<think>
Looking at the current screenshot, the rectangular selection in the upper-right portion of the image has been deleted successfully. I can see the white rectangle where the content was removed.

The task has been completed. I should terminate with success status.
</think>
Action: Terminate the task with success status.
<tool_call>
{"name": "computer_use", "arguments": {"action": "terminate", "status": "success"}}
</tool_call>"""

        return system_prompt

    def step(self, obs, action_outputs):
        """
        Execute one agent step.

        Same as GeminiQwen3Agent.step() but with:
        - Configurable reasoning_effort passed to call_gemini_with_retry()
        - Configurable image resize resolution
        """
        # Save current observation
        self.save_observation(obs)
        self.step_idx += 1

        # Process image
        processed_image_b64 = self.process_image(obs['screen']['path'], resize_to=self.resize_to)
        self.screenshots.append(processed_image_b64)

        # Build messages (uses overridden get_system_prompt)
        messages = self.build_messages(processed_image_b64)

        messages[0]['cache_control'] = {"type": "ephemeral"}

        if self.debug and self.step_idx > 5:
            breakpoint()
        # Save messages for debugging
        try:
            message_file_path = os.path.join(
                self.save_folder_custom, f"messages_step_{self.step_idx}.json"
            )
            with open(message_file_path, "w") as f:
                json.dump(messages, f, indent=2)
        except Exception as e:
            if self.verbose:
                print(f"Failed to save messages: {e}")
        self.save_messages(messages)
        # Call LLM with configurable reasoning_effort and optional response prefix
        print(f"Calling Gemini with temperature: {self.temperature}, reasoning_effort: {self.reasoning_effort}, use_prefix: {self.use_response_prefix}")

        if self.use_response_prefix and self.reasoning_effort == 'none':
            # Use response prefix technique: add partial assistant message
            # to force Gemini to produce <think> blocks
            import litellm
            from dotenv import load_dotenv
            load_dotenv()

            call_messages = list(messages)
            call_messages.append({
                "role": "assistant",
                "content": [{"type": "text", "text": self.response_prefix}]
            })

            resp = litellm.completion(
                model='gemini/' + self.model,
                messages=call_messages,
                temperature=self.temperature,
                top_p=self.top_p,
                max_tokens=16384,
                reasoning_effort=self.reasoning_effort,
                timeout=600,
            )
            text = resp.choices[0].message.content
            if not text or text.strip() == '':
                # Fallback to standard call
                response = call_gemini_with_retry(
                    messages, self.model, self.temperature, self.top_p, self.top_k,
                    reasoning_effort=self.reasoning_effort,
                )
            else:
                response = self.response_prefix + text
        else:
            response = call_gemini_with_retry(
                messages, self.model, self.temperature, self.top_p, self.top_k,
                reasoning_effort=self.reasoning_effort,
            )

        if self.debug:
            breakpoint()

        # Store response for history
        self.responses.append(response)

        # Parse response
        parsed_response = parse_qwen3vl_response(response, scale_dims=True, scale_dims_ratio=(1920/1000, 1080/1000))

        # Store responses for later dumping
        if self.debug:
            breakpoint()
        self.all_model_responses.append(response)
        self.all_parsed_responses.append(parsed_response)

        # Extract actions and metadata
        actions = parsed_response['actions']
        metadata = parsed_response['metadata']

        # Update history with conclusion
        self.history.append(metadata['conclusion'])

        if self.verbose:
            print(f"Step {self.step_idx + 1}:")
            print(f"  Thought: {metadata['thought']}")
            print(f"  Conclusion: {metadata['conclusion']}")
            print(f"  Action Type: {metadata['action_type']}")
            print(f"  Actions: {actions}")

        # Check if terminal
        if metadata['is_terminal']:
            self.done = True
            return [{
                'tool_id': f'qwen3vl_step_{self.step_idx}',
                'actions': actions,
                'metadata': metadata
            }]

        # Check if wait action
        if metadata['wait_time'] is not None:
            return [{
                'tool_id': f'qwen3vl_step_{self.step_idx}',
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata
            }]

        # Regular actions (mouse, keyboard, etc.)
        return [{
            'tool_id': f'qwen3vl_step_{self.step_idx}',
            'actions': actions,
            'metadata': metadata
        }]
