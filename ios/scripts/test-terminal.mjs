import assert from 'node:assert/strict'
import { spawn } from '../runtime/pty.ts'

async function run(file, args) {
  return await new Promise((resolve, reject) => {
    const process = spawn(file, args, { cwd: '.', env: {} })
    let output = ''
    const timeout = setTimeout(() => { process.kill(); reject(new Error('Command timed out')) }, 5000)
    process.onData(data => { output += data })
    process.onExit(({ exitCode }) => { clearTimeout(timeout); resolve({ output, exitCode }) })
  })
}
const success = await run('/bin/sh', ['-c', 'printf hello; printf error >&2; exit 3'])
assert.equal(success.exitCode, 3)
assert.ok(success.output.includes('hello') && success.output.includes('error'))
const missing = await run('/nonexistent/opencode-shell', [])
assert.equal(missing.exitCode, 127)
assert.match(missing.output, /Cannot start command/)
console.log('PASS: terminal output, exit status and missing executable without server crash')
