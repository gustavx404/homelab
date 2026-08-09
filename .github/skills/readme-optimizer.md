# README Optimization Skill — Apple Design System

## Principles

1. **Typography-first** — Clean hierarchy. One `h1` hero title, `h2` sections, `h3` never. Generous line-height via whitespace.
2. **Whitespace is the interface** — Every section separated by `---`. Content breathes. No cramming.
3. **Minimalist badges** — Small, flat, monochrome. No rainbow. Max 4.
4. **Hero section** — Title, one-line description, badges. Nothing else above the fold except architecture diagram.
5. **Card mentality** — Tables ARE cards. Clean borders, consistent padding via markdown formatting. Group related items visually.
6. **San Francisco aesthetic** — Clean prose. No emoji. No terminal prompts (`$`, `#`). No ASCII art blocks. Architecture diagram is the only ASCII permitted and must be under 80 chars.
7. **Progressive disclosure** — Quick start first. Details spiral outward. Don't explain what the table already shows.
8. **Consistent capitalization** — Title Case for headings. lower case for table values. Sentence case for descriptions.
9. **Single source of truth** — Every fact appears once. Tables replace paragraphs. Links replace inline config.
10. **Mobile-first** — Everything under 80 characters wide. Tables max 4 columns. No horizontal scroll ever.

## Structure

```
Hero (centered)
  title
  one-line description
  badges (max 4)

Architecture diagram (ASCII, compact, < 80 cols)

Quick Start (numbered, runnable as-is)

Services (single unified table)
  stack | service | image | access

File tree (minimal, grouped)

Features (IDS rules, security — terse tables)

Ports (what's exposed + why — 3 columns)

Stack management (code block)

Credits (compact, one line)
```

## Color palette

```
Primary:   #10b981 (green)
Secondary: #6b7280 (gray)
Badges:    flat square, single color
Tables:    clean borders, no zebra striping
```

## Anti-patterns

- Figlet or complex ASCII art
- Emoji anywhere
- Terminal `$` or `#` prompts
- Code blocks that aren't runnable
- Walls of text that duplicate table data
- More than 4 badges
- Tables with > 4 columns
- Links without context
- Mixed formatting styles in the same section
