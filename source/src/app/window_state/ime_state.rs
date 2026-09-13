//! IME (input method) state for a window.
//!
//! Extracted from `WindowState` as part of the God Object decomposition (ARC-001).
//!
//! par-term asks the platform for IME events (`set_ime_allowed(true)` in `impl_init`) and
//! winit then reports composition as `WindowEvent::Ime`. The event loop had no arm for that
//! variant, so the composed text was discarded before it could reach a PTY: par-term builds
//! character input from physical keys and escape sequences, and the IME consumes those keys
//! while it is composing, so nothing else could carry the text. Korean input therefore did
//! nothing at all - not even the physical letters.

/// Byte range of the composing caret inside `preedit`, as reported by the IME.
pub(crate) type PreeditCursor = Option<(usize, usize)>;

/// IME composition state for this window.
#[derive(Default)]
pub(crate) struct ImeState {
    /// The platform IME told us it is active (winit's `Ime::Enabled`).
    pub(crate) enabled: bool,
    /// Text currently being composed. Drawn inline at the terminal cursor, and empty when no
    /// composition is in progress.
    pub(crate) preedit: String,
    /// Caret inside `preedit`, byte-indexed. `None` hides the composing caret.
    pub(crate) preedit_cursor: PreeditCursor,
    /// Cell the IME caret area was last published for, so the candidate window is only
    /// repositioned when the caret actually moves.
    pub(crate) published_cell: Option<(usize, usize)>,
}

impl ImeState {
    /// Whether there is preedit text to draw.
    pub(crate) fn is_composing(&self) -> bool {
        !self.preedit.is_empty()
    }

    /// Forget any composition. Called on commit, and when the IME is disabled.
    pub(crate) fn clear_preedit(&mut self) {
        self.preedit.clear();
        self.preedit_cursor = None;
    }
}
