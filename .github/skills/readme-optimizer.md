# README Optimization Skill

## Principles

1. **Above the fold** — Title, one-liner, badges, architecture diagram visible without scrolling.
2. **Scan-first** — Tables over walls of text. Anyone should grasp the project in 10 seconds.
3. **Console aesthetic** — Section headers use terminal-style prompts (`$`, `#`, `▸`). Consistent visual language.
4. **Progressive disclosure** — Quick start first, details later. Don't bury the `docker compose up -d`.
5. **Mobile-friendly** — ASCII art under 80 chars wide. Tables collapse gracefully. No horizontal scroll.
6. **Badge discipline** — Max 5 badges. Show what matters: CI status, stack highlights.
7. **Single source of truth** — Don't repeat information. Each fact lives in exactly one place.
8. **Whitespace is design** — Section breaks, indentation, spacing tell the eye where to look.
9. **Command copy-paste** — Every code block should be runnable as-is. No placeholders that need editing.
10. **Consistent terminology** — Pick one name per concept and use it everywhere.

## Structure

```
1. Title + badges (centered)

2. Architecture diagram (ASCII, < 80 cols)

3. Quick start (numbered, runnable commands)

4. Services table (name, image, port, description)

5. Access URLs (path-based routing)

6. File tree (terminal-style)

7. Features / highlights (IDS rules, security, etc.)

8. Port audit (what's exposed and why)

9. Stack management commands

10. Credits (compact, links only)
```

## Anti-patterns

- Complex figlet/ASCII that's hard to read
- Tables with too many columns (max 5)
- Code blocks with `$` prefix AND `bash` language tag (pick one)
- Duplicate service descriptions (table AND paragraph)
- Walls of YAML inline (link to files instead)
- Emoji overload (max 0)

## Color palette

- Badges: `#10b981` (green) for success/active status
- Section headers: bold + `▸` prefix
- Code blocks: `bash` or `yaml` language tags
- Tables: left-aligned, minimal borders
