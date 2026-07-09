def add_cache_blocks(messages):
    """Place an ephemeral cache marker on the last content block of the last
    message, then keep only the four most-recent markers across the history.

    The last block can be a text block, an image block, or a tool_result block
    (after the multi-tool turn fix), so we can't assume it carries a `text`
    field. We only skip when it is a text block that is literally empty —
    caching an empty string wastes a breakpoint.
    """
    assert "content" in messages[-1]
    if isinstance(messages[-1]["content"], str):
        messages[-1]["content"] = [{"type": "text", "text": messages[-1]["content"]}]

    last_block = messages[-1]["content"][-1]
    is_empty_text = (
        isinstance(last_block, dict)
        and last_block.get("type") == "text"
        and not last_block.get("text")
    )
    if not is_empty_text and isinstance(last_block, dict):
        last_block["cache_control"] = {"type": "ephemeral"}

    counts = 0
    for i in range(len(messages) - 1, -1, -1):
        content = messages[i].get("content")
        if not isinstance(content, list) or not content:
            continue
        tail = content[-1]
        if not isinstance(tail, dict) or "cache_control" not in tail:
            continue
        counts += 1
        if counts > 4:
            del tail["cache_control"]

    return messages