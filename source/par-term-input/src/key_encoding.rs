//! VT byte sequence encoding for keyboard events.
//!
//! Implements [`InputHandler`] methods that translate each
//! [`winit::event::KeyEvent`] into a `Vec<u8>` suitable for writing directly
//! to the PTY, including character keys, named keys, function keys, Option/Alt
//! key modes, and the modifyOtherKeys protocol extension.
//!
//! This module is split from `lib.rs` purely for organization (AUDIT.md
//! ARC-006); it shares the same `impl InputHandler` surface and accesses the
//! modifier-state helpers in `modifiers.rs` via `self`.

use winit::event::{ElementState, KeyEvent};
use winit::keyboard::{Key, KeyCode, NamedKey, PhysicalKey};

use par_term_config::OptionKeyMode;

use super::{InputHandler, KeyInput};

impl InputHandler {
    /// Apply Option/Alt key transformation based on the configured mode
    fn apply_option_key_mode(&self, bytes: &mut Vec<u8>, original_char: char) {
        let mode = self.get_active_option_mode();

        match mode {
            OptionKeyMode::Normal => {
                // Normal mode: the character is already the special character from the OS
                // (e.g., Option+f = ƒ on macOS). Don't modify it.
                // The bytes already contain the correct character from winit.
            }
            OptionKeyMode::Meta => {
                // Meta mode: set the high bit (8th bit) on the character
                // This only works for ASCII characters (0-127)
                if original_char.is_ascii() {
                    let meta_byte = (original_char as u8) | 0x80;
                    bytes.clear();
                    bytes.push(meta_byte);
                }
                // For non-ASCII, fall through to ESC mode behavior
                else {
                    bytes.insert(0, 0x1b);
                }
            }
            OptionKeyMode::Esc => {
                // Esc mode: send ESC prefix before the character
                // First, we need to use the base character, not the special character
                // This requires getting the unmodified key
                if original_char.is_ascii() {
                    bytes.clear();
                    bytes.push(0x1b); // ESC
                    bytes.push(original_char as u8);
                } else {
                    // For non-ASCII original characters, just prepend ESC to what we have
                    bytes.insert(0, 0x1b);
                }
            }
        }
    }

    /// Convert a keyboard event to terminal input bytes
    ///
    /// If `modify_other_keys_mode` is > 0, keys with modifiers will be reported
    /// using the XTerm modifyOtherKeys format: CSI 27 ; modifier ; keycode ~
    pub fn handle_key_event(&mut self, event: KeyEvent) -> Option<Vec<u8>> {
        self.handle_key_event_with_mode(event, 0, false)
    }

    /// Convert a keyboard event to terminal input bytes with modifyOtherKeys support
    ///
    /// `modify_other_keys_mode`:
    /// - 0: Disabled (normal key handling)
    /// - 1: Report modifiers for special keys only
    /// - 2: Report modifiers for all keys
    ///
    /// `application_cursor`: When true (DECCKM mode enabled), arrow keys send
    /// SS3 sequences (ESC O A) instead of CSI sequences (ESC [ A).
    pub fn handle_key_event_with_mode(
        &mut self,
        event: KeyEvent,
        modify_other_keys_mode: u8,
        application_cursor: bool,
    ) -> Option<Vec<u8>> {
        self.handle_key_input_with_mode(
            &KeyInput::from(event),
            modify_other_keys_mode,
            application_cursor,
        )
    }

    /// Convert a keyboard event to terminal input bytes with every keyboard mode.
    ///
    /// `keyboard_flags` carries the Kitty keyboard protocol flags the application
    /// pushed with `CSI > flags u`. When non-zero they select the Kitty CSI-u
    /// encoding, which is the only way an application can tell `Shift+Enter` from
    /// `Enter` — both are a bare CR in the legacy encoding.
    pub fn handle_key_event_with_modes(
        &mut self,
        event: KeyEvent,
        modify_other_keys_mode: u8,
        application_cursor: bool,
        keyboard_flags: u16,
    ) -> Option<Vec<u8>> {
        self.handle_key_input_with_modes(
            &KeyInput::from(event),
            modify_other_keys_mode,
            application_cursor,
            keyboard_flags,
        )
    }

