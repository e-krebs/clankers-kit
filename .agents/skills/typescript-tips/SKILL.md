---
name: typescript-tips
description: TypeScript best-practice conventions and idioms. Use when writing new TypeScript (.ts/.tsx), editing existing code, or reviewing a diff (the tips are the review rubric for the changed lines). Not for untouched code outside the change under review.
---

# TypeScript Tips

Conventions that improve type safety and maintainability.

## How to apply

1. **Scope to your change.** Apply these to code you write or edit, and as the rubric for the changed lines when reviewing a diff — not to surrounding code the change doesn't touch. For unrelated violations in a touched file, note them briefly — don't rewrite them.
2. **Let the tips set direction.** Prefer the idiom for in-scope and new code even when surrounding code diverges; flag divergent existing code (e.g. `enum`s) as a migration candidate rather than silently converting it. Keep fixes proportional — flag heavier type machinery (tips #4, #12, #13) as opt-in on low-churn data rather than applying it by default.
3. **Cite as `tip #N (Title)`** when you apply or flag one, so the reference is traceable and survives reordering.
4. **Open [references/examples.md](references/examples.md)** for the exact before/after when the principle line alone isn't enough.

## The tips

1. **Prefer `unknown` over `any`.** `unknown` forces validation before use; `any` silently disables type checking and spreads unsafety.
2. **Let inference work.** Annotate only where inference can't reach (function boundaries, ambiguous literals) — redundant annotations add maintenance cost.
3. **Prefer `satisfies` over `as`.** `satisfies` validates a value against a type without widening it, so you keep the narrow inferred type; `as` discards precision and can mask errors.
4. **Derive types from values.** Instead of maintaining a value and a parallel type by hand, derive with `as const` + `(typeof value)[number]`.
5. **Model impossible states with discriminated unions.** A shared discriminant field makes invalid combinations (success with no data, error with no message) unrepresentable.
6. **Exhaustive-check with `never`.** Assign the narrowed value to a `never` in the `default` branch so a future added case becomes a compile error, not a runtime bug.
7. **Use `as const` for config and constants.** Without it, literal properties widen to `string`/`number`; with it they keep their literal types.
8. **Extract reusable type predicates.** A `value is T` guard combines a runtime check with compile-time narrowing and is reusable across call sites.
9. **Build types from existing types.** Use `Pick`/`Omit`/`Partial`/indexed access instead of re-declaring overlapping shapes.
10. **Validate external data at runtime.** Type safety ends at the I/O boundary — parse API responses with a runtime schema (e.g. zod) instead of casting.
11. **Avoid `enum` in most cases.** `const` arrays + literal unions are simpler to refactor, trivially serializable, and free of `enum`'s runtime and erasure quirks.
12. **Design generics to infer.** Shape APIs so type parameters come from the arguments rather than being passed explicitly.
13. **Constrain strings with template literal types.** Prefer domain patterns like `` `/api/${string}` `` over bare `string`.
14. **The compiler trusts assertions — it doesn't verify them.** An `as` cast says "trust me" and stops checking; handle the runtime possibility instead of asserting it away.
15. **Enable strict compiler options on new projects.** Turn on `strict` plus `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` from the start — retrofitting them later is painful.

## Gotchas

- **`satisfies` needs TS 4.9+.** Older toolchains won't parse it — check the version before recommending it (tip #3).
- **`as const` is deeply `readonly`.** The frozen value can't be passed where a mutable type is expected; you may need a `readonly`-aware signature or an explicit copy (tips #4, #7).
- **The `never` check only holds for a closed literal union.** If the discriminant is widened to `string`, the `default` value never narrows to `never`, so the assertion fails to compile — and casting that error away silently kills the guarantee (tip #6).
- **Type predicates are unsound.** TS trusts your `value is T` return even if the body lies — a wrong guard is as dangerous as `as`. Keep the check exhaustive (tip #8).
- **Runtime validation has a cost.** Add it at real boundaries (network, storage, user input), not for internal already-typed data — over-validating is noise (tip #10).
- **`noUncheckedIndexedAccess` is painful to retrofit.** It surfaces many latent errors in an existing codebase; enable it at project creation, not mid-flight (tip #15).

---

Adapted from [AllThingsSmitty/typescript-tips-everyone-should-know](https://github.com/AllThingsSmitty/typescript-tips-everyone-should-know) (CC0-1.0).
