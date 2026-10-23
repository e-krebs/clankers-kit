# Plan attachments

An attachment is a file beside the plan, named `<plan name>-<slug>.md` or `.html`. The plan
links it from its `Attachments:` line with an absolute path. Only these five cases exist:

| Case | Format | Built by | Read by |
| --- | --- | --- | --- |
| a spec that two or more briefs share | md | written inline by the session that holds the decisions | the workers whose brief links it, and the plan reviewers |
| a schematic or diagram | html | a worker picked from tiers.md for a self-contained build | the user, and the workers whose brief links it |
| a reference mockup | html | a worker picked from tiers.md for a self-contained build | the user, and the workers whose brief links it |
| a figure: metrics, a before/after, a table wider than markdown allows | html | a worker picked from tiers.md for a self-contained build | the user, and the workers whose brief links it |
| a shareable copy of the plan, on the user's yes | html | a worker picked from tiers.md for a self-contained build | readers beyond the user and the agent |

The markdown stays the plan. The running session reads no attachment. The planning session reads no HTML
attachment, because it hands the worker a brief and takes back a short report. The hooks and the
running session read only the plan markdown, so an attachment is never the source of a row, the fence or a
brief.

Build every attachment before the plan review, so the reviewers see it. The one exception is a
build that a refused write moved to a row, as the next section says.

## When a write is refused

- When plan mode refuses the spec write, the plan uses the inline form, and the spec goes into Briefs as a folded `### Spec`
  block. Each brief that needs it names that block instead of a link.
- When plan mode refuses an HTML write, building it becomes a row before the first row whose
  brief links it.

## The shareable copy

Offer it only when one of three criteria holds:

1. The plan has readers beyond the user and the agent, such as a team share-out, a design
   review, or a hand-off to another engineer.
2. The plan carries metrics, diagrams or diffs that markdown renders poorly.
3. The user asked for a "plan doc".

Offer once, in one line, and build only on a yes. With no criterion met, make no offer.

The copy mirrors all six sections, read-only. No hook, running session or worker reads it. An edit goes
into the markdown, and the copy is rebuilt from it.

## The blueprint look

Use ruled hairlines, monospace structure, and no rounding, glow or shadow in every HTML attachment. Start from [assets/blueprint.html](../assets/blueprint.html). It
carries the tokens, the layout and the six section slots of the shareable copy, in order.

The shareable copy's element order, top to bottom:

1. A kicker: three short dot-separated status words in uppercase mono, for example `PLAN · DRAFT · 2026-09-09`.
2. The heading: a full clause naming the change, not a noun phrase.
3. Summary, styled as the lede: the whole plan in at most five sentences, figures included.
4. Decisions, then Steps, then Run, each under its `<h2>`.
5. Briefs, as a list of links to the brief files, with no fold.
6. Plan review, styled as the colophon, last on the page.

Follow all five visual rules:

1. Monospace carries structure (headings, labels, table headers, figures, captions), and a
   sans face carries prose only.
2. Divisions are hairlines, `1px solid var(--line)`. No boxes, no rounding beyond 1-2px on
   inline code, no shadow.
3. One accent colour. Verdict states may use the three verdict tokens. Nothing else takes a
   colour.
4. Every colour is a token from the palette block, inline SVG included, so the page re-themes
   in one edit. No hex anywhere else.
5. Blocks extend to the ruled column lines, while prose stays inside the padding with a capped
   line length, so block edges meet the rules.

Numbers lead their sentences, carry units, and keep one precision within a column.

## Source lines and the colophon

Every table and figure block ends in one mono `.source` line naming where its data came from:
the command, the query, the file or the transcript. Without that line, no reader can trace the
figure.

The colophon closes the shareable copy: the Plan review content, then when the page was
generated, by which agent, from which inputs (the brief, the ticket, the commit the tree sat
on), and its revision.
