//! Window control actions that need platform support.
//!
//! Minimize and maximize map straight onto winit, so they need nothing here.
//! Closing does: the tab bar's close control has to reach the same code path as the
//! OS close button, because that path is where the `prompt_on_quit` confirmation
//! lives (`WindowEvent::CloseRequested`). On Windows that means posting the native
//! `WM_CLOSE` rather than shutting down directly, so the custom control cannot
//! quietly skip a prompt the native frame would have shown.

/// Ask the platform to close `window` the way its own close button would.
///
/// Returns `true` when the platform accepted the request. A `false` return means
/// the caller should fall back to shutting the window down itself.
#[cfg(not(target_os = "windows"))]
pub fn request_close(_window: &winit::window::Window) -> bool {
    false
}

#[cfg(target_os = "windows")]
pub use imp::request_close;

#[cfg(target_os = "windows")]
mod imp {
    use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};

    const WM_CLOSE: u32 = 0x0010;

    #[link(name = "user32")]
    unsafe extern "system" {
        fn PostMessageW(hwnd: isize, msg: u32, wp: usize, lp: isize) -> i32;
    }

    pub fn request_close(window: &winit::window::Window) -> bool {
        let Ok(handle) = window.window_handle() else {
            log::warn!("window controls: no window handle; close falls back to shutdown");
            return false;
        };
        let RawWindowHandle::Win32(win32) = handle.as_raw() else {
            return false;
        };
        let hwnd = win32.hwnd.get();
        // SAFETY: hwnd comes from winit for this window and stays valid for as long
        // as the window lives; WM_CLOSE carries no payload, so both params are 0.
        let posted = unsafe { PostMessageW(hwnd, WM_CLOSE, 0, 0) } != 0;
        if !posted {
            log::warn!("window controls: PostMessageW(WM_CLOSE) failed for hwnd {hwnd}");
        }
        posted
    }
}
