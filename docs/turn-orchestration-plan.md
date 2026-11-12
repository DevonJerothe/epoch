# Epoch Turn Orchestration Plan

**Status** — Final draft for review, November 11, 2026. Supersedes the initial proposal of the same date.
**Scope** — The iOS turn-based text RPG, from player input through committed game state and narration.
**First playable slice** — Resolve a visible target, pick up and equip a weapon, resolve an attack, then reload the save and recover the same outcome.

## 0. What changed from the initial proposal

The core of the first proposal stands: the engine is the only authority on what happened, every mutation commits with its events and receipt in one transaction, and the model sees a result before it narrates it. The changes below come from checking the proposal against the current repository and the provider documentation.

| # | Change | Reason |
| --- | --- | --- |
| 1 | The tool list is fixed per request. The decision provider selects context to preload, and may narrow tools only through `allowed_tools`. | OpenAI's prompt cache covers tool definitions and their order, so changing the list per turn defeats caching on every request. Gating 13 tools saves few tokens and adds a serial network hop. The widening fallback is no longer needed. |
| 2 | The decision provider gets three engine-side jobs: context selection, difficulty scoring for improvised skill checks, and narration auditing. | The first proposal had no source of difficulty for an unauthored action, and no concrete way to verify narration. Probability answers suit both. |
| 3 | The orchestrator accepts an ordered batch of tool calls in one response and halts at the first step that is not `applied`. | Strict one-call-per-response costs four model round trips for "take, equip, attack". Item IDs are stable across transfers in Epoch's schema, so later steps do not need IDs from earlier results. |
| 4 | Jev is reached through TypeSafe's own API or OpenRouter. `jevmodel.org` is removed. | Its documentation states it is independent and not affiliated with TypeSafe. The eight-question limit was that site's validator, so the two-batch workaround is dropped. |
| 5 | A schema section (§6) lists what `v2` must add before any command can run. | The current schema cannot place an item in a location, has no NPC health, exits, encounters, aliases, or world revision. |
| 6 | `create_character` becomes `introduce_entity`, covering NPCs, items, and objects. | The narrator will describe props the database has never seen. The first proposal only handled that for NPCs. |
| 7 | Plain conversation is no longer a tool call. A `record_fact` tool persists facts the narrator establishes. | The engine cannot author an NPC's reply, so `talk` was a round trip with no rule to apply. Disclosed facts had no path into storage. |
| 8 | Lookup receipts, the pending-clarification record, durable runner ownership, and the stale-state retry loop are removed. | Epoch is a single-process app with a serialized `DatabaseQueue`. The engine rechecks identity inside the write transaction anyway. |
| 9 | Model-facing IDs are short per-story handles, not UUIDs. | Thirty-six-character UUIDs cost tokens in every manifest and are easy for a model to corrupt. |
| 10 | A Milestone 0 fixes the ruleset and schema. Hosted-model latency is measured in Milestone 2. | The engine has no rules to implement yet, and routing should be justified by a baseline before it is built. |
| 11 | Provider credentials are an open decision, not a stated property. | The first proposal said keys stay server-side. Epoch has no server and `EpochLLM` takes keys on the device. |

## 1. Architecture and ownership

Epoch stores game state in GRDB (`Documents/epoch.sqlite`, GRDB 7.11.1, serialized `DatabaseQueue`). A story is the unit the first proposal called a campaign. The narrative LLM interprets the player's language, requests actions, and narrates engine results. The decision provider answers narrow classification questions for the orchestrator and engine.

| Component | Responsibilities |
| --- | --- |
| iOS game UI | Submit input, show committed outcomes and narration, show suggested actions, offer resume after an interruption. |
| Turn orchestrator | One actor per story. Owns the active turn, builds the manifest and model request, validates tool protocol, sequences actions, and finalizes the transcript. |
| Decision provider | Answers context, difficulty, and audit questions with probabilities. Never returns commands or IDs. Play continues without it. |
| Narrative LLM | Resolves names, aliases, and pronouns against the manifest. Chooses tool calls, reads results, then continues, asks, or narrates. |
| Game engine | Validates typed commands and computes outcomes. Owns rolls, action costs, enemy responses, derived effects, and every write. Runs off the main actor. |
| GRDB storage | World state, events, turns, action receipts, transcript. |

