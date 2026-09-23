# Implementation constraints

Every `simple-plan` plan obeys these rules. The drafter applies them. The reviewers enforce
them. Quote the rule number when you reject a plan.

## 1. Least code that solves the problem

Stop at the first option that works:

1. The problem does not need code. Say so and stop.
2. This codebase already has the helper, type, or pattern. Reuse it and cite the path.
3. The standard library solves it. Use it.
4. The platform solves it (a database constraint, a CSS rule, a native input). Use it.
5. An installed dependency solves it. Use it. Never add a dependency for a few lines of code.
6. Write the smallest new code that works.

Do not add an abstraction that has one implementation. Do not add a configuration value that
never changes. Do not scaffold for a future requirement.

## 2. Follow the project, not a generic template

The plan cites real paths as evidence. A claim without a path is an assumption.

Read before you write:

- Every `CLAUDE.md` in the affected directories, and the repository root `CLAUDE.md`.
- `.claude/rules/` when the directory exists.
- Two or three existing files of the same kind as the files you plan to add.
- The dependency manifest, to learn which libraries the project already uses.
- The documentation of each library that the change touches. Follow the library's own idiom.

## 3. Strong typing is mandatory

The plan declares the concrete types before implementation starts. It names each type, each
field, and each field type.

Forbidden unless the plan states why no type is possible:

- `dict[str, str]`, `dict[str, Any]`, `Dict`, or a bare `object` for structured data.
- `Any`, `unknown`, or `any` in a signature.
- A plain `str` where an enum or a literal union describes the real values.
- A cast that only silences the type checker.

Required instead: a dataclass, a Pydantic model, a `TypedDict` with real field types, a
protocol, an enum, or the equivalent in the project's language.

**A type checker that passes does not prove the typing is good.** An agent can satisfy a
checker with `Any`. The plan must show the type declarations, and the reviewer must read
them.

## 4. Validate data at the API boundary

An endpoint validates its input with the framework's own validator, such as a Pydantic model,
a serializer, or a Zod schema. Do not hand-write `if` checks that duplicate a validator.
Do not trust a request body that no schema describes.

Validate at the trust boundary only. Do not re-validate the same data between internal
functions.

## 5. No escape hatches without a reason

Do not add `# noqa`, `# type: ignore`, `eslint-disable`, or `@ts-expect-error`. If one is
unavoidable, the plan names the line, names the rule, and states the reason. The reason goes
in a comment on the same line in the code.

## 6. Comments explain why, not what

Write no comment by default. Add a comment only when the code cannot show the reason: a
hidden constraint, a non-obvious invariant, or a workaround for a specific bug. Delete any
comment that repeats the code.

## 7. Edge cases are listed, not implemented

The plan lists edge cases, race conditions, and failure modes in a table. Each row carries a
decision:

| Decision | Meaning |
|---|---|
| Cover now | The implementation handles it. It gets a test. |
| Fail loudly | The code raises or logs a clear error. It gets no recovery logic. |
| Out of scope | The plan records it. This change ignores it. |

Only `Cover now` rows reach the implementation. A plan where every row is `Cover now` is not
a simple plan.

## 8. Tests come first, and stay small

One test per `Cover now` row, plus one test for the main success path. Write the test list
before the code. No test suite beyond that list.

## 9. Touch only the code the task needs

The diff contains the task and nothing else. An unrelated change hides the real change from
the reviewer.

Do not do any of these while you implement the task:

- Refactor code that the task does not require you to change.
- Rename a symbol, move a file, or reorder imports outside the task.
- Reformat a file, or fix whitespace the task did not touch.
- Fix a bug you found on the way, unless it blocks the task.
- Update a dependency the task does not need.

When you believe a nearby piece of logic needs work — it is already large, it is complex, or
it carries a real defect — **stop and ask the user first**. Describe what you found, name the
path, and propose the change. Wait for a decision. Do not start.

When the user says no, record the finding in the plan's `## Non-goals` section so the work is
not lost.

## 10. Mock only the outermost call to an external service

A test runs the real code of this project. It mocks only the last call that leaves the
process: an HTTP request, a message-broker publish, a third-party SDK call, or the clock.
Services, repositories, dispatchers, clients, and helpers of this project run for real. A
test that replaces an inner collaborator with a mock does not break when that collaborator
changes, so it hides the regression it exists to catch.

Allowed mock targets:

- The HTTP call itself, such as `httpx.AsyncClient.post` or `requests.Session.request`.
- The broker enqueue, such as `some_task.delay` or `apply_async`.
- The SDK call, such as `stripe.Refund.create` or `boto3` client methods.
- The clock, such as `freezegun` or `django.utils.timezone.now`.

Forbidden mock targets, unless the plan states why the real one cannot run:

- A service, repository, dispatcher, or client class of this project, replaced by `MagicMock()`.
- A method of a model or service of this project, such as `Order.issue_refund`.
- A whole HTTP client class, such as `patch("module.httpx.AsyncClient")`, when patching the
  single request method is enough.

Examples:

```python
# Wrong: the dispatcher is this project's code. A broken dispatcher still passes.
dispatcher = MagicMock()
service = InvoiceService(..., supplybuy_invoice_link_dispatcher=dispatcher)
service.persist(order)
dispatcher.enqueue_invoice_link.assert_called_once()

# Right: the real dispatcher runs. Only the broker publish is mocked.
delay = mocker.patch("apps.billing.tasks.deliver_b2b_invoice_link_task.delay")
service = InvoiceService(..., supplybuy_invoice_link_dispatcher=SupplyBuyInvoiceLinkCeleryDispatcher())
service.persist(order)
delay.assert_called_once_with({"order_number": order.order_number, ...})
```

```python
# Wrong: the client and the repository are mocks, so the URL, the headers, the payload,
# and the database lookup are never exercised.
client = MagicMock(); client.link_invoice = AsyncMock(return_value=True)
deliver(payload, client, MagicMock())

# Right: the real client and repository run. Only the HTTP request is mocked.
post = mocker.patch.object(httpx.AsyncClient, "post", AsyncMock(return_value=response))
deliver(payload, SupplyBuyClient(base_url=URL, token=TOKEN), InvoiceRepository())
assert post.call_args.kwargs["json"] == {"fb_wholesale_id": 10042, ...}
```

```python
# Wrong: the model method is this project's code.
@patch("dashboard.models.BusinessCustomerOrder.issue_stripe_refund")

# Right: mock the Stripe SDK call that the method makes.
@patch("dashboard.models.stripe.Refund.create")
```

When many tests build the same service, give the builder the real collaborator and put the
outermost mock in one shared fixture. A spy on an internal method, such as asserting that
`save()` was not called, is also an implementation detail. Assert the observable result
instead.
