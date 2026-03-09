from datetime import datetime


SYSTEM_PROMPT = '\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>\n{"type": "function", "function": {"name": "computer_use", "description": "Use a mouse and keyboard to interact with a computer, and take screenshots.\\n* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.\\n* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions. E.g. if you click on Firefox and a window doesn\'t open, try wait and taking another screenshot.\\n* The screen\'s resolution is 1932x1092.\\n* Whenever you intend to move the cursor to click on an element like an icon, you should consult a screenshot to determine the coordinates of the element before moving the cursor.\\n* If you tried clicking on a program or link but it failed to load, even after waiting, try adjusting your cursor position so that the tip of the cursor visually falls on the element that you want to click.\\n* Make sure to click any buttons, links, icons, etc with the cursor tip in the center of the element. Don\'t click boxes on their edges unless asked.", "parameters": {"properties": {"action": {"description": "The action to perform. The available actions are:\\n* `key`: Performs key down presses on the arguments passed in order, then performs key releases in reverse order.\\n* `type`: Input a string of text. Use the `clear` parameter to decide whether to overwrite the existing text, and use the `enter` parameter to decide whether the enter key should be pressed after typing the text.\\n* `mouse_move`: Move the cursor to a specified (x, y) pixel coordinate on the screen.\\n* `click`: Click the left mouse button at a specified (x, y) pixel coordinate on the screen.\\n* `drag`: Click at a specified (x, y) pixel coordinate on the screen, and drag the cursor to another specified (x2, y2) pixel coordinate on the screen.\\n* `right_click`: Click the right mouse button at a specified (x, y) pixel coordinate on the screen.\\n* `middle_click`: Click the middle mouse button at a specified (x, y) pixel coordinate on the screen.\\n* `double_click`: Double-click the left mouse button at a specified (x, y) pixel coordinate on the screen.\\n* `scroll`: Performs a scroll of the mouse scroll wheel.\\n* `wait`: Wait specified seconds for the change to happen.\\n* `terminate`: Terminate the current task and report its completion status.", "enum": ["key", "type", "mouse_move", "click", "drag", "right_click", "middle_click", "double_click", "scroll", "wait", "terminate"], "type": "string"}, "keys": {"description": "Required only by `action=key`.", "type": "array"}, "text": {"description": "Required only by `action=type`.", "type": "string"}, "clear": {"description": "Assign it to 1 if the text should overwrite the existing text, otherwise assign it to 0. Using this argument clears all text in an element. Required only by `action=type`.", "type": "number"}, "enter": {"description": "Assign it to 1 if the enter key should be pressed after typing the text, otherwise assign it to 0. Required only by `action=type`.", "type": "number"}, "coordinate": {"description": "(x, y): The x (pixels from the left edge) and y (pixels from the top edge) coordinates to move the mouse to.", "type": "array"}, "coordinate2": {"description": "(x2, y2): The x2 (pixels from the left edge) and y2 (pixels from the top edge) coordinates to drag the cursor to. Required only by `action=drag`.", "type": "array"}, "pixels": {"description": "The amount of scrolling to perform. Positive values scroll up, negative values scroll down. This value should be between -5 and 5. Required only by `action=scroll`.", "type": "number"}, "time": {"description": "The seconds to wait. Required only by `action=wait`.", "type": "number"}, "status": {"description": "The status of the task. Required only by `action=terminate`.", "type": "string", "enum": ["success", "failure"]}}, "required": ["action"], "type": "object"}}}\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{"name": <function-name>, "arguments": <args-json-object>}\n</tool_call>'

CLAUDE_SYSTEM_PROMPT = f"""<SYSTEM_CAPABILITY>
* You are utilising an Ubuntu virtual machine with internet access.
* You can feel free to install Ubuntu applications with your bash tool. Use curl instead of wget.
* To open firefox, please just click on the firefox icon.  Note, firefox-esr is what is installed on your system.
* Using bash tool you can start GUI applications, but you need to set export DISPLAY=:1 and use a subshell. For example "(DISPLAY=:1 xterm &)". GUI apps run with bash tool will appear within your desktop environment, but they may take some time to appear. Take a screenshot to confirm it did.
* When using your bash tool with commands that are expected to output very large quantities of text, redirect into a tmp file and use str_replace_based_edit_tool or `grep -n -B <lines before> -A <lines after> <query> <filename>` to confirm output.
* When viewing a page it can be helpful to zoom out so that you can see everything on the page.  Either that, or make sure you scroll down to see everything before deciding something isn't available.
* When using your computer function calls, they take a while to run and send back to you.  Where possible/feasible, try to chain multiple of these calls all into one function calls request.
* The current date is {datetime.today().strftime('%A, %B %-d, %Y')}.
</SYSTEM_CAPABILITY>

<IMPORTANT>
* When using Firefox, if a startup wizard appears, IGNORE IT.  Do not even click "skip this step".  Instead, click on the address bar where it says "Search or enter address", and enter the appropriate search term or URL there.
* If the item you are looking at is a pdf, if after taking a single screenshot of the pdf it seems that you want to read the entire document instead of trying to continue to read the pdf from your screenshots + navigation, determine the URL, use curl to download the pdf, install and use pdftotext to convert it to a text file, and then read that text file directly with your str_replace_based_edit_tool.
</IMPORTANT>"""

