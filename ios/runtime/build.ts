import path from "node:path"
import { fileURLToPath } from "node:url"
import { cp, mkdir, readdir, readFile, writeFile } from "node:fs/promises"
const root = path.dirname(fileURLToPath(import.meta.url))
const engine = process.argv[2]
if (!engine) throw new Error("Usage: bun build.ts /path/to/pinned/opencode")
const pkg = path.resolve(engine, "packages/opencode")
const models = await fetch("https://models.dev/api.json")
if (!models.ok) throw new Error(`Model catalog: HTTP ${models.status}`)
await Bun.write(path.join(pkg, "ios-server.ts"), Bun.file(path.join(root, "server.ts")))
process.chdir(pkg)
const result = await Bun.build({
  entrypoints: ["ios-server.ts"], outdir: path.join(root, "dist"),
  target: "node", format: "esm", conditions: ["node"],
  naming: { entry: "server.mjs", asset: "[name]-[hash].[ext]" },
  external: ["jsonc-parser", "@silvia-odwyer/photon-node"],
  define: {
    OPENCODE_MODELS_DEV: await models.text(),
    OPENCODE_VERSION: JSON.stringify("1.19.4"),
    OPENCODE_CHANNEL: JSON.stringify("latest"),
  },
  plugins: [{ name: "ios-pipe-terminal", setup(build) {
    build.onResolve({ filter: /^@lydell\/node-pty$/ }, () => ({ path: path.join(root, "pty.ts") }))
    build.onResolve({ filter: /photon_rs_bg\.wasm$/ }, () => ({ path: "photon-wasm-path", namespace: "ios-assets" }))
    build.onLoad({ filter: /.*/, namespace: "ios-assets" }, () => ({ contents: 'export default "./node_modules/@silvia-odwyer/photon-node/photon_rs_bg.wasm"', loader: "js" }))
  }}],
})
if (!result.success) throw new AggregateError(result.logs, "iOS engine bundle failed")
for (const name of ["jsonc-parser", "@silvia-odwyer/photon-node"]) {
  const destination = path.join(root, "dist/node_modules", name)
  await mkdir(path.dirname(destination), { recursive: true })
  await cp(path.join(engine, "packages/core/node_modules", name), destination, { recursive: true, dereference: true })
}
console.log(result.outputs.map(x => `${x.path}: ${x.size}`).join("\n"))
const licenses = path.join(root, "dist/Licenses")
await mkdir(licenses, { recursive: true })
await cp(path.join(engine, "LICENSE"), path.join(licenses, "OpenCode-LICENSE"))
const dependencies = []
async function collect(folder: string) {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.isSymbolicLink()) continue
    const pkg = path.join(folder, entry.name)
    if (entry.name.startsWith("@")) { await collect(pkg); continue }
    try {
      const manifest = JSON.parse(await readFile(path.join(pkg, "package.json"), "utf8"))
      dependencies.push({ name: manifest.name, version: manifest.version, license: manifest.license })
      const target = path.join(licenses, `${manifest.name.replaceAll("/", "__")}@${manifest.version}`)
      for (const file of await readdir(pkg)) {
        if (!/^(licen[sc]e|notice|copying)(\.|$)/i.test(file)) continue
        await mkdir(target, { recursive: true })
        await cp(path.join(pkg, file), path.join(target, file), { recursive: true })
      }
    } catch { /* Bun's dependency cache also contains non-package folders. */ }
  }
}
for (const entry of await readdir(path.join(engine, "node_modules/.bun"), { withFileTypes: true })) {
  if (!entry.isDirectory()) continue
  try { await collect(path.join(engine, "node_modules/.bun", entry.name, "node_modules")) } catch { }
}
await writeFile(path.join(licenses, "dependency-inventory.json"), JSON.stringify(dependencies, null, 2))
