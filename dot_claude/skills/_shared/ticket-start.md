# Ticket start — claim the Jira issue and move it to in progress

`jira-workflow`, `deep-plan` and `simple-plan` read this file when the work starts from a Jira
key. Run these steps once, before the plan or the branch work begins. Skip the file when no
ticket key is given.

1. Read the current user with `mcp__atlassian__atlassianUserInfo`. Keep its `account_id`.
   Read the `cloudId` once per session with `mcp__atlassian__getAccessibleAtlassianResources`.
2. Read the issue with `mcp__atlassian__getJiraIssue`. Keep the assignee and the status
   category of the current status.
3. When the assignee is not the current user, set the current user as the assignee with
   `mcp__atlassian__editJiraIssue` (`fields: {"assignee": {"accountId": "<account_id>"}}`).
4. Move the issue to the in-progress state:
   - Skip this step when the current status category key is already `indeterminate`.
   - Never move an issue backwards. When the status is in the done category, or its name
     reads as a review state (for example "In Review" or "Code Review"), do not transition.
     Tell the user the current status.
   - List the transitions with `mcp__atlassian__getTransitionsForJiraIssue`. Keep only the
     transitions whose target status category key is `indeterminate`.
   - Prefer the transition named "In Progress" or "Em andamento" (case-insensitive, trimmed).
     Otherwise take the first kept transition. When none is kept, ask the user which
     transition to apply.
   - Apply it with `mcp__atlassian__transitionJiraIssue`.
5. Report in one line: the assignee change, if any, and the transition name actually chosen.
   Example: `PROJ-123: assigned to you, "Start progress" → In Progress`.

When an Atlassian call fails, re-read the `cloudId` and retry once. Then report the exact
error and continue with the plan. The ticket state does not block the work.
