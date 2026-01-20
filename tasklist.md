1) Correctness improvements (so it stops “obviously bad” moves)
A. Add a “Dead-on-placement” veto (stronger than your current veto set)

Right now you veto:

inside opponent fort (good)

one-move-from-encirclement (good)

danger zone (good)

But the bad move you showed is typically caught by:

Veto 0: No-edge-reach after placement

If the placed stone’s connected empty-space reachability to the board edge is 0, veto unless it immediately captures or creates an escape path.

This is simpler and more general than danger-zone heuristics, and it catches “placing inside sealed pocket” instantly.

Exception list (allow anyway):

Move causes immediate capture / completes encirclement

Move connects to an existing friendly region that has edge reach

Move increases edge exits of that region (escape creation)

B. Don’t use “liberties” as a major signal (rename + align with Faux Go)

Your _evaluateLiberties is still Go-ish. In Faux Go, adjacent empties are weak compared to edge-reachability.

Replace/augment:

Local empties (cheap): keep as a minor tiebreaker

Edge exits / edge reach (important): count number of distinct edge paths / exits

If you keep liberties at 2×, it may bias toward moves like “inside pocket but with adjacent empties”, which is exactly the kind of trap you want to avoid.

2) Performance: why it’s slow at level 5

Your expensive parts are:

_isOneMoveFromEncirclement: for each candidate, simulate move, find region, find gaps, then for each gap simulate opponent and run capture logic. That’s a nested simulation.

_evaluateEncirclementProgress: “for each opponent stone group” per candidate is huge on 48×48.

_evaluateCaptureBlockingMove: iterating “for each empty adjacent to AI stones” with opponent simulation can balloon.

So yes: you must restrict the candidate set and reuse computations.

3) The single biggest speed win: Candidate move filtering
✅ Only consider “frontier” moves

Instead of “all empty intersections”, generate candidates from:

All empty cells within radius 2 of any stone (black or white)

All empty cells that are boundary gaps of endangered regions (yours and opponent’s)

Optionally, a small random sample of far-away moves for low difficulty only

This reduces candidates from ~2300 empties down to maybe 80–300 midgame.

Practical rule:

Level 1–3: radius 1–2

Level 4–7: radius 2

Level 8–10: radius 2 + targeted “gap” candidates

Also add a fast duplicate suppression:

Use a boolean grid considered[x][y] (Uint8List) so you don’t add the same cell multiple times.

4) Second biggest speed win: Cache regions + edge reach per turn

A lot of your logic repeatedly flood-fills the same areas.

Cache these once per AI turn:

Connected groups for each color

For each group:

boundary empties

perimeter ratios

current edge-exit count / edge reachability

Enclosure map / forbidden interior map (precomputed “cannot play here”)

Then scoring a move becomes:

Local updates around pos

A small number of recomputations for affected regions only

Even a “coarse cache” gives huge gains.

5) Replace nested “simulate opponent at every gap” with a cheaper approximation

Your _isOneMoveFromEncirclement is correct but expensive.

Faster version (“critical gap test”)

Instead of simulating capture logic for every gap:

After placing the AI stone:

compute edge exits of that region

if exits >= 3 → return false early

if exits == 1 or 2 → only test those gap cells (1–2 sims)

run full capture sim only for those few gaps

This keeps correctness but avoids a ton of simulations.

6) Scoring simplification that speeds up a lot
A. Encirclement Progress should not loop “for each opponent group” per move

That is a killer.

Instead:

Only evaluate encirclement progress for opponent groups within radius 3–4 of the move

Or: only for opponent groups whose boundary includes pos (or adjacent to pos)

Because a move can’t meaningfully reduce exits of a far group.

B. Territory Control (5×5 scan) is fine, but consider:

Make it conditional:

Only compute territory control if the move is not already strongly scored by capture/defense
This is an easy early-exit optimization.

7) Difficulty scaling that also saves time

Instead of computing everything at every level:

Level-based feature gating

L1–2: only veto1 + simple scoring (capture, connection, center)

L3–5: add urgent defense + capture block

L6–8: add encirclement progress (local only)

L9–10: enable deeper checks + more candidate cells

Right now your level 5 is still paying for almost all expensive heuristics.

8) Concrete “Claude instructions” to implement performance upgrades

Copy/paste this:

Claude tasks

Implement candidate generation:

Build a set of empty positions within radius 2 of any existing stone.

Add boundary gap cells from endangered friendly regions.

Add boundary gap cells from opponent regions with low edge exits (attack targets).

Deduplicate with a Uint8List/bitset grid.

Precompute per-turn caches:

groupIdGridBlack, groupIdGridWhite

group metadata: stones, boundaryEmpties, edgeExitCount, opponentPerimeterRatio

forbiddenInsideOpponentFortGrid

Optimize _isOneMoveFromEncirclement:

Early return safe if edgeExitCount >= 3 after placement

Only simulate opponent placements at 1–2 critical gaps

Avoid running full capture sim for large gap sets

Localize _evaluateEncirclementProgress:

Only consider opponent groups adjacent (distance <= 4) to the candidate move

Or only groups whose boundary empties include pos or adjacent to pos

Add a hard veto:

deadOnPlacement: after placing, if region has 0 edge exits and move does not capture or create edge exits, veto.

Add profiling counters:

time spent per stage: candidateGen, veto, scoring, selection

candidate count before/after veto

number of flood-fills / capture sims

Goal: level 5 should evaluate <250 candidates and finish under a short frame budget in isolate.