**Data flow** — Player → orchestrator → manifest and context load (decision provider in parallel) → narrative LLM → tool adapter → engine and GRDB → result → narrative LLM. The last four stages repeat. The orchestrator stores final narration and hands it to the UI.

**Authority rule.** An NPC introduction, item award, damage total, quest change, or state change needs an engine result before the model may describe it as fact. Ambient prose may add colour within established scene facts. If prose mentions a prop the player later acts on, the prop is materialized through `introduce_entity` (§3) before any action touches it.

**Threading.** `DBManager` is `@MainActor` and its `read`/`write` are synchronous. Engine transactions must not run there. The engine needs a nonisolated path to the same `DatabaseQueue` (GRDB's async `read`/`write`), with the turn actor awaiting it.

## 2. Turn pipeline

1. **Accept input.** Insert the player's `story_message` and a `turn` row in one write. The turn actor serializes turns per story. If the latest turn for the story is not `closed`, resume it (§7) before accepting new input.
2. **Load context.** Build the scene manifest (§3). In parallel, ask the decision provider which optional context slices apply (§4) under a short timeout. On timeout or error, load the default slices for the current mode.
3. **Build the request.** Stable prefix first: instructions, then the full tool list in fixed order. Then the manifest, selected slices, recent dialogue, and the player input. Set `parallelToolCalls: true` and constrain tools by mode with `allowed_tools` where the provider supports it.
4. **Read the response.** Act only on an `isComplete` response. It contains tool calls, or text. Text preceding tool calls in the same response is discarded, not shown.
5. **Execute calls in order.** For each call: decode into a typed command, write a pending action slot, then run the engine transaction. Stop at the first call whose status is not `applied`. Every remaining call receives the result `skipped` with the reason, because the Responses API expects an output for each call.
6. **Continue.** Append the response items and all results, refresh changed manifest facts, and send again. Repeat until the model returns text or a budget is reached.
7. **Finalize.** Save the narration as the bot `story_message`, attach mechanical outcomes from receipts (§5), write suggested next actions as `story_message_action` rows, and close the turn.

**Ordered batch rule.** Calls execute strictly in response order, one transaction each. `resolved_failure` halts the batch as well as `rejected`: a missed attack is a real outcome, and the model should see it before deciding anything else. For "if the door opens, go inside", a failed open halts before the move. For "take it, equip it, attack", a blocked slot halts before the attack. Reads may appear in a batch and never halt it. If a provider or model returns calls one at a time, the same loop handles it with no change.

**Partial completion.** Each applied action stays committed. If take succeeds and equip fails, the player keeps the item, and narration says where the sequence stopped.

**Clarification.** A clarifying question is an ordinary final response and closes the turn with no state change. The player's answer is a new turn, and the question is in its recent dialogue. No pending-action record is kept. The engine validates the eventual command against current state like any other.

**Streaming.** Buffer output until the response's first item type is known. Stream text to the UI only when the response contains no tool calls. Otherwise show a progress state.

## 3. Scene manifest, references, and entities

### Handles

The model never sees UUIDs. Each entity gets a short story-scoped handle at creation, such as `npc_7` or `item_12`, stored in an `entity_handle` table mapping handle to table and UUID. Handles are stable for the life of the story, so they remain valid in transcripts and events. The tool adapter translates handles to UUIDs and rejects unknown ones with `INVALID_TARGET`.

### Manifest

A bounded view of what the player perceives and already knows. Full records are fetched on demand.

```json
{
  "revision": 42,
  "mode": "exploration",
  "location": {"id": "loc_3", "name": "Ash Lantern"},
  "player": {"id": "pc_1", "health": "24/30", "equipped": [{"id": "item_2", "name": "short sword", "slot": "main_hand"}]},
  "visible": [
    {"id": "npc_7", "kind": "npc", "name": "Ilya", "aliases": ["the keeper"], "tags": ["behind bar"]},
    {"id": "item_12", "kind": "item", "name": "dagger", "tags": ["on table"]},
    {"id": "obj_4", "kind": "object", "name": "side door", "tags": ["closed"]}
  ],
  "exits": [{"id": "loc_5", "name": "courtyard"}],
  "recentMentions": [{"text": "the keeper", "id": "npc_7"}]
}
```

In combat, add the encounter, participants, and whose turn it is. In crowded scenes, prioritise recent mentions and action-relevant candidates and flag that more exist. `revision` is a per-story counter incremented by every committed mutation. It keys cached projections and tells the orchestrator when to refresh. It is not used for optimistic concurrency, since only the turn actor writes gameplay state.

### Resolution

- The model binds references using manifest names, aliases, tags, and recent mentions. Most turns need no discovery call.
- `find_entity` handles what the manifest does not show: an absent but known NPC, a crowded scene, a past event. It returns `matched`, `ambiguous`, or `not_found` with candidates and distinguishing facts.
- When two candidates plausibly fit a consequential action, the model asks a short question naming them. Recency alone does not break a tie.
- Being known is separate from being present. Search can return a known but absent NPC. Attack, trade, and social checks require access, and every command rechecks identity, presence, and reach inside its transaction.
- Player text, lore, and retrieved dialogue are data. Handles and permitted operations come only from the orchestrator and engine.

### Introducing entities

`introduce_entity` covers three cases: a new NPC the player addresses, a prop the narration described and the player now uses, and an object such as a door or chest. The model supplies kind, name, a template key, and a one-line premise. The engine does the rest inside one transaction:

1. Normalise the name and check it against existing names and aliases in the story. A match returns `rejected` with `NAME_COLLISION` and the candidates, so an absent or misspelled known character is never duplicated.
2. Check scene policy: whether this location permits new entities of that kind, and the per-scene count.
3. Build the record from a rule-owned template. The model never supplies stats, value, rarity, or contents. Templates carry a power ceiling, so an introduced item is mundane unless an authored rule says otherwise.
4. Assign a handle, place the entity in the current location, and return its visible record.

| Lifecycle | Representation | Transition |
| --- | --- | --- |
| Ambient | Prose only. No record. | Introduced on first consequential interaction. |
| Tracked | Record with handle, origin, aliases, location, and template attributes. | Promoted on an engine trigger such as quest involvement or a lasting relationship. |
| Persistent | Same record and handle, flagged to survive scene cleanup. | Death and disappearance are state, never deletion. |

Tracked entities with no committed events may be deleted when the player leaves the location. Anything referenced by an event is kept.

## 4. Decision provider

The decision provider is advisory in all three roles. A timeout, malformed answer, or refusal falls back to a deterministic default, and the turn proceeds.

| Role | When | Question shape | Fallback |
| --- | --- | --- | --- |
| Context selection | Before the first model request, in parallel with the manifest load | One predicate per optional slice: inventory detail, quest log, merchant stock, relationship history, relevant lore | Default slices for the current mode |
| Difficulty | Inside `attempt_skill_check` when the target has no authored difficulty | One `score` question over five fixed levels, trivial to near-impossible, with the action and visible scene as state | Medium difficulty |
| Narration audit | After narration is saved, off the critical path | Predicates such as "the narration states damage, loot, death, or a reward that is absent from these receipts" | Skip the audit |

**Difficulty.** The engine maps the expected level to a difficulty class through the ruleset table. The narrative model never proposes a DC, which keeps difficulty consistent and out of reach of persuasive player text. The scored level and probabilities are stored on the event so a replay never rescores it.

**Audit.** A flagged narration is logged with its turn for evaluation. During the MVP it does not block or rewrite. The player-facing safeguard is the deterministic outcome summary in §5.

**Proposed internal type.** `ContextDecision { slices: Set<ContextSlice>, providerStatus }`. The nine-domain table from the first proposal survives as the mapping from mode and slices to preloaded projections, not as a tool gate.

**Why tools are not gated.** OpenAI's caching guide lists tool names, schemas, and ordering as part of the cached prefix and advises keeping the list fixed, using `allowed_tools` or `tool_choice` to vary what is callable. A per-turn tool list therefore forfeits the cache discount on the largest stable part of every request, and the routing call sits serially in front of the model. With twelve tools the token saving is small. Revisit this only if Milestone 2's baseline shows tool confusion or prompt cost that routing would fix.

**Provider choice.** `EpochLLM` already supports OpenAI Decisions, OpenRouter Decisions, and TypeSafe's Jev API behind one request type. Pick the default from Milestone 2 latency measurements on device.

## 5. Tool contracts

Twelve definitions, all sent on every request in a fixed order. Four are reads. Signatures describe Epoch's types. `LLMToolParameters` renders them as strict schemas, with optional fields as required nullable properties. The host binds story, actor, and turn. The model supplies handles, enums, and bounded strings only.

| # | Tool | Input | Result and checks |
| --- | --- | --- | --- |
| 1 | `find_entity` | `reference`, optional `kind`, `scope: scene / known_world` | Status, candidate handles, distinguishing facts. |
| 2 | `get_entity` | `id`, `view: summary / interaction / stock` | Kind-specific visible fields and access status. Rejects views that do not apply. |
| 3 | `search_world` | `query`, `kind: npc / location / quest / event / lore`, optional `cursor` | Bounded player-known matches with source and next cursor. |
| 4 | `get_player_state` | `view: summary / inventory / skills / quests` | The selected slice with handles. |
| 5 | `introduce_entity` | `kind: npc / item / object`, `name`, `template`, `premise` | New handle and visible facts, or `NAME_COLLISION` with candidates. Engine applies scene policy and template limits. |
| 6 | `manage_inventory` | `verb: take / drop / give / equip / unequip / use`, `itemId`, optional `quantity`, `targetId`, `slot` | Holder, remaining quantity, slot, item effects. Validates reach, ownership, capacity, slot. The item handle does not change. |
| 7 | `combat_action` | `verb: attack / ability / defend / flee`, optional `targetId`, `weaponId`, `abilityId` | Roll and damage facts, statuses, resolved enemy actions, next phase. `weaponId` must be equipped. The engine never substitutes a weapon. |
| 8 | `explore` | `verb: move / search`, `targetId` | Arrival or discoveries, time cost, scene changes. Validates the exit and access. |
| 9 | `attempt_skill_check` | `skill`, `intent`, optional `targetId`, `approach` | Outcome, costs, visible consequences. Covers social approaches (persuade, deceive, intimidate) against an NPC. Difficulty comes from the target or §4. |
| 10 | `trade` | `verb: buy / sell`, `merchantId`, `itemId`, `quantity`, `expectedPrice` | Atomic exchange, currency delta, stock. A price that differs from `expectedPrice` returns `PRICE_CHANGED` with current terms and changes nothing. |
| 11 | `interact_with_object` | `verb: open / close / activate / unlock`, `objectId`, optional `itemId` | State change, revealed contents, trap or check result. |
| 12 | `record_fact` | `subjectId`, `text`, `category` | Stores a narrative fact as a `lore_item` linked to its subject. No mechanical effect. Bounded length and count per turn. |

Conversation without a check needs no tool: the model writes the NPC's reply as narration and calls `record_fact` for anything worth keeping. `get_scene_state` is dropped because the refreshed manifest already carries it. Quest acceptance and abandonment stay deferred until they have rules.

**Shared result.** `{ status, code, revision, facts, eventIds, nextOptions }`. Statuses are `applied`, `resolved_failure`, `rejected`, and `skipped`. A miss or failed lockpick is `resolved_failure` and commits its costs and events. A rejection such as `ITEM_NOT_EQUIPPED` or `INVALID_TARGET` changes no world state and names the recovery when one exists. `facts` holds only what the player may see. `nextOptions` feeds the suggested-action rows written at finalize.

**Outcome summary.** Each applied or failed action yields a short deterministic line built from its events, such as "Hit gate guard for 6" or "Took dagger". The UI shows these beside the narration. This is the guarantee against invented mechanics, and it doubles as the fallback when narration fails.

Deterministic consequences stay internal to the engine: advancing initiative, defeat checks, XP, quest objective progress, reputation. A public tool is added only for a distinct player choice with its own preconditions.

## 6. Schema additions (`v2` migration)

Development builds still use fresh databases, so this is a new named migration with no upgrade path for older saves to test.

| Gap in `v1` | Addition |
| --- | --- |
| An inventory row must be owned by a player or an NPC, so an item cannot sit in a room or a chest | Add `locationId` and `containerObjectId` as owners on `player_inventory`, with the check extended to exactly one of four |
| NPCs have `isAlive` and attributes but no health | `health` and `maxHealth` on `non_player_character` |
| Locations have only a parent hierarchy | `location_exit` (from, to, name, locked state) |
| No interactable objects | `world_object` (location, name, kind, state, lock, template) |
| No aliases, lifecycle, or origin | `entity_alias` table. `lifecycle` and `origin` columns on NPCs, items, and objects |
| No encounter state | `encounter` and `encounter_participant` (initiative order, current actor, phase) |
| No revision or turn counter | `revision` and `turnCount` on `story` |
| No handles | `entity_handle` (story, handle, table, record ID), unique per story |
| No turn, receipt, or event storage | `turn`, `turn_action`, `game_event` (§7) |
| No merchant stock or pricing | Merchant flag and price modifier on NPCs. Stock is the NPC's inventory |
| `MessageStatus` has no failure state | Add `failed` and `interrupted` |
| Free-text `attributes` and `effects` keys | Unchanged in storage. The ruleset (Milestone 0) defines which keys the engine reads |

Item definitions stay story-local and inventory stays one stack per holder and item, as documented in [database.md](database.md). Transferring an item moves or splits the stack row. The item's ID and handle never change.

## 7. Persistence and recovery

| Record | Contents | Purpose |
| --- | --- | --- |
| `turn` | Story, player message ID, bot message ID, status (`running`, `closed`, `failed`), step count | Ties a turn to its transcript rows and marks an interrupted turn |
| `turn_action` | Turn, step index, provider call ID, tool name, canonical arguments, status, result JSON, event IDs | One slot per dispatched call. Unique on turn and step index |
| `game_event` | Story, turn, action, sequence, type, typed payload, visibility | The record of what happened, including rolls and decision-scored difficulty |

The player's text and the narration live in `story_message`. `turn` references them and does not duplicate them.

**Transaction boundary.** Write the pending `turn_action` first. Then, in one `DatabaseQueue` write: load the slot, return its stored result if it is already complete, validate rules against current state, write the state delta, events, incremented revision, and completed slot. A rejection completes the slot without touching world state. Network calls and text generation happen outside any transaction. Nothing is acknowledged to the model or UI before commit.

**Randomness.** The engine draws from an injected generator. Rolls are stored on events, so replaying a completed slot returns the original result. Fixtures use a seeded generator.

**Concurrency.** The per-story turn actor is the only writer of gameplay state, and the queue is serialized. There is no cross-process contention to defend against. If Epoch later gains an extension or sync that writes gameplay state, revisit this.

**Recovery.** On opening a story whose latest turn is `running`, the turn is orphaned by definition, since no other process could be running it.

| Found state | Recovery |
| --- | --- |
| No actions, or only completed ones, and no narration | Rebuild a fresh model request from the player input, current manifest, and the completed actions listed as established facts. Continue the turn. |
| A pending action slot | Execute it through the normal transaction, which validates against current state. Then continue as above. |
| Narration save failed | Retry finalization from receipts. Never redispatch gameplay. |
| Model unavailable or budget exhausted | Close the turn with the outcome summary as the bot message and say where the sequence stopped. |

Recovery rebuilds the request from receipts and does not persist provider response items. `EpochLLM` is stateless with `store: false`, and encrypted reasoning items are only valid for the model that produced them, so a rebuilt request is simpler and survives a model or provider change.

**Memory.** Recent dialogue supplies short-term reference. Durable knowledge is `game_event` rows plus `lore_item` rows written by `record_fact`. Long-term summaries are a Milestone 4 projection built from events, linked to their sources, and never accepted as proof that a rule outcome occurred.

## 8. Worked turns

Round trips count narrative model requests. The first proposal's counts are given for comparison.

### A. Combat against a known target — 2 requests (was 2)

**Input** — "I slash the gate guard with my sword." The manifest shows `npc_3` and equipped `item_2`.

1. The model calls `combat_action(attack, targetId: npc_3, weaponId: item_2)`.
2. The engine validates weapon and initiative, resolves a hit for 6, advances initiative, and resolves the guard's counterattack for 2. All of it commits together.
3. The model narrates from the result. The UI shows "Hit gate guard for 6. Gate guard hit you for 2."

### B. Introduce a new NPC — 2 requests (was 5)

**Input** — "I approach Mason, the traveler sitting alone, and ask where he's from."

1. The model sees no Mason in the manifest and calls `introduce_entity(npc, "Mason", template: traveler, premise: "sitting alone")`. The engine finds no name or alias collision, applies the tavern's policy, and returns `npc_104`. Had a known Mason existed elsewhere, the result would be `NAME_COLLISION` and the model would ask which Mason is meant.
2. The model narrates Mason's reply and, in the same response or the next, calls `record_fact(npc_104, "Came down from Eastwatch over the pass", origin)`.

### C. Pick up, equip, then attack — 2 requests (was 4)

**Input** — "I grab the dagger from the table, equip it, then stab the guard."

1. The model returns three calls in order: `manage_inventory(take, item_12)`, `manage_inventory(equip, item_12, main_hand)`, `combat_action(attack, npc_3, weaponId: item_12)`.
2. The orchestrator runs them in order, one transaction each. Take and equip apply. The attack misses and commits as `resolved_failure`.
3. The model narrates all three results. The dagger stays equipped.

If the slot were blocked, equip returns `rejected`, the attack returns `skipped`, and the model tells the player the dagger is in their pack. The ruleset decides whether take and equip cost combat actions (§11).

### D. Ambiguous pronoun — 1 request, then 2

**Input** — "I give her the key." Ilya and Mara are both present and were both addressed.

1. The model asks, "Do you give the key to Ilya or Mara?" The turn closes with no state change.
2. The player says "Mara." The new turn's recent dialogue contains the question. The model calls `manage_inventory(give, item_9, quantity: 1, targetId: npc_8)`. The engine checks possession and Mara's presence. If she has left, the result is `rejected` and the key stays.

## 9. Latency and cost

- **Budgets.** Up to four model requests per turn and eight dispatched calls, with one correction per rejected step. The final allowed request has `tool_choice: none` so it must narrate.
- **Caching.** Keep instructions and tools byte-identical across turns and put all dynamic content after them. OpenAI's stated minimum cacheable prefix is 1,024 tokens for current models.
- **Decision calls.** Context selection runs in parallel with local loading and is abandoned at its timeout. Difficulty scoring is on the critical path of one tool only. Audit is off the critical path.
- **Measure** end-to-end p50 and p95, time to first committed outcome, model requests per turn, cached and uncached input tokens, and cost per turn, by scenario. Record the baseline in Milestone 2 before building anything in Milestone 3.
- **UI.** Show progress while actions resolve. Show outcome summary lines as each action commits, ahead of narration.

## 10. Milestones

Each checkbox is a candidate issue. Close it when its acceptance criterion is demonstrated.

### Milestone 0 — Ruleset and schema decisions

**Deliverable** — A written ruleset and an agreed `v2` migration.

- [ ] **Write ruleset v0.** Attribute keys, attack and damage formulas, weapon stats read from item `effects`, the five-level difficulty table, and combat action costs for take, equip, and defend. Acceptance — every formula the three slice commands need is specified with a worked example.
- [ ] **Agree the `v2` schema.** The additions in §6. Acceptance — `docs/database.md` updated and a dagger on a table, a guard with health, and an exit can all be represented.
- [ ] **Decide credential handling.** See §11. Acceptance — a recorded decision.

### Milestone 1 — Local engine and persistence

**Deliverable** — A provider-free turn resolves an action, persists the result, and reloads it.

- [ ] **Add the `v2` migration, handles, and nonisolated database access.** Acceptance — engine writes do not run on the main actor, and handles round-trip to UUIDs.
- [ ] **Define command and result types.** Acceptance — invalid enum values, missing fields, unknown tools, and unknown handles cannot reach a mutation handler.
- [ ] **Add turn, action, and event storage.** Acceptance — state, events, and receipt commit together, and an injected failure leaves the world unchanged.
- [ ] **Implement take, equip, and attack.** Acceptance — a fixed seed reproduces damage and enemy response, and invalid prerequisites leave gameplay state untouched.

### Milestone 2 — Orchestrator, manifest, and baseline

**Deliverable** — The first playable slice runs through the normal iOS input against a hosted model, with measured latency.

- [ ] **Build the orchestrator loop with ordered batches.** Acceptance — a scripted adapter's three-call response executes in order, a failed step skips the rest, and a replayed slot returns its stored result.
- [ ] **Build the manifest and four read tools.** Acceptance — names and aliases resolve, ambiguous references return candidates, and hidden or unreachable entities are never exposed.
- [ ] **Wire transcript, outcome summary, and recovery.** Acceptance — killing the app before commit, after commit, and during narration each restore correctly on reopen.
- [ ] **Record the baseline.** Acceptance — the four worked turns measured on device against the chosen model, with request counts, cache hit rate, latency, and cost.

### Milestone 3 — Entities, decisions, and remaining tools

**Deliverable** — All twelve tools work, with the decision provider in its three roles.

- [ ] **Implement `introduce_entity` and lifecycle.** Acceptance — two equivalent requests produce one identity, a collision returns candidates, and a template ceiling cannot be exceeded.
- [ ] **Implement the decision adapter.** Context selection, difficulty scoring, and audit, each with a timeout and fallback. Acceptance — every role degrades to its default when the provider is unreachable, and a scored difficulty is stable on replay.
- [ ] **Complete the remaining tools.** Skill and social checks, movement and search, trade, object interaction, `record_fact`. Acceptance — every verb has a passing case and at least one rejected precondition, and stock and currency move atomically.

### Milestone 4 — Memory, evaluation, and release

- [ ] **Build event-backed memory retrieval.** Acceptance — facts survive a restart, summaries link to source events, and a rebuild creates no duplicates.
- [ ] **Run the scenario and fault suites.** Acceptance — the matrix below passes against a scripted provider and is repeated against the hosted models.
- [ ] **Review real-device playtests.** Acceptance — release thresholds for cost, latency, and audit-flag rate are agreed and recorded.

### Evaluation matrix

| Test | What to assert |
| --- | --- |
| Four worked turns | Expected calls and order, exact handles, exact final state, request counts as in §8. |
| Pronouns, aliases, duplicate names, absent NPCs | Correct identity or a clarification. No incorrect writes and no duplicate entity. |
| Conditionals and dependencies | A failed open never moves the player. A failed equip skips its attack. |
| Decision provider outage | Every role falls back and the turn completes. |
| Crash injection | Kill before commit, after commit, and during narration. No duplicate effects, lost events, or rerolled outcomes. |
| Malformed calls and hidden state | Unknown tools, fake handles, and incomplete arguments never reach a mutation or disclose hidden facts. |
| Entity introduction limits | Requests for powerful items, forbidden locations, and over-count scenes are rejected by policy. |
| Narrator consistency | Audit-flag rate against a hand-labelled set of narrations. |
| Real-provider regression | Version the fixtures, model, prompts, and schemas. Track action order, clarification quality, p95 latency, and token cost. |

Release invariants: no duplicate writes, no mutation from an ambiguous reference, and no state change from a rejected or skipped call.

## 11. Risks and open decisions

| Risk or question | Decision needed |
| --- | --- |
| Provider credentials on the device | Epoch has no server. Either the player supplies their own key, stored in the Keychain, or Epoch gains a proxy that holds the keys. An embedded shared key can be extracted from the app and must not ship. |
| A batch does too much in combat | Ruleset v0 must say what take, equip, and defend cost, and whether a batch can span an enemy response. Until it does, the combat contract is not frozen. |
| The model orders a batch wrongly or misreads a condition | Halt-on-failure covers mechanical dependencies only. Evaluate ordering and conditional phrasing on fixtures, and fall back to one call per response for a model that fails them. |
| `introduce_entity` is used to conjure advantages | Template ceilings and scene policy are the control. Test with adversarial player input before enabling it outside authored locations. |
| World content at story creation | This plan assumes locations, exits, and starting entities exist. How a new story is populated (authored, generated, or both) needs its own plan. |
| Narration contradicts receipts | The outcome summary is always shown. Decide after playtests whether a high audit-flag rate justifies blocking or regenerating. |
| Models that ignore `allowed_tools` or return unordered calls via OpenRouter | The engine rejects mode-illegal commands regardless. Confirm call ordering per model in the regression suite. |

## 12. Provider details checked against documentation

Checked on November 11, 2026. Live behaviour still needs integration tests.

- **Jev.** TypeSafe's reference documents `POST https://api.typesafe.ai/v1/systemone` with `noul`, `choice`, `score`, and `box` questions and states no maximum question count. This is the endpoint `DecisionService.jev` already uses. `jevmodel.org` documents the same request shape but describes itself as independent and not affiliated with TypeSafe, and the eight-question limit is its own. Do not send game state or keys there. [TypeSafe System One API](https://docs.typesafe.ai/api)
- **OpenAI Decisions.** `POST /v1/decisions` is now generally available with `gpt-6-luna` as the only model, up to 400 questions, and `predicate`, `choice`, and `score` types. Input may be a string or an array of messages and tool items. The shared input prefix is cacheable from 1,024 tokens. The `EpochLLM` README still calls it a public beta. [OpenAI Decisions guide](https://developers.openai.com/api/docs/guides/decisions)
- **OpenAI function calling.** With `parallel_tool_calls: false` the guide promises zero or one call. With it enabled, a response may hold several, and the guide's examples return an output for each. The guide does not state that call order is guaranteed, so §11 lists ordering as a per-model check. Strict schemas need every property required, nullable types for optional values, and `additionalProperties: false`, which `LLMToolParameters` already renders. [OpenAI function calling guide](https://developers.openai.com/api/docs/guides/function-calling)
- **OpenAI prompt caching.** Tool definitions and ordering are part of the cached prefix. The guide advises a fixed tool list with `allowed_tools` or `tool_choice` to vary availability. `LLMRequest` has `toolChoice`. Whether `LLMToolChoice` can express `allowed_tools` needs checking. [OpenAI prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching)
- **GRDB.** 7.11.1 is pinned. `DatabaseQueue.write` wraps the closure in a transaction and rolls back on a thrown error, which is the boundary §7 relies on.

**Plan history** — Initial proposal November 11, 2026. This draft revises it after a review against the repository and provider documentation. Update this file as issues are linked and decisions are made.
