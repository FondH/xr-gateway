const fs = require('node:fs')
const path = require('node:path')
const crypto = require('node:crypto')

const repo = '/home/fond/xr-gateway'
const envPath = path.join(repo, 'deploy/.env')
const backupDir = '/home/fond/backups'
const original = fs.readFileSync(envPath, 'utf8')
const redisLines = original.match(/^REDIS_PASSWORD=.*$/gm) || []
if (redisLines.length !== 1) throw new Error('Expected exactly one REDIS_PASSWORD field')
const bindLines = original.match(/^LAN_BIND_HOST=.*$/gm) || []
if (bindLines.length > 1) throw new Error('Duplicate LAN_BIND_HOST fields')

const redisPassword = redisLines[0].slice('REDIS_PASSWORD='.length) || crypto.randomBytes(32).toString('hex')
if (!/^[0-9a-fA-F]{64}$/.test(redisPassword)) {
  throw new Error('REDIS_PASSWORD must be a 64-character hex string')
}
let updated = original.replace(/^REDIS_PASSWORD=.*$/m, `REDIS_PASSWORD=${redisPassword}`)
updated = bindLines.length
  ? updated.replace(/^LAN_BIND_HOST=.*$/m, 'LAN_BIND_HOST=192.168.31.186')
  : `${updated.trimEnd()}\nLAN_BIND_HOST=192.168.31.186\n`

fs.mkdirSync(backupDir, { recursive: true, mode: 0o700 })
const timestamp = new Date().toISOString().replace(/[-:T.Z]/g, '').slice(0, 14)
const backupPath = path.join(backupDir, `deploy-env-before-lan-${timestamp}`)
fs.writeFileSync(backupPath, original, { mode: 0o600, flag: 'wx' })
const tempPath = `${envPath}.lan-config-tmp`
fs.writeFileSync(tempPath, updated, { mode: 0o600, flag: 'wx' })
fs.renameSync(tempPath, envPath)
console.log(`Configured Redis authentication and LAN bind. Backup: ${backupPath}`)
