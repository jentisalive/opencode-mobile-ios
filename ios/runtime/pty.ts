// Pipe fallback: ordinary command execution works without pretending a PTY exists.
import { spawn as spawnProcess } from "node:child_process"
export function spawn(file: string, args: string[], opts: { cwd: string; env: NodeJS.ProcessEnv }) {
  const child = spawnProcess(file, args, { cwd: opts.cwd, env: opts.env, stdio: "pipe" })
  return {
    pid: child.pid,
    onData(listener: (data: string) => void) {
      const read = (data: Buffer) => listener(data.toString())
      child.stdout.on("data", read); child.stderr.on("data", read)
      return { dispose() { child.stdout.off("data", read); child.stderr.off("data", read) } }
    },
    onExit(listener: (event: { exitCode: number }) => void) {
      const exit = (code: number | null) => listener({ exitCode: code ?? 1 })
      child.on("exit", exit)
      return { dispose() { child.off("exit", exit) } }
    },
    write(data: string) { child.stdin.write(data) },
    resize() { /* Pipes have no terminal dimensions. */ },
    kill(signal?: NodeJS.Signals) { child.kill(signal) },
  }
}
