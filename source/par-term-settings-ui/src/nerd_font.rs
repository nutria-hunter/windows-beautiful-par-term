//! Nerd Font integration for egui.
//!
//! Provides font configuration and curated icon presets for the profile icon picker.
//! Uses SymbolsNerdFontMono-Regular.ttf (Nerd Fonts v3.4.0).

/// Embedded Nerd Font Symbols (Mono variant, ~2.5MB).
const NERD_FONT_BYTES: &[u8] = include_bytes!("../assets/fonts/SymbolsNerdFontMono-Regular.ttf");

/// Configure egui to use Nerd Font Symbols as a fallback font.
///
/// Call this once after creating each `egui::Context` (main window and settings window).
/// Adds the Nerd Font as the last fallback in the Proportional and Monospace families
/// so that standard Latin text still uses egui's default font, but Nerd Font codepoints render.
///
/// Also attempts to load a system font that covers the Braille Patterns Unicode block
/// (U+2800–U+28FF). These characters are used by CLI spinners such as Claude Code's thinking
/// indicator (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏). None of egui's default fonts nor SymbolsNerdFontMono cover
/// this block, so without this fallback they render as □.
///
/// Prefer [`configure_egui_fonts`] where a font is already known: this entry point can only use
/// the platform's CJK faces, not the terminal's configured font.
pub fn configure_nerd_font(ctx: &egui::Context) {
    configure_egui_fonts(ctx, None);
}

/// Font family reserved for the IME composition overlay.
///
/// egui's sanctioned mechanism for a vertical shift is `FontTweak::y_offset_factor`
/// ("Shift font's glyphs downwards by this fraction of the font size ... only a visual effect and
/// does not affect the text layout"). Applying it to the shared CJK faces would move the settings
/// UI and the tab bar with it, and registering a second copy of every face just for the tweak
/// would duplicate ~7 MB of font data per face - so the overlay takes its shift at draw time
/// instead (see `render_ime_preedit`), which has the same effect on the same pixels for nothing.
///
/// The family itself is worth having: it puts the terminal's own face *first* for every codepoint
/// (so a composition mixing Latin and Hangul stays in one face) and the platform CJK face after
/// it, which is what stops a codepoint the terminal font lacks from becoming epaint's replacement
/// box.
pub const IME_PREEDIT_FAMILY: &str = "ime_preedit";

