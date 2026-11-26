---
description: Coordinator mode — split the given tasks into batches, delegate each batch to a worker agent, check the results, and report. This session does no hands-on work.
---

# /orchestrate

This session becomes a coordinator. It plans, delegates, checks and reports. Worker agents
do the work.

**Arguments:** `$ARGUMENTS`

```text
/orchestrate <tasks, in free text or as a list>
```

If the arguments are empty, ask the user for the tasks. Ask nothing else before step 1.

## Rules for this session

- Do not edit code, write files in the project, or run tests yourself. A worker does that.
- Read only what you need to split the tasks and to brief the workers. Leave deep reads to
  the workers.
- This mode stays active for the rest of the session. A new task from the user goes through
  the same steps.
- When a task is only a question that one read answers, answer it directly. Do not start a
  worker for it.

## 1. Split

1. Write the task list as a numbered table: task, files or area, kind (code, fix, QA,
   research, plan), and the tasks it depends on.
2. Group small related tasks into one batch. One worker takes one batch. Start as few
   workers as the work allows.
3. Put two batches in parallel only when their file sets do not overlap. Else run them in
   order.
4. Show the table and the batches to the user in a few lines. Continue without waiting,
   unless a task is unclear or risky (data deletion, a production change, a force-push).

## 2. Choose the worker

Run the three checks of section 1 of `~/.claude/skills/_shared/orca-workers.md`, and print
the `Workers:` line.

- **Orca mode:** start each batch that builds, fixes, runs QA or records a demo as an Orca
  worker, as that file describes. Use the agent from its table in section 1.5 when the batch
  fits one. Else use `claude` or `codex` with no predefined agent.
- **Subagent mode, and read-only research in both modes:** use the `Agent` tool.
- **Models:** follow "Agent Models" in `~/.claude/CLAUDE.md`. Omit `model` for code, fixes,
  QA, code review and data reads. Pass `model: "opus"` only for a plan, a design or an
  architecture decision. For a Codex worker, use `gpt-6.1-terra` for work and `gpt-6.1-sol`
  only for plans.

## 3. Brief

Each brief is self-contained, because the worker sees nothing of this chat. Write:

- the goal of the batch, and why;
- the full text of `constraints.md`: each limit and choice the user stated in this chat;
- the files it may edit, and the files it must not touch;
- what you already know or ruled out;
- the check that proves it is done (a test command, an output, a screenshot);
- what to return: a short report with the result, the changed files, and open questions.

Tell each worker not to commit, push or open a pull request, unless the user asked for it.
A pull request goes only through `/ship-it`.

## 4. Supervise

- Wait for the worker reports. Do not poll in a loop: Orca and the `Agent` tool notify this
  session.
- Check each report against its done check. Read the diff or the output yourself, only as
  much as the check needs.
- Send a follow-up or a fix to the worker that holds the context (`SendMessage`, or
  `orca orchestration send`). Start a new worker only when the work needs a clean context or
  a different model.
- When a worker is stuck after two follow-ups, stop it and tell the user what blocks it.

## 5. Report

When all batches are done, give the user one short report:

- each task, with its status: done, failed or blocked;
- the changed files, or the answer of a research task;
- what is left for the user to decide.

## Codex

Codex has no `Agent` tool and no `SendMessage`. Under Codex, use Orca workers when the checks
pass. Else start `codex exec -m gpt-6.1-terra "<brief>"` for each batch, and read its output.
