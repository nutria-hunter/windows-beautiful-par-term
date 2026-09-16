//! IME (input method) event handling.
//!
//! Composition is a separate path from `key_handler`: the IME consumes the physical keys and
//! reports text instead, so composed Korean/Japanese/Chinese can only reach a child from
//! `Ime::Commit`. See `window_state::ime_state` for what the missing handler did.
//!
//! There are two sources for the *display* of a composition, and `Ime::Preedit` is only one of
//! them: [`sync_ime_composition`](crate::app::window_state::WindowState::sync_ime_composition)
//! also pulls the string read straight out of Imm32 by `window_manager::ime_composition`, because
//! winit's preedit can be empty for an entire composition on Windows.

use winit::dpi::{PhysicalPosition, PhysicalSize};
use winit::event::Ime;

impl crate::app::window_state::WindowState {
    /// Handle a `WindowEvent::Ime`.
    ///
    /// `Enabled`/`Disabled` only track state, `Preedit` is what gets drawn inline at the
    /// cursor, and `Commit` is the only variant carrying finished text - it is the reason this
    /// handler exists at all.
    pub(crate) fn handle_ime_event(&mut self, event: Ime) {
        match event {
            Ime::Enabled => {
                self.ime.enabled = true;
                log::info!("IME: enabled");
                self.publish_ime_cursor_area();
            }
            Ime::Disabled => {
                self.ime.enabled = false;
                self.ime.clear_preedit();
                self.ime.published_cell = None;
                log::info!("IME: disabled");
                self.request_redraw();
            }
            Ime::Preedit(text, cursor) => {
                self.ime.preedit = text;
                self.ime.preedit_cursor = cursor;
                // Chatty - one per keystroke while composing - so debug, not info.
                crate::debug_info!("IME", "preedit: {:?}", self.ime.preedit);
                self.publish_ime_cursor_area();
                // The preedit is an overlay on top of the grid, so the frame has to be rebuilt
                // for it to appear or disappear.
                self.request_redraw();
            }
            Ime::Commit(text) => {
                // winit sends an empty `Preedit` immediately before a commit, but clearing here
                // too keeps the overlay correct if that ever changes.
                let was_composing = self.ime.is_composing();
                self.ime.clear_preedit();
                self.publish_ime_cursor_area();
                // info level: this is the line that proves composed input reached par-term at
                // all, and it is the only evidence available when the composed glyphs render
                // wrongly in some application.
                log::info!("IME: commit {:?} ({} bytes)", text, text.len());
                // A modal egui UI owns text input while it is up, and `handle_window_event`
                // blocks the key path for it. Match that rather than typing into a terminal the
                // user cannot see.
                if !text.is_empty() && !self.any_modal_ui_visible() {
                    self.send_ime_text(&text);
                }
                if was_composing || !text.is_empty() {
                    self.request_redraw();
                }
            }
        }
    }

    /// Pull the Imm32 composition into `ImeState`, and tell the window procedure which renderer
    /// owns the composition this frame.
    ///
    /// Called once per window event rather than from the `Ime` arm: the composition string is
    /// read in the window procedure, so an event that is not `Ime` (the per-frame
    /// `RedrawRequested`, above all) is what carries it to the renderer. That also makes the
    /// reader self-healing - a `Ime::Commit` for the previous syllable clears the state, and the
    /// next frame restores the composition that arrived in the same message.
    pub(crate) fn sync_ime_composition(&mut self) {
        use crate::app::window_manager::ime_composition;
        ime_composition::publish_mode(self.config.load().input.ime_preedit_rendering);
        let observed = ime_composition::current();
        let changed = observed.composing != self.ime.imm_composing
            || (observed.composing && observed.text != self.ime.imm_preedit);
        if observed.composing {
            // The IME is live even when winit has not said so: `Ime::Enabled` rides on the same
            // path this reader exists to cover, and `publish_ime_cursor_area` is gated on it.
            self.ime.enabled = true;
        }
        self.ime.imm_composing = observed.composing;
        self.ime.imm_preedit = if observed.composing {
            observed.text
        } else {
            String::new()
        };
        if changed {
            // Re-publishing on change (not every frame) keeps the candidate window next to the
            // caret without re-issuing IMM calls at frame rate.
            self.publish_ime_cursor_area();
        }
    }

    /// Write composed text to the terminal the keyboard would target.
    ///
    /// Deliberately not `paste_text`: that path goes through `TerminalManager::paste`, which
    /// applies paste semantics (bracketed paste, trailing newline handling). Typing a composed
    /// syllable is not a paste, so the bytes go out the way key input sends them.
    fn send_ime_text(&mut self, text: &str) {
        let Some(tab) = self.tab_manager.active_tab() else {
            return;
        };
        // Same target as key input: the focused pane when split, otherwise the tab terminal.
        let terminal = tab
            .pane_manager
            .as_ref()
            .and_then(|pm| pm.focused_pane())
            .map(|pane| std::sync::Arc::clone(&pane.terminal))
            .unwrap_or_else(|| std::sync::Arc::clone(&tab.terminal));
        let bytes = text.as_bytes().to_vec();
        crate::debug_info!("IME", "composed text to PTY: {} bytes", bytes.len());
        // read() not write(), for the same reason the key handler documents: holding the outer
        // RwLock exclusively while blocked on the inner mutex starves the refresh task
        // (try_read) and the render pipeline (try_write) of their generation checks.
        self.runtime.spawn(async move {
            let term = terminal.read().await;
            if let Err(e) = term.write(&bytes) {
                crate::debug_error!("IME", "PTY write failed (composed text): {e}");
            }
        });
    }

    /// Keep the IME candidate window next to the composing caret.
    ///
    /// Only called on IME events, so the position is re-published as the caret moves through a
    /// composition; `published_cell` keeps repeat publishes of the same cell off the wire.
    fn publish_ime_cursor_area(&mut self) {
        if !self.ime.enabled {
            return;
        }
        let Some(cell) = self.tab_manager.active_tab().and_then(|tab| {
            // Position, not visibility: the candidate window belongs next to the caret even when
            // the application draws its own caret (see the overlay's cell lookup in `egui_submit`).
            let cache = tab.active_cache();
            cache.shader_cursor_pos.or(cache.cursor_pos)
        }) else {
            return;
        };
        if self.ime.published_cell == Some(cell) {
            return;
        }
        let (Some(window), Some(renderer)) = (self.window.as_ref(), self.renderer.as_ref()) else {
            return;
        };
        let (col, row) = cell;
        let x = renderer.content_offset_x() + col as f32 * renderer.cell_width();
        let y = renderer.content_offset_y() + row as f32 * renderer.cell_height();
        window.set_ime_cursor_area(
            PhysicalPosition::new(x, y),
            PhysicalSize::new(renderer.cell_width(), renderer.cell_height()),
        );
        self.ime.published_cell = Some(cell);
    }
}
