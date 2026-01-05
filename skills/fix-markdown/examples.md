# Examples

## Removing Emojis

**Before:**
```markdown
# 🎉 Welcome to My Project! 🚀

This is an awesome 😎 project that does cool ✨ things!
```

**Command:**
```bash
uv run ./scripts/remove-emojis.py README.md
```

**After:**
```markdown
# Welcome to My Project

This is an awesome project that does cool things!
```

## Fixing Duplicate H1 Headings (with Frontmatter)

**Before:**
```markdown
---
title: My Document
---

# Introduction

Some content here.

# Another Top-Level Heading

More content.
```

**Command:**
```bash
./scripts/fix-duplicate-h1.sh document.md
```

**After:**
```markdown
---
title: My Document
---

## Introduction

Some content here.

## Another Top-Level Heading

More content.
```

**Note:** This script only converts H1 to H2 when frontmatter contains a `title:` field.

## Fixing Bold Text as Headings

**Before:**
```markdown
---
title: Guide
---

**Introduction**

This is the intro section.

**Setup**

Installation steps here.
```

**Command:**
```bash
./scripts/fix-bold-h1.sh document.md
```

**After:**
```markdown
---
title: Guide
---

## Introduction

This is the intro section.

## Setup

Installation steps here.
```

**Note:** Only converts bold text on its own line, after frontmatter.

## Fixing Step Headings

**Before:**
```markdown
**Step 1: Install dependencies**

Run npm install

#### Step 2: Configure settings

Edit the config file
```

**Command:**
```bash
uv run ./scripts/fix-step-headings.py guide.md
```

**After:**
```markdown
### Step 1: Install dependencies

Run npm install

### Step 2: Configure settings

Edit the config file
```

**Note:** Converts both `**Step X:**` and `#### Step X:` to `### Step X:`

## Fixing Ordered Lists (MD029)

**Before:**
```markdown
1. First item
2. Second item
3. Third item
  1. Nested first
  2. Nested second
```

**Command:**
```bash
./scripts/fix-ordered-lists.sh document.md
```

**After:**
```markdown
1. First item
1. Second item
1. Third item
  1. Nested first
  1. Nested second
```

**Note:** markdownlint MD029 requires all list items use "1." for auto-numbering.

## Batch Processing

**Fix all markdown issues in a directory:**
```bash
./scripts/fix-all-docs.sh documentation/
```

**Output:**
```
Fixing markdown issues in: documentation

Step 1: Running markdownlint auto-fix...

Step 2: Fixing duplicate H1 headings...
Fixed: documentation/guide.md

Step 3: Fixing image alt text...
Fixed: documentation/intro.md

Step 4: Fixing bold H1 headings...
Fixed: documentation/tutorial.md

Step 5: Fixing ordered list prefixes...
Fixed: documentation/steps.md

Step 6: Removing emojis...
Fixed: documentation/README.md

Step 7: Re-checking issues...
Remaining issues: 0

✓ All markdown issues fixed!
```

**Note:** Uses `uv run` for Python scripts internally.

## Checking Before Fixing

**Generate a detailed report of all issues:**
```bash
./scripts/report-markdownlint-issues.sh documentation/
```

**Example Output:**
```
Markdown Linting Report for: documentation
==========================================

Total issues: 15

Issues by Type:
---------------
   8  MD025
   4  MD029
   2  MD045
   1  MD001

Files Requiring Manual Intervention:
-------------------------------------
  5 issues: documentation/guide.md
  4 issues: documentation/tutorial.md
  3 issues: documentation/setup.md
  2 issues: documentation/intro.md
  1 issues: documentation/README.md

Detailed Issues:
----------------
documentation/guide.md:10 MD025/single-title/single-h1 Multiple top-level headings
documentation/guide.md:25 MD029/ol-prefix Ordered list item prefix
...
```

This helps you understand what issues exist before running fixes.
