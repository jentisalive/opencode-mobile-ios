// Pipe fallback: ordinary command execution works without pretending a PTY exists.
import { spawn as spawnProcess } from "node:child_process"
export function spawn(file: string, args: string[], opts: { cwd: string; env: NodeJS.ProcessEnv }) {
  const child = spawnProcess(file, args, { cwd: opts.cwd, env: opts.env, stdio: "pipe" })
  let result: { exitCode: number } | undefined
  let launchFailed = false
  const listeners = new Set<(event: { exitCode: number }) => void>()
  child.once("error", (error) => {
    launchFailed = true
    child.stderr.emit("data", Buffer.from(`Cannot start command: ${error.message}\n`))
  })
  child.stdin.on("error", () => { /* A closed command may reject pending input. */ })
  child.once("close", (code) => {
    result = { exitCode: launchFailed ? 127 : (code ?? 1) }
    for (const listener of listeners) listener(result)
    listeners.clear()
  })
  return {
    pid: child.pid,
    onData(listener: (data: string) => void) {
      const read = (data: Buffer) => listener(data.toString())
      child.stdout.on("data", read); child.stderr.on("data", read)
      return { dispose() { child.stdout.off("data", read); child.stderr.off("data", read) } }
    },
    onExit(listener: (event: { exitCode: number }) => void) {
      listeners.add(listener)
      if (result) queueMicrotask(() => { if (listeners.delete(listener)) listener(result!) })
      return { dispose() { listeners.delete(listener) } }
    },
    write(data: string) { child.stdin.write(data) },
    resize() { /* Pipes have no terminal dimensions. */ },
    kill(signal?: NodeJS.Signals) { child.kill(signal) },
  }
}
