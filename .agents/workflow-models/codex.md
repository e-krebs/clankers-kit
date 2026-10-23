# Codex models per tier

[tiers.md](tiers.md) says which tier fits the work. `codex -m` takes exact model IDs, not
aliases; edit this file when a model changes. Pass both on every call:
`codex exec -m <model> -c model_reasoning_effort=<effort> ...`. Always set the effort.

| Tier     | Model       | Effort |
| -------- | ----------- | ------ |
| trivial  | gpt-6-luna  | medium |
| routine  | gpt-6-luna  | high   |
| focused  | gpt-6-luna  | high   |
| coupled  | gpt-6-luna  | high   |
| judgment | gpt-6.1-sol | low    |
| executor | gpt-6.1-sol | low    |
| planner  | gpt-6.1-sol | medium |
