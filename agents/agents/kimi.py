from agents.agents.base import BaseAgent
from agents.shared.llm_clients import call_kimi_azure, smart_resize, parse_qwen3vl_response
from PIL import Image
import json
import os
import copy
from io import BytesIO
import base64
import numpy as np


class CustomJSONEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, np.bool_):
            return bool(obj)
        # Let the base class default method raise the TypeError for other unhandled types
        return json.JSONEncoder.default(self, obj)


class KimiAzureAgent(BaseAgent):
    """
    Qwen3VL agent with prompt aligned to osworld implementation.
    Uses relative coordinate scaling (1000x1000 grid) and osworld-matching action enum.
    """

    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'Kimi-K2.5')
        # TODO: Fix this confusion
        self.decoding_params = self.agent_args.get('decoding_params', {})
        # self.temperature = self.decoding_params.get('temperature', 1.0)
        print('Agent args are: ', self.agent_args, 'and temperature is: ', self.agent_args.get('temperature', 1.0))
        self.temperature = self.agent_args.get('temperature', 1.0)

        self.top_p = self.decoding_params.get('top_p', 0.95)
        self.top_k = self.decoding_params.get('top_k', 20)
        self.max_tokens = self.decoding_params.get('max_tokens', 1500)
        self.history_n = self.agent_args.get('history_n', 1)
        self.history_n = 1

        # Setup custom save folder
        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()

        # Agent state
        self.done = False
        self.step_idx = -1

        # History for prompting (previous actions descriptions)
        self.history = []

        # Store processed screenshots and responses for multi-turn conversation
        self.screenshots = []
        self.responses = []

        # Store all responses for final dump
        self.all_model_responses = []
        self.all_parsed_responses = []

        # Mapping from base64 to file path for efficient message saving
        self.b64_to_path = {}

        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)

    def setup_custom_logger(self):
        """Setup custom save folder for agent artifacts."""
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        for run_number in range(0, 1000):
            if os.path.exists(f'{self.save_folder_custom}/run_{run_number}'):
                continue
            self.save_folder_custom = f'{self.save_folder_custom}/run_{run_number}'
            break
        os.makedirs(self.save_folder_custom, exist_ok=False)

    def save_observation(self, observation):
        """Save the current observation screenshot."""
        Image.open(observation['screen']['path']).save(
            f'{self.save_folder_custom}/observation_{self.step_idx}.png'
        )

    def save_messages(self, messages):
        """Save the messages to a file with base64 replaced by file paths."""
        messages_to_save = copy.deepcopy(messages)

        # Replace base64 data with file paths
        for msg in messages_to_save:
            if msg.get('role') != 'user' or not isinstance(msg.get('content'), list):
                continue
            for content in msg['content']:
                if content.get('type') != 'image_url':
                    continue
                url = content['image_url'].get('url', '')
                if 'base64,' in url:
                    b64 = url.split('base64,')[1]
                    if b64 in self.b64_to_path:
                        content['image_url']['url'] = self.b64_to_path[b64]

        with open(f'{self.save_folder_custom}/messages_step_{self.step_idx}.json', 'w') as f:
            json.dump(messages_to_save, f, indent=2)

    def init(self, task_description, display_resolution, save_path):
        """Initialize agent with task description and environment details."""
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path

    def process_image(self, image_path):
        """
        Process an image for Qwen VL models with smart resize.
        Returns tuple of (base64_string, processed_image_path).
        """
        image = Image.open(image_path)
        width, height = image.size

        if self.verbose:
            print(f"Original screen resolution: {width}x{height}")

        # Apply smart resize
        resized_height, resized_width = smart_resize(
            height=height,
            width=width,
            factor=32,
            max_pixels=16 * 16 * 4 * 1280,
        )
        print('Resized image resolution: ', resized_width, resized_height)
        image = image.resize((resized_width, resized_height))

        if self.verbose:
            print(f"Processed image resolution: {resized_width}x{resized_height}")

        # Save processed image to disk (replaces separate observation save)
        processed_path = f'{self.save_folder_custom}/observation_{self.step_idx}.png'
        image.save(processed_path, format="PNG")

        # Convert to base64 by reading the saved file (ensures exact match)
        with open(processed_path, 'rb') as f:
            processed_bytes = f.read()

        return base64.b64encode(processed_bytes).decode("utf-8"), processed_path

    def build_messages(self, current_screenshot_b64):
        """
        Build the messages list for LLM call, including history if available.
        """
        # System prompt
        system_prompt = self.get_system_prompt()

        # Instruction prompt
        current_step = self.step_idx + 1
        history_start_idx = max(0, current_step - self.history_n)

        previous_actions = []
        for i in range(history_start_idx):
            if i < len(self.history):
                previous_actions.append(f"Step {i+1}: {self.history[i]}")
        previous_actions_str = (
            "\n".join(previous_actions) if previous_actions else "None"
        )
        print('Len of previous actions: ', len(previous_actions))

        instruction_prompt = f"""Please generate the next move according to the UI screenshot, instruction and previous actions.

Instruction: {self.task_description}

Previous actions:
{previous_actions_str}"""

        messages = [
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": system_prompt},
                ],
            }
        ]

        # Add conversation history if available
        history_len = min(self.history_n, len(self.responses))
        if history_len > 0:
            history_responses = self.responses[-history_len:]
            history_screenshots = self.screenshots[-history_len - 1:-1]

            for idx in range(history_len):
                if idx < len(history_screenshots):
                    screenshot_b64 = history_screenshots[idx]
                    if idx == 0:
                        # First turn includes the instruction
                        img_url = f"data:image/png;base64,{screenshot_b64}"
                        messages.append({
                            "role": "user",
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {"url": img_url},
                                },
                                {"type": "text", "text": instruction_prompt},
                            ],
                        })
                    else:
                        # Subsequent turns only include screenshot
                        img_url = f"data:image/png;base64,{screenshot_b64}"
                        messages.append({
                            "role": "user",
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {"url": img_url},
                                }
                            ],
                        })

                # Add assistant response
                messages.append({
                    "role": "assistant",
                    "content": [
                        {"type": "text", "text": f"{history_responses[idx]}"},
                    ],
                })

            # Add current screenshot
            curr_img_url = f"data:image/png;base64,{current_screenshot_b64}"
            messages.append({
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": curr_img_url},
                    },
                    # {"type": "text", "text": instruction_prompt},
                ],
            })
        else:
            # First turn
            curr_img_url = f"data:image/png;base64,{current_screenshot_b64}"
            messages.append({
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": curr_img_url},
                    },
                    {"type": "text", "text": instruction_prompt},
                ],
            })

        return messages

    def get_system_prompt(self):
        """Get the system prompt for Qwen3VL (relative coordinate mode, osworld-aligned)."""
        tools_def = {
            "type": "function",
            "function": {
                "name_for_human": "computer_use",
                "name": "computer_use",
                "description": """Use a mouse and keyboard to interact with a computer, and take screenshots.
* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.
* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions. E.g. if you click on Firefox and a window doesn't open, try wait and taking another screenshot.
* The screen's resolution is 1000x1000.
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
* `left_click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `left_click_drag`: Click and drag the cursor to a specified (x, y) pixel coordinate on the screen.
* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate on the screen.
* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate on the screen.
* `double_click`: Double-click the left mouse button at a specified (x, y) pixel coordinate on the screen.
* `scroll`: Performs a scroll of the mouse scroll wheel.
* `wait`: Wait specified seconds for the change to happen.
* `terminate`: Terminate the current task and report its completion status.""",
                            "enum": ["key", "type", "mouse_move", "left_click", "left_click_drag",
                                     "right_click", "middle_click", "double_click", "scroll", "wait", "terminate"],
                            "type": "string"
                        },
                        "keys": {"description": "Required only by `action=key`.", "type": "array"},
                        "text": {"description": "Required only by `action=type`.", "type": "string"},
                        "coordinate": {"description": "The x,y coordinates for mouse actions.", "type": "array"},
                        "coordinate2": {"description": "The x2,y2 coordinates for drag end position. Required only by `action=left_click_drag`.", "type": "array"},
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

Response format for every step:
1) Action: a short imperative describing what to do in the UI.
2) A single <tool_call>...</tool_call> block containing only the JSON: {"name": <function-name>, "arguments": <args-json-object>}.

