"""Revise sync handling to transaction-atomicity (newline-preserving).

Evidence (PI_TUI_WRITE_LOG, 7.9MB/1881 pairs): pi wraps every update
(text + footer) in ONE pair, so the tear is terminal-side. Two defects:

1. Entry path applies split-transaction heads immediately (flag is false
   at entry, so a read ending mid-transaction parses at once).
2. Naive flush applies a trailing partial next-update packed by ConPTY
   as [end of N][partial N+1] in one read.

Fix: buffer from any unclosed begin (entry split); on flush, apply
through the pending begin and retain the partial. New begins supersede
stale explicit disables, so per-update begin/end pairs (pi-style) keep
working across reads.
"""

import sys
from pathlib import Path

MOD = Path(
    "C:/Users/jky72/par-term/build/par-term"
    "/vendor/par-term-emu-core-rust/src/terminal/mod.rs"
)
TESTS = Path(
    "C:/Users/jky72/par-term/build/par-term"
    "/par-term-terminal/tests/sync_updates_regression.rs"
)

OLD_FLUSH = """    /// Flush the synchronized update buffer.
    ///
    /// Applies only complete transactions: the buffer is cut after its last
    /// end marker and any trailing partial update is retained for the next
    /// read. Applying the trailing partial immediately would expose a torn
    /// intermediate grid (e.g. scrolled text with the footer not yet redrawn)
    /// on the next render, which is exactly the judder seen with fast
    /// streaming apps whose updates ConPTY splits across reads.
    pub fn flush_synchronized_updates(&mut self) {
        if self.sync_state.update_buffer.is_empty() {
            return;
        }
        let buffer = std::mem::take(&mut self.sync_state.update_buffer);
        debug::log(
            debug::DebugLevel::Debug,
            "SYNC_UPDATE",
            &format!("Flushing buffer ({} bytes)", buffer.len()),
        );
        // Process the buffered data without synchronized mode
        let saved_mode = self.sync_state.synchronized_updates;
        let explicitly_disabled = self.sync_state.sync_update_explicitly_disabled;
        self.sync_state.sync_update_explicitly_disabled = false;
        self.sync_state.synchronized_updates = false;
        // Keep a trailing partial update buffered instead of applying it.
        // After an explicit DECRST the application ended the transaction, so
        // anything trailing the marker is ordinary output: apply it.
        const SYNC_END: &[u8] = b"\\x1b[?2026l";
        let cut = if explicitly_disabled {
            buffer.len()
        } else {
            find_last_subslice(&buffer, SYNC_END)
                .map(|pos| pos + SYNC_END.len())
                .unwrap_or(0)
        };
        let (apply, retain) = buffer.split_at(cut);
        if !apply.is_empty() {
            self.process(apply);
        }

        if retain.is_empty() {
            // Restore only if it was originally enabled and not explicitly disabled
            if saved_mode
                && !self.sync_state.sync_update_explicitly_disabled
                && !self.sync_state.synchronized_updates
            {
                self.sync_state.synchronized_updates = true;
            }
        } else {
            self.sync_state.update_buffer.extend_from_slice(retain);
            self.sync_state.synchronized_updates = true;
        }
    }
"""

NEW_FLUSH = """    /// Flush the synchronized update buffer.
    ///
    /// Applies only complete transactions: a trailing partial update (a
    /// begin marker with no later end marker) stays buffered for the next
    /// read, while ordinary output past the last transaction applies right
    /// away. Applying the trailing partial immediately would expose a torn
    /// intermediate grid (e.g. scrolled text with the footer not yet
    /// redrawn) on the next render, which is exactly the judder seen with
    /// fast streaming apps whose updates ConPTY splits across reads.
    pub fn flush_synchronized_updates(&mut self) {
        if self.sync_state.update_buffer.is_empty() {
            return;
        }
        let buffer = std::mem::take(&mut self.sync_state.update_buffer);
        debug::log(
            debug::DebugLevel::Debug,
            "SYNC_UPDATE",
            &format!("Flushing buffer ({} bytes)", buffer.len()),
        );
        // Process the buffered data without synchronized mode
        let saved_mode = self.sync_state.synchronized_updates;
        self.sync_state.sync_update_explicitly_disabled = false;
        self.sync_state.synchronized_updates = false;
        const SYNC_BEGIN: &[u8] = b"\\x1b[?2026h";
        const SYNC_END: &[u8] = b"\\x1b[?2026l";
        let search_from = find_last_subslice(&buffer, SYNC_END)
            .map(|pos| pos + SYNC_END.len())
            .unwrap_or(0);
        let pending_start = buffer[search_from..]
            .windows(SYNC_BEGIN.len())
            .position(|window| window == SYNC_BEGIN)
            .map(|pos| search_from + pos)
            .unwrap_or(buffer.len());
        let (apply, retain) = buffer.split_at(pending_start);
        if !apply.is_empty() {
            self.process(apply);
        }

        if retain.is_empty() {
            // Restore only if it was originally enabled and not explicitly disabled
            if saved_mode
                && !self.sync_state.sync_update_explicitly_disabled
                && !self.sync_state.synchronized_updates
            {
                self.sync_state.synchronized_updates = true;
            }
        } else {
            // A new transaction supersedes any earlier explicit disable.
            self.sync_state.update_buffer.extend_from_slice(retain);
            self.sync_state.synchronized_updates = true;
            self.sync_state.sync_update_explicitly_disabled = false;
        }
    }
"""