/// Configure every fallback egui needs: Nerd Font icons, Braille, and CJK.
///
/// `cjk_fallback` is font file data supplied by the caller — normally the terminal's own configured
/// font (see `par_term::egui_font`), so a composed syllable is drawn in the same face as the text
/// it becomes. When it is `None`, or when the caller's font could not be used, a platform CJK face
/// is looked up instead.
///
/// This fallback is what makes Korean, Japanese and Chinese text render at all in egui: egui ships
/// Hack, Ubuntu-Light, NotoEmoji and an icon font, and *none* of them contains a single Hangul
/// codepoint. Without a CJK face every composed syllable paints as epaint's replacement glyph (◻)
/// — which is exactly how a broken IME looks, even though the committed text is fine.
pub fn configure_egui_fonts(ctx: &egui::Context, cjk_fallback: Option<Vec<u8>>) {
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        "nerd_font_symbols".to_owned(),
        egui::FontData::from_static(NERD_FONT_BYTES).into(),
    );

    // Add a system font that covers the Braille Patterns block (U+2800–U+28FF) so that
    // CLI spinner characters render correctly in the tab bar.
    if let Some(braille_bytes) = load_braille_font() {
        fonts.font_data.insert(
            "braille_fallback".to_owned(),
            egui::FontData::from_owned(braille_bytes).into(),
        );
        fonts
            .families
            .entry(egui::FontFamily::Proportional)
            .or_default()
            .push("braille_fallback".to_owned());
        fonts
            .families
            .entry(egui::FontFamily::Monospace)
            .or_default()
            .push("braille_fallback".to_owned());
    }

    // CJK faces, in this order: the caller's (normally the terminal's own configured font, so a
    // composed syllable looks like the text it becomes) and then a platform face as the mop-up.
    //
    // The terminal font is not always complete for composition. Measured on Maple Mono NF KR: the
    // precomposed syllables and the conjoining Jamo block are all present, but 41 compatibility
    // jamo are missing - the archaic vowels and U+3164 HANGUL FILLER, which is the kind of
    // codepoint an IME reports mid-composition - and both Extended Jamo blocks are absent entirely.
    // A missing glyph is painted as epaint's replacement box (◻), which is what "the composition is
    // a small rectangle above the cursor" turned out to be. Appending the platform face last means
    // it only answers for codepoints the terminal face does not have.
    let mut cjk_faces: Vec<(&str, Vec<u8>)> = Vec::new();
    if let Some(bytes) = cjk_fallback {
        cjk_faces.push(("terminal_cjk_fallback", bytes));
    }
    if let Some(bytes) = load_platform_cjk_font() {
        cjk_faces.push(("platform_cjk_fallback", bytes));
    }
    let mut ime_family: Vec<String> = Vec::new();
    for (name, bytes) in cjk_faces {
        fonts
            .font_data
            .insert(name.to_owned(), egui::FontData::from_owned(bytes).into());
        for family in [egui::FontFamily::Proportional, egui::FontFamily::Monospace] {
            fonts
                .families
                .entry(family)
                .or_default()
                .push(name.to_owned());
        }
        ime_family.push(name.to_owned());
    }

    // Add Nerd Font as last fallback for Proportional family
    fonts
        .families
        .entry(egui::FontFamily::Proportional)
        .or_default()
        .push("nerd_font_symbols".to_owned());
    // Also add as fallback for Monospace family (for tab bar, badges, etc.)
    fonts
        .families
        .entry(egui::FontFamily::Monospace)
        .or_default()
        .push("nerd_font_symbols".to_owned());

    // The IME overlay's own family: the terminal's face first (it is what the composition will
    // become), then the platform CJK face, then the symbol faces for anything odder.
    ime_family.push("nerd_font_symbols".to_owned());
    ime_family.push("braille_fallback".to_owned());
    fonts.families.insert(
        egui::FontFamily::Name(IME_PREEDIT_FAMILY.into()),
        ime_family,
    );
    ctx.set_fonts(fonts);
}

/// Load the first platform CJK font that exists.
///
/// Candidate order is deliberate: the Korean-capable faces come first on Windows, because the
/// scripts that need this fallback most (a Hangul IME writing into the preedit overlay) probe for
/// Hangul. A `.ttc` collection is used through its first face.
fn load_platform_cjk_font() -> Option<Vec<u8>> {
    for path in platform_cjk_font_candidates() {
        if let Ok(data) = std::fs::read(path) {
            return Some(data);
        }
    }
    None
}

/// Platform-specific paths for fonts that cover CJK.
fn platform_cjk_font_candidates() -> &'static [&'static str] {
    #[cfg(target_os = "windows")]
    {
        &[
            // Malgun Gothic — Korean, ships with Windows itself
            r"C:\Windows\Fonts\malgun.ttf",
            // Gulim — Korean, older but always present
            r"C:\Windows\Fonts\gulim.ttc",
            // Microsoft YaHei — Simplified Chinese
            r"C:\Windows\Fonts\msyh.ttc",
            // Meiryo — Japanese
            r"C:\Windows\Fonts\meiryo.ttc",
        ]
    }
    #[cfg(target_os = "macos")]
    {
        &[
            "/System/Library/Fonts/AppleSDGothicNeo.ttc",
            "/System/Library/Fonts/Hiragino Sans GB.ttc",
            "/System/Library/Fonts/PingFang.ttc",
        ]
    }
    #[cfg(target_os = "linux")]
    {
        &[
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
            "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc",
        ]
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        &[]
    }
}

/// Try to find a system font that covers the Braille Patterns Unicode block (U+2800–U+28FF).
///
/// Returns the font file bytes if a suitable font is found, or `None` if no font is available.
/// The candidates are platform-specific well-known fonts that include the full Braille block.
fn load_braille_font() -> Option<Vec<u8>> {
    for path in braille_font_candidates() {
        if let Ok(data) = std::fs::read(path) {
            return Some(data);
        }
    }
    None
}

