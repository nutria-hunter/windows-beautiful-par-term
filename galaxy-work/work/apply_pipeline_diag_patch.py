"""Surface why a custom-shader pipeline never arrives, instead of drawing nothing in silence.

Read from the source: `create_render_pipeline` returns `RenderPipeline`, not a `Result`, so a wgpu
validation failure *panics* - and it panics on the `custom-shader-pipeline` worker thread. The only
thing the main thread noticed was a closed channel, and `poll_pipeline` matched `Ok(pipeline)` only,
so the failure produced no log line and no background, forever. This patch catches the panic, sends
its message back, and reports both that and a closed channel.

Kept as a script because these files are checked out CRLF.
"""

import os
import sys

ROOT = (
    r"C:\Users\jky72\par-term\build\par-term\par-term-render\src\custom_shader_renderer"
)
MOD = os.path.join(ROOT, "mod.rs")

EDITS = [
    # 1) the receiver now carries a Result, so a failure has somewhere to live
    (
        """    /// Receives the finished pipeline from that worker thread.
    pub(crate) pipeline_rx: Option<std::sync::mpsc::Receiver<RenderPipeline>>,""",
        """    /// Receives the finished pipeline - or the message explaining why there is none - from that
    /// worker thread. wgpu reports a rejected pipeline by panicking, so a plain `RenderPipeline`
    /// channel could only ever say "closed", which is why a failed shader used to render nothing
    /// with nothing in the log.
    pub(crate) pipeline_rx: Option<std::sync::mpsc::Receiver<Result<RenderPipeline, String>>>,""",
    ),
    # 2) catch the panic on the worker thread and forward its message
    (
        """                .spawn(move || {
                    let pipeline = create_render_pipeline(
                        &device,
                        &shader_module,
                        &bind_group_layout,
                        surface_format,
                        Some(pipeline_label),
                    );
                    // A closed window drops the receiver first; that is not an error.
                    let _ = pipeline_tx.send(pipeline);
                })""",
        """                .spawn(move || {
                    // A rejected pipeline panics inside wgpu (the message names the naga/wgpu error).
                    // Catching it is what turns "no background, no log" into a readable reason.
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        create_render_pipeline(
                            &device,
                            &shader_module,
                            &bind_group_layout,
                            surface_format,
                            Some(pipeline_label),
                        )
                    }))
                    .map_err(|payload| {
                        payload
                            .downcast_ref::<String>()
                            .cloned()
                            .or_else(|| payload.downcast_ref::<&str>().map(|s| (*s).to_string()))
                            .unwrap_or_else(|| {
                                "pipeline thread panicked with a non-string payload".to_owned()
                            })
                    });
                    // A closed window drops the receiver first; that is not an error.
                    let _ = pipeline_tx.send(result);
                })""",
    ),
    # 3) report every way the pipeline can fail to arrive
    (
        """        if let Ok(pipeline) = rx.try_recv() {
            log::info!("[SHADER] custom shader pipeline compiled in background; shader is live");
            self.pipeline = Some(pipeline);
            self.pipeline_rx = None;
            return true;
        }
        false
    }""",
        """        match rx.try_recv() {
            Ok(Ok(pipeline)) => {
                log::info!("[SHADER] custom shader pipeline compiled in background; shader is live");
                self.pipeline = Some(pipeline);
                self.pipeline_rx = None;
                true
            }
            Ok(Err(message)) => {
                // The transpiler accepted the shader but the driver rejected the pipeline. Nothing
                // will be drawn until the shader is fixed, so this must never be silent again.
                log::error!(
                    "[SHADER] pipeline creation failed; no background will be drawn: {message}"
                );
                self.pipeline_rx = None;
                false
            }
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                log::error!(
                    "[SHADER] pipeline thread died without reporting; no background will be drawn"
                );
                self.pipeline_rx = None;
                false
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => false,
        }
    }""",
    ),
]


def main():
    try:
        with open(MOD, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        print(f"FAIL: cannot read {MOD}: {exc}")
        sys.exit(1)

    crlf = raw.count(b"\r\n") > 0
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for index, (anchor, replacement) in enumerate(EDITS, start=1):
        if text.count(anchor) != 1:
            print(f"FAIL: edit {index}: anchor found {text.count(anchor)}x")
            sys.exit(1)
        text = text.replace(anchor, replacement)

    out = text.replace("\n", "\r\n") if crlf else text
    try:
        with open(MOD, "wb") as handle:
            handle.write(out.encode("utf-8"))
    except OSError as exc:
        print(f"FAIL: cannot write {MOD}: {exc}")
        sys.exit(1)
    print(f"ok: applied {len(EDITS)} edits to mod.rs ({'CRLF' if crlf else 'LF'})")


if __name__ == "__main__":
    main()
