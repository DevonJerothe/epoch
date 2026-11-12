# Epoch Implementation Order

**Status** — November 11, 2026. Companion to the [turn orchestration plan](turn-orchestration-plan.md). Ticket numbers refer to the Epoch team in Linear.
**Purpose** — What to pick up first, what can run in parallel, and which decisions constrain later work.

## 1. Summary

The path to the first playable slice runs through seven tickets in a fixed order. Everything else either feeds that path or can run beside it.

**Critical path** — EPO-24 → EPO-25 → EPO-27 → EPO-28 → EPO-30 → EPO-32 → EPO-35

EPO-14 is also on it, because EPO-25 cannot start until database access is off the main actor. EPO-35 is a gate: nothing in M3 starts until its measurements are recorded.

**Start now, in parallel**

| Ticket | Kind | Why now |
| --- | --- | --- |
| EPO-16 Decision API support | Code, in progress | Its changes are uncommitted on the current branch and block EPO-36 and EPO-38. |
| EPO-14 Database off the main actor | Code | Changes every repository signature. Every later ticket that touches the database or calls a repository builds on it. |
| EPO-13 CI for package and app tests | Tooling | AGENT.md forbids running tests or builds on the development machine unless asked, so CI is the only routine validation parallel work will get. |
| EPO-23 Ruleset v0 | Document | Decides formulas and combat action costs. EPO-28 implements it. |
| EPO-29 Starting world content | Document | Decides where templates and scene policy live, which EPO-24 must store. |
| EPO-24 v2 schema design | Document | Head of the critical path. Finalize after EPO-23 and EPO-29 report. |

## 2. Dependency map

An arrow means "must finish before". Tickets with no arrow between them can run at the same time.

```
EPO-16 ──────────────► EPO-36 ─────────────────────────────┐
   └──────────────────────────────────────────► EPO-38 (M3) │
EPO-23 ─┐                                                   │
EPO-29 ─┼► EPO-24 ─┐                                        │
        │          ├► EPO-25 ─┬► EPO-27 ─► EPO-28 ─┐        │
EPO-14 ─┼──────────┘          │                    ├► EPO-30 ─► EPO-32 ─┐
        │           EPO-26 ───┴► EPO-31 ───────────┘                    │
        ├► EPO-8 ──► EPO-33 ────────────────────────────────────────────┼► EPO-35 ─► M3 ─► M4
        │  EPO-29 follow-ups ──► EPO-34 (also needs EPO-30) ────────────┤
EPO-7 ──┴───────────────────────────────────────────────────────────────┘
```

EPO-26 has no hard predecessor. It reads the tool contracts from the plan and can start as soon as someone is free.

## 3. Waves

Each wave lists what can run concurrently. A lane is work one engineer or agent can own without colliding with another lane's files.

### Wave 0 — Decisions and groundwork

| Lane | Tickets | Files touched | Notes |
| --- | --- | --- | --- |
| A | EPO-16, then EPO-36 | `packages/EpochLLM` | Finish and merge EPO-16 first. EPO-36 edits the same README and request types. |
| B | EPO-14 | `epoch/DB`, `EpochApp.swift`, `epochTests` | One owner. Nothing else should edit `epoch/DB` until it merges. |
| C | EPO-13, EPO-12 | `.github`, docs | Independent of all app code. |
| D | EPO-23 | `docs/` | Document only. |
| E | EPO-29 | `docs/` | Document only. Produces follow-up tickets for seeding content. |
| F | EPO-24 | `docs/database.md` | Draft in parallel with D and E, finalize after both. |
| G | EPO-7 | Settings UI, Keychain, `ErrorManager` | Independent. Must be done before EPO-35 can run against a hosted model on a device. |

**Exit** — EPO-14 and EPO-16 merged, ruleset and schema documents agreed, CI running on pull requests.

### Wave 1 — Schema and types