/// Platform-specific candidate paths for fonts that cover the Braille Patterns block.
fn braille_font_candidates() -> &'static [&'static str] {
    #[cfg(target_os = "macos")]
    {
        &[
            // Apple Braille — ships with every macOS, covers all 256 Braille patterns
            "/System/Library/Fonts/Apple Braille.ttf",
            "/System/Library/Fonts/Apple Braille Outline 6 Dot.ttf",
        ]
    }
    #[cfg(target_os = "linux")]
    {
        &[
            // DejaVu Sans Mono — excellent Unicode coverage including full Braille block
            "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
            "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
            // GNU FreeFont — also covers Braille
            "/usr/share/fonts/truetype/freefont/FreeMono.ttf",
            "/usr/share/fonts/gnu-free/FreeMono.ttf",
        ]
    }
    #[cfg(target_os = "windows")]
    {
        &[
            // Segoe UI Symbol covers Braille on modern Windows
            r"C:\Windows\Fonts\seguisym.ttf",
        ]
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        &[]
    }
}

/// Curated Nerd Font icon presets organized by category for the profile icon picker.
///
/// Each entry is (category_name, &[(icon_char, icon_label)]).
/// All codepoints verified against SymbolsNerdFontMono-Regular.ttf v3.4.0.
pub const NERD_FONT_PRESETS: &[(&str, &[(&str, &str)])] = &[
    (
        "Terminal",
        &[
            ("\u{e795}", "Terminal"),
            ("\u{ebca}", "Bash"),
            ("\u{ebc7}", "PowerShell"),
            ("\u{ebc8}", "tmux"),
            ("\u{ea85}", "Console"),
            ("\u{ebc6}", "Linux Term"),
            ("\u{ebc5}", "Debian Term"),
            ("\u{ebc4}", "Cmd"),
            ("\u{f120}", "Prompt"),
            ("\u{e84f}", "Oh My Zsh"),
            ("\u{f489}", "Octicons Term"),
        ],
    ),
    (
        "Dev & Tools",
        &[
            ("\u{f121}", "Code"),
            ("\u{f09b}", "GitHub"),
            ("\u{e7ba}", "React"),
            ("\u{e73c}", "Python"),
            ("\u{e7a8}", "Rust"),
            ("\u{e718}", "Node.js"),
            ("\u{e738}", "Java"),
            ("\u{e755}", "Swift"),
            ("\u{e81b}", "Kotlin"),
            ("\u{e826}", "Lua"),
            ("\u{e73d}", "PHP"),
            ("\u{e605}", "Ruby"),
            ("\u{e62b}", "Vim"),
            ("\u{e6ae}", "Neovim"),
            ("\u{f188}", "Bug"),
            ("\u{f0ad}", "Wrench"),
            ("\u{e74a}", "TypeScript"),
            ("\u{e724}", "Go"),
            ("\u{e61d}", "C"),
            ("\u{e646}", "C++"),
            ("\u{e753}", "Angular"),
            ("\u{e6a0}", "Vue.js"),
            ("\u{e697}", "Svelte"),
            ("\u{e736}", "HTML5"),
            ("\u{e7a6}", "CSS3"),
            ("\u{e739}", "Haskell"),
            ("\u{e737}", "Scala"),
        ],
    ),
    (
        "Files & Data",
        &[
            ("\u{ea7b}", "File"),
            ("\u{eae9}", "File Code"),
            ("\u{ea83}", "Folder"),
            ("\u{eaf7}", "Folder Open"),
            ("\u{f1c0}", "Database"),
            ("\u{eb4b}", "Save"),
            ("\u{f02d}", "Book"),
            ("\u{ea66}", "Tag"),
            ("\u{f1b2}", "Cube"),
            ("\u{f487}", "Package"),
            ("\u{f019}", "Download"),
            ("\u{f093}", "Upload"),
        ],
    ),
    (
        "Network & Cloud",
        &[
            ("\u{f0ac}", "Globe"),
            ("\u{f1eb}", "WiFi"),
            ("\u{ebaa}", "Cloud"),
            ("\u{f233}", "Server"),
            ("\u{ef09}", "Network"),
            ("\u{f0e8}", "Sitemap"),
            ("\u{eb2d}", "Plug"),
            ("\u{e8b1}", "SSH"),
            ("\u{e7ad}", "AWS"),
            ("\u{eac2}", "Cloud DL"),
            ("\u{eac3}", "Cloud UL"),
            ("\u{f27a}", "Message"),
        ],
    ),
    (
        "Security",
        &[
            ("\u{f023}", "Lock"),
            ("\u{eb74}", "Unlock"),
            ("\u{f132}", "Shield"),
            ("\u{ed25}", "Shield Check"),
            ("\u{eb11}", "Key"),
            ("\u{f49c}", "Oct Shield"),
            ("\u{ea70}", "Eye"),
            ("\u{eae7}", "Eye Closed"),
            ("\u{f06a}", "Warning"),
            ("\u{f05a}", "Info"),
            ("\u{edcf}", "User Shield"),
            ("\u{f12e}", "Puzzle"),
        ],
    ),
    (
        "Git & VCS",
        &[
            ("\u{e725}", "Branch"),
            ("\u{e727}", "Merge"),
            ("\u{e729}", "Commit"),
            ("\u{f09b}", "GitHub"),
            ("\u{e65c}", "GitLab"),
            ("\u{e702}", "Git"),
            ("\u{e65d}", "Gitignore"),
            ("\u{e5fb}", "Git Folder"),
            ("\u{ea64}", "Pull Request"),
            ("\u{e72a}", "Bitbucket"),
            ("\u{ea6d}", "Diff"),
        ],
    ),
    (
        "Weather & Nature",
        &[
            ("\u{f185}", "Sun"),
            ("\u{f186}", "Moon"),
            ("\u{f2dc}", "Snowflake"),
            ("\u{f0e9}", "Umbrella"),
            ("\u{f0e7}", "Lightning"),
            ("\u{f06c}", "Leaf"),
            ("\u{f1bb}", "Tree"),
            ("\u{f2c9}", "Thermometer"),
            ("\u{f1b0}", "Paw"),
            ("\u{e30d}", "Day Sunny"),
            ("\u{e308}", "Rainy"),
            ("\u{e31a}", "Night Clear"),
        ],
    ),
    (
        "Containers & Infra",
        &[
            ("\u{f308}", "Docker"),
            ("\u{e81d}", "Kubernetes"),
            ("\u{f1b3}", "Cubes"),
            ("\u{f4b7}", "Container"),
            ("\u{f4bc}", "CPU"),
            ("\u{f2db}", "Chip"),
            ("\u{efc5}", "Memory"),
            ("\u{f013}", "Gear"),
            ("\u{f085}", "Gears"),
            ("\u{f1de}", "Sliders"),
            ("\u{eb06}", "Home"),
            ("\u{f0e8}", "Sitemap"),
        ],
    ),
    (
        "OS & Platforms",
        &[
            ("\u{f179}", "Apple"),
            ("\u{f17a}", "Windows"),
            ("\u{f17c}", "Linux"),
            ("\u{f31a}", "Tux"),
            ("\u{e712}", "Linux Dev"),
            ("\u{e70f}", "Windows Dev"),
            ("\u{e7ad}", "AWS"),
            ("\u{e7e9}", "GitHub Actions"),
            ("\u{e71e}", "npm"),
            ("\u{e7fd}", "Homebrew"),
            ("\u{f31b}", "Ubuntu"),
            ("\u{f303}", "Arch"),
            ("\u{f315}", "Raspi"),
            ("\u{f30a}", "Fedora"),
            ("\u{f17b}", "Android"),
        ],
    ),
    (
        "Status & Alerts",
        &[
            ("\u{f05d}", "Check"),
            ("\u{f057}", "Times"),
            ("\u{f058}", "Check Circle"),
            ("\u{f056}", "Minus Circle"),
            ("\u{f059}", "Question Circle"),
            ("\u{f06a}", "Exclamation"),
            ("\u{f071}", "Warning"),
            ("\u{f0e7}", "Bolt"),
            ("\u{f0eb}", "Lightbulb"),
            ("\u{f135}", "Rocket"),
            ("\u{f140}", "Crosshairs"),
            ("\u{f06d}", "Fire"),
            ("\u{f0f3}", "Bell"),
            ("\u{f005}", "Star"),
            ("\u{eb05}", "Heart"),
            ("\u{ea74}", "Info"),
        ],
    ),
    (
        "UI Actions",
        &[
            ("\u{f002}", "Search"),
            ("\u{f044}", "Edit"),
            ("\u{f0c5}", "Copy"),
            ("\u{f0ea}", "Clipboard"),
            ("\u{f0c4}", "Cut"),
            ("\u{f1f8}", "Trash"),
            ("\u{f067}", "Plus"),
            ("\u{f00d}", "Close"),
            ("\u{f021}", "Refresh"),
            ("\u{f0b0}", "Filter"),
            ("\u{f03a}", "List"),
            ("\u{f0c1}", "Link"),
            ("\u{f08e}", "External Link"),
            ("\u{eb4b}", "Save"),
            ("\u{f00c}", "Apply"),
            ("\u{f05e}", "Ban/Cancel"),
        ],
    ),
    (
        "Navigation",
        &[
            ("\u{f062}", "Arrow Up"),
            ("\u{f063}", "Arrow Down"),
            ("\u{f060}", "Arrow Left"),
            ("\u{f061}", "Arrow Right"),
            ("\u{f106}", "Angle Up"),
            ("\u{f107}", "Angle Down"),
            ("\u{f104}", "Angle Left"),
            ("\u{f105}", "Angle Right"),
            ("\u{f0d8}", "Caret Up"),
            ("\u{f0d7}", "Caret Down"),
            ("\u{f176}", "Long Arrow Up"),
            ("\u{f175}", "Long Arrow Down"),
            ("\u{f112}", "Reply/Back"),
            ("\u{f148}", "Level Up"),
            ("\u{f149}", "Level Down"),
            ("\u{f01e}", "Rotate/Undo"),
        ],
    ),
    (
        "People & Misc",
        &[
            ("\u{f007}", "User"),
            ("\u{f0c0}", "Users"),
            ("\u{ea67}", "Person"),
            ("\u{ee0d}", "Robot"),
            ("\u{f11b}", "Gamepad"),
            ("\u{f001}", "Music"),
            ("\u{f030}", "Camera"),
            ("\u{f1fc}", "Paint"),
            ("\u{f040}", "Pencil"),
            ("\u{f02e}", "Bookmark"),
            ("\u{eb1c}", "Mail"),
            ("\u{f29f}", "Diamond"),
        ],
    ),
    (
        "Fun & Seasonal",
        &[
            ("\u{f091}", "Trophy"),
            ("\u{f521}", "Crown"),
            ("\u{f1fd}", "Birthday Cake"),
            ("\u{f06b}", "Gift"),
            ("\u{eefe}", "Ghost"),
            ("\u{ee15}", "Skull"),
            ("\u{eeed}", "Cat"),
            ("\u{eef7}", "Dog"),
            ("\u{eef8}", "Dragon"),
            ("\u{f0d0}", "Magic Wand"),
            ("\u{f1e2}", "Bomb"),
            ("\u{f0fc}", "Beer"),
            ("\u{f0f4}", "Coffee"),
            ("\u{ef8c}", "Pizza"),
            ("\u{f522}", "Dice"),
            ("\u{eb2b}", "Sparkle"),
        ],
    ),
];

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
        ctx.run_ui(Default::default(), |_| {});

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
    /// a single Hangul codepoint (measured with fontTools over Hack, Ubuntu-Light, NotoEmoji and
    /// emoji-icon-font), so a composing syllable painted as epaint's replacement glyph instead.
    /// Skipped on a machine with no CJK font installed, where there is nothing to fall back to.
    #[test]
    fn assembled_stack_covers_hangul_when_a_cjk_font_exists() {
        if load_platform_cjk_font().is_none() {
            eprintln!("skipping: no platform CJK font installed");
            return;
        }
        let ctx = egui::Context::default();
        configure_nerd_font(&ctx);
        ctx.run_ui(Default::default(), |_| {});

        let font = egui::FontId::monospace(14.0);
        assert!(
            ctx.fonts_mut(|fonts| fonts.has_glyphs(&font, "\u{d55c}\u{ae00}")),
            "Hangul must resolve to a face in the egui font stack"
        );
        // No Latin assertion here on purpose. `FontsView::has_glyphs` reports whether a character
        // resolves to a face *other than* the replacement-glyph face, and in this stack that face is
        // Hack, which is the first Monospace face - so every ordinary Latin letter reports `false`
        // (epaint documents this as a false negative). Hangul is a real signal precisely because it
        // resolves to the appended CJK face instead.
    }
}
