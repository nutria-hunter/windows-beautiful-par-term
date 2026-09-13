//! Frame setup helpers for the render pipeline.
//!
//! These functions run at the beginning of every render cycle:
//! - `should_render_frame`: FPS gate — decides whether to render this frame
//! - `update_frame_metrics`: rolling frame-time tracking for FPS overlay
//! - `update_animations`: scroll animation tick, tab title refresh, font rebuild
//! - `sync_layout`: tab bar / status bar geometry sync with renderer

use crate::app::window_state::WindowState;

impl WindowState {
    const TAB_TITLE_REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_millis(250);

    /// Returns true if enough time has elapsed since the last frame and rendering should proceed.
    /// Updates last_render_time and resets needs_redraw on success.
    ///
    /// When the FPS gate rejects a `RedrawRequested`, `pending_egui_repaint` is set so
    /// `about_to_wait` can re-arm a frame at the earliest eligible time. Otherwise any
    /// events already queued into `egui_winit`'s `raw_input` (e.g. a tab click's
    /// press/release) would stall until the next unrelated wake — the "have to click
    /// twice to switch tabs" bug.
    pub(super) fn should_render_frame(&mut self) -> bool {
        // A minimized window has no drawable area. Building a frame for it drives the
        // layout code against a zero-sized surface, which is what made par-term panic
        // (`f32::clamp` with min > max) the moment the window was minimized — the same
        // panic the stock 0.45.0 build shows. No frame is built while minimized; a
        // repaint is armed so restoring the window redraws immediately.
        if self
            .window
            .as_ref()
            .is_some_and(|window| window.is_minimized() == Some(true))
        {
            // A minimized window reports its icon size, not a usable terminal size
            // (192x34 -> a 12x1 grid). Mark the grid untrustworthy and drop any pending
            // candidate: restoring re-enables frames a few milliseconds before the
            // restored size arrives, so the renderer still holds that one-row grid when
            // settling resumes. Without this the gate would see the same grid on two
            // consecutive frames and hand a one-row terminal to the children. The flag
            // is cleared by the next real `WindowEvent::Resized`.
            self.pty_grid_suspect = true;
            self.pty_grid_candidate = None;
            self.focus_state.pending_egui_repaint = true;
            return false;
        }

        let target_fps =
            if self.config.load().power.pause_refresh_on_blur && !self.focus_state.is_focused {
                self.config.load().power.unfocused_fps
            } else {
                self.config.load().rendering.max_fps
            };
        let frame_interval = std::time::Duration::from_millis((1000 / target_fps.max(1)) as u64);
        if let Some(last_render) = self.focus_state.last_render_time
            && last_render.elapsed() < frame_interval
        {
            self.focus_state.pending_egui_repaint = true;
            return false;
        }
        self.focus_state.last_render_time = Some(std::time::Instant::now());
        self.focus_state.needs_redraw = false;
        self.focus_state.pending_egui_repaint = false;
        true
    }

    /// Record the start of this render frame for timing and update rolling frame-time metrics.
    pub(super) fn update_frame_metrics(&mut self) {
        let frame_start = std::time::Instant::now();
        self.debug.render_start = Some(frame_start);
        if let Some(last_start) = self.debug.last_frame_start {
            let frame_time = frame_start.duration_since(last_start);
            self.debug.frame_times.push_back(frame_time);
            if self.debug.frame_times.len() > 60 {
                self.debug.frame_times.pop_front();
            }
        }
        self.debug.last_frame_start = Some(frame_start);
    }

