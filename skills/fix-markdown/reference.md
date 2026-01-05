# Reference

## Script Details

### detect-emojis.py

**Language:** Python 3

**Purpose:** Detect and optionally remove emoji characters from markdown files

**Usage:**

```bash
uv run scripts/detect-emojis.py <file-or-directory>           # Detect only
uv run scripts/detect-emojis.py --remove <file-or-directory>  # Remove emojis
```

**What it does:**

- **Detect mode (default)**: Scans for emojis and exits with code 1 if found
- **Remove mode (`--remove`)**: Strips all Unicode emoji characters
- Cleans up multiple spaces left by emoji removal
- Preserves all markdown formatting
- Works on single files or recursively processes directories

**How it works:**

- Uses regex pattern covering emoji ranges: U+1F300-1FAF6, U+2600-26FF, etc.
- Processes files with UTF-8 encoding
- In detect mode: exits 0 if clean, exits 1 if emojis found
- In remove mode: only modifies files that contain emojis

---

### fix-step-headings.py

**Language:** Python 3

**Purpose:** Convert step emphasis to proper H3 headings

**Usage:**

```bash
uv run scripts/fix-step-headings.py <file-or-directory>
```

**What it fixes:**

- Converts `**Step N: text**` to `### Step N: text`
- Converts `#### Step N: text` to `### Step N: text`
- Works on single files or recursively processes directories

**Rationale:**

