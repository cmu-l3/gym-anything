def add_cache_blocks(messages):
    # Add cache block to last message
    assert "content" in messages[-1]
    if isinstance(messages[-1]["content"], str):
        messages[-1]["content"] = [{"type": "text", "text": messages[-1]["content"]}]
    try:
        if messages[-1]["content"][-1]["text"] != "":
            messages[-1]["content"][-1]["cache_control"] = {"type": "ephemeral"}
    except Exception as e:
        messages[-1]["content"][-1]["cache_control"] = {"type": "ephemeral"}
        print(f"Error adding cache block: {e}")
        pass
    counts = 0
    for i in range(len(messages) - 1, -1, -1):
        if (
            isinstance(messages[i]["content"], list)
            and "cache_control" in messages[i]["content"][-1]
        ):
            counts += 1
            if counts > 4:
                del messages[i]["content"][-1]["cache_control"]

    return messages