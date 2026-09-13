use par_term_emu_core_rust::pty_session::PtySession;
use std::{fs::OpenOptions, io::Write, sync::Arc, thread, time::Duration};

fn main() {
    let out = std::env::args().nth(1).expect("output directory");
    let cli = std::env::args().nth(2).expect("pi cli.js path");
    let refresh = std::env::args().nth(3);
    let mut pty = PtySession::new(145, 39, 1000);
    let raw = format!("{out}/conpty.raw");
    std::fs::write(&raw, b"").unwrap();
    pty.set_output_callback(Arc::new(move |data| {
        OpenOptions::new()
            .append(true)
            .open(&raw)
            .unwrap()
            .write_all(data)
            .unwrap();
    }));
    pty.set_env("PI_OFFLINE", "1");
    pty.set_env("TERM", "xterm-256color");
    let mut args = Vec::new();
    if let Some(ref module) = refresh {
        args.extend(["--import", module.as_str()]);
    }
    args.extend([
        cli.as_str(),
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "--no-context-files",
        "--no-session",
    ]);
    pty.spawn("node", &args).unwrap();
    thread::sleep(Duration::from_secs(3));
    pty.resize(79, 24).unwrap();
    thread::sleep(Duration::from_secs(12));
    std::fs::write(format!("{out}/core-before.txt"), pty.content()).unwrap();
    pty.write(b"hello kitty").unwrap();
    thread::sleep(Duration::from_secs(2));
    let text = pty.content();
    std::fs::write(format!("{out}/core-after.txt"), &text).unwrap();
    println!(
        "core contains input: {}, generation: {}",
        text.contains("hello kitty"),
        pty.update_generation()
    );
    pty.kill().unwrap();
}
