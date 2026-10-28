# Codex models per tier

[tiers.md](tiers.md) says which tier fits the work. `codex -m` takes exact model IDs, not
aliases; edit this file when a model changes. Pass both on every call:
`codex exec -m <model> -c model_reasoning_effort=<effort> ...`. Always set the effort.

| Tier     | Model         | Effort |
| -------- | ------------- | ------ |
| trivial  | gpt-6-luna    | medium |
| routine  | gpt-6-luna    | high   |
| focused  | gpt-6.1-terra | low    |
| coupled  | gpt-6.1-terra | low    |
| judgment | gpt-6.1-terra | medium |
| executor | gpt-6.1-terra | medium |
| planner  | gpt-6.1-terra | medium |