    /// Tick scroll animations, refresh tab titles, and rebuild renderer if font settings changed.
    pub(super) fn update_animations(&mut self) {
        let animation_running = if let Some(tab) = self.tab_manager.active_tab_mut() {
            tab.active_scroll_state_mut().update_animation()
        } else {
            false
        };

        // Updating titles walks every tab/pane and touches terminal state, so avoid
        // doing it on every animation frame. A short throttle keeps OSC/CWD-derived
        // titles responsive without scaling frame cost with idle tab count.
        let now = std::time::Instant::now();
        let should_refresh_titles = self
            .render_loop
            .last_tab_title_refresh
            .is_none_or(|last| now.duration_since(last) >= Self::TAB_TITLE_REFRESH_INTERVAL);
        if should_refresh_titles {
            self.tab_manager.update_all_titles(
                self.config.load().tabs.tab_title_mode,
                self.config.load().tabs.remote_tab_title_format,
                self.config.load().tabs.remote_tab_title_osc_priority,
            );
            self.render_loop.last_tab_title_refresh = Some(now);
        }

        // Rebuild renderer if font-related settings changed
        if self.render_loop.pending_font_rebuild {
            if let Err(e) = self.rebuild_renderer() {
                log::error!("Failed to rebuild renderer after font change: {}", e);
            }
            self.render_loop.pending_font_rebuild = false;
        }

        if animation_running && let Some(window) = &self.window {
            window.request_redraw();
        }
    }

    /// Sync tab bar and status bar geometry with the renderer every frame.
    /// Resizes terminal grids if the tab bar dimensions changed.
    pub(super) fn sync_layout(&mut self) {
        // Sync tab bar offsets with renderer's content offsets
        // This ensures the terminal grid correctly accounts for the tab bar position
        let tab_count = self.tab_manager.visible_tab_count();
        let tab_bar_height = self.tab_bar_ui.get_height(tab_count, &self.config.load());
        let tab_bar_width = self.tab_bar_ui.get_width(tab_count, &self.config.load());
        crate::debug_trace!(
            "TAB_SYNC",
            "Tab count={}, tab_bar_height={:.0}, tab_bar_width={:.0}, position={:?}, mode={:?}",
            tab_count,
            tab_bar_height,
            tab_bar_width,
            self.config.load().tabs.tab_bar_position,
            self.config.load().tabs.tab_bar_mode
        );
        if let Some(renderer) = &mut self.renderer {
            let grid_changed = Self::apply_tab_bar_offsets_for_position(
                self.config.load().tabs.tab_bar_position,
                renderer,
                tab_bar_height,
                tab_bar_width,
            );
            if let Some((new_cols, new_rows)) = grid_changed {
                // Invalidate the caches only. The PTY learns the new grid from
                // `commit_pty_grid_when_settled`, once the size stops changing, so a
                // tab-bar offset that is itself still settling cannot reach the child.
                for tab in self.tab_manager.tabs_mut() {
                    tab.active_cache_mut().cells = None;
                }
                crate::debug_info!(
                    "TAB_SYNC",
                    "Tab bar offsets changed (position={:?}), grid now {}x{}",
                    self.config.load().tabs.tab_bar_position,
                    new_cols,
                    new_rows
                );
            }
        }

        // Sync status bar inset so the terminal grid does not extend behind it.
        // Must happen before cell gathering so the row count is correct.
        self.sync_status_bar_inset();
    }

    /// Hand the terminal grid to the PTY, but only once it has stopped changing.
    ///
    /// Window setup and display changes report several grids within a few
    /// milliseconds — a restored placement, the real window size, then the tab bar
    /// offset — and each one used to be pushed straight to the children. A TUI that
    /// reads the size during that burst lays out for a value that is already stale
    /// and leaves its input box off-screen, which is why the pi agent looks like it
    /// is not accepting input. Waiting for the same grid on two consecutive frames
    /// costs one frame of latency and removes the burst entirely.
    pub(super) fn commit_pty_grid_when_settled(&mut self) {
        // A minimized window's grid is its icon size, and the frames that resume on
        // restore run before the restored size event arrives. Hold the children on
        // their last good grid until a real size lands.
        if self.pty_grid_suspect {
            self.pty_grid_candidate = None;
            return;
        }
        let Some(renderer) = &self.renderer else {
            return;
        };
        let current = renderer.grid_size();

        if self.pty_grid_committed == Some(current) {
            // Already delivered; nothing left to settle.
            self.pty_grid_candidate = None;
            return;
        }
        if self.pty_grid_candidate != Some(current) {
            // New value: remember it and wait to see whether it survives a frame.
            self.pty_grid_candidate = Some(current);
            return;
        }
        self.push_grid_to_pty(current);
    }

