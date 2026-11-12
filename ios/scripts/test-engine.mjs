import { spawn } from 'node:child_process'
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import assert from 'node:assert/strict'
import { setTimeout } from 'node:timers/promises'
import { createServer } from 'node:net'
import { createServer as createHTTPServer } from 'node:http'

const folder = await mkdtemp(join(tmpdir(), 'opencode-ios-test-'))
const socket = createServer()
await new Promise(r => socket.listen(0, '127.0.0.1', r))
const port = socket.address().port
await new Promise(r => socket.close(r))
const workspace = join(folder, 'project & unicode 日本語')
await mkdir(workspace)
const password = 'test-' + crypto.randomUUID()
let modelRequests = 0
const provider = createHTTPServer(async (req, res) => {
  let input = ''
  for await (const chunk of req) input += chunk
  const body = JSON.parse(input || '{}')
  modelRequests++
  if (body.stream) {
    res.writeHead(200, { 'content-type': 'text/event-stream' })
    for (const choice of [
      { delta: { role: 'assistant', content: 'PORT_OK' }, finish_reason: null },
      { delta: {}, finish_reason: 'stop' },
    ]) res.write('data: ' + JSON.stringify({ id: 'chatcmpl-ios-test', object: 'chat.completion.chunk', created: 1, model: 'mock', choices: [{ index: 0, ...choice }] }) + '\n\n')
    res.end('data: [DONE]\n\n')
  } else {
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify({ id: 'chatcmpl-ios-test', object: 'chat.completion', created: 1, model: 'mock', choices: [{ index: 0, message: { role: 'assistant', content: 'PORT_OK' }, finish_reason: 'stop' }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }))
  }
})
await new Promise(r => provider.listen(0, '127.0.0.1', r))
await mkdir(join(folder, 'config/opencode'), { recursive: true })
await writeFile(join(folder, 'config/opencode/opencode.json'), JSON.stringify({ provider: { 'ios-test': {
  npm: '@ai-sdk/openai-compatible', name: 'iOS test provider',
  options: { baseURL: `http://127.0.0.1:${provider.address().port}/v1`, apiKey: 'test-only' },
  models: { mock: { name: 'Mock', limit: { context: 32000, output: 1024 } } },
} } }))
const nodeFlags = process.env.OPENCODE_TEST_NODE_FLAGS?.split(' ').filter(Boolean) ?? []
const child = spawn(process.execPath, [...nodeFlags, '--experimental-sqlite', resolve('ios/runtime/dist/server.mjs')], {
  env: { ...process.env, OPENCODE_PRINT_LOGS: '1', OPENCODE_LOG_LEVEL: 'DEBUG', OPENCODE_SERVER_PASSWORD: password, OPENCODE_PORT: String(port),
    OPENCODE_WORKSPACE: workspace, OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER: 'true',
    XDG_DATA_HOME: join(folder, 'data'), XDG_CONFIG_HOME: join(folder, 'config'), XDG_CACHE_HOME: join(folder, 'cache'), XDG_STATE_HOME: join(folder, 'state') },
  stdio: ['ignore', 'pipe', 'pipe'],
})
let output = ''
child.stdout.on('data', x => { output += x }); child.stderr.on('data', x => { output += x })
let exit
const exited = new Promise(r => child.once('exit', code => { exit = code; r(code) }))
const base = `http://127.0.0.1:${port}`
const streamController = new AbortController()
let eventText = ''
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
  const stream = await fetch(base + '/event?directory=' + encodeURIComponent(workspace), { headers: { authorization: 'Basic ' + Buffer.from(`opencode:${password}`).toString('base64') }, signal: streamController.signal })
  void (async () => { try { for await (const chunk of stream.body) eventText += new TextDecoder().decode(chunk) } catch {} })()
  await request(`/session/${session.id}/prompt_async`, 'POST', {
    model: { providerID: 'ios-test', modelID: 'mock' }, agent: 'build',
    parts: [{ type: 'text', text: 'Say PORT_OK without using tools.' }],
  })
  let reply = false
  let lastMessages = []
  for (let i = 0; i < 80; i++) {
    const messages = await request(`/session/${session.id}/message`)
    lastMessages = messages
    const failure = messages.find(m => m.info.error)
    assert.ok(!failure, JSON.stringify(failure?.info.error))
    assert.ok(!eventText.includes('"type":"session.error"'), eventText)
    reply = messages.some(m => m.info.role === 'assistant' && m.parts.some(p => p.type === 'text' && p.text.includes('PORT_OK')))
    if (reply) break
    await setTimeout(500)
  }
  assert.ok(reply && modelRequests > 0, `No real engine response from the local mock provider. Requests=${modelRequests}, messages=${JSON.stringify(lastMessages)}, status=${JSON.stringify(await request('/session/status'))}\n${output}`)
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
  console.log('PASS: authenticated server, version, session CRUD, encoded paths, actual prompt execution against a local mock provider, permissions, questions, agents, providers and SSE')
} finally {
  streamController.abort()
  child.kill('SIGTERM')
  await Promise.race([exited, setTimeout(5000).then(() => child.kill('SIGKILL'))])
  await exited
  provider.closeAllConnections()
  await new Promise(r => provider.close(r))
  await rm(folder, { recursive: true, force: true })
}
