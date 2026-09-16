//! Drag-from-the-tab-bar support for borderless windows.
//!
//! `window_decorations: false` removes the native title bar, and with it the
//! only place the user could grab to move the window. WezTerm solves this inside
//! its own window procedure (handling `WM_NCCALCSIZE` and `WM_NCHITTEST` so the
//! empty area of its tab bar behaves like a native title bar — see wezterm
//! PR #1675 / #1677, and its `window_decorations = "RESIZE"` mode).
//!
//! par-term has no equivalent, so this module implements the same idea from
//! inside the process: it subclasses the window and answers `WM_NCHITTEST` with
//! `HTCAPTION` when the cursor is over the empty part of the tab bar. Windows
//! then runs its own modal move loop, so dragging behaves exactly like a native
//! title bar, and the resize borders keep working because `WS_THICKFRAME` is
//! still set by winit when the window is resizable.
//!
//! The tab bar renderer publishes the current strip geometry every frame through
//! [`publish_region`]. Rendering and window messages both run on the event-loop
//! thread, so a thread-local is enough and the message path never takes a lock.
//!
//! The FFI is declared by hand rather than pulling in the `windows` crate, so
//! this patch adds no new dependency.

use std::cell::Cell;

/// Geometry of the draggable strip, in egui logical points.
///
/// `rect` is `(left, top, right, bottom)` of the tab bar row; `free_from_x` is
/// the x where the tabs and the `+` / chevron buttons end, so anything to the
/// right of it inside the row is empty space that can act as a title bar.
#[derive(Clone, Copy, Default)]
struct Region {
    rect: (f32, f32, f32, f32),
    free_from_x: f32,
    scale: f32,
    valid: bool,
}

thread_local! {
    static REGION: Cell<Region> = const { Cell::new(Region {
        rect: (0.0, 0.0, 0.0, 0.0),
        free_from_x: 0.0,
        scale: 1.0,
        valid: false,
    }) };
}

/// Publish the tab bar's draggable strip for this frame.
///
/// Called by the tab bar renderer every frame. `scale` is egui's
/// `pixels_per_point`, used to convert the physical pixel coordinates that
/// Windows reports in `WM_NCHITTEST` into the logical points egui lays out in.
pub fn publish_region(rect: (f32, f32, f32, f32), free_from_x: f32, scale: f32) {
    REGION.with(|cell| {
        cell.set(Region {
            rect,
            free_from_x,
            scale,
            valid: true,
        })
    });
}

/// Forget the strip, e.g. when the tab bar is hidden so the whole bar would
/// otherwise stay draggable.
pub fn clear_region() {
    REGION.with(|cell| {
        cell.set(Region {
            rect: (0.0, 0.0, 0.0, 0.0),
            free_from_x: 0.0,
            scale: 1.0,
            valid: false,
        })
    });
}

/// True when a window-local physical point falls in the empty part of the strip.
#[cfg(target_os = "windows")]
fn hits_free_tab_strip(local_x: f64, local_y: f64) -> bool {
    REGION.with(|cell| {
        let r = cell.get();
        if !r.valid || r.scale <= 0.0 {
            return false;
        }
        let x = (local_x / r.scale as f64) as f32;
        let y = (local_y / r.scale as f64) as f32;
        let (left, top, right, bottom) = r.rect;
        y >= top && y < bottom && x >= left && x < right && x >= r.free_from_x
    })
}

