# HTML rendering of a plan

Offered only when one of three criteria holds:

1. The plan has readers beyond the author and the agent — a team share-out, a design review, a
   hand-off to another engineer.
2. The plan carries metrics, diagrams or diffs that markdown renders poorly.
3. The user asked for a "plan doc".

Offer once, in one line, and render only on a yes. Two of three is not a stronger case than
one: any single criterion is enough, and none means no offer.

## The HTML is the plan

On a yes, `<plan>.html` beside the markdown file becomes the source of truth, so the plan is
never held twice. The markdown file shrinks to a stub: the H1, a line `Source: <plan>.html`
(relative to the markdown file's directory), then the ten `## ` headings with one pointer line
each, `See [<plan>.html](<plan>.html#<id>)`. The gate follows the `Source:` line and checks the
HTML's `<h2>` headings and sections; every skill that reads the plan does the same. An edit to
the plan goes into the HTML, and the re-review reads the HTML.

## The blueprint look

The page reads as a technical drawing rather than a web page: ruled, measured, drafted. Nothing
rounded, nothing glowing, no shadow. Start from
[assets/blueprint.html](../assets/blueprint.html) — it carries the tokens, the layout and ten
`<section>` slots whose `<h2>` texts are the contract headings, spelled exactly.

Element order, top to bottom:

1. A kicker: three short dot-separated status words in uppercase mono, e.g. `PLAN · DRAFT · 2026-09-09`.
2. The heading: a full clause naming the change, not a noun phrase.
3. The Context section, styled as the lede: the whole plan in three to five sentences, figures
   included.
4. The other sections, each under its `<h2>`, in contract order.
5. The Plan review section, styled as the colophon, last on the page.

Five visual rules hold the look together; break one and the page stops reading as a blueprint:

1. Monospace carries structure — headings, labels, table headers, figures, captions — and a
   sans face carries prose only. That split is the loudest signal of the style.
2. Divisions are hairlines, `1px solid var(--line)`. No boxes, no rounding beyond 1-2px on
   inline code, no shadow.
3. One accent colour. Verdict states may use the three verdict tokens; nothing else takes a
   colour.
4. Every colour is a token from the palette block, inline SVG included, so the page re-themes
   in one edit. No hex anywhere else.
5. Blocks bleed to the ruled column lines while prose stays inside the padding and caps its
   measure, so the eye sees block edges meeting the rules.

Numbers lead their sentences, carry units, and keep one precision within a column.

## Source lines and the colophon

An untraceable figure is an assertion, so every table and figure block ends in one mono
`.source` line naming where it came from: the command, the query, the file, the transcript.

The colophon closes the page: the Plan review content, then when the page was generated, by
which agent, from which inputs (the brief, the ticket, the commit the tree sat on), and its
revision.

## Provenance of the style

The structure and the invariant set are modelled on the public `blueprint-docs` skill at
https://github.com/SunkenInTime/skills (`blueprint-docs/SKILL.md`), read on 2026-09-09: the
element order, the five rules, the token vocabulary and the bleed idiom follow it. That
repository ships no licence file, so no sentence is carried over; the wording here and the
scaffold's markup are ours. Treat the URL as the reference, not as a source to paste from.
