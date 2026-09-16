//! Font bytes for egui's overlay font stack.
//!
//! egui draws the terminal's overlays (the IME preedit at the cursor, dialogs, the settings
//! window) from *its own* font stack, not from the terminal's renderer. egui ships Latin and
//! emoji faces only, so CJK text there has no glyph and lands on epaint's replacement character:
//! a Hangul syllable being composed painted as `◻` while the syllable it became drew correctly
//! from the grid font. That is the entire reason Korean composition looked broken while committed
//! Korean looked fine.
//!
//! The terminal's own configured font is the best candidate for that stack — it is the face the
//! user already chose, so a composition and the text it turns into look identical — but only if it
//! actually contains the codepoints a Korean IME composes. Otherwise the caller leaves the choice
//! to the platform candidates in `par_term_settings_ui::nerd_font`.

use fontdb::{Database, Family, Query};

use crate::config::Config;

/// Codepoints a Korean composition passes through.
///
/// A syllable alone is not enough: an IME that has only received a consonant commits compatibility
/// jamo (ㄱ, ㅏ) rather than a precomposed syllable, so both blocks have to be covered.
const KOREAN_PROBE: &[char] = &['한', '글', 'ㄱ', 'ㅏ'];

/// Font file bytes for `config`'s terminal font, when that font covers Korean.
///
/// Returns `None` when the family is missing, unreadable, or has no Hangul coverage — the caller
/// then falls back to the platform faces.
pub fn cjk_fallback_bytes(config: &Config) -> Option<Vec<u8>> {
    let mut db = Database::new();
    db.load_system_fonts();

    let mut families: Vec<&str> = vec![config.font_family.as_str()];
    if let Some(bold) = config.font_family_bold.as_deref()
        && !families.contains(&bold)
    {
        families.push(bold);
    }

    for family in families {
        let Some(bytes) = load_family_bytes(&mut db, family) else {
            log::debug!("egui CJK fallback: font family '{family}' not found");
            continue;
        };
        if covers(&bytes, KOREAN_PROBE) {
            log::info!(
                "egui CJK fallback: '{family}' covers Korean; overlays will use the terminal face"
            );
            return Some(bytes);
        }
        log::info!("egui CJK fallback: '{family}' has no Korean coverage");
    }

    log::info!("egui CJK fallback: no configured family covers Korean; using a platform face");
    None
}

/// Read a family's font bytes out of the system font database.
fn load_family_bytes(db: &mut Database, family: &str) -> Option<Vec<u8>> {
    let query = Query {
        families: &[Family::Name(family)],
        weight: fontdb::Weight::NORMAL,
        style: fontdb::Style::Normal,
        ..Query::default()
    };
    let id = db.query(&query)?;
    // SAFETY: `make_shared_face_data` may hand back a memory map of the font file rather than an
    // owned buffer, so the bytes are only valid while that file is not modified or truncated by
    // another process. A valid `id` from `query()` is necessary but is *not* the invariant that
    // makes this call sound. The mapping is copied into an owned `Vec` on the next line and the
    // shared handle is dropped immediately after, which keeps the exposure window to a single
    // synchronous copy. Same reasoning as `crate::font_metrics`.
    let (data, _) = unsafe { db.make_shared_face_data(id) }?;
    Some(data.as_ref().as_ref().to_vec())
}

/// Whether every probed codepoint has a glyph in `bytes`.
fn covers(bytes: &[u8], chars: &[char]) -> bool {
    let Some(font) = swash::FontRef::from_index(bytes, 0) else {
        return false;
    };
    let charmap = font.charmap();
    chars.iter().all(|c| charmap.map(*c) != 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The configured font is used only when it really has Hangul.
    #[test]
    fn coverage_probe_rejects_fonts_without_hangul() {
        // DejaVu Sans Mono is the embedded fallback: Latin, Greek, Cyrillic, Braille, no Hangul.
        const DEJAVU: &[u8] = include_bytes!("../fonts/DejaVuSansMono.ttf");
        assert!(!covers(DEJAVU, KOREAN_PROBE));
        assert!(covers(DEJAVU, &['A']));
    }
}
