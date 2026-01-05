# Setup Semantic Release

Automated version management and package publishing using semantic-release. Automatically determines the next version number, generates a changelog, and publishes the package based on commit messages.

## Purpose

This skill provides configuration and guidance for setting up semantic-release:

- Automated versioning based on commit messages
- Automatic CHANGELOG.md generation
- GitHub releases with release notes
- npm/GitHub Packages publishing
- Git tagging and commits
- Conventional commits integration

## When to Use

Use this skill when:

- Setting up automated releases for a library or package
- Want to automate version bumping based on commit messages
- Need automatic changelog generation
- Publishing packages to npm or GitHub Packages
- Want consistent versioning across team
- Need to enforce conventional commits

## How Semantic Release Works

1. **Analyzes commits** since the last release using conventional commit format
1. **Determines version bump** (major, minor, patch) based on commit types
1. **Generates release notes** from commit messages
1. **Updates CHANGELOG.md** with new version
1. **Updates package.json** version
1. **Creates git tag** for the new version
1. **Publishes to npm/GitHub Packages** (optional)
1. **Creates GitHub release** with release notes

## Commit Message Format

Semantic release uses **Conventional Commits** format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Commit Types and Version Bumps

| Commit Type | Version Bump | Example |
|-------------|--------------|---------|
| `feat:` | Minor (0.x.0) | `feat: add user authentication` |
| `fix:` | Patch (0.0.x) | `fix: resolve memory leak` |
| `BREAKING CHANGE:` | Major (x.0.0) | `feat!: remove deprecated API` |
| `perf:` | Patch (0.0.x) | `perf: improve query performance` |
| `docs:` | No release | `docs: update API documentation` |
| `chore:` | No release | `chore: update dependencies` |
| `style:` | No release | `style: format code` |
| `refactor:` | No release | `refactor: restructure module` |
| `test:` | No release | `test: add unit tests` |
| `ci:` | No release | `ci: update GitHub Actions` |

### Examples

**Patch release (0.0.1):**

```
fix: correct calculation in interest formula

Fixes an off-by-one error that caused incorrect results
for edge cases.

Closes #123
```

**Minor release (0.1.0):**

```
feat: add export to CSV functionality

Users can now export their data to CSV format through
the new export button in the toolbar.
```

**Major release (1.0.0):**

```
feat!: redesign authentication API

BREAKING CHANGE: The authenticate() method now returns
a Promise instead of a callback. All authentication code
must be updated to use async/await or .then().

Migration guide: https://docs.example.com/v1-migration
```

## Configuration

### 1. Install Dependencies

```bash
npm install --save-dev semantic-release \
 @semantic-release/changelog \
 @semantic-release/git \
 @semantic-release/github \
 @semantic-release/npm
```

### 2. Configuration File (.releaserc.json)

**Basic configuration:**

```json
{
 "branches": ["main"],
 "plugins": [
 "@semantic-release/commit-analyzer",
 "@semantic-release/release-notes-generator",
 "@semantic-release/changelog",
 "@semantic-release/npm",
 "@semantic-release/github",
 "@semantic-release/git"
 ]
}
```

**With custom configuration:**

```json
{
 "branches": ["main"],
 "plugins": [
 "@semantic-release/commit-analyzer",
 "@semantic-release/release-notes-generator",
 [
 "@semantic-release/changelog",
 {
 "changelogFile": "CHANGELOG.md"
 }
 ],
 [
 "@semantic-release/npm",
 {
 "npmPublish": true,
 "tarballDir": "dist"
 }
 ],
 [
 "@semantic-release/github",
 {
 "assets": ["dist/*.tgz"]
 }
 ],
 [
 "@semantic-release/git",
 {
 "assets": ["CHANGELOG.md", "package.json", "package-lock.json"],
 "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
 }
 ]
 ]
}
```

**GitHub Packages only (no npm):**

```json
{
 "branches": ["main"],
 "plugins": [
 "@semantic-release/commit-analyzer",
 "@semantic-release/release-notes-generator",
 [
 "@semantic-release/changelog",
 {
 "changelogFile": "CHANGELOG.md"
 }
 ],
 "@semantic-release/github",
 [
 "@semantic-release/git",
 {
 "assets": ["CHANGELOG.md", "package.json"],
 "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
 }
 ],
 "@semantic-release/npm"
 ]
}
```

