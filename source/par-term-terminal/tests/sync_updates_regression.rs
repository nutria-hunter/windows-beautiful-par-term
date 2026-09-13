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