#[cfg(target_os = "windows")]
mod imp {
    use super::hits_free_tab_strip;
    use std::collections::HashMap;
    use std::ffi::c_void;
    use std::sync::{Mutex, OnceLock};
    use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};

    const GWLP_WNDPROC: i32 = -4;
    const WM_NCHITTEST: u32 = 0x0084;
    const WM_NCDESTROY: u32 = 0x0082;

    // WM_NCHITTEST results we hand back ourselves.
    const HTCAPTION: isize = 2;
    const HTLEFT: isize = 10;
    const HTRIGHT: isize = 11;
    const HTTOP: isize = 12;
    const HTTOPLEFT: isize = 13;
    const HTTOPRIGHT: isize = 14;
    const HTBOTTOM: isize = 15;
    const HTBOTTOMLEFT: isize = 16;
    const HTBOTTOMRIGHT: isize = 17;

    /// Width of the invisible resize border, in physical pixels. A borderless
    /// window has no non-client frame, so without this the window cannot be
    /// resized by dragging its edge at all.
    const BORDER: f64 = 6.0;

    type LResult = isize;

    /// Resize-border hit test. Corners win over edges.
    fn border_hit(local_x: f64, local_y: f64, w: f64, h: f64) -> Option<isize> {
        // Too small to carve borders out of; let it be all client area.
        if w < 3.0 * BORDER || h < 3.0 * BORDER {
            return None;
        }
        let left = local_x < BORDER;
        let right = local_x >= w - BORDER;
        let top = local_y < BORDER;
        let bottom = local_y >= h - BORDER;
        let ht = match (top, bottom, left, right) {
            (true, _, true, _) => HTTOPLEFT,
            (true, _, _, true) => HTTOPRIGHT,
            (_, true, true, _) => HTBOTTOMLEFT,
            (_, true, _, true) => HTBOTTOMRIGHT,
            (true, _, _, _) => HTTOP,
            (_, true, _, _) => HTBOTTOM,
            (_, _, true, _) => HTLEFT,
            (_, _, _, true) => HTRIGHT,
            _ => return None,
        };
        Some(ht)
    }

    #[repr(C)]
    struct Rect {
        left: i32,
        top: i32,
        right: i32,
        bottom: i32,
    }

    #[link(name = "user32")]
    unsafe extern "system" {
        fn SetWindowLongPtrW(hwnd: isize, index: i32, value: isize) -> isize;
        fn CallWindowProcW(prev: isize, hwnd: isize, msg: u32, wp: usize, lp: isize) -> LResult;
        fn GetWindowRect(hwnd: isize, out: *mut Rect) -> i32;
        fn IsZoomed(hwnd: isize) -> i32;
    }

    /// Previous window procedures, keyed by HWND, so subclassing composes with
    /// winit's own procedure instead of replacing it.
    fn previous() -> &'static Mutex<HashMap<isize, isize>> {
        static PREV: OnceLock<Mutex<HashMap<isize, isize>>> = OnceLock::new();
        PREV.get_or_init(|| Mutex::new(HashMap::new()))
    }

    unsafe extern "system" fn subclass_proc(
        hwnd: isize,
        msg: u32,
        wp: usize,
        lp: isize,
    ) -> LResult {
        if msg == WM_NCHITTEST {
            // lParam carries screen coordinates as two i16 halves.
            let screen_x = (lp & 0xFFFF) as i16 as f64;
            let screen_y = ((lp >> 16) & 0xFFFF) as i16 as f64;
            let mut r = Rect {
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
            };
            // SAFETY: hwnd is the window we are subclassing and r is a live local.
            if unsafe { GetWindowRect(hwnd, &mut r) } != 0 {
                // A borderless window's window rect equals its client rect, so
                // subtracting the origin is enough to get window-local pixels.
                let local_x = screen_x - r.left as f64;
                let local_y = screen_y - r.top as f64;
                let w = (r.right - r.left) as f64;
                let h = (r.bottom - r.top) as f64;

                // A maximized window has no draggable border; offering one would
                // let the user "resize" an edge that is pinned to the screen.
                // SAFETY: hwnd is valid for the duration of this message.
                let maximized = unsafe { IsZoomed(hwnd) } != 0;
                if !maximized && let Some(ht) = border_hit(local_x, local_y, w, h) {
                    return ht;
                }
                if hits_free_tab_strip(local_x, local_y) {
                    return HTCAPTION;
                }
            }
        }

        let prev = previous()
            .lock()
            .ok()
            .and_then(|m| m.get(&hwnd).copied())
            .unwrap_or(0);
        if prev == 0 {
            return 0;
        }
        if msg == WM_NCDESTROY
            && let Ok(mut m) = previous().lock()
        {
            m.remove(&hwnd);
        }
        // SAFETY: prev is the procedure this window had before we subclassed it.
        unsafe { CallWindowProcW(prev, hwnd, msg, wp, lp) }
    }

    /// Subclass `window` so the empty tab bar strip drags the window.
    ///
    /// Safe to call once per window. A no-op if the handle is unavailable.
    pub fn install(window: &winit::window::Window) {
        let Ok(handle) = window.window_handle() else {
            log::warn!("titlebar drag: no window handle; tab bar drag disabled");
            return;
        };
        let RawWindowHandle::Win32(win32) = handle.as_raw() else {
            return;
        };
        let hwnd = win32.hwnd.get();

        // SAFETY: hwnd comes from winit for this window and stays valid while the
        // window lives; the procedure is a 'static fn with the expected ABI.
        unsafe {
            let prev =
                SetWindowLongPtrW(hwnd, GWLP_WNDPROC, subclass_proc as *const c_void as isize);
            if prev == 0 {
                log::warn!("titlebar drag: SetWindowLongPtrW failed for hwnd {hwnd}");
                return;
            }
            if let Ok(mut m) = previous().lock() {
                m.insert(hwnd, prev);
            }
        }
        log::info!("titlebar drag installed for hwnd {hwnd}");
    }
}

#[cfg(target_os = "windows")]
pub use imp::install;

/// Non-Windows builds have no borderless drag problem to solve here.
#[cfg(not(target_os = "windows"))]
pub fn install(_window: &winit::window::Window) {}
