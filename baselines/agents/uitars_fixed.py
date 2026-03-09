from baselines.agents.base import BaseAgent
from baselines.common.llm_clients import call_llm, smart_resize_uitars, parse_uitars_response, pil_to_base64
from PIL import Image
import json
import os
from io import BytesIO
import base64


# Prompt template with thinking (uses {language} placeholder) - SAME AS ORIGINAL
COMPUTER_USE_DOUBAO = """You are a GUI agent. You are given a task and your action history, with screenshots. You need to perform the next action to complete the task.

## Output Format
You should first think about the reasoning process in the mind and then provide the user with the answer. 
The reasoning process is enclosed within <think> </think> tags
After the <think> tags, you should place final answer, which concludes your summarized thought and your action.

For example,
```
<think>detailed reasoning content here</think>
Thought: a small plan and finally summarize your next action (with its target element) in one sentence
Action: ...
```

## Action Space

click(point='<point>x1 y1</point>')
left_double(point='<point>x1 y1</point>')
right_single(point='<point>x1 y1</point>')
drag(start_point='<point>x1 y1</point>', end_point='<point>x2 y2</point>')
hotkey(key='ctrl c') # Split keys with a space and use lowercase. Also, do not use more than 3 keys in one hotkey action.
type(content='xxx') # Use escape characters \\', \\", and \\n in content part to ensure we can parse the content in normal python string format. If you want to submit your input, use \\n at the end of content. 
scroll(point='<point>x1 y1</point>', direction='down or up or right or left') # Show more information on the `direction` side.
wait() #Sleep for 5s and take a screenshot to check for any changes.
finished(content='xxx') # Use escape characters \\', \\", and \\n in content part to ensure we can parse the content in normal python string format.

## Output Example
<think>Now that...</think>
Thought: Let's click ...
Action: click(point='<point>100 200</point>')

## Note
- Use {language} in `Thought` part.
- Write a small plan and finally summarize your next action (with its target element) in one sentence in `Thought` part.
- If you have executed several same actions (like repeatedly clicking the same point) but the screen keeps no change, please try to execute a modified action when necessary.

## User Instruction
{instruction}
"""

# Prompt template without thinking - FIXED: uses {language} instead of hardcoded "Chinese"
COMPUTER_USE_NO_THINKING = """You are a GUI agent. You are given a task and your action history, with screenshots. You need to perform the next action to complete the task.

## Output Format
```
Thought: ...
Action: ...
```

## Action Space

click(point='<point>x1 y1</point>')
left_double(point='<point>x1 y1</point>')
right_single(point='<point>x1 y1</point>')
drag(start_point='<point>x1 y1</point>', end_point='<point>x2 y2</point>')
hotkey(key='ctrl c') # Split keys with a space and use lowercase. Also, do not use more than 3 keys in one hotkey action.
type(content='xxx') # Use escape characters \\', \\", and \\n in content part to ensure we can parse the content in normal python string format. If you want to submit your input, use \\n at the end of content. 
scroll(point='<point>x1 y1</point>', direction='down or up or right or left') # Show more information on the `direction` side.
wait() #Sleep for 5s and take a screenshot to check for any changes.
finished(content='xxx') # Use escape characters \\', \\", and \\n in content part to ensure we can parse the content in normal python string format.


## Note
- Use {language} in `Thought` part.
- Write a small plan and finally summarize your next action (with its target element) in one sentence in `Thought` part.

## User Instruction
{instruction}
"""