CLAUDE_SYSTEM_PROMPT_MASTER = CLAUDE_SYSTEM_PROMPT + """\n\nIf you see cloudflare captcha or verification, go ahead and complete it, without asking for permission."""

CLAUDE_SYSTEM_PROMPT_CAREFUL = CLAUDE_SYSTEM_PROMPT + """\n\nAfter each step, take a screenshot and carefully evaluate if you have achieved the right outcome. Explicitly show your thinking: "I have evaluated step X..." If not correct, try again. Only when you confirm a step was executed correctly should you move on to the next one."""

CLAUDE_SYSTEM_PROMPT_ZOOM = CLAUDE_SYSTEM_PROMPT + """\n\n<ZOOM_FEEDBACK>
* After each mouse interaction (click, double-click, right-click, or drag), you will receive a zoomed-in 100x100 pixel crop of the area around your mouse coordinates.
* This zoom crop is provided to help you verify that your mouse action targeted the correct UI element.
* Please review the zoomed area and confirm whether your action was accurate before proceeding to the next step.
* If the zoomed area shows that you missed the intended target, you can take corrective action by clicking at adjusted coordinates.
</ZOOM_FEEDBACK>"""


USER_PROMPT = '''Please generate the next move according to the UI screenshot, instruction and previous actions.
    Instruction: {instruction}
    Previous actions:
    {history}
    Before answering, explain your reasoning step-by-step in <thinking></thinking> tags, and insert them before the <tool_call></tool_call> XML tags.\nAfter answering, summarize your action in <conclusion></conclusion> tags, and insert them after the <tool_call></tool_call> XML tags.'''


GEMINI_SYSTEM_PROMPT = """<SYSTEM_CAPABILITY>
* You are utilising an virtual machine with internet access.
* You can feel free to do anything.
* Each turn you will be provided current screenshot of the screen.
* If you want to run a specific gui application, make sure to set the display variable to :1.
* When using your computer function calls, they take a while to run and send back to you.  Where possible/feasible, try to chain multiple of these calls all into one function calls request.
* Enclose all your tool calls inside <tool_call></tool_call> tags.

You have access to the following tools:
<<TOOL_DEFINITIONS>>

Example tool call usage:

```
....thinking....
....response....

<tool_call>
{"name": "computer_use", "arguments": {"action": "click", "coordinate": [100, 200]}}
</tool_call>

<tool_call>
{"name": "computer_use", "arguments": {"action": "type", "keys": ["Control", "a"]}}
</tool_call>

<tool_call>
{"name": "computer_use", "arguments": {"action": "wait", "time": 2}}
</tool_call>

<tool_call>
{"name": "computer_use", "arguments": {"action": "key", "type": "Hello World!"}}
</tool_call>
```

The above example would make 4 tool calls in order.

</SYSTEM_CAPABILITY>
"""

GEMINI_SYSTEM_PROMPT_SINGLE_STEP = """<SYSTEM_CAPABILITY>
* You are utilising an virtual machine with internet access.
* You can feel free to do anything.
* Each turn you will be provided current screenshot of the screen.
* If you want to run a specific gui application, make sure to set the display variable to :1.
* When using your computer function calls, they take a while to run and send back to you.
* Enclose your tool call inside <tool_call></tool_call> tags.
* Important: Only use one tool call per turn.

You have access to the following tools:
<<TOOL_DEFINITIONS>>

Example tool call usage:

```
....thinking....
....response....

<tool_call>
{"name": "computer_use", "arguments": {"action": "click", "coordinate": [100, 200]}}
</tool_call>
```

The above example would make 1 tool call and click at coordinate [100, 200].

</SYSTEM_CAPABILITY>"""


TOOL_DEFINITIONS = {
            "type": "function", 
            "function": {
                "name": "computer_use", 
                "description": f"""Use a mouse and keyboard to interact with a computer, and take screenshots.
* This is an interface to a desktop GUI. You do not have access to a terminal or applications menu. You must click on desktop icons to start applications.
* Some applications may take time to start or process actions, so you may need to wait and take successive screenshots to see the results of your actions. E.g. if you click on Firefox and a window doesn't open, try wait and taking another screenshot.
* The screen's resolution is 1280x720.
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
