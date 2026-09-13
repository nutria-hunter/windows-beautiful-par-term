//! Horizontal tab painting for the tab bar.
//!
//! Contains [`TabBarUI::render_tab_with_width`], the per-tab drawing routine
//! used by the horizontal tab bar layout.  The shared [`TabRenderParams`] struct
//! and [`TabBarUI::compute_tab_bg_color`] helper live in the sibling
//! `tab_rendering` module.

use crate::ui_constants::{
    TAB_CLOSE_BTN_MARGIN, TAB_CLOSE_BTN_SIZE_V, TAB_CONTENT_PAD_X, TAB_CONTENT_PAD_Y,
    TAB_CONTEXT_PADDING, TAB_HOTKEY_LABEL_WIDTH, TAB_INDICATOR_INSET_X, TAB_INDICATOR_LIFT_Y,
};
use egui::emath::GuiRounding as _;

use super::TabBarAction;
use super::TabBarUI;
use super::tab_rendering::TabRenderParams;
use super::title_utils::{
    estimate_max_chars, parse_html_title, render_segments, sanitize_egui_title_text,
    sanitize_styled_segments_for_egui, truncate_plain, truncate_segments,
};

impl TabBarUI {
    /// Render a single tab with specified width and return any action triggered plus the tab rect.
    pub(super) fn render_tab_with_width(
        &mut self,
        ui: &mut egui::Ui,
        p: TabRenderParams<'_>,
    ) -> (TabBarAction, egui::Rect) {
        let TabRenderParams {
            id,
            index,
            title,
            profile_icon,
            custom_icon,
            is_active,
            has_activity,
            is_bell_active,
            custom_color,
            config,
            tab_size: tab_width,
            tab_count,
        } = p;
        let mut action = TabBarAction::None;

        // Determine if this tab should be dimmed
        // Active tabs and hovered inactive tabs are NOT dimmed
        // Also dim the tab being dragged
        let (bg_color, opacity) = self.compute_tab_bg_color(id, is_active, custom_color, config);

        // Whether this inactive tab should render as outline-only (no fill)
        let outline_only = config.tab_colors.tab_inactive_outline_only && !is_active;

        // Tab frame - allocate the pill's full slot, then inset once when drawing.
        // Insetting twice (once here, once in `shrink2`) made the pill shorter than
        // the strip's centred row, so all the leftover space landed below the pill and
        // the tabs read as top-heavy.
        let tab_height = config.tabs.tab_bar_height;
        let (tab_rect, _) =
            ui.allocate_exact_size(egui::vec2(tab_width, tab_height), egui::Sense::hover());

        // Draw tab background with pill shape
        // Use rounding based on tab height for a smooth pill appearance
        // The pill's vertical clearance is configurable: raising `tab_bar_height`
        // alone would grow the pill alongside the bar and leave the air unchanged.
        let pill_inset_y = config.tab_colors.tab_pill_inset_y.max(0.0);
        let tab_draw_rect = tab_rect
            .shrink2(egui::vec2(0.0, pill_inset_y))
            .round_to_pixels(ui.pixels_per_point());
        let tab_rounding = tab_draw_rect.height() / 2.0;
        if ui.is_rect_visible(tab_rect) {
            ui.painter()
                .rect_filled(tab_draw_rect, tab_rounding, bg_color);

            // Draw border around tab
            // The active tab is marked by the bottom indicator bar drawn below, so its
            // pill keeps the same hairline as every other tab. Painting the indicator
            // colour around the whole pill as well would spend the accent twice and
            // leave the chrome carrying more accent than the content does.
            // Outline-only inactive tabs always get a border (brightened on hover)
            let is_hovered = self.hovered_tab == Some(id);
            if config.tab_colors.tab_border_width > 0.0 || outline_only {
                let (border_color, border_width) = if outline_only {
                    // Outline-only inactive tab: use border color, brighten on hover
                    let base = if let Some(custom) = custom_color {
                        custom
                    } else {
                        config.tab_colors.tab_border_color
                    };
                    let c = if is_hovered {
                        let brighten = |v: u8| v.saturating_add(60);
                        [brighten(base[0]), brighten(base[1]), brighten(base[2])]
                    } else {
                        base
                    };
                    (c, config.tab_colors.tab_border_width.max(1.0))
                } else {
                    // Inactive tabs: use normal border color
                    (
                        config.tab_colors.tab_border_color,
                        config.tab_colors.tab_border_width,
                    )
                };

                if border_width > 0.0 {
                    ui.painter().rect_stroke(
                        tab_draw_rect,
                        tab_rounding,
                        egui::Stroke::new(
                            border_width,
                            egui::Color32::from_rgb(
                                border_color[0],
                                border_color[1],
                                border_color[2],
                            ),
                        ),
                        egui::StrokeKind::Middle,
                    );
                }
            }

            // Active-tab accent: a thin bar along the bottom edge. Inset and lifted so
            // it stays inside the pill's rounded bottom, since a stadium pill is only
            // flat across the middle of that edge.
            let indicator_height = config.tab_colors.tab_indicator_height;
            if is_active && indicator_height > 0.0 {
                let c = if let Some(custom) = custom_color {
                    // Lighten the custom color for the indicator
                    let lighten = |v: u8| v.saturating_add(50);
                    [lighten(custom[0]), lighten(custom[1]), lighten(custom[2])]
                } else {
                    config.tab_colors.tab_active_indicator
                };
                let inset = TAB_INDICATOR_INSET_X
                    .min(tab_draw_rect.width() / 2.0 - 1.0)
                    .max(0.0);
                let bar = egui::Rect::from_min_max(
                    egui::pos2(
                        tab_draw_rect.left() + inset,
                        tab_draw_rect.bottom() - TAB_INDICATOR_LIFT_Y - indicator_height,
                    ),
                    egui::pos2(
                        tab_draw_rect.right() - inset,
                        tab_draw_rect.bottom() - TAB_INDICATOR_LIFT_Y,
                    ),
                );
                ui.painter().rect_filled(
                    bar,
                    indicator_height / 2.0,
                    egui::Color32::from_rgb(c[0], c[1], c[2]),
                );
            }

            // Create a child UI for the tab content
            let mut content_ui = ui.new_child(
                egui::UiBuilder::new()
                    .max_rect(
                        tab_rect.shrink2(egui::vec2(TAB_CONTENT_PAD_X, TAB_CONTENT_PAD_Y * 2.0)),
                    )
                    .layout(egui::Layout::left_to_right(egui::Align::Center)),
            );

            content_ui.horizontal(|ui| {
                // Indicators, sized explicitly and capped at half the strip height.
                //
                // Emoji render noticeably larger than their nominal font size, so an
                // uncapped bell or dot can outgrow the pill it sits in — the same
                // reason the profile icon is capped. The horizontal guard matches the
                // icon's: never more than half of this tab's width.
                let indicator_size = (config.tabs.tab_bar_height * 0.5)
                    .max(8.0)
                    .min((tab_width * 0.5).max(8.0));

                // Bell indicator (takes priority over activity indicator)
                if is_bell_active {
                    let c = config.tab_colors.tab_bell_indicator;
                    ui.label(
                        egui::RichText::new("🔔")
                            .size(indicator_size)
                            .color(egui::Color32::from_rgb(c[0], c[1], c[2])),
                    );
                    ui.add_space(4.0);
                } else if has_activity && !is_active {
                    // Activity indicator
                    let c = config.tab_colors.tab_activity_indicator;
                    ui.label(
                        egui::RichText::new("•")
                            .size(indicator_size)
                            .color(egui::Color32::from_rgb(c[0], c[1], c[2])),
                    );
                    ui.add_space(4.0);
                }

                // Tab index if configured
                if config.tabs.tab_show_index {
                    // We'd need to get the index, skip for now
                }

                // Tab text colour, shared by the icon and the title.
                let text_color = if is_active {
                    let c = config.tab_colors.tab_active_text;
                    egui::Color32::from_rgba_unmultiplied(c[0], c[1], c[2], 255)
                } else {
                    let c = config.tab_colors.tab_inactive_text;
                    egui::Color32::from_rgba_unmultiplied(c[0], c[1], c[2], opacity)
                };

                // Profile icon (from auto-applied directory/hostname profile).
                //
                // The width is capped at half of *this tab's* width, so a wide glyph
                // can never take over a narrow tab. The height cap is unchanged — only
                // the horizontal extent is limited. A text glyph advances roughly one
                // em, so bounding the font size bounds the drawn width with it.
                let icon_width = if let Some(icon) = profile_icon {
                    let icon = sanitize_egui_title_text(icon);
                    let icon_height = (config.tabs.tab_bar_height * 0.5).max(8.0);
                    let icon_max_width = (tab_width * 0.5).max(8.0);
                    let icon_size = (icon_height * 0.9).min(icon_max_width);
                    let (icon_rect, _) = ui.allocate_exact_size(
                        egui::vec2(icon_size, icon_height),
                        egui::Sense::hover(),
                    );
                    ui.painter().text(
                        icon_rect.center(),
                        egui::Align2::CENTER_CENTER,
                        icon.as_ref(),
                        egui::FontId::proportional(icon_size),
                        text_color,
                    );
                    ui.add_space(2.0);
                    icon_size + 2.0
                } else {
                    0.0
                };

                // Title rendering with width-aware truncation
                let base_font_id = ui.style().text_styles[&egui::TextStyle::Button].clone();
                let indicator_width = if is_bell_active {
                    18.0
                } else if has_activity && !is_active {
                    14.0
                } else {
                    0.0
                };
                let hotkey_width = if index < 9 {
                    TAB_HOTKEY_LABEL_WIDTH
                } else {
                    0.0
                };
                let close_width = if config.tabs.tab_show_close_button {
                    TAB_CLOSE_BTN_SIZE_V + TAB_CLOSE_BTN_MARGIN
                } else {
                    0.0
                };
                let padding = TAB_CONTEXT_PADDING;
                let title_available_width = (tab_width
                    - indicator_width
                    - icon_width
                    - hotkey_width
                    - close_width
                    - padding)
                    .max(TAB_CONTENT_PAD_X * 2.0);

                let max_chars = estimate_max_chars(ui, &base_font_id, title_available_width);

                if config.tab_colors.tab_html_titles {
                    let segments = sanitize_styled_segments_for_egui(parse_html_title(title));
                    let truncated = truncate_segments(&segments, max_chars);
                    render_segments(ui, &truncated, text_color);
                } else {
                    let safe_title = sanitize_egui_title_text(title);
                    let display_title = truncate_plain(safe_title.as_ref(), max_chars);
                    let mut label = egui::RichText::new(display_title).color(text_color);
                    if config.tab_colors.tab_text_bold {
                        label = label.strong();
                    }
                    ui.label(label);
                }

                // Hotkey indicator (only for tabs 1-9) - show on right side, leave space for close button
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    // Add space for close button if shown
                    if config.tabs.tab_show_close_button {
                        ui.add_space(24.0);
                    }
                    if index < 9 {
                        // Use ⌘ on macOS, ^ on other platforms
                        let modifier_symbol = if cfg!(target_os = "macos") {
                            "⌘"
                        } else {
                            "^"
                        };
                        let hotkey_text = format!("{}{}", modifier_symbol, index + 1);
                        let hotkey_color =
                            egui::Color32::from_rgba_unmultiplied(180, 180, 180, opacity);
                        ui.label(
                            egui::RichText::new(hotkey_text)
                                .color(hotkey_color)
                                .size(11.0),
                        );
                    }
                });
            });
        }

        // Close button - render AFTER the content so it's on top
        // Position at far right edge of tab
        let close_btn_size = TAB_CLOSE_BTN_SIZE_V;
        let close_btn_rect = if config.tabs.tab_show_close_button {
            Some(egui::Rect::from_min_size(
                egui::pos2(
                    tab_rect.right() - close_btn_size - TAB_CLOSE_BTN_MARGIN,
                    tab_rect.center().y - close_btn_size / 2.0,
                ),
                egui::vec2(close_btn_size, close_btn_size),
            ))
        } else {
            None
        };

        // Check if pointer is over close button using egui's input state
        let pointer_pos = ui.ctx().input(|i| i.pointer.hover_pos());
        let close_hovered = close_btn_rect
            .zip(pointer_pos)
            .is_some_and(|(rect, pos)| rect.contains(pos));

        if close_hovered {
            self.close_hovered = Some(id);
        } else if self.close_hovered == Some(id) {
            self.close_hovered = None;
        }

        // Draw close button if configured
        if let Some(close_rect) = close_btn_rect {
            let close_color = if self.close_hovered == Some(id) {
                let c = config.tab_colors.tab_close_button_hover;
                egui::Color32::from_rgb(c[0], c[1], c[2])
            } else {
                let c = config.tab_colors.tab_close_button;
                egui::Color32::from_rgba_unmultiplied(c[0], c[1], c[2], opacity)
            };

            // Draw the × character centered in the close button rect
            ui.painter().text(
                close_rect.center(),
                egui::Align2::CENTER_CENTER,
                "×",
                egui::FontId::proportional(14.0),
                close_color,
            );
        }

        // Handle tab click and drag (switch to tab / initiate drag)
        // Use click_and_drag sense to enable both click and drag detection
        let tab_response = ui.interact(
            tab_rect,
            egui::Id::new(("tab_click", id)),
            egui::Sense::click_and_drag(),
        );

        // Use egui's response for click detection
        let pointer_in_tab = tab_response.hovered();
        let clicked = tab_response.clicked_by(egui::PointerButton::Primary);

        // Drag initiation: only start drag if multiple tabs exist,
        // not hovering close button, and not already dragging
        if tab_count > 1
            && !self.drag_in_progress
            && self.close_hovered != Some(id)
            && tab_response.drag_started_by(egui::PointerButton::Primary)
        {
            self.drag_in_progress = true;
            self.dragging_tab = Some(id);
            self.dragging_title = title.to_string();
            self.dragging_color = custom_color;
            self.dragging_tab_width = tab_width;
        }

        // Suppress SwitchTo while this tab is being dragged
        let is_dragging_this = self.dragging_tab == Some(id) && self.drag_in_progress;

        // Detect click using clicked_by() to only respond to mouse clicks, not keyboard
        // This prevents Enter key from triggering tab switches when a tab has keyboard focus
        // IMPORTANT: Skip if close button is hovered - let the close button handle the click
        if clicked
            && !is_dragging_this
            && action == TabBarAction::None
            && self.close_hovered != Some(id)
        {
            action = TabBarAction::SwitchTo(id);
        }

        // Handle close button click - check if close button is hovered
        if clicked && self.close_hovered == Some(id) {
            action = TabBarAction::Close(id);
        }

        // Handle right-click for context menu
        if tab_response.secondary_clicked() {
            // Initialize editing color from custom color or a default
            self.editing_color = custom_color.unwrap_or([100, 100, 100]);
            self.context_menu_tab = Some(id);
            self.context_menu_title = title.to_string();
            self.context_menu_icon = custom_icon.map(|s| s.to_string());
            self.icon_buffer = custom_icon.unwrap_or("").to_string();
            self.picking_icon = false;
            // Store click position for menu placement
            if let Some(pos) = ui.ctx().input(|i| i.pointer.interact_pos()) {
                self.context_menu_pos = pos;
            }
            // Store frame number to avoid closing on same frame
            self.context_menu_opened_frame = ui.ctx().cumulative_frame_nr();
        }

        // Update hover state (using manual detection)
        if pointer_in_tab {
            self.hovered_tab = Some(id);
        } else if self.hovered_tab == Some(id) {
            self.hovered_tab = None;
        }

        (action, tab_rect)
    }
}
