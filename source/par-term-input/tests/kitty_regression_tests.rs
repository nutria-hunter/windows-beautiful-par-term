use par_term_input::{InputHandler, KeyInput};
use winit::event::{ElementState, Modifiers};
use winit::keyboard::{Key, KeyCode, ModifiersState, NamedKey, PhysicalKey};

fn encode(key: Key, code: KeyCode, modifiers: ModifiersState, flags: u16) -> Vec<u8> {
    let mut handler = InputHandler::new();
    handler.modifiers = Modifiers::from(modifiers);
    handler
        .handle_key_input_with_modes(
            &KeyInput {
                logical_key: key,
                physical_key: PhysicalKey::Code(code),
                state: ElementState::Pressed,
            },
            0,
            false,
            flags,
        )
        .unwrap()
}

#[test]
fn kitty_pi_flags_preserve_text_and_shell_recovery_keys() {
    for (key, code, expected) in [
        (Key::Character("a".into()), KeyCode::KeyA, "a"),
        (Key::Named(NamedKey::Space), KeyCode::Space, " "),
        (Key::Named(NamedKey::Enter), KeyCode::Enter, "\r"),
        (Key::Named(NamedKey::Tab), KeyCode::Tab, "\t"),
        (Key::Named(NamedKey::Backspace), KeyCode::Backspace, "\x7f"),
    ] {
        assert_eq!(
            encode(key, code, ModifiersState::empty(), 7),
            expected.as_bytes()
        );
    }
    assert_eq!(
        encode(
            Key::Character("!".into()),
            KeyCode::Digit1,
            ModifiersState::SHIFT,
            7
        ),
        b"!"
    );
    assert_eq!(
        encode(
            Key::Character("A".into()),
            KeyCode::KeyA,
            ModifiersState::SHIFT,
            7
        ),
        b"A"
    );
}

#[test]
fn kitty_explicit_all_keys_still_encodes_space() {
    assert_eq!(
        encode(
            Key::Named(NamedKey::Space),
            KeyCode::Space,
            ModifiersState::empty(),
            8
        ),
        b"\x1b[32u"
    );
}

#[test]
fn kitty_press_uses_the_default_event_type_for_conpty_compatibility() {
    assert_eq!(
        encode(
            Key::Character("c".into()),
            KeyCode::KeyC,
            ModifiersState::CONTROL,
            7
        ),
        b"\x1b[99;5u"
    );
    assert_eq!(
        encode(
            Key::Named(NamedKey::Enter),
            KeyCode::Enter,
            ModifiersState::SHIFT,
            7
        ),
        b"\x1b[13;2u"
    );
}
