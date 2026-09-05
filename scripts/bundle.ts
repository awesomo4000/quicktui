const result = await Bun.build({
  entrypoints: ["js/smoke.ts"],
  target: "browser",
  format: "iife",
  minify: true,
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
});
if (!result.success) {
  for (const log of result.logs) console.error(log);
  process.exit(1);
}
const licenses = await Promise.all(
  ["react", "react-reconciler", "scheduler"].map(async (name) =>
    `${name}\n${await Bun.file(`vendor/js/node_modules/${name}/LICENSE`).text()}`,
  ),
);
await Bun.write("src/app.js", `/*!\n${licenses.join("\n")}\n*/\n${await result.outputs[0].text()}`);