| Lane | Tickets | Files touched | Notes |
| --- | --- | --- | --- |
| A | EPO-25 | `DatabaseMigrations.swift`, new records and models | Single owner of the v2 migration. |
| B | EPO-26 | New engine feature folder | Defines all twelve tool schemas and the result envelope. Uses a protocol for handle lookup so it does not wait on EPO-25. |
| C | EPO-8 | Story library and creation UI | Uses the async repositories from EPO-14. Split into library, creation, and resume children as its ticket says. |
| D | EPO-36 | `packages/EpochLLM` | If not finished in Wave 0. |

**Exit** — a fresh database migrates through v2, handles round-trip, and no malformed call can reach a handler.

### Wave 2 — Engine and read side

| Lane | Tickets | Files touched | Notes |
| --- | --- | --- | --- |
| A | EPO-27, then EPO-28 | Engine write path, command handlers | Sequential and on the critical path. Give it the strongest owner. |
| B | EPO-31 | Manifest builder, read tools | Read-only. Needs EPO-25 and EPO-26. |
| C | EPO-33 | Story feed and input screen | Build against saved `story_message` fixtures. Needs EPO-8 for navigation into a story. |
| D | EPO-29 follow-ups | Seed content, templates | Whatever EPO-29 decided. Must deliver a location, a guard, and a dagger for the slice. |
| E | EPO-41 (start) | Test fixtures | Begin the scripted provider and the seeded-generator fixtures here. Later suites reuse them. |

**Exit** — Milestone 1 deliverable: with a fixed seed, take, equip, and attack give the same state after a reload, with no model involved.

### Wave 3 — Orchestrator and the playable slice

| Lane | Tickets | Files touched | Notes |
| --- | --- | --- | --- |
| A | EPO-30, then EPO-32 | Turn actor, finalization, recovery | EPO-30 can start against the scripted adapter as soon as EPO-27 lands, before EPO-28 is finished. |
| B | EPO-34 | Opening scene | Needs EPO-30 and the seeded content. |
| C | EPO-33 (finish) | Feed UI | Wire outcome lines and progress to the live orchestrator. |
| D | EPO-35 | Measurement | Last. Needs everything above plus EPO-7. |

**Exit** — Milestone 2 deliverable and the EPO-35 gate decisions recorded.

### Wave 4 — M3: entities, decisions, remaining tools

Starts only after EPO-35. Split EPO-39 into one ticket per tool before the wave begins.

| Lane | Tickets | Notes |
| --- | --- | --- |
| A | EPO-37 `introduce_entity` | Depends on templates and scene policy from the EPO-29 follow-ups. |
| B | EPO-38 decision adapter | Context selection and audit are independent. The difficulty role needs `attempt_skill_check` from lane C. |
| C | EPO-39: skill and social checks | Coordinate with lane B on the difficulty hook. |
| D | EPO-39: explore, object interaction | Share exits and object state. Keep them with one owner. |
| E | EPO-39: trade | Independent. |
| F | EPO-39: remaining inventory and combat verbs, `record_fact` | Extends the Wave 2 handlers. |

Every lane adds a handler to the same registry and dispatch code. Agree a one-file-per-tool layout in EPO-26 so these lanes do not edit the same file.

### Wave 5 — M4: memory, evaluation, release

| Lane | Tickets | Notes |
| --- | --- | --- |
| A | EPO-40 memory retrieval | Reads `game_event` and `lore_item`. Can start once event payloads stop changing. |
| B | EPO-41 scenario and fault suites | Finishes the suites started in Wave 2 and adds the hosted-model regression run. |
| C | EPO-42 playtests and thresholds | Last. Needs a build with all of the above. |

## 4. Callouts

### Decisions that constrain later work

