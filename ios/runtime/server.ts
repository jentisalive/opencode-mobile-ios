import { Server } from "./src/server/server"
import "./src/server/init-projectors"
import { DatabaseSync } from "node:sqlite"
import { AppRuntime } from "./src/effect/app-runtime"
import { Effect } from "effect"

// Fail explicitly if the bundled runtime lacks the ordered-row backport.
// Object.values(row) would silently corrupt joins with duplicate column names.
const probe = new DatabaseSync(":memory:")
const statement = probe.prepare("SELECT 1 AS duplicate, 2 AS duplicate")
statement.setReturnArrays(true)
if (JSON.stringify(statement.get()) !== "[1,2]") throw new Error("SQLite ordered-row runtime check failed")
probe.close()

const port = Number(process.env.OPENCODE_PORT || 4096)
if (!process.env.OPENCODE_SERVER_PASSWORD) throw new Error("Local server password is required")
if (process.env.OPENCODE_WORKSPACE) process.chdir(process.env.OPENCODE_WORKSPACE)
// The CLI's serve command owns AppRuntime for the lifetime of the process.
// Keep its shared scopes alive so async prompt fibers survive the HTTP response.
await AppRuntime.runPromise(Effect.void)
const server = await Server.listen({ hostname: "127.0.0.1", port, mdns: false })
console.log(`OpenCode iOS listening on ${server.url}`)
const parent = process.ppid
setInterval(() => {
  if (process.ppid !== parent) process.exit(0)
}, 2000).unref()
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.once(signal, async () => { await server.stop(true); await AppRuntime.dispose(); process.exit(0) })
}
