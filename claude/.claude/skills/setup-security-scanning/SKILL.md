# Setup Security Scanning

Automated security scanning for code, dependencies, infrastructure-as-code, and secrets using industry-standard tools in CI/CD pipelines.

## Purpose

This skill provides configuration and guidance for setting up security scanning:

- Static code analysis with Checkov
- Dependency vulnerability scanning with npm audit and Dependabot
- Secret detection with git-secrets or TruffleHog
- YAML linting for configuration files
- Infrastructure-as-code security scanning
- Container image scanning
- License compliance checking

## When to Use

Use this skill when:

- Setting up security scanning for a new project
- Implementing security best practices in CI/CD
- Need to comply with security policies
- Want to catch vulnerabilities early in development
- Publishing open-source software
- Working with sensitive data or credentials
- Deploying to cloud infrastructure

## Security Scanning Tools

### 1. Checkov - Infrastructure as Code Scanning

**What it scans:**

- Terraform configurations
- CloudFormation templates
- Kubernetes manifests
- Dockerfile
- GitHub Actions workflows
- Docker Compose files
- ARM templates
- Serverless framework

**GitHub Action (.github/workflows/security.yml):**

```yaml
name: Security Scanning

on:
 push:
 branches-ignore:
 - main
 pull_request:
 branches:
 - main

permissions:
 contents: read
 security-events: write
 actions: read

jobs:
 checkov:
 name: Checkov IaC Scan
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - name: Run Checkov
 uses: bridgecrewio/checkov-action@v12
 with:
 directory: "."
 framework: all
 skip_framework: ansible
 quiet: true
 soft_fail: true
 output_format: cli,sarif
 output_file_path: console,checkov.sarif
 skip_check: CKV_GHA_7,CKV2_GHA_1

 - name: Upload Checkov results to GitHub Security
 uses: github/codeql-action/upload-sarif@v3
 if: always()
 with:
 sarif_file: checkov.sarif
```

**Configuration (.checkov.yaml):**

```yaml
framework:
 - terraform
 - cloudformation
 - kubernetes
 - dockerfile
 - github_actions

skip-check:
 - CKV_GHA_7 # Skip specific checks if needed
 - CKV2_GHA_1

soft-fail: true # Don't fail the build, just report

compact: true
quiet: false
```

**Common skip checks:**

- `CKV_GHA_7` - Unpinned GitHub Actions versions
- `CKV2_GHA_1` - Token permissions
- `CKV_DOCKER_2` - HEALTHCHECK instruction
- `CKV_K8S_8` - Liveness probe

### 2. npm audit - Dependency Vulnerability Scanning

**Basic scan:**

```bash
npm audit
```

**Fix vulnerabilities automatically:**

```bash
npm audit fix
```

**GitHub Action:**

```yaml
name: Security Scanning

on:
 push:
 branches:
 - main
 pull_request:

jobs:
 npm-audit:
 name: npm Audit
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - name: Setup Node.js
 uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'

 - name: Install dependencies
 run: npm ci

 - name: Run npm audit
 run: npm audit --audit-level=moderate
 continue-on-error: true
```

**Audit levels:**

- `info` - Show all vulnerabilities
- `low` - Low and above
- `moderate` - Moderate and above (recommended)
- `high` - High and critical only
- `critical` - Critical only

### 3. Dependabot - Automated Dependency Updates

**Configuration (.github/dependabot.yml):**

```yaml
version: 2
updates:
 - package-ecosystem: "npm"
 directory: "/"
 schedule:
 interval: "weekly"
 day: "monday"
 time: "09:00"
 open-pull-requests-limit: 5
 reviewers:
 - "team-name"
 assignees:
 - "username"
 labels:
 - "dependencies"
 - "automated"
 commit-message:
 prefix: "chore"
 include: "scope"
 versioning-strategy: increase

 - package-ecosystem: "github-actions"
 directory: "/"
 schedule:
 interval: "weekly"
 commit-message:
 prefix: "ci"
```

**With security-only updates:**

```yaml
version: 2
updates:
 - package-ecosystem: "npm"
 directory: "/"
 schedule:
 interval: "daily"
 open-pull-requests-limit: 10
 labels:
 - "dependencies"
 - "security"
```

**With grouping (reduces PR noise):**

```yaml
version: 2
updates:
 - package-ecosystem: "npm"
 directory: "/"
 schedule:
 interval: "weekly"
 groups:
 development-dependencies:
 dependency-type: "development"
 production-dependencies:
 dependency-type: "production"
```

### 4. TruffleHog - Secret Detection

**GitHub Action:**

```yaml
name: Security Scanning

on:
 push:
 pull_request:

jobs:
 trufflehog:
 name: TruffleHog Secret Scan
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 with:
 fetch-depth: 0

 - name: TruffleHog OSS
 uses: trufflesecurity/trufflehog@main
 with:
 path: ./
 base: ${{ github.event.repository.default_branch }}
 head: HEAD
 extra_args: --debug --only-verified
```

