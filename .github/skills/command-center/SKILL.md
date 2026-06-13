---
name: command-center
description: Agent fleet management dashboard. Shows active PRs and issues, lets you issue actions to Copilot agents wholesale (merge, rebase, review, assign, close). Use when user says "command center", "show me PRs", "fleet status", or wants to manage multiple agent PRs/issues at once.
---

# Command Center

Manage the fleet of Copilot coding agent PRs and issues from a single dashboard. Loop: show status → accept action → execute → refresh → repeat.

## Constants

```
COPILOT_BOT_NODE_ID = "BOT_kgDOC9w8XQ"
COPILOT_LOGIN = "Copilot"
```

## Invocation

When the user invokes `/command-center`, immediately run the **Dashboard** phase. Then loop on **Actions** until dismissed.

## Phase 1: Dashboard

Gather state and display a compact summary.

### Data collection

1. **Branch target**: Read `AGENTS.md` at the repo root. Look for a "Branch target" section to determine the active development branch. If not found, default to the repo's default branch.

2. **Open PRs**: Run `gh pr list --state open --json number,title,headRefName,baseRefName,isDraft,reviewDecision,mergeable,assignees,updatedAt`

   Group into:
   - 🔴 **Conflicts** — mergeable state indicates conflicts
   - 🟡 **Changes Requested** — reviewDecision = "CHANGES_REQUESTED"
   - 🟢 **Ready to Merge** — not draft, no conflicts, approved or no review required
   - 🔵 **In Progress** — draft or awaiting review

3. **Open Issues**: Run `gh issue list --state open --json number,title,labels,assignees,updatedAt`

   Group into:
   - ⚡ **Assigned to Copilot** — has Copilot in assignees
   - 🏷️ **Ready for Agent** — has `ready-for-agent` label but not assigned
   - 📋 **Other Open** — everything else

### Display format

```
═══ COMMAND CENTER ═══

📌 Branch target: feature/carom

── PRs ──────────────────────────────────
🔴 Conflicts (2):
   #54  Deepen Replay module             copilot/deepen-replay-module
   #55  Absorb ceremony into GameScreen  copilot/architecture-absorb-ceremony

🟡 Changes Requested (1):
   #54  Deepen Replay module             (2 issues: phantom frames, scrubbing)

🟢 Ready to Merge (0):

🔵 In Progress (1):
   #55  Absorb ceremony into GameScreen  [draft]

── Issues ───────────────────────────────
⚡ Assigned to Copilot (2):
   #48  Deepen Replay module
   #49  Absorb ceremony into GameScreen

📋 Other Open (2):
   #50  Extract pure Game Logic modules
   #24  feat: Carom — 3D arena ricochet game

── Quick Actions ────────────────────────
[1] Rebase all conflicted PRs
[2] Merge all ready PRs
[3] Review unreviewed PRs
[4] Assign issue to Copilot
[5] Close completed issues

What would you like to do? (pick a number or type a command)
```

A PR can appear in multiple groups (e.g., both Conflicts and Changes Requested). That's fine — show the most urgent grouping first.

### Auto-review

After displaying the dashboard, check for PRs with new commits since their last review. If found, silently kick off code-review agents in the background. Report findings inline in the dashboard on the NEXT refresh — do NOT post to GitHub without user approval.

Announce: "🔍 Reviewing N PRs with new changes..." if any are queued.

## Phase 2: Actions

Accept the user's command. Interpret it and execute. Common patterns:

### Merge

- "merge #56" / "merge all ready" / "2"
- Use `gh pr merge <number> --squash`
- After merge, close the associated issue if identifiable

### Rebase / retarget

- "rebase #54" / "rebase all conflicted" / "1"
- Post a comment: `@copilot This PR has merge conflicts with <branch>. Please rebase onto <branch> and resolve conflicts.`
- If the PR also has outstanding review issues, include those in the same comment.

### Review

- "review #54" / "review all" / "3"
- Launch code-review agents. Report findings inline.
- Ask user: "Post these findings to the PR?" before actually posting.

### Request changes

- "request changes on #54: fix the scrubbing"
- Post a `REQUEST_CHANGES` review via API with `@copilot` in the body.

### Approve

- "approve #57" / "approve all clean"
- Post approval review via `gh pr review <number> --approve`

### Assign to Copilot

- "assign #50 to copilot" / "4"
- Use GraphQL mutation:
  ```
  gh api graphql -f query='mutation { addAssigneesToAssignable(input: { assignableId: "<issue_node_id>", assigneeIds: ["BOT_kgDOC9w8XQ"] }) { assignable { ... on Issue { assignees(first: 5) { nodes { login } } } } } }'
  ```
- Also add `ready-for-agent` label if not present.
- If the issue lacks an agent brief, warn the user.

### Close

- "close #47" / "close completed issues"
- Use `gh issue close <number> --comment "Completed — merged in PR #<pr>."`

### Comment

- "tell #54 to rebase" / "nudge all stale PRs"
- Post `@copilot <message>` comment on the PR.

### Wholesale actions

When the user says "all" (e.g., "rebase all conflicted"), iterate over the matching group and apply the action to each. Confirm before executing if the group has more than 3 items.

## Phase 3: Refresh & Loop

After executing an action:
1. Wait 2-3 seconds for GitHub state to propagate
2. Re-fetch dashboard data
3. Display updated dashboard
4. Show results of the action just taken (e.g., "✅ Merged #56, closed #51")
5. Wait for next command

Exit when the user says "done", "exit", "quit", or invokes a different skill.

## Edge cases

- **PR not mergeable due to required checks**: Report which checks are pending/failing. Suggest "approve workflow runs" (note: can't be done via API for same-repo bot PRs — tell user to approve in GitHub UI).
- **Stale PRs**: If a Copilot PR hasn't been updated in >24h despite having requested changes, flag it as "⚠️ Stale — agent may need a nudge."
- **Branch target changes**: If `AGENTS.md` branch target changes, warn about PRs targeting the old branch.
- **Merge conflicts after merge**: When merging creates conflicts on other PRs, immediately flag them and offer to request rebases.
