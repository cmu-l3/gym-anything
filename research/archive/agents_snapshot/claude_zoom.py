from agents.claude import ClaudeAgent
from agent_prompts import CLAUDE_SYSTEM_PROMPT_ZOOM
from agent_utils import create_zoom_crop


class ClaudeZoomAgent(ClaudeAgent):
    """
    Claude agent with zoom feedback on mouse interactions.
    After each mouse action (click, double-click, right-click, drag),
    provides a 100x100 pixel zoomed crop around the interaction coordinates.
    """
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Override system prompt to use zoom version
        self.system_prompt = CLAUDE_SYSTEM_PROMPT_ZOOM
        # Track mouse actions for zoom feedback
        self.mouse_actions = {}  # tool_id -> (x, y, action_type)
    
    def _get_actions_from_response(self, response_content):
        """Override to track mouse interaction coordinates."""
        all_actions = super()._get_actions_from_response(response_content)
        
        # Track mouse actions for zoom feedback
        for action_group in all_actions:
            tool_id = action_group['tool_id']
            actions = action_group['actions']
            
            # Check if any action is a mouse interaction
            for action in actions:
                if 'mouse' in action:
                    # breakpoint()
                    mouse_action = action['mouse']
                    # Extract coordinates based on action type
                    coords = None
                    action_type = None
                    
                    if 'left_click' in mouse_action:
                        coords = mouse_action['left_click']
                        action_type = 'click'
                    elif 'right_click' in mouse_action:
                        coords = mouse_action['right_click']
                        action_type = 'right_click'
                    elif 'double_click' in mouse_action:
                        coords = mouse_action['double_click']
                        action_type = 'double_click'
                    elif 'move' in mouse_action:
                        # For drag operations, we track the final position
                        coords = mouse_action['move']
                        # Check if this is part of a drag (has button down before it)
                        if len(actions) > 1:
                            action_type = 'drag'
                        else:
                            action_type = 'move'
                    
                    if coords and action_type in ['click', 'left_click', 'right_click', 'double_click', 'drag']:
                        self.mouse_actions[tool_id] = (coords[0], coords[1], action_type)
                        break  # Only track first mouse action per tool call
        
        return all_actions
    
    def _convert_action_outputs(self, action_outputs):
        """Override to add zoom crops for mouse interactions."""
        tool_call_content = []
        
        for action_output in action_outputs:
            tool_id = action_output['tool_id']
            
            # Get base tool content
            tool_content = self._get_tool_content_from_output(action_output)
            # breakpoint()
            # Check if this was a mouse action that needs zoom feedback
            if tool_id in self.mouse_actions and action_output['action'] == 'other':
                x, y, action_type = self.mouse_actions[tool_id]
                
                # Get the current observation path (last saved observation)
                obs_path = f'{self.save_folder_custom}/observation_{self.step_idx-1}.png'
                
                try:
                    # Create zoom crop
                    # breakpoint()
                    zoom_crop_base64 = create_zoom_crop(obs_path, x, y, crop_size=100)
                    
                    # Add zoom image to the tool result content
                    tool_content['content'].append({
                        'type': 'text',
                        'text': f'Zoomed view (100x100 pixels) around your {action_type} at coordinates ({x}, {y}):'
                    })
                    tool_content['content'].append({
                        'type': 'image',
                        'source': {
                            'type': 'base64',
                            'media_type': 'image/png',
                            'data': zoom_crop_base64,
                        },
                    })
                except Exception as e:
                    # If zoom creation fails, log but continue
                    if self.verbose:
                        print(f"Failed to create zoom crop: {e}")
                
                # Clean up tracked action
                del self.mouse_actions[tool_id]
            
            tool_call_content.append(tool_content)
        
        return tool_call_content