    /// Convert a [`KeyInput`] to terminal input bytes with modifyOtherKeys support.
    ///
    /// This is the implementation behind the [`KeyEvent`] entry points above, which
    /// exist only to convert. Prefer this when you do not already hold a winit
    /// event: `KeyEvent` cannot be constructed outside winit without undefined
    /// behaviour, so callers that would otherwise forge one should use this.
    pub fn handle_key_input_with_modes(
        &mut self,
        input: &KeyInput,
        modify_other_keys_mode: u8,
        application_cursor: bool,
        keyboard_flags: u16,
    ) -> Option<Vec<u8>> {
        if input.state != ElementState::Pressed {
            return None;
        }

        // Kitty keyboard protocol first: the application opted in explicitly and it
        // carries more information than modifyOtherKeys, so it wins when both are on.
        if let Some(bytes) = self.try_kitty_encoding(input, keyboard_flags) {
            return Some(bytes);
        }

        let ctrl = self.modifiers.state().control_key();
        let alt = self.modifiers.state().alt_key();

        // Check if we should use modifyOtherKeys encoding.
        //
        // Both mode 1 and mode 2 use the same encoding path here — the per-mode routing
        // decisions are made inside `try_modify_other_keys_encoding` (e.g. the Shift-only
        // exemption that matches iTerm2's reference implementation).
        if modify_other_keys_mode > 0
            && let Some(bytes) = self.try_modify_other_keys_encoding(input)
        {
            return Some(bytes);
        }

        match input.logical_key {
            // Character keys
            Key::Character(ref s) => {
                if ctrl {
                    // Handle Ctrl+key combinations
                    let ch = s.chars().next()?;

                    // Note: Ctrl+V paste is handled at higher level for bracketed paste support

                    if ch.is_ascii_alphabetic() {
                        // Ctrl+A through Ctrl+Z map to ASCII 1-26.
                        // When Alt/Option is also held and enhanced modifier reporting is
                        // unavailable, preserve the Alt modifier using the configured
                        // Option-key mode so Ctrl+Alt+letter stays distinct from plain
                        // Ctrl+letter for terminal applications that rely on Meta+Ctrl.
                        let byte = (ch.to_ascii_lowercase() as u8) - b'a' + 1;
                        if alt {
                            return Some(match self.get_active_option_mode() {
                                OptionKeyMode::Meta => vec![byte | 0x80],
                                OptionKeyMode::Normal | OptionKeyMode::Esc => vec![0x1b, byte],
                            });
                        }
                        return Some(vec![byte]);
                    }

                    // Ctrl with ASCII punctuation in 0x40-0x5F range (@, [, \, ], ^, _)
                    // maps to control codes via char & 0x1F (e.g. Ctrl+_ → 0x1F for joe undo).
                    //
                    // The ASCII guard is load-bearing: `ch as u8` truncates, so without it
                    // a non-ASCII scalar whose low byte lands in this range is sent as a
                    // control code. Ctrl+ŕ (U+0155) would become 0x15 — Ctrl+U, which
                    // kills the line in readline.
                    let byte = ch as u8;
                    if ch.is_ascii() && (0x40..=0x5F).contains(&byte) {
                        let ctrl_byte = byte & 0x1F;
                        if alt {
                            return Some(match self.get_active_option_mode() {
                                OptionKeyMode::Meta => vec![ctrl_byte | 0x80],
                                OptionKeyMode::Normal | OptionKeyMode::Esc => {
                                    vec![0x1b, ctrl_byte]
                                }
                            });
                        }
                        return Some(vec![ctrl_byte]);
                    }
                }

                // Get the base character (without Alt modification) for Option key modes
                // We need to look at the physical key to get the unmodified character
                let base_char = self.get_base_character(input);

                // Regular character input
                let mut bytes = s.as_bytes().to_vec();

                // Handle Alt/Option key based on configured mode
                if alt {
                    if let Some(base) = base_char {
                        self.apply_option_key_mode(&mut bytes, base);
                    } else {
                        // Fallback: if we can't determine base character, use the first char
                        let ch = s.chars().next().unwrap_or('\0');
                        self.apply_option_key_mode(&mut bytes, ch);
                    }
                }

                Some(bytes)
            }

            // Special keys
            Key::Named(named_key) => {
                // Handle Ctrl+Space specially - sends NUL (0x00)
                if ctrl && matches!(named_key, NamedKey::Space) {
                    return Some(vec![0x00]);
                }

                // Note: Shift+Insert paste is handled at higher level for bracketed paste support

                let shift = self.modifiers.state().shift_key();

                // Compute xterm modifier parameter for named keys.
                // Standard: bit0=Shift, bit1=Alt, bit2=Ctrl; value = bits + 1.
                // Only applied when at least one modifier is held.
                let has_modifier = shift || alt || ctrl;
                let modifier_param = if has_modifier {
                    let mut bits = 0u8;
                    if shift {
                        bits |= 1;
                    }
                    if alt {
                        bits |= 2;
                    }
                    if ctrl {
                        bits |= 4;
                    }
                    Some(bits + 1)
                } else {
                    None
                };

                // Keys that use the "letter" form: CSI 1;modifier letter (with modifier)
                // or CSI letter / SS3 letter (without modifier).
                // Note: SS3 (application cursor mode) is only used when no modifier is
                // present — with a modifier the sequence switches to CSI form per xterm.
                if let Some(suffix) = match named_key {
                    NamedKey::ArrowUp => Some('A'),
                    NamedKey::ArrowDown => Some('B'),
                    NamedKey::ArrowRight => Some('C'),
                    NamedKey::ArrowLeft => Some('D'),
                    NamedKey::Home => Some('H'),
                    NamedKey::End => Some('F'),
                    _ => None,
                } {
                    return if let Some(m) = modifier_param {
                        // CSI 1 ; modifier letter
                        Some(format!("\x1b[1;{m}{suffix}").into_bytes())
                    } else if application_cursor
                        && matches!(
                            named_key,
                            NamedKey::ArrowUp
                                | NamedKey::ArrowDown
                                | NamedKey::ArrowRight
                                | NamedKey::ArrowLeft
                        )
                    {
                        // SS3 letter (application cursor, no modifier)
                        Some(format!("\x1bO{suffix}").into_bytes())
                    } else {
                        // CSI letter (normal mode, no modifier)
                        Some(format!("\x1b[{suffix}").into_bytes())
                    };
                }

                // Keys that use the "tilde" form: CSI keycode ; modifier ~ (with modifier)
                // or CSI keycode ~ (without modifier).
                if let Some(keycode) = match named_key {
                    NamedKey::Insert => Some(2),
                    NamedKey::Delete => Some(3),
                    NamedKey::PageUp => Some(5),
                    NamedKey::PageDown => Some(6),
                    NamedKey::F5 => Some(15),
                    NamedKey::F6 => Some(17),
                    NamedKey::F7 => Some(18),
                    NamedKey::F8 => Some(19),
                    NamedKey::F9 => Some(20),
                    NamedKey::F10 => Some(21),
                    NamedKey::F11 => Some(23),
                    NamedKey::F12 => Some(24),
                    _ => None,
                } {
                    return if let Some(m) = modifier_param {
                        Some(format!("\x1b[{keycode};{m}~").into_bytes())
                    } else {
                        Some(format!("\x1b[{keycode}~").into_bytes())
                    };
                }

                // F1-F4 use SS3 form without modifier, CSI form with modifier.
                // SS3 P/Q/R/S → CSI 1;modifier P/Q/R/S
                if let Some(suffix) = match named_key {
                    NamedKey::F1 => Some('P'),
                    NamedKey::F2 => Some('Q'),
                    NamedKey::F3 => Some('R'),
                    NamedKey::F4 => Some('S'),
                    _ => None,
                } {
                    return if let Some(m) = modifier_param {
                        Some(format!("\x1b[1;{m}{suffix}").into_bytes())
                    } else {
                        Some(format!("\x1bO{suffix}").into_bytes())
                    };
                }

                // Remaining keys with special handling (no modifier encoding)
                let seq = match named_key {
                    // Shift+Enter sends LF (newline) for soft line breaks (like iTerm2)
                    // Regular Enter sends CR (carriage return) for command execution
                    NamedKey::Enter => {
                        if shift {
                            "\n"
                        } else {
                            "\r"
                        }
                    }
                    // Shift+Tab sends reverse-tab escape sequence (CSI Z)
                    // Regular Tab sends HT (horizontal tab)
                    NamedKey::Tab => {
                        if shift {
                            "\x1b[Z"
                        } else {
                            "\t"
                        }
                    }
                    NamedKey::Space => " ",
                    NamedKey::Backspace => "\x7f",
                    NamedKey::Escape => "\x1b",

                    _ => return None,
                };

                Some(seq.as_bytes().to_vec())
            }

            _ => None,
        }
    }

