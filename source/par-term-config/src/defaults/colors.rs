//! Default values for color settings across all UI components.

/// Default scrollbar thumb color as RGBA floats (medium gray, nearly opaque).
pub fn scrollbar_thumb_color() -> [f32; 4] {
    [0.4, 0.4, 0.4, 0.95] // Medium gray, nearly opaque
}

/// Default scrollbar track color as RGBA floats (dark gray, semi-transparent).
pub fn scrollbar_track_color() -> [f32; 4] {
    [0.15, 0.15, 0.15, 0.6] // Dark gray, semi-transparent
}

/// Default command separator line color as RGB bytes.
pub fn command_separator_color() -> [u8; 3] {
    [128, 128, 128] // Medium gray
}

/// Default URL and file path highlight color as RGB bytes.
pub fn link_highlight_color() -> [u8; 3] {
    [79, 195, 247] // Bright cyan (#4FC3F7)
}

/// Default cursor color as RGB bytes.
pub fn cursor_color() -> [u8; 3] {
    [255, 255, 255] // White cursor
}

/// Default tab bar background color as RGB bytes.
pub fn tab_bar_background() -> [u8; 3] {
    [40, 40, 40] // Dark gray background
}

/// Default tab bar background opacity (0.0–1.0).
///
/// 1.0 keeps the bar fully opaque. Below 1.0 the bar blends over whatever the
/// window already rendered there (terminal cells, background image, or a custom
/// shader), which is how the bar stops reading as a separate surface — the same
/// approach the status bar takes with `status_bar_bg_alpha`.
pub fn tab_bar_bg_alpha() -> f32 {
    1.0
}

/// Default vertical inset of a tab pill inside the tab bar strip, in pixels.
///
/// This is the air above and below the pill. `tab_bar_height` alone cannot change
/// it: the pill is derived as `tab_bar_height - 2 * inset`, so raising the bar
/// grows the pill with it and the clearance stays the same. Raise this instead.
pub fn tab_pill_inset_y() -> f32 {
    3.0
}

/// Default flag rendering tab titles in bold.
///
/// The tab strip sits behind the terminal, so heavier text keeps the titles
/// readable over a translucent bar without needing a brighter colour.
pub fn tab_text_bold() -> bool {
    false
}

/// Default height of the active tab's bottom indicator bar, in pixels.
///
/// 0.0 disables the indicator entirely; the active tab is then marked only by
/// its background fill and border.
pub fn tab_indicator_height() -> f32 {
    2.0
}

/// Default active tab background color as RGB bytes.
pub fn tab_active_background() -> [u8; 3] {
    [60, 60, 60] // Slightly lighter for active tab
}

/// Default inactive tab background color as RGB bytes.
pub fn tab_inactive_background() -> [u8; 3] {
    [40, 40, 40] // Same as bar background
}

/// Default tab hover background color as RGB bytes.
pub fn tab_hover_background() -> [u8; 3] {
    [50, 50, 50] // Between inactive and active
}

/// Default active tab text color as RGB bytes.
pub fn tab_active_text() -> [u8; 3] {
    [255, 255, 255] // White text for active tab
}

/// Default inactive tab text color as RGB bytes.
pub fn tab_inactive_text() -> [u8; 3] {
    [180, 180, 180] // Gray text for inactive tabs
}

/// Default active tab underline indicator color as RGB bytes.
pub fn tab_active_indicator() -> [u8; 3] {
    [100, 150, 255] // Blue underline for active tab
}

/// Default tab activity dot color as RGB bytes.
pub fn tab_activity_indicator() -> [u8; 3] {
    [100, 180, 255] // Light blue activity dot
}

/// Default tab bell icon color as RGB bytes.
pub fn tab_bell_indicator() -> [u8; 3] {
    [255, 200, 100] // Orange/yellow bell icon
}

/// Default tab close button color as RGB bytes.
pub fn tab_close_button() -> [u8; 3] {
    [150, 150, 150] // Gray close button
}

/// Default tab close button hover color as RGB bytes.
pub fn tab_close_button_hover() -> [u8; 3] {
    [255, 100, 100] // Red on hover
}

/// Default tab border color as RGB bytes.
pub fn tab_border_color() -> [u8; 3] {
    [80, 80, 80] // Subtle gray border between tabs
}

/// Default progress bar normal-state color as RGB bytes.
pub fn progress_bar_normal_color() -> [u8; 3] {
    [80, 180, 255] // Blue for normal progress
}

/// Default progress bar warning-state color as RGB bytes.
pub fn progress_bar_warning_color() -> [u8; 3] {
    [255, 200, 50] // Yellow for warning
}

/// Default progress bar error-state color as RGB bytes.
pub fn progress_bar_error_color() -> [u8; 3] {
    [255, 80, 80] // Red for error
}

/// Default progress bar indeterminate-state color as RGB bytes.
pub fn progress_bar_indeterminate_color() -> [u8; 3] {
    [150, 150, 150] // Gray for indeterminate
}

/// Default cursor guide (crosshair) highlight color as RGBA bytes.
pub fn cursor_guide_color() -> [u8; 4] {
    [255, 255, 255, 20] // Subtle white highlight
}

/// Default cursor drop shadow color as RGBA bytes.
pub fn cursor_shadow_color() -> [u8; 4] {
    [0, 0, 0, 128] // Semi-transparent black
}

/// Default cursor glow boost color as RGB bytes.
pub fn cursor_boost_color() -> [u8; 3] {
    [255, 255, 255] // White glow
}

/// Default badge text color as RGB bytes.
pub fn badge_color() -> [u8; 3] {
    [255, 0, 0] // Red text (matches iTerm2 default)
}

/// Default split-pane divider color as RGB bytes.
pub fn pane_divider_color() -> [u8; 3] {
    [80, 80, 80] // Subtle gray divider
}

/// Default split-pane divider hover color as RGB bytes (shown during resize).
pub fn pane_divider_hover_color() -> [u8; 3] {
    [120, 150, 200] // Brighter color on hover for resize feedback
}

/// Default focused pane border color as RGB bytes.
pub fn pane_focus_color() -> [u8; 3] {
    [100, 150, 255] // Blue highlight for focused pane
}

/// Default pane title bar text color as RGB bytes.
pub fn pane_title_color() -> [u8; 3] {
    [200, 200, 200] // Light gray text for pane titles
}

/// Default pane title bar background color as RGB bytes.
pub fn pane_title_bg_color() -> [u8; 3] {
    [40, 40, 50] // Dark background for pane title bars
}

/// Default search match highlight color as RGBA bytes.
pub fn search_highlight_color() -> [u8; 4] {
    [255, 200, 0, 180] // Yellow with some transparency
}

/// Default current search match highlight color as RGBA bytes.
pub fn search_current_highlight_color() -> [u8; 4] {
    [255, 100, 0, 220] // Orange, more visible for current match
}

/// Default visual bell flash color as RGB bytes.
pub fn visual_bell_color() -> [u8; 3] {
    [255, 255, 255] // White flash
}