- Step sequences should use H3 (###) for consistency
- Bold text is not semantically a heading
- H4 is too deeply nested for implementation plan steps

---

### fix-duplicate-h1.sh

**Language:** Bash

**Purpose:** Fix MD025 - ensure only one H1 per document

**Usage:**

```bash
./scripts/fix-duplicate-h1.sh <file-or-directory>
```

**What it fixes:**

- Converts all H1 headings to H2 **only if** frontmatter contains `title:` field
- Uses Perl regex to handle multiline frontmatter
- Preserves frontmatter and only processes content after `---`

**Rationale:**

- When frontmatter has `title:`, that's the H1 - other headings should be H2
- Files without frontmatter titles are left unchanged

**Implementation:**

- Uses `perl -i -0pe` for in-place multiline editing
- Pattern: `s/(---\n.*?---\n.*)^# (.+)$/\1## \2/msg`

---

### fix-bold-h1.sh

**Language:** Bash

**Purpose:** Convert standalone bold text to H2 headings

**Usage:**

```bash
./scripts/fix-bold-h1.sh <file-or-directory>
```

**What it fixes:**

- Identifies `**Text**` on its own line (not inline bold)
- Converts to `## Text` (H2) for files with frontmatter
- Only processes content after frontmatter section

**How it works:**

1. Checks if file has `title:` in frontmatter
2. Finds bold text patterns after frontmatter: `^\*\*[^\*\n]+\*\*\s*$`
3. Converts to H2 using Perl regex

**Note:** Preserves inline bold (e.g., `This is **bold** text`)

---

### fix-ordered-lists.sh

**Language:** Bash

**Purpose:** Fix MD029 - standardize ordered list prefixes to "1."

**Usage:**

```bash
./scripts/fix-ordered-lists.sh <file-or-directory>
```

**What it fixes:**

- Replaces `2.`, `3.`, `4.`, etc. with `1.`
- Works on numbered lists with any indentation
- Preserves nested list structure

**Rationale:**

- markdownlint MD029 requires "one" style: all items use `1.`
- Markdown auto-numbers items, so `1. 1. 1.` renders as `1. 2. 3.`

**Implementation:**

- Uses `sed` with regex: `s/^([[:space:]]*)([2-9][0-9]*)\./\11./`
- Only modifies if file contains numbered items > 1

---

### fix-image-alt-text.sh

**Language:** Bash

**Purpose:** Fix MD045 - add alt text to images

**Usage:**

```bash
./scripts/fix-image-alt-text.sh <file-or-directory>
```

**What it fixes:**

- Identifies `![](path/to/image.png)` (empty alt text)
- Adds generic alt text: `![Image](path/to/image.png)`

**Rationale:**

- Accessibility: screen readers need alt text
- markdownlint MD045 requires non-empty alt text

**Note:** Uses generic "Image" placeholder - manual improvement recommended

---

### fix-all-docs.sh

**Language:** Bash

**Purpose:** Run all markdown fixes in sequence

**Usage:**

```bash
./scripts/fix-all-docs.sh [directory]
```

**Default directory:** `documentation` (if not specified)

**Process:**

1. `markdownlint-cli2 --fix` - Auto-fix simple issues
2. `fix-duplicate-h1.sh` - Fix H1 in files with frontmatter
3. `fix-image-alt-text.sh` - Add missing alt text
4. `fix-bold-h1.sh` - Convert bold headings to H2
5. `fix-ordered-lists.sh` - Standardize list prefixes
6. `uv run detect-emojis.py --remove` - Strip emojis
7. Re-check with markdownlint-cli2 and report remaining issues

**Output:**

- Progress messages for each step
- "Fixed: filename" for each modified file
- Final count of remaining issues
- Sample of remaining issues (first 20 lines)

---

### report-markdownlint-issues.sh

**Language:** Bash

**Purpose:** Generate detailed markdown linting report

**Usage:**

```bash
./scripts/report-markdownlint-issues.sh [directory]
```

**Default directory:** `documentation` (if not specified)

**Output sections:**

1. **Total issues count**
2. **Issues by type** - Grouped by MD rule (e.g., MD025, MD029)
3. **Files requiring intervention** - Sorted by issue count
4. **Detailed issues** - Full markdownlint output

**How it works:**

- Runs `markdownlint-cli2 --config .markdownlint.yaml`
- Parses output with `awk` to group and count
- Uses temp file for processing: `/tmp/markdownlint-report.$$`

**Exit codes:**

- 0 if no issues found
- Non-zero if issues exist (but doesn't fail the script)

**Note:** Uses markdownlint-cli2 (faster, newer) instead of markdownlint-cli

---

### setup-precommit.sh

**Language:** Bash

**Purpose:** Set up pre-commit hooks for markdown linting and emoji checking

**Usage:**

```bash
./scripts/setup-precommit.sh [directory]
```

**Default directory:** current directory (if not specified)

**What it creates:**

- `.pre-commit-config.yaml` - Pre-commit configuration with:
  - markdownlint-cli2 (linting only, no auto-fix)
  - emoji checker (fails if emojis detected)
  - General file checks (trailing whitespace, end-of-file, YAML validation)
- `.git-hooks/check-emojis.sh` - Shell script for emoji detection in pre-commit

**Behavior:**

- If `.pre-commit-config.yaml` exists: shows instructions for manual addition
- If not present: offers to create minimal config
- Interactive prompts before creating files
- Sets executable permissions on hook scripts

**Exit codes:**

- 0 if successful or config already exists
- 1 if user cancels or pre-commit not installed

## Dependencies

**Required:**

- `markdownlint-cli2` - For linting validation and auto-fixing (faster than markdownlint-cli)
- `uv` - For running Python scripts
- `sed` - For single-line editing (fix-ordered-lists, fix-image-alt-text)

**Optional:**

- `perl` - For multiline regex editing in frontmatter-aware scripts (fix-duplicate-h1, fix-bold-h1)
  - Pre-installed on macOS and most Linux distributions
  - Only needed if fixing markdown files with YAML frontmatter

**Installation:**

```bash
# markdownlint-cli2 (installed via npm, managed by fnm Node version)
npm install -g markdownlint-cli2

# uv (if not already installed)
brew install uv
```

## Configuration

**Config file detection (priority order):**

1. `.markdownlint.yaml` in current working directory (local project config)
2. `scripts/../.markdownlint.yaml` in skill directory (bundled config)
3. markdownlint-cli2 defaults (if no config found)

This allows the skill to work in any directory while respecting local project standards when present.

**Common rules these scripts address:**

- `MD025` - Multiple H1 headings (fixed by fix-duplicate-h1.sh)
- `MD029` - Ordered list item prefix (fixed by fix-ordered-lists.sh)
- `MD045` - Missing image alt text (fixed by fix-image-alt-text.sh)

**Bundled .markdownlint.yaml:**

```yaml
default: true
MD013: false  # Line length - disabled (code blocks exceed 80 chars)
MD024: false  # Duplicate headings - allow repeated section headings
MD033: false  # Inline HTML - allow for special formatting
MD041: false  # First-line heading - not always applicable
```

## Notes

- **No backups created** - Scripts modify files in-place (use git for safety)
- **Idempotent** - Safe to run multiple times (won't create duplicate fixes)
- **UTF-8 encoding** - Python scripts require UTF-8 support
- **Cross-platform sed** - Detects macOS (BSD sed) vs Linux (GNU sed) and adjusts syntax automatically
- **uv run** - Python scripts use `uv run` instead of `python3` for dependency management
- **Perl multiline** - Uses `-0pe` flags for processing entire file as single string