    /// Try to encode a key event using modifyOtherKeys format
    ///
    /// Returns Some(bytes) if the key should be encoded with modifyOtherKeys,
    /// None if normal handling should be used.
    ///
    /// modifyOtherKeys format: CSI 27 ; modifier ; keycode ~
    /// Where modifier is:
    /// - 2 = Shift
    /// - 3 = Alt
    /// - 4 = Shift+Alt
    ///
    /// Convert a [`KeyInput`] to terminal input bytes with modifyOtherKeys support.
    ///
    /// Kept for callers that do not track the Kitty keyboard protocol: it is the same
    /// encoder with zero flags, which is exactly the pre-Kitty behaviour.
    pub fn handle_key_input_with_mode(
        &mut self,
        input: &KeyInput,
        modify_other_keys_mode: u8,
        application_cursor: bool,
    ) -> Option<Vec<u8>> {
        self.handle_key_input_with_modes(input, modify_other_keys_mode, application_cursor, 0)
    }

    /// Kitty keyboard protocol flag bits.
    const KITTY_DISAMBIGUATE_ESCAPE_CODES: u16 = 0b1;
    const KITTY_REPORT_ALL_KEYS_AS_ESCAPE_CODES: u16 = 0b1000;

    /// Encode a key event with the Kitty keyboard protocol.
    ///
    /// Returns `None` for keys that keep their legacy encoding, which is what makes the
    /// protocol a progressive enhancement: an application that never pushed flags sees
    /// exactly the bytes it saw before, while one that did gets `CSI code ; modifiers u`
    /// and can therefore tell `Shift+Enter` (`13;2`) from `Enter` (`13`).
    fn try_kitty_encoding(&self, input: &KeyInput, flags: u16) -> Option<Vec<u8>> {
        if flags == 0 {
            return None;
        }

        let mut modifier_bits = 0u16;
        if self.modifiers.state().shift_key() {
            modifier_bits |= 1;
        }
        if self.modifiers.state().alt_key() {
            modifier_bits |= 2;
        }
        if self.modifiers.state().control_key() {
            modifier_bits |= 4;
        }
        if self.modifiers.state().super_key() {
            modifier_bits |= 8;
        }

        // The reported code point: a printable key reports its unshifted base, because
        // the protocol expresses Shift as a modifier bit. The ambiguous control keys
        // report their legacy code points so they can be told apart from Ctrl+I,
        // Ctrl+M and Ctrl+[ (which are the same bytes in the legacy encoding).
        let codepoint = match &input.logical_key {
            Key::Character(text) => {
                (self
                    .get_base_character(input)
                    .or_else(|| text.chars().next())?) as u32
            }
            Key::Named(NamedKey::Enter) => 13,
            Key::Named(NamedKey::Tab) => 9,
            Key::Named(NamedKey::Backspace) => 127,
            Key::Named(NamedKey::Escape) => 27,
            Key::Named(NamedKey::Space) => 32,
            // Arrows, function keys and the rest are already unambiguous in their
            // legacy form, so they keep it.
            _ => return None,
        };

        let report_all = flags & Self::KITTY_REPORT_ALL_KEYS_AS_ESCAPE_CODES != 0;
        let disambiguate = flags & Self::KITTY_DISAMBIGUATE_ESCAPE_CODES != 0;
        // Text (including Shift-only text and Space) stays UTF-8 unless all-key
        // reporting is requested. Keep the unmodified shell recovery keys legacy
        // too: encoding them as CSI-u makes ConPTY discard ordinary input.
        let text_key = matches!(
            input.logical_key,
            Key::Character(_) | Key::Named(NamedKey::Space)
        );
        let recovery_key = matches!(
            input.logical_key,
            Key::Named(NamedKey::Enter | NamedKey::Tab | NamedKey::Backspace)
        );
        if !report_all
            && ((text_key && modifier_bits & !1 == 0) || (recovery_key && modifier_bits == 0))
        {
            return None;
        }
        let ambiguous = matches!(input.logical_key, Key::Named(NamedKey::Escape)) || recovery_key;
        if !report_all && !(disambiguate && (modifier_bits != 0 || ambiguous)) {
            return None;
        }

        // Press is the protocol default. Omit its optional :1 subfield: ConPTY
        // does not reliably preserve colon subparameters in keyboard input.
        let mut sequence = format!("\x1b[{codepoint}");
        if modifier_bits != 0 {
            sequence.push(';');
            sequence.push_str(&(modifier_bits + 1).to_string());
        }
        sequence.push('u');
        Some(sequence.into_bytes())
    }

