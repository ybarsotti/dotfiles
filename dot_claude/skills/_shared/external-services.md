# External services sit behind an adapter

An external service is any system the code calls over a network or through a vendor SDK: an
LLM or a classifier, a payment or email provider, a CRM, a search engine, another company's
API. Its name, its SDK types and its error codes stay inside one adapter. The domain code
calls a method named for the domain task, such as `categorize(email)`, never `jev.request(...)`.

This rule is an exception to "no abstraction with one implementation": the vendor can change,
and its SDK must not leak into the domain. It never justifies a second layer on top of the
adapter.

## The two shapes

Choose one shape for each external service, and write the reason in the plan.

| Shape | What it is | Choose it when |
|---|---|---|
| **A. One adapter class** | One class owns everything vendor-specific: the client, the auth, the request, the response mapping, the errors. The domain imports this class and calls its domain-named methods. | One vendor is the only real option today. A switch would replace the class body, not run two vendors side by side. This is the default. |
| **B. Port and injected implementation** | The domain defines a small interface (a `Protocol` in Python, an `interface` in TypeScript) with the domain-named methods. The vendor class implements it. The composition root (settings, DI container, factory) chooses the class and injects it. | A second vendor is planned or likely soon, the choice depends on configuration or a feature flag, two vendors run at the same time (fallback, A/B), or the domain tests need an in-memory fake. |

Move from A to B when a second vendor becomes real. The domain code does not change, because
it already calls domain-named methods.

## Rules for both shapes

1. Domain types go in and come out. No vendor SDK type, response dict or error class crosses
   the adapter.
2. The adapter maps vendor errors to two neutral errors that carry the retry decision:
   - transient (timeout, no answer, 5xx, 429): the caller retries;
   - permanent (the vendor refused, or sent a malformed answer): the caller records the
     result and stops.
   The domain never reads HTTP status codes. The adapter sets a timeout, logs the vendor call
   with its context, and never returns a success result after a vendor failure.
3. Vendor configuration (keys, model names, endpoints, prompt and prompt version) lives in
   settings or in the adapter, and reaches only the adapter. The result names the model or
   version that produced it, so a stored result stays traceable.
4. Product rules stay in the domain service, not in the adapter: thresholds, which labels lead
   to which action, fallbacks. A new vendor must not change a product rule by accident.
5. The data that may leave the system is part of the port contract: the fields sent, their
   limits, and the fields never sent (personal data, addresses, files). A test proves it, and
   every future implementation must pass it.
6. One adapter per external service, in the module that owns the integration, for example
   `integrations/<vendor>/` or the project's existing place for clients.
7. Tests:
   - The adapter's tests mock only the outermost call: HTTP or the SDK client.
   - Shape A: the domain tests mock the outermost call the same way, or use the project's
     existing fake client.
   - Shape B: the domain tests may inject an in-memory fake of the port. That fake implements
     the port; it never patches the domain code.

## In a plan

The plan names each external service the change calls, the shape (A or B), the reason, the
adapter's place, and its domain-named methods.

## In a review

Flag as MEDIUM:

- Domain code that calls a vendor SDK or a vendor URL directly.
- A vendor name in a domain class, method or variable.
- A vendor type or a vendor error that crosses into the domain.

Flag as LOW: shape B with no reason that the table above accepts. Shape A is then enough.
