//! Horizontal tab bar layout rendering.
//!
//! Contains the [`TabBarUI`] `render_horizontal` method and its helpers.

use crate::config::{Config, TabBarPosition};
use crate::tab::TabManager;
use crate::ui_constants::{
    TAB_LEFT_PADDING, TAB_NEW_BTN_BASE_WIDTH, TAB_SCROLL_BTN_WIDTH, TAB_SPACING,
};

use super::CHEVRON_RESERVED;
use super::TabBarAction;
use super::state::TabBarUI;
use super::tab_rendering::TabRenderParams;

impl TabBarUI {
    /// Render the tab bar in horizontal layout (top or bottom)
    pub(super) fn render_horizontal(
        &mut self,
        ctx: &mut egui::Ui,
        tabs: &TabManager,
        config: &Config,
        profiles: &crate::profile::ProfileManager,
        right_reserved_width: f32,
    ) -> TabBarAction {
        let tab_count = tabs.visible_tab_count();
        let visible_tabs = tabs.visible_tabs();

        // Clear per-frame tab rect cache
        self.tab_rects.clear();

        // Read the scale factor here: `ctx` is borrowed for the whole panel
        // closure below, so it cannot be read from inside it.
        let ppp = ctx.ctx().pixels_per_point();

        let mut action = TabBarAction::None;
        let active_tab_id = tabs.active_tab_id();

        // Layout constants
        let tab_spacing = TAB_SPACING;
        let left_padding = TAB_LEFT_PADDING;
        // The row fills the strip so `Align::Center` puts the pill in the middle of
        // it; the pill's own `TAB_DRAW_SHRINK_Y` inset creates the air on both sides.
        let btn_h = config.tabs.tab_bar_height;
        // Show the chevron dropdown when there's menu content:
        // profiles to pick from, or the AI assistant toggle.
        let show_chevron = !profiles.is_empty() || config.ai_inspector.ai_inspector_enabled;
        let new_tab_btn_width =
            TAB_NEW_BTN_BASE_WIDTH + if show_chevron { CHEVRON_RESERVED } else { 0.0 };
        let scroll_btn_width = TAB_SCROLL_BTN_WIDTH;
        // The in-app menu shares the tab bar strip, so it needs no space of its
        // own in the terminal grid — but it does take width from the tabs.
        let show_app_menu = crate::menu::AppMenuUi::enabled();
        let app_menu_width = if show_app_menu {
            crate::menu::AppMenuUi::BUTTON_WIDTH + tab_spacing
        } else {
            0.0
        };

        let bar_bg = config.tab_colors.tab_bar_background;
        // The OS draws its own window controls whenever the native frame is on, so a
        // second set would duplicate them.
        let show_caption_buttons = !config.window.window_decorations;
        // Translucent bar: egui renders on top of the terminal with LoadOp::Load, so
        // an alpha below 1.0 lets the cells / background image / custom shader show
        // through instead of the bar reading as its own floating surface.
        let bar_alpha = (config.tab_colors.tab_bar_bg_alpha.clamp(0.0, 1.0) * 255.0).round() as u8;
        let frame = egui::Frame::NONE.fill(egui::Color32::from_rgba_unmultiplied(
            bar_bg[0], bar_bg[1], bar_bg[2], bar_alpha,
        ));

        let panel = if config.tabs.tab_bar_position == TabBarPosition::Bottom {
            egui::Panel::bottom("tab_bar").exact_size(config.tabs.tab_bar_height)
        } else {
            egui::Panel::top("tab_bar").exact_size(config.tabs.tab_bar_height)
        };

        panel.frame(frame).show(ctx, |ui| {
            // Reserve space on the right for overlay panels (e.g. AI inspector Area)
            // so tabs/buttons don't render underneath them, plus the window controls.
            // Keeping the controls out of the tab budget is also what keeps them out of
            // the drag region published to `titlebar_drag` further down.
            let caption_width = if show_caption_buttons {
                super::caption_buttons::reserved_width()
            } else {
                0.0
            };
            let total_bar_width =
                (ui.available_width() - right_reserved_width.max(0.0) - caption_width).max(0.0);

            // Calculate minimum total width needed for all tabs at min_width
            let min_total_tabs_width = if tab_count > 0 {
                tab_count as f32 * config.tab_colors.tab_min_width
                    + (tab_count - 1) as f32 * tab_spacing
            } else {
                0.0
            };

            // Available width for tabs (without scroll buttons initially).
            // Budget: left_padding + app_menu_width + tabs + tab_spacing (cursor gap)
            //         + new_tab_btn_width = total
            let base_tabs_area_width =
                (total_bar_width - new_tab_btn_width - tab_spacing - left_padding - app_menu_width)
                    .max(0.0);

            // Determine if scrolling is needed
            let needs_scroll = tab_count > 0 && min_total_tabs_width > base_tabs_area_width;
            self.needs_horizontal_scroll = needs_scroll;

            // Actual tabs area width (accounting for scroll buttons if needed)
            let tabs_area_width = if needs_scroll {
                (base_tabs_area_width - 2.0 * scroll_btn_width - 2.0 * tab_spacing).max(0.0)
            } else {
                base_tabs_area_width
            };

            // Calculate tab width
            let tab_width = if tab_count == 0 || needs_scroll {
                config.tab_colors.tab_min_width
            } else if config.tab_colors.tab_stretch_to_fill {
                let total_spacing = (tab_count - 1) as f32 * tab_spacing;
                let stretched = (tabs_area_width - total_spacing) / tab_count as f32;
                // A lone tab must not consume the entire title strip. Keep its
                // height unchanged and leave room to drag the window.
                stretched
                    .max(config.tab_colors.tab_min_width)
                    .min((tabs_area_width * 0.5).max(config.tab_colors.tab_min_width))
            } else {
                config.tab_colors.tab_min_width
            };

            // Calculate max scroll offset
            let max_scroll = if needs_scroll {
                (min_total_tabs_width - tabs_area_width).max(0.0)
            } else {
                0.0
            };

            // Clamp scroll offset
            self.scroll_offset = self.scroll_offset.clamp(0.0, max_scroll);

            // Fixed-height row prevents any child widget (ScrollArea, buttons)
            // from expanding the vertical space and pushing tab pills down.
            ui.allocate_ui_with_layout(
                egui::vec2(total_bar_width, btn_h),
                egui::Layout::left_to_right(egui::Align::Center),
                |ui| {
                    let row_rect = ui.max_rect();
                    ui.spacing_mut().item_spacing = egui::vec2(tab_spacing, 0.0);
                    ui.spacing_mut().button_padding = egui::vec2(0.0, 0.0);
                    // Small left padding so the first tab's border isn't clipped by the panel edge
                    ui.add_space(left_padding);

                    if show_app_menu {
                        self.app_menu.show(ui, profiles, btn_h);
                    }

                    if needs_scroll {
                        // Left scroll button
                        let can_scroll_left = self.scroll_offset > 0.0;
                        let (left_rect, left_resp) = ui.allocate_exact_size(
                            egui::vec2(scroll_btn_width, btn_h),
                            egui::Sense::click(),
                        );
                        if left_resp.clicked() && can_scroll_left {
                            self.scroll_offset =
                                (self.scroll_offset - tab_width - tab_spacing).max(0.0);
                        }
                        let left_color = if can_scroll_left {
                            egui::Color32::from_rgb(180, 180, 180)
                        } else {
                            egui::Color32::from_rgba_unmultiplied(100, 100, 100, 80)
                        };
                        ui.painter().text(
                            left_rect.center(),
                            egui::Align2::CENTER_CENTER,
                            "<",
                            egui::FontId::proportional(14.0),
                            left_color,
                        );

                        // Tab area — child UI with explicit clip rect for horizontal
                        // clipping. No ScrollArea (it adds vertical padding that shifts
                        // tab pills down).
                        let (tab_area_rect, _) = ui.allocate_exact_size(
                            egui::vec2(tabs_area_width, btn_h),
                            egui::Sense::hover(),
                        );
                        let content_origin_x = Self::horizontal_tab_content_origin_x(
                            tab_area_rect.min.x,
                            self.scroll_offset,
                        );
                        let content_rect = egui::Rect::from_min_size(
                            egui::pos2(content_origin_x, tab_area_rect.min.y),
                            egui::vec2(min_total_tabs_width, btn_h),
                        );
                        let mut tab_ui = ui.new_child(
                            egui::UiBuilder::new()
                                .max_rect(content_rect)
                                .layout(egui::Layout::left_to_right(egui::Align::Center)),
                        );
                        // Clip the child UI to the tab area so tabs don't bleed into buttons
                        tab_ui.set_clip_rect(tab_area_rect.intersect(tab_ui.clip_rect()));
                        tab_ui.spacing_mut().item_spacing = egui::vec2(tab_spacing, 0.0);

                        for (index, tab) in visible_tabs.iter().enumerate() {
                            let is_active = Some(tab.id) == active_tab_id;
                            let is_bell_active = tab.is_bell_active();
                            let (tab_action, tab_rect) = self.render_tab_with_width(
                                &mut tab_ui,
                                TabRenderParams {
                                    id: tab.id,
                                    index,
                                    title: &tab.title,
                                    profile_icon: tab
                                        .custom_icon
                                        .as_deref()
                                        .or(tab.profile.profile_icon.as_deref()),
                                    custom_icon: tab.custom_icon.as_deref(),
                                    is_active,
                                    has_activity: tab.activity.has_activity,
                                    is_bell_active,
                                    custom_color: tab.custom_color,
                                    config,
                                    tab_size: tab_width,
                                    tab_count,
                                },
                            );
                            self.tab_rects.push((tab.id, tab_rect));

                            if tab_action != TabBarAction::None {
                                action = tab_action;
                            }
                        }

                        // Right scroll button
                        let can_scroll_right = self.scroll_offset < max_scroll;
                        let (right_rect, right_resp) = ui.allocate_exact_size(
                            egui::vec2(scroll_btn_width, btn_h),
                            egui::Sense::click(),
                        );
                        if right_resp.clicked() && can_scroll_right {
                            self.scroll_offset =
                                (self.scroll_offset + tab_width + tab_spacing).min(max_scroll);
                        }
                        let right_color = if can_scroll_right {
                            egui::Color32::from_rgb(180, 180, 180)
                        } else {
                            egui::Color32::from_rgba_unmultiplied(100, 100, 100, 80)
                        };
                        ui.painter().text(
                            right_rect.center(),
                            egui::Align2::CENTER_CENTER,
                            ">",
                            egui::FontId::proportional(14.0),
                            right_color,
                        );
                    } else {
                        // No scrolling needed - render all tabs with equal width
                        for (index, tab) in visible_tabs.iter().enumerate() {
                            let is_active = Some(tab.id) == active_tab_id;
                            let is_bell_active = tab.is_bell_active();
                            let (tab_action, tab_rect) = self.render_tab_with_width(
                                ui,
                                TabRenderParams {
                                    id: tab.id,
                                    index,
                                    title: &tab.title,
                                    profile_icon: tab
                                        .custom_icon
                                        .as_deref()
                                        .or(tab.profile.profile_icon.as_deref()),
                                    custom_icon: tab.custom_icon.as_deref(),
                                    is_active,
                                    has_activity: tab.activity.has_activity,
                                    is_bell_active,
                                    custom_color: tab.custom_color,
                                    config,
                                    tab_size: tab_width,
                                    tab_count,
                                },
                            );
                            self.tab_rects.push((tab.id, tab_rect));

                            if tab_action != TabBarAction::None {
                                action = tab_action;
                            }
                        }
                    }

                    // New tab split button: [+][chevron]

                    let prev_spacing = ui.spacing().item_spacing.x;
                    ui.spacing_mut().item_spacing.x = 0.0;

                    // "+" button — creates default tab
                    let (plus_rect, plus_resp) = ui.allocate_exact_size(
                        egui::vec2(TAB_NEW_BTN_BASE_WIDTH, btn_h),
                        egui::Sense::click(),
                    );
                    // Everything right of the buttons is empty bar = drag handle.
                    let mut free_from_x = plus_rect.right();
                    if plus_resp.clicked_by(egui::PointerButton::Primary) {
                        action = TabBarAction::NewTab;
                    }
                    let plus_color = if plus_resp.hovered() {
                        egui::Color32::WHITE
                    } else {
                        egui::Color32::from_rgb(180, 180, 180)
                    };
                    ui.painter().text(
                        plus_rect.center(),
                        egui::Align2::CENTER_CENTER,
                        "+",
                        egui::FontId::proportional(16.0),
                        plus_color,
                    );
                    if plus_resp.hovered() {
                        #[cfg(target_os = "macos")]
                        plus_resp.on_hover_text("New Tab (Cmd+T)");
                        #[cfg(not(target_os = "macos"))]
                        plus_resp.on_hover_text("New Tab (Ctrl+Shift+T)");
                    }

                    // Chevron — opens dropdown (profiles and/or assistant toggle)
                    if show_chevron {
                        let (chev_rect, chev_resp) = ui.allocate_exact_size(
                            egui::vec2(CHEVRON_RESERVED / 2.0, btn_h),
                            egui::Sense::click(),
                        );
                        free_from_x = chev_rect.right();
                        if chev_resp.clicked_by(egui::PointerButton::Primary) {
                            self.show_new_tab_profile_menu = !self.show_new_tab_profile_menu;
                        }
                        let chev_color = if chev_resp.hovered() {
                            egui::Color32::WHITE
                        } else {
                            egui::Color32::from_rgb(180, 180, 180)
                        };
                        ui.painter().text(
                            chev_rect.center(),
                            egui::Align2::CENTER_CENTER,
                            "v",
                            egui::FontId::proportional(10.0),
                            chev_color,
                        );
                        if chev_resp.hovered() {
                            chev_resp.on_hover_text("New tab from profile");
                        }
                    }

                    // Publish the empty part of the strip so a borderless window
                    // can be dragged by it (see window_manager::titlebar_drag).
                    crate::app::window_manager::titlebar_drag::publish_region(
                        (
                            row_rect.left(),
                            row_rect.top(),
                            row_rect.left() + total_bar_width,
                            row_rect.bottom(),
                        ),
                        free_from_x,
                        ppp,
                    );

                    // Restore original spacing
                    ui.spacing_mut().item_spacing.x = prev_spacing;
                },
            );

            // macOS-style window controls, drawn in the panel rather than inside the
            // tab row so they own their footprint outright.
            if show_caption_buttons {
                let theme = config.load_theme();
                let colors = super::caption_buttons::CaptionColors {
                    close: [theme.red.r, theme.red.g, theme.red.b],
                    minimize: [theme.yellow.r, theme.yellow.g, theme.yellow.b],
                    maximize: [theme.green.r, theme.green.g, theme.green.b],
                };
                // Read the rect before `show` borrows `ui` mutably for the interaction.
                let strip_rect = ui.max_rect();
                let caption_action = super::caption_buttons::show(ui, strip_rect, &colors);
                if caption_action != TabBarAction::None {
                    action = caption_action;
                }
            }

            // Handle drag feedback and drop detection (outside horizontal layout
            // so we can paint over the tab bar)
            if self.drag_in_progress {
                let drag_action = self.render_drag_feedback(ui, config);
                if drag_action != TabBarAction::None {
                    action = drag_action;
                }
            }
        });

        // Render floating ghost tab during drag (must be outside the panel)
        if self.drag_in_progress && self.dragging_tab.is_some() {
            self.render_ghost_tab(ctx, config);
        }

        // Handle context menu (color picker popup)
        if let Some(context_tab_id) = self.context_menu_tab {
            let menu_action = self.render_context_menu(ctx, context_tab_id);
            if menu_action != TabBarAction::None {
                action = menu_action;
            }
        }

        // Render new-tab profile menu if open
        let menu_action = self.render_new_tab_profile_menu(ctx, profiles, config);
        if menu_action != TabBarAction::None {
            action = menu_action;
        }

        action
    }
}
