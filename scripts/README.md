# Scripts

## browser-tools

Standalone Chrome DevTools helper. Source lives at `scripts/browser-tools.ts`.

Build a local binary (not committed):

```bash
./scripts/build-browser-tools.sh
```

The build script will install `commander` and `puppeteer-core` in `scripts/node_modules` as needed.

Usage:

```bash
bin/browser-tools --help
```

Makefile target:

```bash
make browser-tools
```