class UITarsFixedAgent(BaseAgent):
    """
    UI-TARS agent implementation (Fixed version).
    
    Fixes applied from original uitars.py:
    - Issue 6: History message building logic aligned with uitars_from_osworld.py
      (All assistant responses included, but only last N images sent)
    - Issue 7: Language setting properly dynamic in both thinking/no-thinking modes
      (COMPUTER_USE_NO_THINKING now uses {language} instead of hardcoded "Chinese")
    - Issue 8: Default language behavior aligned
    
    Supports models like DoubAO and similar architectures with special prompting.
    """
    
    def __init__(self, *args, **kwargs):
        self.agent_args = kwargs.get('agent_args', {})
        self.model = self.agent_args.get('model', 'doubao-vision')
        self.decoding_params = self.agent_args.get('decoding_params', {})
        self.temperature = self.decoding_params.get('temperature', 0.0)
        self.top_p = self.decoding_params.get('top_p', 0.9)
        self.max_tokens = self.decoding_params.get('max_tokens', 3000)
        self.history_n = self.agent_args.get('history_n', 1)  # UITars typically uses 5
        print(f"History n: {self.history_n}")
        
        # Language parameter with default
        self.language = self.agent_args.get('language', 'English')
        self.use_thinking = self.agent_args.get('use_thinking', False)
        
        # Select prompt template based on thinking mode (same as original)
        if self.use_thinking:
            self.system_prompt = COMPUTER_USE_DOUBAO
        else:
            self.system_prompt = COMPUTER_USE_NO_THINKING
        
        # Setup custom save folder
        self.exp_name = self.agent_args.get('exp_name', 'exp')
        self.setup_custom_logger()
        
        # Agent state
        self.done = False
        self.step_idx = -1
        
        # History for prompting (previous thought/actions)
        self.history = []
        
        # Store processed screenshots and responses for multi-turn conversation
        # Fix #6: Separate storage for history_images (trimmed) and all responses
        self.history_images = []  # Will be trimmed to last history_n
        self.history_responses = []  # All responses kept
        
        # Store all responses for final dump
        self.all_model_responses = []
        self.all_parsed_responses = []
        
        self.debug = kwargs.get('debug', False)
        self.verbose = kwargs.get('verbose', False)
    
    def setup_custom_logger(self):
        """Setup custom save folder for agent artifacts."""
        task_name = self.agent_args.get('task_name', 'task')
        self.save_folder_custom = f'all_runs/{self.exp_name}/{self.model}/{task_name}'
        for run_number in range(0, 100):
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
        """Save the messages to a file."""
        with open(f'{self.save_folder_custom}/messages_step_{self.step_idx}.json', 'w') as f:
            json.dump(messages, f, indent=2)
    
    def init(self, task_description, display_resolution, save_path):
        """Initialize agent with task description and environment details."""
        self.task_description = task_description
        self.display_resolution = display_resolution
        self.save_path = save_path
    
    def process_image(self, image_path):
        """
        Process an image for UITars models with smart resize.
        Returns base64 encoded processed image.
        """
        image = Image.open(image_path)
        width, height = image.size
        
        if self.verbose:
            print(f"Original screen resolution: {width}x{height}")
        
        # Apply smart resize for UITars
        resized_height, resized_width = smart_resize_uitars(
            height=height,
            width=width,
            factor=28,
            max_pixels=16384 * 28 * 28,
            min_pixels=100 * 28 * 28,
        )
        
        image = image.resize((resized_width, resized_height))
        
        if self.verbose:
            print(f"Processed image resolution: {resized_width}x{resized_height}")
        
        # Convert to base64
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        processed_bytes = buffer.getvalue()
        
        return base64.b64encode(processed_bytes).decode("utf-8")
    
    def build_messages(self, current_screenshot_b64):
        """
        Build the messages list for LLM call, including history if available.
        
        Fix #6: Aligned with uitars_from_osworld.py history building logic:
        - All assistant responses are included
        - Only the last history_n images are sent (with corresponding user messages)
        - Images appear before their corresponding assistant responses
        - Uses .format() with {instruction} and {language} placeholders
        """
        # Format system prompt with instruction and language (same as original)
        formatted_prompt = self.system_prompt.format(
            instruction=self.task_description,
            language=self.language
        )
        
        messages = [
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": formatted_prompt},
                ],
            }
        ]
        
        # Fix #6: Match uitars_from_osworld.py history building logic exactly
        # - Iterate over ALL history responses
        # - Only add images for the last history_n turns
        # - All assistant responses are added
        
        images = self.history_images  # Already trimmed to last history_n
        image_num = 0
        
        if len(self.history_responses) > 0:
            for history_idx, history_response in enumerate(self.history_responses):
                # Only send images for the last history_n responses
                # Condition: history_idx + history_n > len(history_responses)
                # Using '>' (not '>=') to match uitars_from_osworld.py exactly
                if history_idx + self.history_n > len(self.history_responses):
                    if image_num < len(images):
                        img_url = f"data:image/png;base64,{images[image_num]}"
                        messages.append({
                            "role": "user",
                            "content": [
                                {
                                    "type": "image_url",
                                    "image_url": {"url": img_url},
                                }
                            ],
                        })
                        image_num += 1
                
                # Always add assistant response
                messages.append({
                    "role": "assistant",
                    "content": [
                        {"type": "text", "text": history_response},
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
                    }
                ],
            })
        else:
            # First turn - just add current screenshot
            curr_img_url = f"data:image/png;base64,{current_screenshot_b64}"
            messages.append({
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": curr_img_url},
                    }
                ],
            })
        
        return messages
    
    def step(self, obs, action_outputs):
        """
        Execute one agent step.
        
        Args:
            obs: Current observation from environment
            action_outputs: List of outputs from previous actions (not used for UITars agent)
        
        Returns:
            List of action groups to execute
        """
        # Save current observation
        self.save_observation(obs)
        self.step_idx += 1
        
        # Process image
        processed_image_b64 = self.process_image(obs['screen']['path'])
        
        # Fix #6: Store image in history_images and trim to last history_n
        self.history_images.append(processed_image_b64)
        if len(self.history_images) > self.history_n:
            self.history_images = self.history_images[-self.history_n:]
        
        # Build messages
        messages = self.build_messages(processed_image_b64)
        
        if self.debug and self.step_idx > 5:
            breakpoint()
        
        # Save messages for debugging
        try:
            self.save_messages(messages)
        except Exception as e:
            if self.verbose:
                print(f"Failed to save messages: {e}")
        
        # Call LLM
        response = call_llm(
            messages, 
            self.model, 
            self.temperature, 
            self.top_p,
            max_tokens=self.max_tokens
        )
        
        if self.debug:
            breakpoint()
        
        # Fix #6: Store response in history_responses (keep all, don't trim)
        self.history_responses.append(response)
        
        # Parse response using UITars parser
        width, height = self.display_resolution
        parsed_response = parse_uitars_response(response, origin_height=height, origin_width=width)
        
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
                'tool_id': f'uitars_step_{self.step_idx}',
                'actions': actions,
                'metadata': metadata
            }]
        
        # Check if wait action
        if metadata['wait_time'] is not None:
            return [{
                'tool_id': f'uitars_step_{self.step_idx}',
                'actions': [{'action': 'wait', 'time': metadata['wait_time']}],
                'metadata': metadata
            }]
        
        # Regular actions (mouse, keyboard, etc.)
        return [{
            'tool_id': f'uitars_step_{self.step_idx}',
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
            json.dump(info, open(f'{self.save_folder_custom}/info.json', 'w'), indent=4)