    /// Send `size` to every tab's PTY, retrying on the next frame if a lock is missed.
    fn push_grid_to_pty(&mut self, size: (usize, usize)) {
        let Some(renderer) = &self.renderer else {
            return;
        };
        let cell_width = renderer.cell_width();
        let cell_height = renderer.cell_height();
        let (cols, rows) = size;
        let width_px = (cols as f32 * cell_width) as usize;
        let height_px = (rows as f32 * cell_height) as usize;

        // The reader thread holds a terminal's write lock while it parses output, and
        // contention peaks exactly when a TUI floods the screen. Leaving the size
        // uncommitted on a miss makes the next frame retry instead of dropping it.
        let mut all_delivered = true;
        for tab in self.tab_manager.tabs_mut() {
            let Ok(mut term) = tab.terminal.try_write() else {
                crate::debug::record_try_lock_failure("pty_grid_settle");
                all_delivered = false;
                continue;
            };
            term.set_cell_dimensions(cell_width as u32, cell_height as u32);
            // A same-size re-assert is a no-op for ConPTY: only a real size change makes
            // it queue a size record for the child. Shrink one column and restore it,
            // which is the sequence that forces a Windows TUI to re-lay out (the same
            // trick wmux uses to make Claude redraw after re-attaching to a session).
            if cols > 1 {
                let narrow_px = ((cols - 1) as f32 * cell_width) as usize;
                let _ = term.resize_with_pixels(cols - 1, rows, narrow_px, height_px);
            }
            if let Err(e) = term.resize_with_pixels(cols, rows, width_px, height_px) {
                crate::debug_error!("TERMINAL", "grid commit failed: {e}");
                all_delivered = false;
            }
        }

        if all_delivered {
            self.pty_grid_committed = Some(size);
            self.pty_grid_candidate = None;
            crate::debug_info!("PTY_GRID", "committed settled grid {}x{}", cols, rows);
        }
        // Otherwise the candidate stays set, so the next frame retries the same size.
    }

    /// Re-assert the PTY size for tabs that entered the alternate screen.
    ///
    /// Unix terminals deliver a `SIGWINCH` pulse at that moment (the emulator core
    /// does it), but Windows/ConPTY has no out-of-band resize channel — so the only
    /// way to make the child re-read its size there is to set the size again
    /// through the PTY. Entering the alternate screen is exactly when a TUI reads
    /// its geometry, which is why the pulse is timed to that transition.
    ///
    /// The request stays pending until a write actually succeeds. The reader thread
    /// holds the terminal write lock while it parses output, so a one-shot attempt
    /// dropped on contention would leave a TUI on a stale size with nothing left to
    /// retry it — and contention peaks precisely when the TUI floods output.
    pub(super) fn sync_resize_pulses(&mut self) {
        // Hoist the cell metrics so the immutable borrow of `self.renderer` ends
        // before `self.tab_manager` is borrowed mutably below.
        let Some(renderer) = &self.renderer else {
            return;
        };
        let cell_width = renderer.cell_width();
        let cell_height = renderer.cell_height();

        for tab in self.tab_manager.tabs_mut() {
            if !tab.pending_resize_pulse {
                continue;
            }
            let Ok(mut term) = tab.terminal.try_write() else {
                // Still held by the reader thread; retry on the next frame.
                continue;
            };
            let (cols, rows) = term.dimensions();
            term.set_cell_dimensions(cell_width as u32, cell_height as u32);
            let width_px = (cols as f32 * cell_width) as usize;
            let height_px = (rows as f32 * cell_height) as usize;
            match term.resize_with_pixels(cols, rows, width_px, height_px) {
                Ok(()) => {
                    tab.pending_resize_pulse = false;
                    crate::debug_info!(
                        "TAB_SYNC",
                        "Alt-screen resize pulse applied ({}x{})",
                        cols,
                        rows
                    );
                }
                Err(e) => {
                    // Keep it pending so the next frame tries again.
                    crate::debug_error!("TERMINAL", "Alt-screen resize pulse failed: {e}");
                }
            }
        }
    }
}