**Pre-commit hook (.husky/pre-commit):**

```bash
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# Run trufflehog on staged files
git diff --staged --name-only | xargs trufflehog filesystem --no-update
```

### 5. git-secrets - Prevent Committing Secrets

**Installation:**

```bash
# macOS
brew install git-secrets

# Linux
git clone https://github.com/awslabs/git-secrets.git
cd git-secrets
make install
```

**Setup in repository:**

```bash
cd your-repo
git secrets --install
git secrets --register-aws
```

**Add custom patterns:**

```bash
git secrets --add 'password\s*=\s*.+'
git secrets --add 'api[_-]?key\s*=\s*.+'
git secrets --add '[0-9a-f]{64}' # Private keys
```

**Scan existing repository:**

```bash
git secrets --scan-history
```

### 6. YAML Linting

**Configuration (.yamllint.yml):**

```yaml
extends: default

rules:
 line-length:
 max: 120
 level: warning
 indentation:
 spaces: 2
 comments:
 min-spaces-from-content: 1
```

**GitHub Action:**

```yaml
name: Security Scanning

on:
 push:
 pull_request:

jobs:
 yaml-lint:
 name: YAML Lint
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - name: YAML Lint
 uses: ibiqlik/action-yamllint@v3
 with:
 file_or_dir: .
 config_file: .yamllint.yml
 format: github
 strict: false
```

### 7. CodeQL - Advanced Security Analysis

**GitHub Action (.github/workflows/codeql.yml):**

```yaml
name: CodeQL Analysis

on:
 push:
 branches: [main]
 pull_request:
 branches: [main]
 schedule:
 - cron: '0 0 * * 1' # Weekly on Monday

permissions:
 actions: read
 contents: read
 security-events: write

jobs:
 analyze:
 name: Analyze Code
 runs-on: ubuntu-latest

 strategy:
 fail-fast: false
 matrix:
 language: ['javascript', 'typescript']

 steps:
 - uses: actions/checkout@v4

 - name: Initialize CodeQL
 uses: github/codeql-action/init@v3
 with:
 languages: ${{ matrix.language }}
 queries: security-extended,security-and-quality

 - name: Autobuild
 uses: github/codeql-action/autobuild@v3

 - name: Perform CodeQL Analysis
 uses: github/codeql-action/analyze@v3
 with:
 category: "/language:${{ matrix.language }}"
```

### 8. License Compliance

**Using license-checker:**

```bash
npm install --save-dev license-checker
```

**Package.json script:**

```json
{
 "scripts": {
 "license-check": "license-checker --summary",
 "license-report": "license-checker --json --out licenses.json"
 }
}
```

**GitHub Action:**

```yaml
name: Security Scanning

on:
 push:
 pull_request:

jobs:
 license-check:
 name: License Compliance
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'

 - run: npm ci

 - name: Check licenses
 run: npx license-checker --failOn 'GPL;AGPL'
```

## Complete Security Workflow

**Comprehensive security scanning (.github/workflows/security.yml):**

```yaml
name: Security Scanning

on:
 push:
 branches-ignore:
 - main
 pull_request:
 branches:
 - main
 schedule:
 - cron: '0 0 * * 1' # Weekly on Monday

permissions:
 contents: read
 security-events: write
 actions: read

jobs:
 checkov:
 name: Checkov IaC Scan
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - name: Run Checkov
 uses: bridgecrewio/checkov-action@v12
 with:
 directory: "."
 framework: all
 skip_framework: ansible
 quiet: true
 soft_fail: true
 output_format: cli,sarif
 output_file_path: console,checkov.sarif

 - name: Upload to Security tab
 uses: github/codeql-action/upload-sarif@v3
 if: always()
 with:
 sarif_file: checkov.sarif

 npm-audit:
 name: npm Audit
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'

 - run: npm ci

 - name: Run npm audit
 run: npm audit --audit-level=moderate
 continue-on-error: true

 trufflehog:
 name: Secret Scan
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4
 with:
 fetch-depth: 0

 - name: TruffleHog
 uses: trufflesecurity/trufflehog@main
 with:
 path: ./
 base: ${{ github.event.repository.default_branch }}
 head: HEAD
 extra_args: --only-verified

 yaml-lint:
 name: YAML Lint
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - name: YAML Lint
 uses: ibiqlik/action-yamllint@v3
 with:
 file_or_dir: .
 format: github

 license-check:
 name: License Compliance
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v4

 - uses: actions/setup-node@v4
 with:
 node-version: '20'
 cache: 'npm'

 - run: npm ci

 - name: Check licenses
 run: npx license-checker --summary
```

## CODEOWNERS File

**Purpose:** Automatically request reviews from code owners for security-sensitive files.

**Configuration (.github/CODEOWNERS):**

```
# Global owners
* @org/team-name

# Security-sensitive files
/.github/ @org/security-team
/Dockerfile @org/infrastructure-team
/docker-compose.yml @org/infrastructure-team
*.tf @org/infrastructure-team
*.tfvars @org/infrastructure-team
/src/auth/ @org/security-team
/src/payments/ @org/security-team

# Configuration files
package.json @org/team-leads
tsconfig.json @org/team-leads
```

