//! Imm32 composition observer for the main window.
//!
//! Windows hands the composition (preedit) string to the focused application and expects it to
//! draw the text itself; winit enforces that by clearing `ISC_SHOWUICOMPOSITIONWINDOW` out of
//! every `WM_IME_SETCONTEXT` before calling `DefWindowProcW`. That is the same contract WezTerm
//! implements as `ime_preedit_rendering = "Builtin"`, and par-term already has the drawing half:
//! [`render_ime_preedit`](crate::app::render_pipeline::egui_overlays) paints the string at the
//! cursor cell with the terminal's own font.
//!
//! What par-term did not have is a reliable source for the string. Its only supply was winit's
//! `WM_IME_COMPOSITION` -> `Ime::Preedit`, and when that path yields nothing the composition is
//! simply invisible: the committed syllable still reaches the PTY (it also arrives as `WM_CHAR`
//! text), so Korean *works* while the letters being composed are never drawn — which is exactly
//! how this was reported.
//!
//! So this module reads the composition string straight out of Imm32, and does nothing else with
//! it:
//!
//! - **Display only.** Commits stay on winit's path. Writing `GCS_RESULTSTR` here as well would
//!   put every syllable on the wire twice.
//! - **Chained, not replaced.** Every message still reaches winit's own procedure, so its IME
//!   bookkeeping (and its suppression of the OS composition window) is unchanged.
//! - **Flags handled independently.** A single `WM_IME_COMPOSITION` may carry `GCS_RESULTSTR` and
//!   `GCS_COMPSTR` together (the IME committed one syllable and already opened the next). That is
//!   the case a naive implementation clears the composition on, leaving the new preedit invisible;
//!   see the same fix in wispterm's `src/apprt/win32.zig`.
//!
//! `ImePreeditRendering::System` flips one thing here: `WM_IME_SETCONTEXT` is answered with
//! `ISC_SHOWUICOMPOSITIONWINDOW` put back, and Windows draws its own composition window while this
//! module observes nothing. That is WezTerm's `"System"` mode, kept as an escape hatch because it
//! cannot be lost to a frame that never renders.

use std::cell::{Cell, RefCell};

use par_term_config::ImePreeditRendering;

/// What the window procedure last saw, in the shape the renderer needs.
#[derive(Clone, Default)]
pub struct Observed {
    /// A composition session is open (`WM_IME_STARTCOMPOSITION` .. `ENDCOMPOSITION`).
    pub composing: bool,
    /// The composition string, empty until the IME has produced one.
    pub text: String,
}

thread_local! {
    static COMPOSITION: RefCell<Observed> = const { RefCell::new(Observed {
        composing: false,
        text: String::new(),
    }) };
    static MODE: Cell<ImePreeditRendering> = const { Cell::new(ImePreeditRendering::Builtin) };
}

#[cfg(target_os = "windows")]
/// The rendering mode last published by the input layer; `Builtin` means par-term draws the
/// composition itself (the cell-buffer stamp in `render_pipeline::ime_stamp`), `System` means
/// the OS composition window is left alone.
pub fn mode() -> ImePreeditRendering {
    MODE.with(Cell::get)
}

/// Tell the window procedure which renderer owns the composition.
///
/// Called once per frame, so a config change (the settings UI writes the same field) takes effect
/// on the next frame without restarting. Switching to `System` also drops whatever was observed,
/// so the built-in overlay cannot linger under the OS-drawn window.
pub fn publish_mode(mode: ImePreeditRendering) {
    if MODE.with(|cell| cell.get()) == mode {
        return;
    }
    MODE.with(|cell| cell.set(mode));
    COMPOSITION.with(|cell| *cell.borrow_mut() = Observed::default());
    log::info!("IME: composition rendering is now {mode:?}");
}

/// Snapshot of the composition as the window procedure last saw it.
pub fn current() -> Observed {
    COMPOSITION.with(|cell| cell.borrow().clone())
}

/// Test hook: pretend a composition is open, the way `PAR_TERM_IME_PREEDIT` seeds winit's path.
///
/// The overlay screenshot harness cannot drive a real IME from a script, and this module is the
/// other source it has to cover, so it needs its own seed (`PAR_TERM_IME_IMM_PREEDIT`).
pub fn seed(text: &str) {
    COMPOSITION.with(|cell| {
        let mut observed = cell.borrow_mut();
        observed.composing = !text.is_empty();
        observed.text = text.to_owned();
    });
}

