"""Apply the Hangul-fallback patch to the par-term tree, preserving each file's newline style.

Used instead of a text editor because part of this tree is checked out CRLF and part LF; a
multi-line match has to normalise before comparing or it silently misses.
"""

import os
import sys

ROOT = r"C:\Users\jky72\par-term\build\par-term"


def patch(rel, pairs, append=None):
    path = os.path.join(ROOT, rel)
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        print(f"FAIL {rel}: cannot read {path}: {exc}")
        sys.exit(1)
    crlf = raw.count(b"\r\n") > 0
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for old, new in pairs:
        if old not in text:
            print(f"FAIL {rel}: anchor not found:\n---\n{old[:200]}\n---")
            sys.exit(1)
        if text.count(old) != 1:
            print(
                f"FAIL {rel}: anchor appears {text.count(old)}x:\n---\n{old[:120]}\n---"
            )
            sys.exit(1)
        text = text.replace(old, new)
    if append:
        if not text.endswith("\n"):
            text += "\n"
        text += append
    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(path, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL {rel}: cannot write {path}: {exc}")
        sys.exit(1)
    print(f"ok   {rel} ({'CRLF' if crlf else 'LF'})")


# ---------------------------------------------------------------- settings-ui fonts
patch(
    r"par-term-settings-ui\src\nerd_font.rs",
    [],
    append="""
#[cfg(test)]
mod tests {
    use super::*;

    /// Caller-supplied CJK bytes must be registered in both families.
    ///
    /// The bytes themselves are irrelevant here - only that the face is wired into the stack,
    /// which `configure_nerd_font` cannot do on its own.
    #[test]
    fn supplied_cjk_face_is_registered_in_both_families() {
        let ctx = egui::Context::default();
        configure_egui_fonts(&ctx, Some(NERD_FONT_BYTES.to_vec()));
        ctx.run(Default::default(), |_| {});

        let families = ctx.fonts(|fonts| fonts.definitions().families.clone());
        for family in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
            let names = families.get(&family).cloned().unwrap_or_default();
            assert!(
                names.iter().any(|name| name == "cjk_fallback"),
                "{family} must be able to fall back to the CJK face, got {names:?}"
            );
        }
    }

    /// The assembled stack must actually be able to draw Hangul.
    ///
    /// Regression guard for the bug that motivated the fallback: none of egui's own faces carries
    /// a single Hangul codepoint, so a composing syllable painted as the replacement glyph.
    /// Skipped on a machine with no CJK font installed, where there is nothing to fall back to.
    #[test]
    fn assembled_stack_covers_hangul_when_a_cjk_font_exists() {
        if load_platform_cjk_font().is_none() {
            eprintln!("skipping: no platform CJK font installed");
            return;
        }
        let ctx = egui::Context::default();
        configure_nerd_font(&ctx);
        ctx.run(Default::default(), |_| {});

        let font = egui::FontId::monospace(14.0);
        assert!(
            ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "\\u{d55c}\\u{ae00}")),
            "Hangul must resolve to a face in the egui font stack"
        );
        // The fallback must not have displaced the primary face for ordinary text.
        assert!(ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "abc")));
    }
}
""",
)

# ---------------------------------------------------------------- crate root
patch(
    r"src\lib.rs",
    [("pub mod font_metrics;", "pub mod egui_font;\npub mod font_metrics;")],
)

# ---------------------------------------------------------------- main window egui init
patch(
    r"src\app\window_state\renderer_init.rs",
    [
        (
            """        let egui_ctx = egui::Context::default();
        crate::settings_ui::nerd_font::configure_nerd_font(&egui_ctx);""",
            """        let egui_ctx = egui::Context::default();
        // egui's own faces carry no CJK codepoints, so the IME preedit would paint a composed
        // syllable as a replacement box. Hand it the terminal's font when that font covers Korean,
        // so the composition is drawn in the very face the committed text will use.
        let cjk_fallback = crate::egui_font::cjk_fallback_bytes(&self.config.load());
        crate::settings_ui::nerd_font::configure_egui_fonts(&egui_ctx, cjk_fallback);""",
        )
    ],
)

# ---------------------------------------------------------------- settings window egui init
patch(
    r"src\settings_window\mod.rs",
    [
        (
            """        let egui_ctx = egui::Context::default();
        crate::settings_ui::nerd_font::configure_nerd_font(&egui_ctx);""",
            """        let egui_ctx = egui::Context::default();
        // Same CJK fallback as the main window: the settings UI shows font names and profile
        // labels, which are Korean for a Korean setup.
        let cjk_fallback = crate::egui_font::cjk_fallback_bytes(&config);
        crate::settings_ui::nerd_font::configure_egui_fonts(&egui_ctx, cjk_fallback);""",
        )
    ],
)

# ---------------------------------------------------------------- IME state seed hook
patch(
    r"src\app\window_state\ime_state.rs",
    [
        (
            """impl ImeState {
    /// Whether there is preedit text to draw.""",
            """impl ImeState {
    /// Seed a composition from `PAR_TERM_IME_PREEDIT`, for screenshots without a human at the
    /// keyboard.
    ///
    /// A real composition is only delivered by the platform IME to the *active* window, and
    /// Windows refuses to hand a background process an input context, so the preedit overlay had
    /// no automated coverage at all. This hook feeds the same state `Ime::Preedit` feeds, which is
    /// what makes the overlay screenshot-testable (see `galaxy-work/work/ime_preedit_probe.ps1`).
    /// It is inert unless the variable is set.
    pub(crate) fn with_env_seed(mut self) -> Self {
        match std::env::var("PAR_TERM_IME_PREEDIT") {
            Ok(text) if !text.is_empty() => {
                log::warn!("IME: seeding a composition from PAR_TERM_IME_PREEDIT (test hook)");
                self.enabled = true;
                self.preedit = text;
            }
            _ => {}
        }
        self
    }

    /// Whether there is preedit text to draw.""",
        )
    ],
)

patch(
    r"src\app\window_state\impl_init.rs",
    [
        (
            "ime: super::ime_state::ImeState::default(),",
            "ime: super::ime_state::ImeState::default().with_env_seed(),",
        )
    ],
)

# ---------------------------------------------------------------- preedit overlay background
patch(
    r"src\app\render_pipeline\egui_overlays.rs",
    [
        (
            """/// Composing text is not part of the grid - the child learns nothing about it until the IME
/// commits - so it is painted over the cursor cell, which is how a native terminal shows a
/// syllable being composed. The caller passes the renderer's physical-pixel metrics while egui
/// works in logical points, hence the `scale` division.""",
            """/// Composing text is not part of the grid - the child learns nothing about it until the IME
/// commits - so it is painted over the cursor cell, which is how a native terminal shows a
/// syllable being composed. The caller passes the renderer's physical-pixel metrics while egui
/// works in logical points, hence the `scale` division.
///
/// `bg` is the fill behind the composing glyphs, and it is `None` whenever something other than
/// the theme paints the grid background (a custom shader or a background image). Filling with the
/// theme background there would stamp an opaque rectangle through an animated background.""",
        ),
        (
            """    scale: f32,
    fg: egui::Color32,
    bg: egui::Color32,
) {""",
            """    scale: f32,
    fg: egui::Color32,
    bg: Option<egui::Color32>,
) {""",
        ),
        (
            """            ui.painter().rect_filled(rect, 0.0, bg);
            ui.painter().galley(rect.min, galley, fg);""",
            """            if let Some(bg) = bg {
                ui.painter().rect_filled(rect, 0.0, bg);
            }
            ui.painter().galley(rect.min, galley, fg);""",
        ),
    ],
)

print("done")