**For libraries (with npm publishing):**

```json
{
 "branches": ["main"],
 "plugins": [
 "@semantic-release/commit-analyzer",
 "@semantic-release/release-notes-generator",
 [
 "@semantic-release/changelog",
 {
 "changelogFile": "CHANGELOG.md"
 }
 ],
 "@semantic-release/npm",
 "@semantic-release/github",
 [
 "@semantic-release/git",
 {
 "assets": ["CHANGELOG.md", "package.json", "package-lock.json", "npm-shrinkwrap.json"],
 "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
 }
 ]
 ]
}
```

### 3. Package.json Configuration

**For npm publishing:**

```json
{
 "name": "my-package",
 "version": "0.0.0-development",
 "repository": {
 "type": "git",
 "url": "https://github.com/username/repo.git"
 },
 "publishConfig": {
 "access": "public"
 }
}
```

**For GitHub Packages:**

```json
{
 "name": "@username/my-package",
 "version": "0.0.0-development",
 "repository": {
 "type": "git",
 "url": "https://github.com/username/repo.git"
 },
 "publishConfig": {
 "registry": "https://npm.pkg.github.com"
 }
}
```

**For private packages (no publishing):**

```json
{
 "name": "my-package",
 "version": "0.0.0-development",
 "private": true,
 "repository": {
 "type": "git",
 "url": "https://github.com/username/repo.git"
 }
}
```

Note: When private is true, semantic-release will skip npm publishing but still create releases and update changelog.

### 4. GitHub Actions Workflow

**Basic release workflow (.github/workflows/release.yml):**

```yaml
name: Release

on:
 push:
 branches:
 - main

permissions:
 contents: write
 issues: write
 pull-requests: write
 packages: write

jobs:
 release:
 name: Release
 runs-on: ubuntu-latest
 steps:
 - name: Checkout
 uses: actions/checkout@v4
 with:
 fetch-depth: 0
 persist-credentials: false

 - name: Setup Node.js
 uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'

 - name: Install dependencies
 run: npm ci

 - name: Build
 run: npm run build

 - name: Test
 run: npm test

 - name: Release
 env:
 GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
 NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
 run: npx semantic-release
```

**With GitHub App token (recommended for protected branches):**

```yaml
name: Release

on:
 push:
 branches:
 - main
 workflow_dispatch:

jobs:
 release:
 name: Release
 runs-on: ubuntu-latest
 steps:
 - name: Generate token
 id: generate-token
 uses: actions/create-github-app-token@v1
 with:
 app-id: ${{ secrets.APP_ID }}
 private-key: ${{ secrets.APP_PRIVATE_KEY }}
 owner: ${{ github.repository_owner }}

 - name: Checkout
 uses: actions/checkout@v4
 with:
 fetch-depth: 0
 persist-credentials: false
 token: ${{ steps.generate-token.outputs.token }}

 - name: Setup Node.js
 uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'

 - name: Install dependencies
 run: npm ci

 - name: Build
 run: npm run build
 if: hashFiles('tsconfig.json') != ''

 - name: Test
 run: npm test
 if: hashFiles('vitest.config.js', 'playwright.config.ts') != ''

 - name: Semantic release
 uses: cycjimmy/semantic-release-action@v4
 with:
 tag_format: ${version}
 env:
 GITHUB_TOKEN: ${{ steps.generate-token.outputs.token }}
 NPM_TOKEN: ${{ secrets.GITHUB_TOKEN }}
 GIT_AUTHOR_NAME: ${{ github.actor }}
 GIT_AUTHOR_EMAIL: ${{ github.actor }}@users.noreply.github.com
 GIT_COMMITTER_NAME: ${{ github.actor }}
 GIT_COMMITTER_EMAIL: ${{ github.actor }}@users.noreply.github.com
```

**For GitHub Packages:**

```yaml
name: Release

on:
 push:
 branches:
 - main

permissions:
 contents: write
 packages: write

jobs:
 release:
 name: Release
 runs-on: ubuntu-latest
 steps:
 - name: Checkout
 uses: actions/checkout@v4
 with:
 fetch-depth: 0

 - name: Setup Node.js
 uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'
 registry-url: 'https://npm.pkg.github.com'

 - name: Install dependencies
 run: npm ci

 - name: Build
 run: npm run build

 - name: Test
 run: npm test

 - name: Release
 env:
 GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
 NODE_AUTH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
 run: npx semantic-release
```