## Security Policy

**Create SECURITY.md in repository root:**

```markdown
## Security Policy

### Supported Versions

| Version | Supported |
| ------- | ------------------ |
| 2.x.x | :white_check_mark: |
| 1.x.x | :white_check_mark: |
| < 1.0 | :x: |

### Reporting a Vulnerability

If you discover a security vulnerability, please do NOT open a public issue.

Instead, please email security@example.com with:

1. Description of the vulnerability
1. Steps to reproduce
1. Potential impact
1. Suggested fix (if any)

We will respond within 48 hours and work with you to resolve the issue.

### Security Update Process

1. Security issues are prioritized and fixed immediately
1. Fixes are released as patch versions
1. Security advisories are published on GitHub
1. Users are notified via release notes
```

## Branch Protection Rules

**Recommended security settings:**

1. **Require pull request reviews:**
 - At least 1 approval
 - Dismiss stale reviews
 - Require review from code owners

1. **Require status checks:**
 - Security scanning must pass
 - npm audit must pass
 - All tests must pass

1. **Require branches to be up to date**

1. **Do not allow bypassing required pull requests**

1. **Restrict who can push to main:**
 - Only admins and release bot

## Pre-commit Security Checks

**Husky hook (.husky/pre-commit):**

```bash
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"

# Run quality checks
npm run quality:commit

# Check for secrets (if git-secrets is installed)
if command -v git-secrets >/dev/null 2>&1; then
 git secrets --pre_commit_hook -- "$@"
fi

# Check for large files
MAX_SIZE=1048576 # 1MB
for file in $(git diff --cached --name-only); do
 if [ -f "$file" ]; then
 size=$(wc -c < "$file")
 if [ $size -gt $MAX_SIZE ]; then
 echo "Error: $file is too large ($(($size / 1024))KB > 1MB)"
 exit 1
 fi
 fi
done
```

## Best Practices

### 1. Secrets Management

**Never commit:**

- API keys
- Passwords
- Private keys
- Tokens
- Connection strings
- Certificates

**Use instead:**

- Environment variables
- Secret management services (AWS Secrets Manager, Azure Key Vault)
- GitHub Secrets for CI/CD
- .env files (gitignored)

**Example .gitignore:**

```
.env
.env.local
.env.*.local
*.key
*.pem
credentials.json
secrets.yaml
```

### 2. Dependency Management

- Keep dependencies up to date
- Review Dependabot PRs promptly
- Use `npm audit` regularly
- Pin GitHub Actions versions
- Use lock files (package-lock.json)

### 3. Security Scanning Frequency

- **On every PR:** Checkov, TruffleHog, npm audit
- **Weekly scheduled:** CodeQL, full security scan
- **Before release:** Comprehensive security review
- **On dependency update:** Re-run all security scans

### 4. False Positive Management

- Document skip reasons in configuration
- Use specific skip checks, not blanket disabling
- Review skipped checks periodically
- Re-evaluate skips when tools update

### 5. Security Advisories

- Enable GitHub security advisories
- Subscribe to security mailing lists
- Monitor CVE databases for dependencies
- Set up alerts for critical vulnerabilities

## Troubleshooting

### Issue: Checkov fails with too many errors

**Solution:** Start with soft_fail: true and fix issues gradually. Use skip_check for false positives.

### Issue: npm audit fails build for low-severity issues

**Solution:** Use `--audit-level=moderate` or `--audit-level=high` to focus on critical issues.

### Issue: Dependabot creates too many PRs

**Solution:** Use grouping in dependabot.yml or reduce frequency to weekly/monthly.

### Issue: TruffleHog reports false positives

**Solution:** Use `--only-verified` flag to reduce noise. Add exceptions to .trufflehog.yml.

### Issue: CodeQL takes too long

**Solution:** Run CodeQL only on main branch and schedule weekly, not on every PR.

### Issue: Secret accidentally committed

**Solution:**

1. Immediately revoke/rotate the secret
1. Use `git filter-branch` or BFG Repo-Cleaner to remove from history
1. Force push (requires coordination with team)
1. Set up git-secrets to prevent recurrence

## Quick Start

### 1. Set up Dependabot

Create `.github/dependabot.yml` with npm and github-actions updates.

### 2. Add security workflow

Create `.github/workflows/security.yml` with Checkov and npm audit.

### 3. Set up git-secrets

```bash
brew install git-secrets
git secrets --install
git secrets --register-aws
```

### 4. Create SECURITY.md

Add security policy to repository root.

### 5. Configure branch protection

Enable required status checks and code owner reviews.

### 6. Add CODEOWNERS

Create `.github/CODEOWNERS` for sensitive files.

### 7. Test security scanning

```bash
npm audit
npx checkov -d .
git secrets --scan-history
```

Your project now has comprehensive security scanning!
