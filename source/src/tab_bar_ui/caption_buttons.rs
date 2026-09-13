//! macOS-style window controls drawn at the right end of the tab strip.
//!
//! With `window_decorations: false` the OS draws no frame, so nothing offers
//! minimize / maximize / close. Rather than hand-rolling a whole title bar, this
//! only draws the three controls and reuses the strip the tab bar already has.
//!
//! Two details make that work:
//!
//! * The group sits in strip width the tab layout never receives, so tabs cannot
//!   render underneath it and it needs no clipping.
//! * That same reservation keeps the group outside the drag region published to
//!   [`crate::app::window_manager::titlebar_drag`] (the region's right edge is the
//!   tab area's right edge). Without it, `WM_NCHITTEST` would answer `HTCAPTION`
//!   over the buttons and every click would start a window move.
//!
//! The colours come from the active theme rather than being hard-coded, so the
//! controls read as part of the terminal instead of a separate widget set.

use super::TabBarAction;
use crate::ui_constants::{
    CAPTION_BUTTON_DIAMETER, CAPTION_BUTTON_GAP, CAPTION_BUTTON_GLYPH_SIZE, CAPTION_BUTTON_MARGIN,
};

/// Colours for the three controls, resolved from the active theme.
pub(super) struct CaptionColors {
    pub close: [u8; 3],
    pub minimize: [u8; 3],
    pub maximize: [u8; 3],
}

/// Strip width that has to stay free for the controls, including their leading gap.
///
/// The tab layout subtracts this from its budget so tabs stop before the group.
pub(super) fn reserved_width() -> f32 {
    CAPTION_BUTTON_DIAMETER * 3.0
        + CAPTION_BUTTON_GAP * 2.0
        + CAPTION_BUTTON_MARGIN
        + crate::ui_constants::CAPTION_BUTTON_LEADING_GAP
}

/// Lighter shade used while a control is hovered, matching how the tab controls
/// brighten under the pointer.
fn hover_tint(rgb: [u8; 3]) -> egui::Color32 {
    let lift = |v: u8| v.saturating_add(45);
    egui::Color32::from_rgb(lift(rgb[0]), lift(rgb[1]), lift(rgb[2]))
}

/// Draw the controls at the right end of `strip_rect` and report a click.
///
/// Returns [`TabBarAction::None`] when nothing was clicked.
pub(super) fn show(
    ui: &mut egui::Ui,
    strip_rect: egui::Rect,
    colors: &CaptionColors,
) -> TabBarAction {
    let diameter = CAPTION_BUTTON_DIAMETER;
    let radius = diameter / 2.0;
    let center_y = strip_rect.center().y;

    // Right to left: close sits outermost, then maximize, then minimize — the
    // order Windows users expect from the right edge, and the mirror of macOS
    // putting close nearest the corner.
    let controls = [
        (TabBarAction::CloseWindow, colors.close, "×"),
        (TabBarAction::ToggleMaximizeWindow, colors.maximize, "+"),
        (TabBarAction::MinimizeWindow, colors.minimize, "-"),
    ];

    let right_edge = strip_rect.right() - CAPTION_BUTTON_MARGIN;
    let mut centers = Vec::with_capacity(controls.len());
    for index in 0..controls.len() {
        centers.push(egui::pos2(
            right_edge - radius - index as f32 * (diameter + CAPTION_BUTTON_GAP),
            center_y,
        ));
    }

    // macOS keeps the glyphs hidden until the pointer is over the group, which is
    // what makes the controls read as quiet dots rather than three labelled buttons.
    let group_rect = egui::Rect::from_min_max(
        egui::pos2(centers[controls.len() - 1].x - radius, center_y - radius),
        egui::pos2(centers[0].x + radius, center_y + radius),
    );
    let pointer = ui.ctx().input(|i| i.pointer.hover_pos());
    let group_hovered = pointer.is_some_and(|p| group_rect.contains(p));
    let hovered_index = pointer.and_then(|p| {
        centers.iter().position(|center| {
            egui::Rect::from_center_size(*center, egui::vec2(diameter, diameter)).contains(p)
        })
    });

    let mut action = TabBarAction::None;
    for (index, (click_action, rgb, glyph)) in controls.iter().enumerate() {
        let center = centers[index];
        let rect = egui::Rect::from_center_size(center, egui::vec2(diameter, diameter));
        let response = ui.interact(
            rect,
            egui::Id::new(("caption_button", index)),
            egui::Sense::click(),
        );
        if response.clicked_by(egui::PointerButton::Primary) {
            action = click_action.clone();
        }

        let fill = if hovered_index == Some(index) {
            hover_tint(*rgb)
        } else {
            egui::Color32::from_rgb(rgb[0], rgb[1], rgb[2])
        };
        ui.painter().circle_filled(center, radius, fill);

        if group_hovered {
            ui.painter().text(
                center,
                egui::Align2::CENTER_CENTER,
                *glyph,
                egui::FontId::proportional(CAPTION_BUTTON_GLYPH_SIZE),
                // Dark ink reads on every theme accent; the controls are the only
                // place in the strip where the fill is the bright colour.
                egui::Color32::from_rgb(24, 24, 28),
            );
        }
    }

    action
}
