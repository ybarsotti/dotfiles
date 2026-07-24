# Manual QA Plan — {{ plan.feature }}

- **Plan ID:** `{{ plan.plan_id }}`
- **Schema:** `{{ plan.schema_version }}`
- **Ticket:** {{ plan.ticket or "none" }}
- **Source plan:** `{{ plan.source_plan }}`

## Requirements coverage

| Requirement | Manual scenarios |
|---|---|
{% for requirement in plan.requirements -%}
| `{{ requirement.id }}` — {{ requirement.text }} | {% for scenario in plan.scenarios if requirement.id in scenario.requirement_ids %}`{{ scenario.id }}`{% if not loop.last %}, {% endif %}{% endfor %} |
{% endfor %}

## Personas

{% for persona in plan.personas -%}
- **{{ persona.name }}** (`{{ persona.id }}`): {{ persona.description }}
{% endfor %}

{% for scenario in plan.scenarios %}
## {{ scenario.id }} — {{ scenario.name }}

- **Persona:** `{{ scenario.persona_id }}`
- **Requirements:** {% for id in scenario.requirement_ids %}`{{ id }}`{% if not loop.last %}, {% endif %}{% endfor %}

### Preconditions

{% for item in scenario.preconditions -%}
- {{ item }}
{% endfor %}

### Test data

{% for item in scenario.test_data -%}
- {{ item }}
{% else -%}
- None.
{% endfor %}

### Steps

| Step | Screen | Action | Input | Expected | Evidence |
|---|---|---|---|---|---|
{% for step in scenario.steps -%}
| `{{ step.id }}` | {{ step.screen }} | {{ step.action }} | {{ step.input or "—" }} | {{ step.expected }} | screenshot={{ step.evidence.screenshot.value }}, video={{ step.evidence.video }}, console={{ step.evidence.console.value }}, network={{ step.evidence.network.value }} |
{% endfor %}

### Edge cases

{% for item in scenario.edge_cases -%}
- {{ item }}
{% endfor %}

### Acceptance rules

{% for item in scenario.acceptance_rules -%}
- {{ item }}
{% endfor %}
{% endfor %}
