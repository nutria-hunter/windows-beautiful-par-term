use par_term_emu_core_rust::terminal::Terminal;

#[test]
fn conpty_sync_end_before_a_long_repaint_flushes_the_buffer() {
    let mut term = Terminal::new(120, 24);
    term.process(b"\x1b[?2026h");
    let payload = format!("\x1b[?2026lhello kitty{}", " ".repeat(80));
    term.process(payload.as_bytes());
    assert!(
        !term.synchronized_updates(),
        "end marker is not necessarily in the last 32 bytes"
    );
    assert!(term.content().contains("hello kitty"));
}

#[test]
fn split_sync_end_is_detected_at_every_chunk_boundary() {
    let end = b"\x1b[?2026l";
    for split in 0..=end.len() {
        let mut term = Terminal::new(120, 24);
        term.process(b"\x1b[?2026h");
        term.process(&end[..split]);
        let mut rest = end[split..].to_vec();
        rest.extend_from_slice(b"hello kitty");
        rest.extend_from_slice(&[b' '; 80]);
        term.process(&rest);
        assert!(!term.synchronized_updates(), "split {split}");
        assert!(term.content().contains("hello kitty"), "split {split}");
    }
}

#[test]
fn split_transaction_head_is_not_applied_until_complete() {
    let mut term = Terminal::new(120, 24);
    // A read ending mid-transaction must not become visible on its own.
    term.process(b"\x1b[?2026hTORN-HEAD-");
    assert!(
        !term.content().contains("TORN-HEAD-"),
        "partial transaction head leaked"
    );
    assert!(term.synchronized_updates());
    // The completing read applies the whole transaction atomically.
    term.process(b"REST\x1b[?2026l");
    assert!(!term.synchronized_updates());
    assert!(term.content().contains("TORN-HEAD-REST"));
}

#[test]
fn complete_pair_then_partial_next_update_in_one_read() {
    let mut term = Terminal::new(120, 24);
    // ConPTY packs [end of N][partial N+1] into one read: N applies,
    // the partial stays hidden until its own end marker arrives.
    term.process(b"\x1b[?2026hFIRST\x1b[?2026l\x1b[?2026hSECO");
    assert!(term.content().contains("FIRST"));
    assert!(!term.content().contains("SECO"));
    term.process(b"ND\x1b[?2026l");
    assert!(term.content().contains("SECOND"));
}

#[test]
fn per_update_pairs_do_not_stick_disabled() {
    // pi-style: every update is its own begin/end pair, so each end fires
    // DECRST. A split in a later update must still buffer.
    let mut term = Terminal::new(120, 24);
    term.process(b"\x1b[?2026hONE\x1b[?2026l");
    assert!(term.content().contains("ONE"));
    term.process(b"\x1b[?2026hTW");
    assert!(!term.content().contains("TW"));
    term.process(b"O\x1b[?2026l");
    assert!(term.content().contains("TWO"));
}
