# TypeScript Tips — worked examples

Before/after (❌ avoid → ✅ prefer) for each tip in [../SKILL.md](../SKILL.md). Numbers match the tip numbers there.

## 1. Prefer `unknown` over `any`

```ts
// ❌ avoid
function parse(data: any) {
  return data.toUpperCase();
}

// ✅ prefer
function parse(data: unknown) {
  if (typeof data === "string") {
    return data.toUpperCase();
  }
}
```

## 2. Let type inference do the work

```ts
// ❌ avoid
const name: string = "Ada";

// ✅ prefer
const name = "Ada";
```

## 3. Prefer `satisfies` over `as`

```ts
// ❌ avoid — routes.home widens to string
const routes = {
  home: "/",
  about: "/about",
} as Record<string, string>;

// ✅ prefer — validated, but keys/values stay literal
const routes = {
  home: "/",
  about: "/about",
} satisfies Record<string, string>;
```

## 4. Derive types from values instead of duplicating them

```ts
// ❌ avoid
const roles = ["admin", "user", "guest"];
type Role = "admin" | "user" | "guest";

// ✅ prefer
const roles = ["admin", "user", "guest"] as const;
type Role = (typeof roles)[number];
```

## 5. Model impossible states with discriminated unions

```ts
// ❌ avoid — allows status:"success" with no data
type State = {
  status: string;
  data?: User;
  error?: Error;
};

// ✅ prefer
type State =
  | { status: "loading" }
  | { status: "success"; data: User }
  | { status: "error"; error: Error };
```

## 6. Use exhaustive checks with `never`

```tsx
// ❌ avoid — silently misses "error"
switch (state.status) {
  case "loading": return <Spinner />;
  case "success": return <Data />;
}

// ✅ prefer
switch (state.status) {
  case "loading": return <Spinner />;
  case "success": return <Data />;
  case "error": return <Error />;
  default: {
    const exhaustive: never = state;
    return exhaustive;
  }
}
```

## 7. Use `as const` for configuration and constants

```ts
// ❌ avoid — theme.mode: string
const theme = { mode: "dark" };

// ✅ prefer — theme.mode: "dark"
const theme = { mode: "dark" } as const;
```

## 8. Use type predicates for reusable narrowing

```ts
// ❌ avoid — inline, type stays unclear
if (typeof data === "object" && data !== null && "id" in data) {
  data.id;
}

// ✅ prefer
function isUser(value: unknown): value is User {
  return typeof value === "object" && value !== null && "id" in value;
}

if (isUser(data)) {
  data.id; // narrowed to User
}
```

## 9. Build new types from existing types

```ts
// ❌ avoid
type UserPreview = {
  id: string;
  name: string;
};

// ✅ prefer
type UserPreview = Pick<User, "id" | "name">;
```

## 10. Validate external data at runtime

```ts
// ❌ avoid — a lie if the shape differs
const user = (await response.json()) as User;

// ✅ prefer — with zod
const UserSchema = z.object({
  id: z.string(),
  name: z.string(),
});
const user = UserSchema.parse(await response.json());
```

## 11. Avoid `enum` in most cases

```ts
// ❌ avoid
enum Role {
  Admin,
  User,
}

// ✅ prefer
const roles = ["admin", "user"] as const;
type Role = (typeof roles)[number];
```

## 12. Prefer generics that infer automatically

```ts
// ❌ avoid
getData<User>();

// ✅ prefer — T inferred from the schema arg
getData(userSchema);
```

## 13. Constrain strings with template literal types

```ts
// ❌ avoid — too permissive
type Route = string;

// ✅ prefer
type Route = `/api/${string}`;
```

## 14. The type system trusts your assertions — it doesn't verify them

```ts
// ❌ avoid — compiles, but the cast lies: nothing checks the key exists
const config = cache.get(key) as Config;
config.retries; // 💥 at runtime if key was missing

// ✅ prefer — handle the real runtime possibility
const config = cache.get(key);
if (!config) throw new Error(`missing config: ${key}`);
config.retries;
```

## 15. Enable strict compiler options (when creating a new project)

```json
// ❌ avoid — minimal, permissive
{
  "target": "es2020"
}

// ✅ prefer
{
  "strict": true,
  "noUncheckedIndexedAccess": true,
  "exactOptionalPropertyTypes": true
}
```
