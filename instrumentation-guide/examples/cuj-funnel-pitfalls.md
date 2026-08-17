# Two ways a CUJ funnel comes out silently empty

Both of these were hit for real while building the checkout funnel in
[Step 19](../INSTRUMENTATION_GUIDE.md#19-turn-crashes-and-journeys-into-workflows-and-dashboards).
Neither produces an error — the workflow deploys, reports LIVE, and charts nothing. That's the
dangerous part: a funnel at 0% conversion looks like a *product* problem, not a config problem,
and teams have burned days on that confusion during a POC.

## 1. The step name you were given is a category, not a screen

The journey was described to me as `ProductDetail → Cart → CheckoutGuest → CheckoutSignIn →
Payment → Confirmation`. Five of those six are real screens. `Payment` is not — the app actually
emits `PaymentCard`, `PaymentApplePay`, `PaymentAndroidPay`, `PaymentPayPal`, and `PaymentFailed`.
A matcher on `_screen_name == "Payment"` matches nothing, forever, and every step downstream of
it reports zero.

**Catch it before deploying** by listing what the app really emits, rather than trusting the
names in the journey description:

```bash
# Android
grep -rhoE 'screenName *= *"[^"]*"|logScreenView\("[^"]*"\)' --include=*.kt app/src/main | sort -u
```

Or read them off live traffic with `bd tail`. Then make the step an `or_matcher` over the real
variants — the funnel step is "reached payment by any method," which is what you actually meant:

```json
{ "and_matcher": { "matchers": [
  { "or_matcher": { "matchers": [
    { "base_matcher": { "log_field": "_screen_name", "operator": "EQUAL", "string_value": "PaymentCard" } },
    { "base_matcher": { "log_field": "_screen_name", "operator": "EQUAL", "string_value": "PaymentApplePay" } },
    { "base_matcher": { "log_field": "_screen_name", "operator": "EQUAL", "string_value": "PaymentAndroidPay" } },
    { "base_matcher": { "log_field": "_screen_name", "operator": "EQUAL", "string_value": "PaymentPayPal" } }
  ] } }
] } }
```

The same reasoning applies to `CheckoutGuest` / `CheckoutSignIn`: those are **mutually exclusive
branches**, so a strictly linear funnel listing both in sequence can never complete. Collapse them
into one "entered checkout" step with an `or_matcher` — otherwise you've built a funnel that
measures nothing but is entirely plausible-looking.

## 2. `or_matcher` at the root of `generic_match`

This is accepted by the API and deploys clean, but the workflow page fails to render in the UI:

```json
"generic_match": { "or_matcher": { "matchers": [ ... ] } }
```

Always keep `and_matcher` at the root and nest `or_matcher` inside it, as in the snippet above —
even when there's only one condition. Wrapping a single `or_matcher` in a one-element
`and_matcher` costs nothing and keeps the chart viewable.

## The general lesson

Deployed ≠ working. After deploying any funnel, confirm the *deployed* matchers are what you
intended and that data is actually arriving:

```bash
# What screen names did the platform actually accept?
bd workflow describe <ID> -o json \
  --jq '[.workflow.flows[0].steps[].match_rule.ootb_match.generic_match.and_matcher.matchers[0]
         | (.or_matcher.matchers[]?.base_matcher.string_value // .base_matcher.string_value)] | join(" | ")'

# Is anything landing?
bd workflow charts <ID> --last 1h
```

If the first command prints a name your app never emits, you found it. This is the same class of
failure as the empty-`issue_match` drift described in
[crash-workflow-bdrl-examples.md](crash-workflow-bdrl-examples.md) — verify the deployed
definition, not just the deployed state.