## Protected Branches Setup

If you have branch protection rules that prevent direct commits to main:

### Option 1: GitHub App (Recommended)

1. Create a GitHub App with repository permissions:
 - Contents: Read and write
 - Pull requests: Read and write
 - Issues: Read and write
 - Metadata: Read-only

1. Install the app on your repository

1. Generate a private key for the app

1. Add secrets to your repository:
 - `APP_ID`: Your GitHub App ID
 - `APP_PRIVATE_KEY`: Your GitHub App private key

1. Use the workflow with GitHub App token (shown above)

### Option 2: Allow Bypassing

Configure branch protection to allow semantic-release bot to bypass:

1. Go to repository Settings → Branches
1. Edit branch protection rule for `main`
1. Under "Allow force pushes" → Enable for specific actors
1. Add `github-actions[bot]` or your GitHub App

## Workflow Integration

### Separate Quality Checks and Release

**Quality checks on PRs (.github/workflows/checks.yml):**

```yaml
name: Checks

on:
 push:
 branches-ignore:
 - main
 pull_request:
 branches:
 - main

jobs:
 quality:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 - uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'
 - run: npm ci
 - run: npm run build
 - run: npm test
 - run: npm run lint
```

**Release on main (.github/workflows/release.yml):**

```yaml
name: Release

on:
 push:
 branches:
 - main

jobs:
 release:
 # ... semantic-release steps
```

## Commit Message Enforcement

### Option 1: Commitlint

**Install:**

```bash
npm install --save-dev @commitlint/cli @commitlint/config-conventional
```

**Configuration (commitlint.config.js):**

```javascript
export default {
 extends: ['@commitlint/config-conventional']
}
```

**Husky hook (.husky/commit-msg):**

```bash
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

npx --no -- commitlint --edit $1
```

### Option 2: GitHub Action

**PR title validation (.github/workflows/pr-title.yml):**

```yaml
name: PR Title Check

on:
 pull_request:
 types: [opened, edited, synchronize]

jobs:
 check:
 runs-on: ubuntu-latest
 steps:
 - uses: amannn/action-semantic-pull-request@v5
 env:
 GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Version Ranges and Pre-releases

### Stable Releases

```json
{
 "branches": ["main"]
}
```

Produces: 1.0.0, 1.1.0, 1.2.0, 2.0.0, etc.

### With Next/Beta Channel

```json
{
 "branches": [
 "main",
 {
 "name": "beta",
 "prerelease": true
 }
 ]
}
```

Produces:

- `main`: 1.0.0, 1.1.0, 1.2.0
- `beta`: 1.1.0-beta.1, 1.1.0-beta.2

### Maintenance Branches

```json
{
 "branches": [
 "main",
 {
 "name": "1.x",
 "range": "1.x",
 "channel": "1.x"
 }
 ]
}
```

Produces:

- `main`: 2.0.0, 2.1.0, 2.2.0
- `1.x`: 1.1.0, 1.2.0, 1.3.0

## Best Practices

### 1. Commit Messages

- Write clear, descriptive commit messages
- Use conventional commit format consistently
- Include scope when possible: `feat(auth): add login`
- Reference issues: `Closes #123` or `Fixes #456`
- Explain "why" in commit body, not "what"

### 2. Breaking Changes

Always document breaking changes clearly:

```
feat!: change API response format

BREAKING CHANGE: The API now returns data in a new format.
Before: { user: { name: "John" } }
After: { data: { user: { name: "John" } } }

Migration: Update all API calls to access data.user instead of user.
```

### 3. Initial Release

For the first release, use:

```json
{
 "version": "0.0.0-development"
}
```

Semantic release will create 1.0.0 on first release with breaking change, or 0.1.0 for features.

### 4. Testing

- Test semantic-release locally using dry-run mode
- Verify CHANGELOG.md generation
- Check that version bumps are correct

**Dry run command:**

```bash
npx semantic-release --dry-run
```

### 5. GitHub App vs GITHUB_TOKEN

