//! Stamp the IME composition into the cell buffer so it renders as terminal text.
//!
//! The egui overlay drew the composing string as a separate layer, which meant the overlay
//! needed its own font family, its own baseline correction and its own scale arithmetic to look
//! like the text it becomes — and every DPI or font change reopened the gap (the way Windows
//! Terminal, kitty and ghostty render preedit is to write it into the grid and let the normal
//! cell pipeline draw it; that is what this module does). A glyph stamped here is drawn by the
//! same cell renderer as the committed text around it, so font, size, colors, wide-cell spacing
//! and the underline all come out right by construction. The stamp is per-frame: nothing is
//! written back into the render cache, exactly like the URL/search overlays in `overlay_cells`.

use std::sync::Arc;

use par_term_emu_core_rust::unicode_width_config::{WidthConfig, char_width};

use crate::config::Cell;

/// Characters a renderer is required to draw as nothing.
///
/// The Korean IME reports U+3164 HANGUL FILLER while a syllable is still incomplete (and the
/// conjoining fillers U+115F/U+1160 exist for the same purpose); they are
/// `Default_Ignorable_Code_Point`, so drawing them is wrong to begin with — and a face that
/// lacks them turns into a replacement box, which is how a filler once read as "a small
/// rectangle above the cursor".
fn is_ignorable(c: char) -> bool {
    matches!(c, '\u{115F}' | '\u{1160}' | '\u{3164}' | '\u{FFA0}')
}

/// Write `text` into `cells` (row-major, `cols` wide) starting at `cursor` (col, row), the same
/// viewport coordinates the geometric cursor consumes.
///
/// Each glyph inherits the colors/weight of the cell it replaces and is underlined; a
/// double-width glyph (Hangul syllables) gets a `wide_char_spacer` after it — the exact layout
/// the emulator core produces for committed Hangul, so the composition is indistinguishable
/// from the text it will become. Overflow past the right edge wraps to the next row, like
/// Windows Terminal; past the last viewport row the stamp simply stops.
pub(super) fn stamp_preedit_cells(
    cells: &mut [Cell],
    cols: usize,
    cursor: (usize, usize),
    text: &str,
) {
    let rows = if cols > 0 { cells.len() / cols } else { 0 };
    if cols == 0 || rows == 0 {
        return;
    }
    let (mut col, mut row) = cursor;
    if row >= rows {
        return;
    }
    for ch in text.chars().filter(|c| !is_ignorable(*c)) {
        let width = char_width(ch, &WidthConfig::default()).max(1).min(cols);
        if col + width > cols {
            row += 1;
            col = 0;
            if row >= rows {
                break;
            }
        }
        let idx = row * cols + col;
        if idx >= cells.len() {
            break;
        }
        // Copy the inherited style out before overwriting the cell (borrow ends at the block).
        let (fg, bg, bold, italic) = {
            let base = &cells[idx];
            (base.fg_color, base.bg_color, base.bold, base.italic)
        };
        cells[idx] = Cell {
            grapheme: ch.to_string(),
            fg_color: fg,
            bg_color: bg,
            bold,
            italic,
            underline: true,
            strikethrough: false,
            hyperlink_id: None,
            wide_char: width == 2,
            wide_char_spacer: false,
        };
        if width == 2 {
            // The core pairs a wide glyph with a spacer cell (see the grid tests); without it
            // the cell behind the glyph's second half would still paint its old contents.
            let spacer_idx = idx + 1;
            if col + 1 < cols && spacer_idx < cells.len() {
                let spacer_bg = cells[spacer_idx].bg_color;
                cells[spacer_idx] = Cell {
                    grapheme: String::new(),
                    fg_color: fg,
                    bg_color: spacer_bg,
                    bold: false,
                    italic: false,
                    underline: true,
                    strikethrough: false,
                    hyperlink_id: None,
                    wide_char: false,
                    wide_char_spacer: true,
                };
            }
            col += 2;
        } else {
            col += 1;
        }
    }
}

/// Clone-stamp an `Arc`'d cell buffer for one frame.
///
/// Returns `None` when there is nothing to draw or nowhere to draw it; the caller keeps the
/// original buffer in that case. The clone is composition-scoped, so the common (not composing)
/// path never copies the grid.
pub(super) fn stamp_arc_cells(
    cells: &Arc<Vec<Cell>>,
    cols: usize,
    cursor: Option<(usize, usize)>,
    text: &str,
) -> Option<Arc<Vec<Cell>>> {
    let cursor = cursor?;
    if text.is_empty() {
        return None;
    }
    let mut owned = (**cells).clone();
    stamp_preedit_cells(&mut owned, cols, cursor, text);
    Some(Arc::new(owned))
}
