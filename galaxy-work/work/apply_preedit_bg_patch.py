"""Second half of the Hangul/preedit patch: stop the preedit from filling an opaque box.

Split from apply_hangul_patch.py because a re-run of that script is not idempotent (its anchors
are gone once applied).
"""

import os
import sys

ROOT = r"C:\Users\jky72\par-term\build\par-term"
REL = r"src\app\render_pipeline\egui_submit.rs"

OLD = """        let ime_colors = if ime_active {
            let theme = self.config.load().load_theme();
            (
                egui::Color32::from_rgb(theme.foreground.r, theme.foreground.g, theme.foreground.b),
                egui::Color32::from_rgb(theme.background.r, theme.background.g, theme.background.b),
            )
        } else {
            (egui::Color32::TRANSPARENT, egui::Color32::TRANSPARENT)
        };"""

NEW = """        let ime_colors = if ime_active {
            let config = self.config.load();
            let theme = config.load_theme();
            // The theme background is only behind the grid when nothing else paints it. A custom
            // shader or a background image owns that layer, and filling the composing cell with
            // the theme colour would stamp an opaque rectangle through them.
            let theme_paints_background = !(config.shader.custom_shader_enabled
                && config.shader.custom_shader.is_some())
                && !(config.background.background_image_enabled
                    && config.background.background_image.is_some());
            (
                egui::Color32::from_rgb(theme.foreground.r, theme.foreground.g, theme.foreground.b),
                theme_paints_background.then(|| {
                    egui::Color32::from_rgb(theme.background.r, theme.background.g, theme.background.b)
                }),
            )
        } else {
            (egui::Color32::TRANSPARENT, None)
        };"""


def main():
    path = os.path.join(ROOT, REL)
    try:
        with open(path, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        print(f"FAIL {REL}: cannot read {path}: {exc}")
        sys.exit(1)
    crlf = raw.count(b"\r\n") > 0
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if text.count(OLD) != 1:
        print(f"FAIL {REL}: anchor found {text.count(OLD)}x")
        sys.exit(1)
    text = text.replace(OLD, NEW)
    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(path, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL {REL}: cannot write {path}: {exc}")
        sys.exit(1)
    print(f"ok   {REL} ({'CRLF' if crlf else 'LF'})")


if __name__ == "__main__":
    main()
