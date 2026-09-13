//! Native window effects delegated to the compositor (Windows).
//!
//! A borderless window (`window_decorations: false`) gives up everything the
//! native frame used to provide: rounded corners, the thin accent border, and the
//! system shadow. par-term does not hand-draw any of that. Instead it asks the
//! desktop compositor, which keeps the result consistent with every other window
//! on the system and costs no rendering code of our own.
//!
//! Everything here is best-effort: DWM attributes only exist on Windows 11, and an
//! unsupported attribute makes `DwmSetWindowAttribute` return a failure HRESULT
//! rather than doing anything. We log at debug level and carry on, so the window
//! simply keeps its square, borderless appearance. No attribute affects window
//! behaviour, size, or input, so a failure cannot break the window.
//!
//! The FFI is declared by hand, matching `titlebar_drag`, so this adds no
//! dependency.

/// Window effects resolved from config, so this module stays free of config types.
#[derive(Debug, Clone, Copy)]
pub struct WindowEffects {
    /// Ask DWM to round the window corners.
    pub rounded_corners: bool,
    /// Draw DWM's 1px border, and the colour to draw it in.
    pub border_color: Option<[u8; 3]>,
}

/// Applies [`WindowEffects`] to `window`. A no-op on non-Windows platforms.
#[cfg(not(target_os = "windows"))]
pub fn install(_window: &winit::window::Window, _effects: WindowEffects) {}

#[cfg(target_os = "windows")]
pub use imp::install;

#[cfg(target_os = "windows")]
mod imp {
    use super::WindowEffects;
    use std::ffi::c_void;
    use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};

    /// `DWMWA_USE_IMMERSIVE_DARK_MODE` — dark title bar / border, for the case
    /// where decorations are on.
    const DWMWA_USE_IMMERSIVE_DARK_MODE: u32 = 20;
    /// `DWMWA_WINDOW_CORNER_PREFERENCE`.
    const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;
    /// `DWMWA_BORDER_COLOR`.
    const DWMWA_BORDER_COLOR: u32 = 34;

    /// `DWMWCP_ROUND` — the standard Windows 11 corner radius.
    const DWMWCP_ROUND: i32 = 2;

    /// `DWMWA_COLOR_NONE` is `0xFFFFFFFE`; DWM draws no border at all.
    const DWMWA_COLOR_NONE: u32 = 0xFFFF_FFFE;

    /// A DWM colour is a `COLORREF`-style `0x00BBGGRR`.
    fn colorref(rgb: [u8; 3]) -> u32 {
        (rgb[0] as u32) | ((rgb[1] as u32) << 8) | ((rgb[2] as u32) << 16)
    }

    #[link(name = "dwmapi")]
    unsafe extern "system" {
        fn DwmSetWindowAttribute(
            hwnd: isize,
            attribute: u32,
            value: *const c_void,
            value_size: u32,
        ) -> i32;
    }

    /// Set one DWM attribute, logging (not failing) when the OS rejects it.
    ///
    /// # Safety
    /// `value` must point to `size` readable bytes.
    unsafe fn set_attribute(hwnd: isize, attribute: u32, value: *const c_void, size: u32, name: &str) {
        // SAFETY: forwarded directly to DWM; the caller guarantees `value`/`size`.
        let hr = unsafe { DwmSetWindowAttribute(hwnd, attribute, value, size) };
        if hr != 0 {
            // Windows 10 and earlier have no such attribute; this is expected.
            log::debug!("window effects: {name} unavailable (hr=0x{hr:08X})");
        } else {
            log::debug!("window effects: {name} applied");
        }
    }

    pub fn install(window: &winit::window::Window, effects: WindowEffects) {
        let Ok(handle) = window.window_handle() else {
            log::warn!("window effects: no window handle; native effects skipped");
            return;
        };
        let RawWindowHandle::Win32(win32) = handle.as_raw() else {
            return;
        };
        let hwnd = win32.hwnd.get();

        // Immersive dark mode only matters while the native frame is visible.
        let dark: i32 = 1;
        // SAFETY: `dark` is a live local matching the size we pass, and DWMWA takes
        // a BOOL for this attribute.
        unsafe {
            set_attribute(
                hwnd,
                DWMWA_USE_IMMERSIVE_DARK_MODE,
                std::ptr::from_ref(&dark).cast(),
                std::mem::size_of_val(&dark) as u32,
                "dark mode",
            );
        }

        if effects.rounded_corners {
            let preference = DWMWCP_ROUND;
            // SAFETY: `preference` is a live local and the attribute takes an int.
            unsafe {
                set_attribute(
                    hwnd,
                    DWMWA_WINDOW_CORNER_PREFERENCE,
                    std::ptr::from_ref(&preference).cast(),
                    std::mem::size_of_val(&preference) as u32,
                    "rounded corners",
                );
            }
        }

        // A `COLORREF`-free sentinel means "leave the border as the OS decides".
        let border = effects
            .border_color
            .map_or(DWMWA_COLOR_NONE, colorref);
        // SAFETY: `border` is a live local and the attribute takes a COLORREF.
        unsafe {
            set_attribute(
                hwnd,
                DWMWA_BORDER_COLOR,
                std::ptr::from_ref(&border).cast(),
                std::mem::size_of_val(&border) as u32,
                "window border",
            );
        }
    }
}
