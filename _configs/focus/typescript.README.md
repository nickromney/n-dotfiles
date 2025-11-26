# TypeScript Focus Configuration

Modern, performance-focused TypeScript toolchain.

## Tools

| Tool | Purpose | Speed Benefit |
|------|---------|---------------|
| **bun** | Runtime, bundler, package manager, test runner | Much faster than node/npm |
| **typescript** | Type checking | Standard tsc |
| **tsgo** | Type checking (Go port) | ~10x faster than tsc |
| **biome** | Linting + formatting | ~100x faster than ESLint |
| **swc** | Transpilation/bundling | Much faster than tsc emit |

## Installation

```bash
# Install all tools via brew
./install.sh -c focus/typescript

# Install tsgo (npm package, not in brew)
npm install -g @typescript/native-preview
```

## tsgo (TypeScript 7 Preview)

Native Go port of TypeScript compiler. Significantly faster for large codebases.

```bash
# Check version
tsgo --version

# Use instead of tsc
tsgo --build
tsgo --noEmit
```

### VS Code Integration

Add to your settings.json:

```json
{
  "typescript.experimental.useTsgo": true
}
```

### Status

As of November 2025, tsgo is in preview with most features working:

- ✅ Program creation and parsing
- ✅ Type resolution and checking
- ✅ JSX support
- ✅ Build mode and incremental builds
- 🚧 Declaration emit (in progress)
- 🚧 JS output emission (in progress)

Track progress: <https://github.com/microsoft/typescript-go>

## Biome

Fast linter and formatter replacing ESLint + Prettier.

```bash
# Initialize in project
biome init

# Check and format
biome check .
biome format --write .

# Lint only
biome lint .
```

## SWC

Rust-based transpiler for when you need fast JS output.

```bash
# Compile TypeScript to JavaScript
swc src -d dist

# Watch mode
swc src -d dist --watch
```

## Bun

All-in-one JavaScript runtime and toolkit.

```bash
# Run TypeScript directly (no transpilation)
bun run script.ts

# Package management (faster than npm)
bun install
bun add package

# Run tests
bun test

# Bundle
bun build ./src/index.ts --outdir ./dist
```