    /// - 5 = Ctrl
    /// - 6 = Shift+Ctrl
    /// - 7 = Alt+Ctrl
    /// - 8 = Shift+Alt+Ctrl
    fn try_modify_other_keys_encoding(&self, input: &KeyInput) -> Option<Vec<u8>> {
        let ctrl = self.modifiers.state().control_key();
        let alt = self.modifiers.state().alt_key();
        let shift = self.modifiers.state().shift_key();

        // No modifiers means no special encoding needed
        if !ctrl && !alt && !shift {
            return None;
        }

        // Get the base character for the key
        let base_char = self.get_base_character(input)?;

        // Skip modifyOtherKeys encoding for any Shift-only combination on printable
        // characters, regardless of mode or character class.
        //
        // This matches iTerm2's reference implementation (sources/iTermModifyOtherKeysMapper.m
        // and iTermModifyOtherKeysMapper1.m), which is confirmed by its `iTermModifyOtherKeys1Test`
        // suite: for Shift+letter, Shift+digit, and Shift+symbol iTerm2 returns `nil` from
        // `keyMapperStringForPreCocoaEvent` and lets Cocoa's text-input system emit the OS-
        // resolved shifted character (`A`, `!`, `@`, `{`, etc.) directly to the PTY. The same
        // rule applies in both mode 1 (via `shouldModifyOtherKeysForNumberEvent` / ...Symbol /
        // ...RegularEvent returning NO) and mode 2 (via the base mapper returning nil unless
        // Control is held).
        //
        // Why this is necessary: winit's `logical_key` already contains the layout-correct
        // shifted character. TUI applications built on crossterm (Claude Code, etc.) that see
        // a `CSI 27;2;49~` sequence cannot reverse-map the base codepoint `49` ('1') to the
        // shifted codepoint `33` ('!') because they have no access to the OS keyboard layout
        // tables — they just render the base character. Falling through to the normal
        // `Key::Character` path below sends the winit-provided shifted character as raw bytes,
        // which every application handles correctly.
        //
        // We intentionally keep Shift+Alt/Shift+Ctrl etc. encoded here because those carry
        // modifier information that cannot be recovered from the character alone.
        if shift && !ctrl && !alt {
            return None;
        }

        // Calculate the modifier value
        // bit 0 (1) = Shift
        // bit 1 (2) = Alt
        // bit 2 (4) = Ctrl
        // The final value is bits + 1
        let mut modifier_bits = 0u8;
        if shift {
            modifier_bits |= 1;
        }
        if alt {
            modifier_bits |= 2;
        }
        if ctrl {
            modifier_bits |= 4;
        }

        // Add 1 to get the XTerm modifier value (so no modifiers would be 1, but we already checked for that)
        let modifier_value = modifier_bits + 1;

        // Get the Unicode codepoint of the base character
        let keycode = base_char as u32;

        // Format: CSI 27 ; modifier ; keycode ~
        // CSI = ESC [
        Some(format!("\x1b[27;{};{}~", modifier_value, keycode).into_bytes())
    }