OLD_ENTRY = """            return false;
        }

        if self.tmux.tmux_parser.is_control_mode() || self.tmux.tmux_parser.is_auto_detect() {
"""

NEW_ENTRY = """            return false;
        }

        // A transaction beginning without a later end marker in this read
        // continues in a later read (ConPTY splits updates arbitrarily).
        // Buffer from the pending begin so a torn head is never applied on
        // its own; complete transactions and ordinary output still parse
        // immediately below. A new begin always supersedes any earlier
        // explicit disable (per-update begin/end pairs keep working).
        let mut immediate = data;
        {
            const SYNC_BEGIN: &[u8] = b"\\x1b[?2026h";
            const SYNC_END: &[u8] = b"\\x1b[?2026l";
            let search_from = find_last_subslice(data, SYNC_END)
                .map(|pos| pos + SYNC_END.len())
                .unwrap_or(0);
            if let Some(pending) = data[search_from..]
                .windows(SYNC_BEGIN.len())
                .position(|window| window == SYNC_BEGIN)
                .map(|pos| search_from + pos)
            {
                self.sync_state.update_buffer.extend_from_slice(&data[pending..]);
                self.sync_state.synchronized_updates = true;
                self.sync_state.sync_update_explicitly_disabled = false;
                if pending == 0 {
                    return false;
                }
                immediate = &data[..pending];
            }
        }

        if self.tmux.tmux_parser.is_control_mode() || self.tmux.tmux_parser.is_auto_detect() {
"""

OLD_PARSE_TMUX = "let notifications = self.tmux.tmux_parser.parse(data);"
NEW_PARSE_TMUX = "let notifications = self.tmux.tmux_parser.parse(immediate);"

OLD_PARSE_STD = """        } else {
            // Process as standard terminal output (with Kitty APC pre-filtering)
            self.filter_apc_and_advance(data);
        }"""
NEW_PARSE_STD = """        } else {
            // Process as standard terminal output (with Kitty APC pre-filtering)
            self.filter_apc_and_advance(immediate);
        }"""

OLD_TEST_TAIL = """        assert!(term.content().contains("hello kitty"), "split {split}");
    }
}"""

NEW_TESTS = """        assert!(term.content().contains("hello kitty"), "split {split}");
    }
}

#[test]
fn split_transaction_head_is_not_applied_until_complete() {
    let mut term = Terminal::new(120, 24);
    // A read ending mid-transaction must not become visible on its own.
    term.process(b"\\x1b[?2026hTORN-HEAD-");
    assert!(
        !term.content().contains("TORN-HEAD-"),
        "partial transaction head leaked"
    );
    assert!(term.synchronized_updates());
    // The completing read applies the whole transaction atomically.
    term.process(b"REST\\x1b[?2026l");
    assert!(!term.synchronized_updates());
    assert!(term.content().contains("TORN-HEAD-REST"));
}

#[test]
fn complete_pair_then_partial_next_update_in_one_read() {
    let mut term = Terminal::new(120, 24);
    // ConPTY packs [end of N][partial N+1] into one read: N applies,
    // the partial stays hidden until its own end marker arrives.
    term.process(b"\\x1b[?2026hFIRST\\x1b[?2026l\\x1b[?2026hSECO");
    assert!(term.content().contains("FIRST"));
    assert!(!term.content().contains("SECO"));
    term.process(b"ND\\x1b[?2026l");
    assert!(term.content().contains("SECOND"));
}

#[test]
fn per_update_pairs_do_not_stick_disabled() {
    // pi-style: every update is its own begin/end pair, so each end fires
    // DECRST. A split in a later update must still buffer.
    let mut term = Terminal::new(120, 24);
    term.process(b"\\x1b[?2026hONE\\x1b[?2026l");
    assert!(term.content().contains("ONE"));
    term.process(b"\\x1b[?2026hTW");
    assert!(!term.content().contains("TW"));
    term.process(b"O\\x1b[?2026l");
    assert!(term.content().contains("TWO"));
}"""


def patch_file(path, pairs):
    """Apply (old, new) replacements with uniqueness checks. Returns text meta."""
    try:
        raw = path.read_bytes()
    except OSError as exc:
        print(f"FAIL: cannot read {path}: {exc}")
        return None
    crlf = raw.count(b"\\r\\n")
    lf = raw.count(b"\\n") - crlf
    newline = "\\r\\n" if crlf >= lf else "\\n"
    try:
        text = raw.decode("utf-8").replace("\\r\\n", "\\n")
    except UnicodeDecodeError as exc:
        print(f"FAIL: not valid UTF-8: {exc}")
        return None
    for name, old, new in pairs:
        occurrences = text.count(old)
        if occurrences != 1:
            print(f"FAIL: {path.name} :: {name} count={occurrences}")
            return None
        text = text.replace(old, new)
    try:
        path.write_bytes(text.replace("\\n", newline).encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {path}: {exc}")
        return None
    style = "CRLF" if newline == "\\r\\n" else "LF"
    print(f"ok {path.name} ({style})")
    return True


def main() -> int:
    ok = patch_file(
        MOD,
        [
            ("flush", OLD_FLUSH, NEW_FLUSH),
            ("entry", OLD_ENTRY, NEW_ENTRY),
            ("parse-tmux", OLD_PARSE_TMUX, NEW_PARSE_TMUX),
            ("parse-std", OLD_PARSE_STD, NEW_PARSE_STD),
        ],
    )
    if not ok:
        return 1
    if not patch_file(TESTS, [("tests", OLD_TEST_TAIL, NEW_TESTS)]):
        return 1
    return 0


sys.exit(main())
