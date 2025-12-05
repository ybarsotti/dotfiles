---
globs: ["**/*.ts", "**/*.tsx", "**/tsconfig.json"]
---

# TypeScript Development

## Testing (Jest/Vitest)

### Structure
```typescript
describe("UserService", () => {
  let service: UserService;

  beforeEach(() => {
    service = new UserService(mockRepo);
  });

  it("should return user by id", async () => {
    const user = await service.getById(1);
    expect(user).toEqual(expect.objectContaining({ id: 1 }));
  });

  it.each([
    [null, "User not found"],
    [undefined, "User not found"],
  ])("should throw for %s", async (input, message) => {
    await expect(service.getById(input)).rejects.toThrow(message);
  });
});
```

### Mocking
```typescript
// Mock modules
vi.mock("./api", () => ({
  fetchUser: vi.fn().mockResolvedValue({ id: 1 }),
}));

// Mock implementations
const mockFn = vi.fn<[number], Promise<User>>();
mockFn.mockResolvedValueOnce(user);
```

## Strict Typing

### Utility Types
```typescript
// Pick/Omit
type UserInput = Omit<User, "id" | "createdAt">;

// Partial/Required
type UpdateUser = Partial<User> & { id: string };

// Record
type StatusMap = Record<Status, string>;

// Extract/Exclude
type NumericKeys = Extract<keyof Data, number>;
```

### Discriminated Unions
```typescript
type Result<T> =
  | { success: true; data: T }
  | { success: false; error: Error };

function handle(result: Result<User>) {
  if (result.success) {
    // result.data is typed as User
  }
}
```

### Branded Types
```typescript
type UserId = string & { readonly brand: unique symbol };

function createUserId(id: string): UserId {
  return id as UserId;
}
```

## React Patterns

### Component Types
```typescript
// Props with children
type Props = React.PropsWithChildren<{
  title: string;
}>;

// Event handlers
type ButtonProps = {
  onClick: React.MouseEventHandler<HTMLButtonElement>;
};

// Ref forwarding
const Input = React.forwardRef<HTMLInputElement, InputProps>((props, ref) => (
  <input ref={ref} {...props} />
));
```

### Hooks
```typescript
// Custom hook with generics
function useAsync<T>(fn: () => Promise<T>) {
  const [state, setState] = useState<{
    data: T | null;
    loading: boolean;
    error: Error | null;
  }>({ data: null, loading: true, error: null });
  // ...
}
```

## Config (tsconfig.json)
```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true
  }
}
```
