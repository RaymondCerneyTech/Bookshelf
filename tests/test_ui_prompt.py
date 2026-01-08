from goldevidencebench.ui_prompt import (
    DEFAULT_UI_INSTRUCTION,
    build_ui_prompt,
    format_ui_candidate,
)


def test_ui_prompt_uses_instruction() -> None:
    row = {"instruction": "Click the Save button."}
    candidates = [
        {
            "candidate_id": "btn_save_primary",
            "label": "Save",
            "role": "button",
            "action_type": "click",
            "app_path": "Settings > Profile",
            "visible": True,
            "enabled": True,
            "modal_scope": "profile_dialog",
            "bbox": [120, 220, 80, 28],
        }
    ]
    prompt = build_ui_prompt(row, candidates)
    assert "Click the Save button." in prompt
    assert "btn_save_primary" in prompt


def test_ui_prompt_default_instruction() -> None:
    row = {}
    candidates = [
        {
            "candidate_id": "btn_next",
            "label": "Next",
            "role": "button",
            "action_type": "click",
            "app_path": "Checkout > Cart",
            "visible": True,
            "enabled": True,
            "modal_scope": None,
            "bbox": [820, 620, 90, 28],
        }
    ]
    prompt = build_ui_prompt(row, candidates)
    assert DEFAULT_UI_INSTRUCTION in prompt


def test_format_ui_candidate_includes_key_fields() -> None:
    candidate = {
        "candidate_id": "btn_continue_modal",
        "label": "Continue",
        "role": "button",
        "action_type": "click",
        "app_path": "Billing > Review",
        "visible": True,
        "enabled": True,
        "modal_scope": "payment_modal",
        "bbox": [700, 460, 110, 32],
    }
    line = format_ui_candidate(candidate)
    assert "btn_continue_modal" in line
    assert "Continue" in line
    assert "payment_modal" in line
