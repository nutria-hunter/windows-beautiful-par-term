"""Apply sync-flush transaction-cut patch (newline-preserving).

Background (evidence: PI_TUI_WRITE_LOG byte log, 7.9MB/1881 pairs):
pi wraps every update (text + footer) in one ESC[?2026h...l pair, so the
tear is NOT app-side. The vendor core's flush_synchronized_updates applies
the WHOLE buffer including a trailing partial next-update whenever ConPTY
packs [end of N][partial N+1] into one read. The next 60fps present then
shows scrolled text with the footer not yet redrawn = footer judder.

Fix: cut the buffer after its LAST end marker, apply only complete
transactions, retain the trailing partial buffered (stay in sync mode).
"""

import sys
from pathlib import Path

PATH = Path(
    "C:/Users/jky72/par-term/build/par-term"
    "/vendor/par-term-emu-core-rust/src/terminal/mod.rs"
)

OLD_HELPER = """pub(crate) fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() || haystack.len() < needle.len() {
        return false;
    }
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}
"""

NEW_HELPER = """pub(crate) fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() || haystack.len() < needle.len() {
        return false;
    }
    haystack
        .windows(needle.len())
        .any(|window| window == needle)
}

/// Helper function to find the last occurrence of a subsequence.
/// Used to cut a synchronized-update buffer after its last complete
/// transaction so a trailing partial update stays buffered.
#[inline]
pub(crate) fn find_last_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return None;
    }
    let mut last = None;
    let mut index = 0;
    while index + needle.len() <= haystack.len() {
        if haystack[index..index + needle.len()] == *needle {
            last = Some(index);
            index += needle.len();
        } else {
            index += 1;
        }
    }
    last
}
"""

OLD_FLUSH = """    /// Flush the synchronized update buffer
    pub fn flush_synchronized_updates(&mut self) {
        if !self.sync_state.update_buffer.is_empty() {
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
            self.process(&buffer);

            // Restore only if it was originally enabled and not explicitly disabled
            if saved_mode
                && !self.sync_state.sync_update_explicitly_disabled
                && !self.sync_state.synchronized_updates
            {
                self.sync_state.synchronized_updates = true;
            }
        }
    }
"""

NEW_FLUSH = """    /// Flush the synchronized update buffer.
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


def main() -> int:
    try:
        raw = PATH.read_bytes()
    except OSError as exc:
        print(f"FAIL: cannot read {PATH}: {exc}")
        return 1
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n") - crlf
    newline = "\r\n" if crlf >= lf else "\n"
    try:
        text = raw.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as exc:
        print(f"FAIL: not valid UTF-8: {exc}")
        return 1
    for name, old, new in (
        ("helper", OLD_HELPER, NEW_HELPER),
        ("flush", OLD_FLUSH, NEW_FLUSH),
    ):
        occurrences = text.count(old)
        if occurrences != 1:
            print(f"FAIL: {name} block count={occurrences}")
            return 1
        text = text.replace(old, new)
    try:
        PATH.write_bytes(text.replace("\n", newline).encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {PATH}: {exc}")
        return 1
    style = "CRLF" if newline == "\r\n" else "LF"
    print(f"ok terminal/mod.rs ({style})")
    return 0


sys.exit(main())
