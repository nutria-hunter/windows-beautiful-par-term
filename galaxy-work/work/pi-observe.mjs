// Observation shim injected into pi with `node --import`.
//   * records every byte pi receives on stdin (proof the keystrokes arrived)
//   * records the resize records ConPTY delivered to pi (proof of grid deliveries)
import fs from "node:fs";

const output = process.env.PI_OBSERVE_OUT;
const emit = (data) => {
  if (output) fs.appendFileSync(output, JSON.stringify(data) + "\n");
};

process.stdin.on("data", (data) =>
  emit({ event: "input", hex: Buffer.from(data).toString("hex") }),
);
process.stdout.on("resize", () =>
  emit({
    event: "resize",
    columns: process.stdout.columns,
    rows: process.stdout.rows,
  }),
);
setInterval(() => {
  const nativeSize = [];
  const error = process.stdout._handle?.getWindowSize(nativeSize);
  emit({
    event: "state",
    columns: process.stdout.columns,
    rows: process.stdout.rows,
    nativeSize,
    error,
  });
}, 5000).unref();
