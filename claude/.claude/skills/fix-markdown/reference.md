# Reference

## Script Details

### remove-emojis.py

**Language:** Python 3

**Purpose:** Remove all emoji characters from markdown files

**Usage:**
```bash
uv run scripts/remove-emojis.py <file-or-directory>
```

**What it fixes:**
- Strips all Unicode emoji characters (emoticons, symbols, dingbats, pictographs)
- Cleans up multiple spaces left by emoji removal
- Preserves all markdown formatting
- Works on single files or recursively processes directories

**How it works:**
- Uses regex pattern covering emoji ranges: U+1F300-1FAF6, U+2600-26FF, etc.
- Processes files in-place with UTF-8 encoding
- Only modifies files that contain emojis

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
6. `uv run remove-emojis.py` - Strip emojis
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

## Dependencies

**Required:**
- `markdownlint-cli2` - For linting validation and auto-fixing (faster than markdownlint-cli)
- `uv` - For running Python scripts
- `perl` - For multiline regex editing (fix-duplicate-h1, fix-bold-h1)
- `sed` - For single-line editing (fix-ordered-lists, fix-image-alt-text)

**Installation:**
```bash
# markdownlint-cli2 (installed via npm, managed by fnm Node version)
npm install -g markdownlint-cli2

# uv (if not already installed)
brew install uv
```

## Configuration

These scripts respect `.markdownlint.yaml` configuration in the repository root.

**Common rules these scripts address:**
- `MD025` - Multiple H1 headings (fixed by fix-duplicate-h1.sh)
- `MD029` - Ordered list item prefix (fixed by fix-ordered-lists.sh)
- `MD045` - Missing image alt text (fixed by fix-image-alt-text.sh)

**Typical .markdownlint.yaml:**
```yaml
MD013: false  # Line length - disabled
MD025: true   # Single H1
MD029: true   # Ordered list prefix (one style)
MD045: true   # Images must have alt text
```

## Notes

- **No backups created** - Scripts modify files in-place (use git for safety)
- **Idempotent** - Safe to run multiple times (won't create duplicate fixes)
- **UTF-8 encoding** - Python scripts require UTF-8 support
- **Cross-platform sed** - Detects macOS (BSD sed) vs Linux (GNU sed) and adjusts syntax automatically
- **uv run** - Python scripts use `uv run` instead of `python3` for dependency management
- **Perl multiline** - Uses `-0pe` flags for processing entire file as single string
