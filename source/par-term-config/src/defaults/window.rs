//! Default values for window and visual-appearance settings.

/// Default terminal width in columns.
pub fn cols() -> usize {
    80
}

/// Default terminal height in rows.
pub fn rows() -> usize {
    24
}

/// Default window title string.
pub fn window_title() -> String {
    "par-term".to_string()
}

/// Default color theme identifier.
pub fn theme() -> String {
    "dark-background".to_string()
}

/// Default light color theme identifier.
pub fn light_theme() -> String {
    "light-background".to_string()
}

/// Default dark color theme identifier.
pub fn dark_theme() -> String {
    "dark-background".to_string()
}

/// Default screenshot file format (`"png"`, `"jpg"`, etc.).
pub fn screenshot_format() -> String {
    "png".to_string()
}

/// Default maximum render frames per second.
pub fn max_fps() -> u32 {
    60
}

/// Default window padding in pixels around the terminal content.
pub fn window_padding() -> f32 {
    1.0
}

/// Default window opacity (1.0 = fully opaque).
pub fn window_opacity() -> f32 {
    1.0 // Fully opaque by default
}

/// Default background image opacity (1.0 = fully opaque).
pub fn background_image_opacity() -> f32 {
    1.0 // Fully opaque by default
}

/// Default pane background darkening amount (0.0 = no darkening).
pub fn pane_background_darken() -> f32 {
    0.0 // No darkening by default
}

/// Default terminal background color as RGB bytes.
pub fn background_color() -> [u8; 3] {
    [30, 30, 30] // Dark gray
}

/// Default text opacity (1.0 = fully opaque).
pub fn text_opacity() -> f32 {
    1.0 // Fully opaque text by default
}

/// Default tab bar height in pixels.
pub fn tab_bar_height() -> f32 {
    28.0 // Default tab bar height in pixels
}

/// Default tab bar width in pixels (used when tab bar is in left/right position).
pub fn tab_bar_width() -> f32 {
    160.0 // Default tab bar width in pixels (for left position)
}

/// Default render FPS when the window is not focused.
pub fn unfocused_fps() -> u32 {
    30 // Reduced FPS when window is not focused
}

/// Default render FPS for inactive (non-visible) tabs.
pub fn inactive_tab_fps() -> u32 {
    2 // Very low FPS for inactive (non-visible) tabs - just enough for activity detection
}

/// Default opacity for inactive tabs (0.0–1.0).
pub fn inactive_tab_opacity() -> f32 {
    0.6 // Default opacity for inactive tabs (60%)
}

/// Default minimum tab width in pixels before tab bar scrolling activates.
pub fn tab_min_width() -> f32 {
    120.0 // Minimum tab width in pixels before scrolling kicks in
}

/// Default flag controlling whether tabs stretch to fill available bar width.
pub fn tab_stretch_to_fill() -> bool {
    true // Tabs stretch to share available width by default
}

/// Default flag enabling HTML rendering in tab titles.
pub fn tab_html_titles() -> bool {
    false // Render tab titles as plain text unless explicitly enabled
}

/// Default tab border width in pixels.
pub fn tab_border_width() -> f32 {
    1.0 // 1 pixel border
}

/// Default flag enabling cubemap sampling for shader channel 2.
pub fn cubemap_enabled() -> bool {
    true // Cubemap sampling enabled by default when a path is configured
}

/// Default flag enabling window size snapping to the terminal cell grid.
pub fn snap_window_to_grid() -> bool {
    true
}

/// Default flag controlling whether the background image is used as shader channel 0.
pub fn use_background_as_channel0() -> bool {
    false // By default, use configured channel0 texture, not background image
}

/// Default flag asking Windows to round the window's corners.
///
/// Windows 11 rounds decorated windows by itself; a borderless window has to ask
/// via DWM (`DWMWA_WINDOW_CORNER_PREFERENCE`). A no-op on other platforms and on
/// Windows 10, where the request simply fails and the window stays square.
pub fn window_rounded_corners() -> bool {
    true
}

/// Default flag drawing a thin DWM border around the window.
///
/// With `window_decorations: false` Windows draws no frame at all, which leaves
/// the window as a raw rectangle. Enabling this asks DWM for its 1px border so
/// the window reads as a finished surface. Off by default because it only has an
/// effect on Windows 11.
pub fn window_border_enabled() -> bool {
    false
}

/// Default DWM window border colour as RGB bytes.
pub fn window_border_color() -> [u8; 3] {
    [80, 80, 80]
}