/// Apply `PAR_TERM_IME_IMM_PREEDIT`, if set. Inert without it.
fn with_env_seed() {
    match std::env::var("PAR_TERM_IME_IMM_PREEDIT") {
        Ok(text) if !text.is_empty() => {
            log::warn!(
                "IME: seeding an Imm32-side composition from PAR_TERM_IME_IMM_PREEDIT (test hook)"
            );
            seed(&text);
        }
        _ => {}
    }
}

#[cfg(target_os = "windows")]
mod imp {
    use super::{COMPOSITION, mode};
    use par_term_config::ImePreeditRendering;
    use std::collections::HashMap;
    use std::ffi::c_void;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Mutex, OnceLock};
    use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};

    const GWLP_WNDPROC: i32 = -4;
    const WM_NCDESTROY: u32 = 0x0082;
    const WM_IME_SETCONTEXT: u32 = 0x0281;
    const WM_IME_STARTCOMPOSITION: u32 = 0x010D;
    const WM_IME_ENDCOMPOSITION: u32 = 0x010E;
    const WM_IME_COMPOSITION: u32 = 0x010F;

    /// `WM_IME_COMPOSITION` lParam bits (IME composition string values).
    const GCS_COMPSTR: u32 = 0x0008;
    const GCS_RESULTSTR: u32 = 0x0800;

    /// `WM_IME_SETCONTEXT` lParam: let Windows draw its own composition window.
    const ISC_SHOWUICOMPOSITIONWINDOW: isize = 0x8000_0000;

    /// Every IME UI bit: composition window, guideline and all candidate windows.
    ///
    /// winit clears only `ISC_SHOWUICOMPOSITIONWINDOW` on this message, leaving the candidate bits
    /// set - so an IME is still free to draw a box of its own near the caret. That is what was
    /// reported: a small rectangle above the cursor, whose click commits the composition. winit's
    /// own intent is the opposite (PR #2241: "Hide OS-drawn composing text", same as every other
    /// platform), so the whole mask is cleared here for `Builtin`, where par-term draws the
    /// composition itself. `System` restores the composition bit instead and the rest of the OS UI
    /// keeps working there, which is the mode to use if a candidate list is needed (한자/변환).
    const ISC_SHOWUIALL: u32 = 0xC000_000F;

    /// `ImmAssociateContextEx` flags: hand the window the default input context.
    const IACE_DEFAULT: u32 = 0x0010;

    type LResult = isize;

    #[link(name = "user32")]
    unsafe extern "system" {
        fn SetWindowLongPtrW(hwnd: isize, index: i32, value: isize) -> isize;
        fn CallWindowProcW(prev: isize, hwnd: isize, msg: u32, wp: usize, lp: isize) -> LResult;
        fn DefWindowProcW(hwnd: isize, msg: u32, wp: usize, lp: isize) -> LResult;
        fn ShowWindow(hwnd: isize, cmd: i32) -> i32;
    }

    #[link(name = "imm32")]
    unsafe extern "system" {
        fn ImmGetContext(hwnd: isize) -> isize;
        fn ImmReleaseContext(hwnd: isize, himc: isize) -> i32;
        fn ImmAssociateContextEx(hwnd: isize, himc: isize, flags: u32) -> i32;
        fn ImmGetCompositionStringW(himc: isize, index: u32, buf: *mut c_void, len: u32) -> i32;
        fn ImmGetDefaultIMEWnd(hwnd: isize) -> isize;
    }

    /// `ShowWindow` command: hide the window.
    const SW_HIDE: i32 = 0;

    /// Previous window procedures, keyed by HWND. Two modules subclass the same window
    /// (`titlebar_drag` does too), so each one chains to what it found.
    fn previous() -> &'static Mutex<HashMap<isize, isize>> {
        static PREV: OnceLock<Mutex<HashMap<isize, isize>>> = OnceLock::new();
        PREV.get_or_init(|| Mutex::new(HashMap::new()))
    }

    /// One warning is enough; a missing input context would otherwise log per keystroke.
    fn warned_no_context() -> &'static AtomicBool {
        static WARNED: AtomicBool = AtomicBool::new(false);
        &WARNED
    }

    /// Read one composition string out of the input context.
    ///
    /// `size` comes back as a byte count, and the buffer has to be asked for twice (size, then
    /// contents). A negative result is an error, `0` an empty string.
    unsafe fn composition_string(himc: isize, index: u32) -> Option<String> {
        // SAFETY: null buffer with length 0 is the documented size query.
        let size = unsafe { ImmGetCompositionStringW(himc, index, std::ptr::null_mut(), 0) };
        if size < 0 {
            return None;
        }
        if size == 0 {
            return Some(String::new());
        }
        let mut buf = vec![0u16; size as usize / 2];
        // SAFETY: buf.as_mut_ptr() is valid for `size` bytes, which is what we advertise.
        let written = unsafe {
            ImmGetCompositionStringW(himc, index, buf.as_mut_ptr() as *mut c_void, size as u32)
        };
        if written < 0 {
            return None;
        }
        buf.truncate(written as usize / 2);
        Some(String::from_utf16_lossy(&buf))
    }

    /// Update the observed composition from one `WM_IME_COMPOSITION`.
    ///
    /// The flags are deliberately not treated as mutually exclusive: a message may carry
    /// `GCS_RESULTSTR | GCS_COMPSTR`, meaning "the previous syllable is finished and here is the
    /// next one already". Committing the result is winit's job, so only the preedit is read here,
    /// and an empty result-only message ends the displayed composition.
    unsafe fn observe_composition(hwnd: isize, lp: isize) {
        // SAFETY: hwnd is the window this procedure was installed on.
        let himc = unsafe { ImmGetContext(hwnd) };
        if himc == 0 {
            if !warned_no_context().swap(true, Ordering::Relaxed) {
                log::warn!(
                    "IME: ImmGetContext returned no input context for hwnd {hwnd}; the composition \
                     string cannot be read (set ime_preedit_rendering: system to let Windows draw it)"
                );
            }
            return;
        }

        let flags = lp as u32;
        let text = if flags & GCS_COMPSTR != 0 {
            // SAFETY: himc is a live context until released below.
            unsafe { composition_string(himc, GCS_COMPSTR) }
        } else if flags & GCS_RESULTSTR != 0 {
            // The composed string was committed and no new preedit came with it.
            Some(String::new())
        } else {
            None
        };
        // SAFETY: himc came from ImmGetContext above and is not used afterwards.
        unsafe { ImmReleaseContext(hwnd, himc) };

        if let Some(text) = text {
            // One line per keystroke while composing, so debug: `DEBUG_LEVEL=2` on the command line
            // is what makes a real-IME run diagnosable (the committed glyphs alone cannot tell you
            // whether the composition reached us or only winit's commit did).
            crate::debug_info!("IME", "imm32 composition: {text:?} (flags=0x{flags:x})");
            COMPOSITION.with(|cell| {
                let mut observed = cell.borrow_mut();
                observed.composing = true;
                observed.text = text;
            });
        }
    }

    fn end_composition() {
        COMPOSITION.with(|cell| {
            let mut observed = cell.borrow_mut();
            observed.composing = false;
            observed.text.clear();
        });
    }

    /// Hide the IME's own UI window, when it has one.
    ///
    /// Clearing `ISC_SHOWUIALL` says what Windows may draw, and on its own that is not enough: a
    /// legacy IMM32 IME also owns a small top-level window for its UI, and Windows 11 draws the
    /// composition for some Korean IMEs in a floating box there regardless - which is the
    /// rectangle reported above the cursor whose click commits the composition. Hiding the window
    /// is the direct way to keep it off screen while par-term draws the composition inline. A
    /// no-op for a TSF-only IME, whose UI belongs to `TextInputHost.exe` and cannot be suppressed
    /// from the application at all (that case needs `ime_preedit_rendering: system`).
    fn hide_ime_ui(hwnd: isize) {
        // SAFETY: hwnd is the window we subclassed; ImmGetDefaultIMEWnd only reads thread state.
        let ime_window = unsafe { ImmGetDefaultIMEWnd(hwnd) };
        if ime_window == 0 || ime_window == hwnd {
            return;
        }
        // SAFETY: a window handle handed back by ImmGetDefaultIMEWnd. Hiding it does not stop the
        // IME from composing - it still owns this window and keeps receiving its messages - it
        // only stops it from being drawn, which is what we are replacing.
        unsafe { ShowWindow(ime_window, SW_HIDE) };
    }

    unsafe extern "system" fn subclass_proc(
        hwnd: isize,
        msg: u32,
        wp: usize,
        mut lp: isize,
    ) -> LResult {
        match mode() {
            ImePreeditRendering::Builtin => {
                if msg == WM_IME_SETCONTEXT {
                    crate::debug_info!(
                        "IME",
                        "WM_IME_SETCONTEXT ui flags 0x{:x} -> suppressed",
                        lp
                    );
                    // Windows offers its composition/candidate windows here; we draw the
                    // composition ourselves, so none of them should appear. Chaining afterwards
                    // lets winit strip the composition bit again, which is harmless.
                    lp &= !(ISC_SHOWUIALL as isize);
                    hide_ime_ui(hwnd);
                }
                match msg {
                    WM_IME_STARTCOMPOSITION => {
                        COMPOSITION.with(|cell| cell.borrow_mut().composing = true);
                        // A composition is exactly when an IME may raise its UI, and the flags
                        // message is not guaranteed to have arrived first (logged: it can land
                        // seconds after the composition it was meant to govern), so hide the UI
                        // window at the moment it would appear.
                        hide_ime_ui(hwnd);
                    }
                    WM_IME_COMPOSITION => {
                        // SAFETY: hwnd is the window this procedure was installed on.
                        unsafe { observe_composition(hwnd, lp) };
                    }
                    WM_IME_ENDCOMPOSITION => end_composition(),
                    _ => {}
                }
            }
            ImePreeditRendering::System => {
                if msg == WM_IME_SETCONTEXT {
                    // winit strips this bit on every one of these messages; putting it back and
                    // answering here (instead of chaining) is what makes Windows draw the
                    // composition window itself. winit has no other logic in this arm.
                    // SAFETY: same arguments Windows passed to us, plus the restored bit.
                    return unsafe {
                        DefWindowProcW(hwnd, msg, wp, lp | ISC_SHOWUICOMPOSITIONWINDOW)
                    };
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

    /// Subclass `window` to observe the IME composition, and make sure it has an input context.
    ///
    /// Safe to call once per window. A no-op if the handle is unavailable.
    pub fn install(window: &winit::window::Window) {
        super::with_env_seed();
        let Ok(handle) = window.window_handle() else {
            log::warn!("IME composition: no window handle; the composition string cannot be read");
            return;
        };
        let RawWindowHandle::Win32(win32) = handle.as_raw() else {
            return;
        };
        let hwnd = win32.hwnd.get();

        // SAFETY: hwnd comes from winit for this window and stays valid while the window lives;
        // the procedure is a 'static fn with the expected ABI.
        unsafe {
            // winit only associates a context when the system reports IME support, and a window
            // with none cannot be asked for a composition string at all. Asking for the default
            // context is harmless when one is already associated.
            ImmAssociateContextEx(hwnd, 0, IACE_DEFAULT);

            // Best effort before the first composition: hide the IME's UI window if it already
            // exists, so the floating composition box never gets a chance to be on screen.
            hide_ime_ui(hwnd);

            let prev =
                SetWindowLongPtrW(hwnd, GWLP_WNDPROC, subclass_proc as *const c_void as isize);
            if prev == 0 {
                log::warn!("IME composition: SetWindowLongPtrW failed for hwnd {hwnd}");
                return;
            }
            if let Ok(mut m) = previous().lock() {
                m.insert(hwnd, prev);
            }
        }
        log::info!("IME composition observer installed for hwnd {hwnd}");
    }
}

#[cfg(target_os = "windows")]
pub use imp::install;

/// Non-Windows platforms get the composition from winit directly (which is what the preedit
/// overlay was written against); there is no Imm32 to read.
#[cfg(not(target_os = "windows"))]
pub fn install(_window: &winit::window::Window) {
    with_env_seed();
}
