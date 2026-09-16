"""Add the 'before' assertion for the Hangul fallback to the settings-ui test module.

Kept as a script because that file is checked out CRLF and a multi-line editor match would miss.
"""

import sys

PATH = r"C:\Users\jky72\par-term\build\par-term\par-term-settings-ui\src\nerd_font.rs"

ANCHOR = """        // The fallback must not have displaced the primary face for ordinary text.
        assert!(ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "abc")));
    }
}
"""

ADDITION = """        // The fallback must not have displaced the primary face for ordinary text.
        assert!(ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "abc")));
    }

    /// The defect this fallback exists for: egui's own faces cannot draw Hangul at all.
    ///
    /// Measured rather than assumed - none of Hack, Ubuntu-Light, NotoEmoji or emoji-icon-font has
    /// a single Hangul codepoint - which is why a composing syllable used to land on epaint's
    /// replacement glyph. If this ever starts failing, egui has shipped CJK coverage of its own and
    /// the fallback can be reconsidered.
    #[test]
    fn egui_default_faces_cannot_draw_hangul() {
        let ctx = egui::Context::default();
        ctx.set_fonts(egui::FontDefinitions::default());
        ctx.run(Default::default(), |_| {});

        let font = egui::FontId::monospace(14.0);
        assert!(!ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "\\u{d55c}")));
        assert!(ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "a")));
    }
}
"""


def main():
    try:
        with open(PATH, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        print(f"FAIL: cannot read {PATH}: {exc}")
        sys.exit(1)

    crlf = raw.count(b"\r\n") > 0
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if text.count(ANCHOR) != 1:
        print(f"FAIL: anchor found {text.count(ANCHOR)}x")
        sys.exit(1)
    text = text.replace(ANCHOR, ADDITION)
    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(PATH, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {PATH}: {exc}")
        sys.exit(1)
    print(f"ok: added the before-assertion test ({'CRLF' if crlf else 'LF'})")


if __name__ == "__main__":
    main()