**Use GitHub App when:**

- You have branch protection rules
- You need commits to trigger other workflows
- You want fine-grained permissions

**Use GITHUB_TOKEN when:**

- Simple setup without branch protection
- Public repositories
- No need to bypass protection rules

### 6. Release Notes

Semantic release generates release notes automatically from commits. To improve them:

- Write clear commit messages
- Use scopes consistently
- Group related changes in PR
- Add context in commit body

## Troubleshooting

### Issue: Semantic release not creating a release

**Cause:** No relevant commits since last release (only chore, docs, etc.)

**Solution:** Make a commit with feat, fix, or breaking change.

### Issue: "Permission denied" when pushing tags

**Cause:** GITHUB_TOKEN doesn't have permission to push

**Solution:** Add `contents: write` permission to workflow

### Issue: Release commit triggers another workflow

**Cause:** GITHUB_TOKEN creates commits that trigger workflows

**Solution:** Use `[skip ci]` in commit message or use GitHub App token

### Issue: Branch protection prevents semantic-release commit

**Cause:** Branch protection rules block direct commits

**Solution:** Use GitHub App token with bypass permissions

### Issue: Wrong version number generated

**Cause:** Commit messages don't follow conventional format

**Solution:** Fix commit messages and ensure commitlint is configured

## Complete Example

**Package.json:**

```json
{
 "name": "@myorg/my-package",
 "version": "0.0.0-development",
 "repository": {
 "type": "git",
 "url": "https://github.com/myorg/my-package.git"
 },
 "scripts": {
 "build": "tsc",
 "test": "vitest run",
 "prepare": "husky"
 },
 "devDependencies": {
 "@commitlint/cli": "^18.0.0",
 "@commitlint/config-conventional": "^18.0.0",
 "husky": "^9.0.0",
 "semantic-release": "^22.0.0",
 "@semantic-release/changelog": "^6.0.3",
 "@semantic-release/git": "^10.0.1",
 "@semantic-release/github": "^9.0.0",
 "@semantic-release/npm": "^11.0.0"
 }
}
```

**.releaserc.json:**

```json
{
 "branches": ["main"],
 "plugins": [
 "@semantic-release/commit-analyzer",
 "@semantic-release/release-notes-generator",
 [
 "@semantic-release/changelog",
 {
 "changelogFile": "CHANGELOG.md"
 }
 ],
 "@semantic-release/npm",
 "@semantic-release/github",
 [
 "@semantic-release/git",
 {
 "assets": ["CHANGELOG.md", "package.json", "package-lock.json"],
 "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
 }
 ]
 ]
}
```

**commitlint.config.js:**

```javascript
export default {
 extends: ['@commitlint/config-conventional']
}
```

**.husky/commit-msg:**

```bash
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

npx --no -- commitlint --edit $1
```

**.github/workflows/release.yml:**

```yaml
name: Release

on:
 push:
 branches:
 - main

permissions:
 contents: write
 issues: write
 pull-requests: write

jobs:
 release:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 with:
 fetch-depth: 0
 - uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'
 - run: npm ci
 - run: npm run build
 - run: npm test
 - name: Release
 env:
 GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
 NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
 run: npx semantic-release
```

## Quick Start

### 1. Install Semantic Release

```bash
npm install --save-dev semantic-release \
 @semantic-release/changelog \
 @semantic-release/git \
 @semantic-release/github \
 @semantic-release/npm
```

### 2. Create .releaserc.json

Copy the configuration from this skill.

### 3. Update package.json

Set version to `0.0.0-development` and add repository URL.

### 4. Create GitHub Actions workflow

Copy the release workflow from this skill to `.github/workflows/release.yml`.

### 5. Optional: Set up commitlint

```bash
npm install --save-dev @commitlint/cli @commitlint/config-conventional
echo "export default { extends: ['@commitlint/config-conventional'] }" > commitlint.config.js
echo 'npx --no -- commitlint --edit $1' > .husky/commit-msg
chmod +x .husky/commit-msg
```

### 6. Test with dry-run

```bash
npx semantic-release --dry-run
```

### 7. Make a commit and push to main

```bash
git add .
git commit -m "feat: initial release"
git push origin main
```

Semantic release will automatically create version 1.0.0 and publish!
