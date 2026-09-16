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
    /// Composition string read straight out of Imm32 by `window_manager::ime_composition`.
    ///
    /// Display only, and a second source on purpose: `preedit` above is whatever winit reported,
    /// and experience on Windows is that it can be empty for the whole composition while the
    /// committed syllable still arrives through `WM_CHAR`. Nothing here is ever written to a PTY.
    pub(crate) imm_preedit: String,
    /// True while Imm32 reports a composition is open, even if its string is still empty.
    pub(crate) imm_composing: bool,
}

impl ImeState {
    /// Seed a composition from `PAR_TERM_IME_PREEDIT`, for screenshots without a human at the
    /// keyboard.
    ///
    /// A real composition is only delivered by the platform IME to the *active* window, and
    /// Windows refuses to hand a background process an input context, so the preedit overlay had
    /// no automated coverage at all. This hook feeds the same state `Ime::Preedit` feeds, which is
    /// what makes the overlay screenshot-testable (see `galaxy-work/work/ime_preedit_probe.ps1`).
    /// It is inert unless the variable is set.
    pub(crate) fn with_env_seed(mut self) -> Self {
        match std::env::var("PAR_TERM_IME_PREEDIT") {
            Ok(text) if !text.is_empty() => {
                log::warn!("IME: seeding a composition from PAR_TERM_IME_PREEDIT (test hook)");
                self.enabled = true;
                self.preedit = text;
            }
            _ => {}
        }
        self
    }

    /// Whether there is preedit text to draw.
    ///
    /// Either source counts: winit's `Ime::Preedit` when it carries text, and the Imm32 reader
    /// otherwise (see `display_preedit`).
    pub(crate) fn is_composing(&self) -> bool {
        !self.preedit.is_empty() || !self.imm_preedit.is_empty()
    }

    /// The string to draw for the composition in progress.
    ///
    /// winit's preedit wins when it has text, because it also carries the clause cursor; the
    /// Imm32 string is the fallback that keeps the composition visible when winit reports
    /// nothing.
    pub(crate) fn display_preedit(&self) -> &str {
        if self.preedit.is_empty() {
            &self.imm_preedit
        } else {
            &self.preedit
        }
    }

    /// Forget any composition. Called on commit, and when the IME is disabled.
    pub(crate) fn clear_preedit(&mut self) {
        self.preedit.clear();
        self.preedit_cursor = None;
        // Both sources, or a composition that winit dropped would stay on screen from the
        // Imm32 copy until the next keystroke.
        self.imm_preedit.clear();
        self.imm_composing = false;
    }
}