Rules:
- Output exactly in the order: Action, <tool_call>.
- Be brief: one sentence for Action.
- Do not output anything else outside those parts.
- If finishing, use action=terminate in the tool call."""

        return system_prompt

    def step(self, obs, action_outputs):
        """
        Execute one agent step.

        Args:
            obs: Current observation from environment
            action_outputs: List of outputs from previous actions (not used for Qwen3VL agent)

        Returns:
            List of action groups to execute
        """
        self.step_idx += 1

        # Process image and save to disk (also saves as observation)
        processed_image_b64, processed_path = self.process_image(obs['screen']['path'])
        self.screenshots.append(processed_image_b64)

        # Store mapping for efficient message saving
        self.b64_to_path[processed_image_b64] = processed_path

        # Build messages
        messages = self.build_messages(processed_image_b64)


        # Save messages with file paths instead of base64
        self.save_messages(messages)

        # Call LLM
        print(f"Calling LLM with temperature: {self.temperature}")
        response = call_kimi_azure(
            messages,
            self.model,
            self.temperature,
            self.top_p,
            self.top_k,
            # self.max_tokens
        )


        # Store response for history
        self.responses.append(response)

        # Parse response using existing parse_qwen3vl_response function
        parsed_response = parse_qwen3vl_response(response, scale_dims=True, scale_dims_ratio=(1920/1000, 1080/1000))

        # Store responses for later dumping
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
                'actions': actions,  # Empty list from parse_owl_response
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

    def finish(self, *args, **kwargs):
        """Save all agent artifacts."""
        # Save responses as JSON
        json.dump(
            {
                'model_responses': self.all_model_responses,
                'parsed_responses': self.all_parsed_responses
            },
            open(f'{self.save_path}/responses.json', 'w'),
            indent=4
        )

        json.dump(
            self.all_parsed_responses,
            open(f'{self.save_path}/parsed_responses.json', 'w'),
            indent=4
        )

        # Also save to custom folder
        json.dump(
            {
                'model_responses': self.all_model_responses,
                'parsed_responses': self.all_parsed_responses,
                'history': self.history
            },
            open(f'{self.save_folder_custom}/responses.json', 'w'),
            indent=4
        )

        json.dump(
            self.all_parsed_responses,
            open(f'{self.save_folder_custom}/parsed_responses.json', 'w'),
            indent=4
        )

        # Save info if provided
        if 'info' in kwargs:
            info = kwargs['info']
            try:
                json.dump(info, open(f'{self.save_folder_custom}/info.json', 'w'), indent=4)
            except Exception as e:
                json.dump(info, open(f'{self.save_folder_custom}/info.json', 'w'), indent=4, cls=CustomJSONEncoder)
