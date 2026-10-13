/** Build and ad-hoc sign the AppKit addon; output belongs to the consuming project. */
import { execFileSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { mkdir, rename, rm } from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'
import { randomUUID } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const usage = 'Usage: node build-native.mjs [--outdir <directory>]\nOptional NODE_HEADERS_DIR must contain node_api.h.'
const args = process.argv.slice(2)
if (args.length === 1 && args[0] === '--help') {
  console.log(usage)
  process.exit(0)
}
if (args.length !== 0 && (args.length !== 2 || args[0] !== '--outdir' || !args[1].trim())) throw new Error(usage)
if (process.platform !== 'darwin') throw new Error('This AppKit addon builds only on macOS; use the target platform\'s native backdrop API or a scoped CSS fallback.')

const directory = fileURLToPath(new URL('.', import.meta.url))
const headers = process.env.NODE_HEADERS_DIR ? resolve(process.env.NODE_HEADERS_DIR) : resolve(dirname(process.execPath), '../include/node')
if (!existsSync(join(headers, 'node_api.h'))) throw new Error('Node headers were not found beside this Node installation. Set NODE_HEADERS_DIR to an installed Node include/node directory.')
const compiler = execFileSync('/usr/bin/xcrun', ['--find', 'clang++'], { encoding: 'utf8' }).trim()
const sdk = execFileSync('/usr/bin/xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { encoding: 'utf8' }).trim()
if (!existsSync(join(sdk, 'System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h'))) throw new Error('A macOS 26 or newer SDK with NSGlassEffectView is required.')
const architecture = { arm64: 'arm64', x64: 'x86_64' }[process.arch]
if (!architecture) throw new Error(`Unsupported macOS architecture: ${process.arch}`)
const outputDirectory = args.length ? resolve(args[1]) : resolve(process.cwd(), 'build/native-glass')
await mkdir(outputDirectory, { recursive: true })
const output = join(outputDirectory, 'native-glass.node')
const temporary = join(outputDirectory, `.native-glass-${randomUUID()}.node`)
try {
  execFileSync(compiler, ['-std=c++17', '-fobjc-arc', '-O2', '-dynamiclib', '-undefined', 'dynamic_lookup', '-DNAPI_VERSION=8', '-mmacosx-version-min=12.0', '-arch', architecture, '-isysroot', sdk, '-I', headers, '-framework', 'Cocoa', '-framework', 'QuartzCore', join(directory, 'native-glass.mm'), '-o', temporary], { stdio: 'inherit' })
  execFileSync('/usr/bin/codesign', ['--force', '--sign', '-', temporary], { stdio: 'inherit' })
  await rename(temporary, output)
} finally {
  await rm(temporary, { force: true })
}
console.log(`Native AppKit glass bridge built: ${output}`)
