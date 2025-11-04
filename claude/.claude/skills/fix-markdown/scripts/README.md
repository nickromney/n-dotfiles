# Fix Markdown Scripts

This directory contains markdown linting and fixing utilities.

## Scripts Included

### Python Scripts (use `uv run`)

- **remove-emojis.py** - Strip all emoji characters from markdown files
- **fix-step-headings.py** - Convert `**Step X:**` and `#### Step X:` to `### Step X:`

### Shell Scripts

- **fix-all-docs.sh** - Run all fixes in sequence (orchestrator)
- **fix-bold-h1.sh** - Convert standalone bold text to H2 headings
- **fix-duplicate-h1.sh** - Convert H1 to H2 when frontmatter has title (MD025)
- **fix-image-alt-text.sh** - Add "Image" alt text to images (MD045)
- **fix-ordered-lists.sh** - Standardize list prefixes to "1." (MD029)
- **report-markdownlint-issues.sh** - Generate detailed linting report

## Quick Usage

```bash
# From the skill directory
cd ~/.claude/skills/fix-markdown

# Run individual scripts
uv run scripts/remove-emojis.py documentation/
./scripts/fix-ordered-lists.sh documentation/

# Fix everything
./scripts/fix-all-docs.sh documentation/

# Report issues
./scripts/report-markdownlint-issues.sh documentation/
```

## Requirements

- **markdownlint-cli** - `npm install -g markdownlint-cli`
- **uv** - For Python scripts (installed via dotfiles)
- **perl** - For multiline regex editing
- **sed** - For single-line editing (macOS BSD sed)

## Integration with Dotfiles

After running `stow -R claude`, these scripts are available at:

```
~/.claude/skills/fix-markdown/scripts/
```

The skill is version-controlled in your dotfiles repo at:

```
claude/.claude/skills/fix-markdown/scripts/
```