| Decision | Made in | What it locks |
| --- | --- | --- |
| Combat action costs, and whether one input can span an enemy response | EPO-23 | The `combat_action` contract, the encounter tables in EPO-24, and whether worked turn C is legal as written. Do not start EPO-28 without it. |
| Where templates and scene policy are stored | EPO-29 | Tables in EPO-24 and the whole of EPO-37. If EPO-29 slips, EPO-24 has to guess. |
| The v2 schema | EPO-24, EPO-25 | `docs/database.md` says a migration is never edited once released. While development builds use fresh databases, v2 can still be amended. Agree the point at which it freezes, for example the first build that leaves the development machine, and use v3 after that. |
| Handle format | EPO-25 | Handles appear in transcripts and events and never change. Pick the format once. |
| Tool names, schemas, and order | EPO-26 | They form the cached prompt prefix and the regression fixtures. Define all twelve in EPO-26, even though only three have handlers until M3, so the list does not change shape later. Unimplemented tools are hidden through `allowed_tools` (EPO-36) or return a fixed rejection. |
| Event payload shapes | EPO-27, EPO-28 | Outcome lines, recovery, the narration audit, and memory all read them. Version the payloads from the start. |
| Whether ordered batches stay on, and the default decision provider | EPO-35 | The orchestrator's default mode and all of EPO-38. This is why M3 waits for it. |

### Hazards for parallel work

- **EPO-14 lands first.** It makes every repository call async. Anything written against the current synchronous API will need rework, including EPO-8 and EPO-33.
- **One owner for `DatabaseMigrations.swift`.** Two branches adding to v2 will conflict and can produce different schemas under the same migration name.
- **EPO-16 is uncommitted.** The Decision API work exists only in the working tree of `epo-16-add-decision-api-support-to-epochllm`. Commit and merge it before anyone branches for EPO-36 or EPO-38.
- **The plan documents are uncommitted too.** Tickets cite `docs/turn-orchestration-plan.md`. Commit both documents before handing tickets to anyone who works from a fresh checkout.
- **Validation depends on CI.** AGENT.md says not to run tests or builds locally unless asked. Until EPO-13 is done, parallel branches merge unverified. Several tickets also require device evidence (EPO-14, EPO-32, EPO-35), which no agent can produce.
- **New Swift files do not conflict in the Xcode project.** The project uses file-system synchronized groups, so adding files under `epoch/` needs no project file edit.
- **EPO-12 conflicts with this document as drafted.** It describes one implementation issue in progress at a time. If several agents or engineers work in parallel, change that rule to one issue per person or agent, each on its own branch.

### Gaps in the ticket set

- **EPO-21, EPO-22 and their children have no project milestone.** The existing "Playable game loop" milestone lists full combat as follow-up work. Add a milestone or a second project for M3 and M4.
- **EPO-39 is one ticket for six tools.** Split it before Wave 4.
- **EPO-29's follow-ups do not exist yet.** They are on the path to EPO-34 and EPO-37 and will appear only when EPO-29 closes.
- **EPO-33 has no design reference.** The feed is the main screen of the game. Check DESIGN.md covers outcome lines, progress, and suggested actions before it starts, and extend DESIGN.md first if it does not.

### Unverified assumptions

These come from the plan and have not been measured. EPO-35 tests them.

- Ordered batches cut "take, equip, attack" from four model requests to two.
- A fixed tool list yields a useful prompt-cache hit rate.
- The model returns multiple tool calls in the intended order. OpenAI's guide does not promise this.

If the third fails for the chosen model, the orchestrator falls back to one call per response. EPO-30 requires that path to work, so the fallback costs latency and no rework.

## 5. Suggested staffing

With one engineer and several agents, a workable split is:

- **Engineer** — the decisions (EPO-23, EPO-24, EPO-29), review of every merge, and all device validation.
- **Agent 1** — critical path code: EPO-14, EPO-25, EPO-27, EPO-28, EPO-30, EPO-32, in order.
- **Agent 2** — `EpochLLM` and tooling: EPO-16, EPO-36, EPO-13, EPO-12, then EPO-41 fixtures.
- **Agent 3** — app surfaces: EPO-7, EPO-8, EPO-33, EPO-34.
- **Agent 4, from Wave 1** — EPO-26, EPO-31, then M3 tool lanes.

The engineer is the constraint in Wave 0. No code on the critical path past EPO-14 can start until the ruleset and schema documents are agreed.
