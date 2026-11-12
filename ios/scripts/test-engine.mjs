import { spawn } from 'node:child_process'
import { mkdtemp, mkdir, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import assert from 'node:assert/strict'
import { setTimeout } from 'node:timers/promises'
import { createServer } from 'node:net'

const folder = await mkdtemp(join(tmpdir(), 'opencode-ios-test-'))
const socket = createServer()
await new Promise(r => socket.listen(0, '127.0.0.1', r))
const port = socket.address().port
await new Promise(r => socket.close(r))
const workspace = join(folder, 'project & unicode 日本語')
await mkdir(workspace)
const password = 'test-' + crypto.randomUUID()
const nodeFlags = process.env.OPENCODE_TEST_NODE_FLAGS?.split(' ').filter(Boolean) ?? []
const child = spawn(process.execPath, [...nodeFlags, '--experimental-sqlite', resolve('ios/runtime/dist/server.mjs')], {
  env: { ...process.env, OPENCODE_SERVER_PASSWORD: password, OPENCODE_PORT: String(port),
    OPENCODE_WORKSPACE: workspace, OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER: 'true',
    XDG_DATA_HOME: join(folder, 'data'), XDG_CONFIG_HOME: join(folder, 'config'), XDG_CACHE_HOME: join(folder, 'cache'), XDG_STATE_HOME: join(folder, 'state') },
  stdio: ['ignore', 'pipe', 'pipe'],
})
let output = ''
child.stdout.on('data', x => { output += x }); child.stderr.on('data', x => { output += x })
let exit
const exited = new Promise(r => child.once('exit', code => { exit = code; r(code) }))
const base = `http://127.0.0.1:${port}`
async function request(path, method = 'GET', body) {
  const url = new URL(path, base)
  url.searchParams.set('directory', workspace)
  const response = await fetch(url, { method, signal: AbortSignal.timeout(20000),
    headers: { authorization: 'Basic ' + Buffer.from(`opencode:${password}`).toString('base64'), 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body) })
  const text = await response.text()
  assert.ok(response.ok, `${method} ${path}: ${response.status}: ${text}`)
  return text ? JSON.parse(text) : null
}
try {
  let ready = false
  for (let i = 0; i < 90; i++) {
    if (exit !== undefined) throw new Error(`Engine exited (${exit}):\n${output}`)
    try { ready = (await request('/global/health')).healthy } catch {}
    if (ready) break
    await setTimeout(500)
  }
  assert.ok(ready, `Server failed to start:\n${output}`)
  assert.equal((await fetch(base + '/global/health')).status, 401, 'Unauthenticated localhost requests must be rejected')
  const health = await request('/global/health')
  assert.equal(health.version, '1.19.4')
  const session = await request('/session', 'POST', { title: 'iOS integration' })
  assert.ok(session.id)
  assert.ok((await request('/session')).some(x => x.id === session.id))
  await request(`/session/${session.id}`, 'PATCH', { title: 'Renamed from iOS' })
  assert.equal((await request(`/session/${session.id}`)).title, 'Renamed from iOS')
  assert.ok(Array.isArray(await request(`/session/${session.id}/message`)))
  assert.ok(Array.isArray(await request('/permission')))
  assert.ok(Array.isArray(await request('/question')))
  assert.ok(Array.isArray(await request('/agent')))
  assert.ok(Array.isArray((await request('/provider')).all))
  const controller = new AbortController()
  const sse = await fetch(base + '/event?directory=' + encodeURIComponent(workspace), { headers: { authorization: 'Basic ' + Buffer.from(`opencode:${password}`).toString('base64') }, signal: controller.signal })
  assert.equal(sse.status, 200)
  assert.match(sse.headers.get('content-type'), /text\/event-stream/)
  const reader = sse.body.getReader()
  const first = await Promise.race([reader.read(), setTimeout(10000).then(() => { throw new Error('SSE did not emit initial event') })])
  assert.match(new TextDecoder().decode(first.value), /data:/)
  controller.abort()
  await request(`/session/${session.id}`, 'DELETE')
  assert.ok(!(await request('/session')).some(x => x.id === session.id))
  console.log('PASS: authenticated server, version, session CRUD, encoded paths, messages, permissions, questions, agents, providers and SSE')
} finally {
  child.kill('SIGTERM')
  await Promise.race([exited, setTimeout(5000).then(() => child.kill('SIGKILL'))])
  await exited
  await rm(folder, { recursive: true, force: true })
}