    /// Get the base character from a key event (the character without Alt modification)
    /// This maps physical key codes to their unmodified ASCII characters
    fn get_base_character(&self, input: &KeyInput) -> Option<char> {
        // Map physical key codes to their base characters
        // This is needed because on macOS, Option+key produces a different logical character
        match input.physical_key {
            PhysicalKey::Code(code) => match code {
                KeyCode::KeyA => Some('a'),
                KeyCode::KeyB => Some('b'),
                KeyCode::KeyC => Some('c'),
                KeyCode::KeyD => Some('d'),
                KeyCode::KeyE => Some('e'),
                KeyCode::KeyF => Some('f'),
                KeyCode::KeyG => Some('g'),
                KeyCode::KeyH => Some('h'),
                KeyCode::KeyI => Some('i'),
                KeyCode::KeyJ => Some('j'),
                KeyCode::KeyK => Some('k'),
                KeyCode::KeyL => Some('l'),
                KeyCode::KeyM => Some('m'),
                KeyCode::KeyN => Some('n'),
                KeyCode::KeyO => Some('o'),
                KeyCode::KeyP => Some('p'),
                KeyCode::KeyQ => Some('q'),
                KeyCode::KeyR => Some('r'),
                KeyCode::KeyS => Some('s'),
                KeyCode::KeyT => Some('t'),
                KeyCode::KeyU => Some('u'),
                KeyCode::KeyV => Some('v'),
                KeyCode::KeyW => Some('w'),
                KeyCode::KeyX => Some('x'),
                KeyCode::KeyY => Some('y'),
                KeyCode::KeyZ => Some('z'),
                KeyCode::Digit0 => Some('0'),
                KeyCode::Digit1 => Some('1'),
                KeyCode::Digit2 => Some('2'),
                KeyCode::Digit3 => Some('3'),
                KeyCode::Digit4 => Some('4'),
                KeyCode::Digit5 => Some('5'),
                KeyCode::Digit6 => Some('6'),
                KeyCode::Digit7 => Some('7'),
                KeyCode::Digit8 => Some('8'),
                KeyCode::Digit9 => Some('9'),
                KeyCode::Minus => Some('-'),
                KeyCode::Equal => Some('='),
                KeyCode::BracketLeft => Some('['),
                KeyCode::BracketRight => Some(']'),
                KeyCode::Backslash => Some('\\'),
                KeyCode::Semicolon => Some(';'),
                KeyCode::Quote => Some('\''),
                KeyCode::Backquote => Some('`'),
                KeyCode::Comma => Some(','),
                KeyCode::Period => Some('.'),
                KeyCode::Slash => Some('/'),
                KeyCode::Space => Some(' '),
                _ => None,
            },
            _ => None,
        }
    }
}
