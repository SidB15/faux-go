# Simply GO - AI Engine Logic

This document describes the complete AI decision-making logic for the Simply GO (Faux Go) game.

---

## Overview

The AI uses a **3-step move selection process**:

1. **Hard Veto** - Reject moves that are clearly dangerous (before scoring)
2. **Score** - Evaluate all remaining candidate moves
3. **Select** - Choose the highest-scoring move (with randomization among equals)

The AI runs in an **isolate** (separate thread) to prevent ANR (Application Not Responding) on the main UI thread.

---

## Step 1: Hard Veto Rules

Before any move is scored, it must pass these veto checks. If a move fails any veto, it is **rejected immediately**.

### Veto 1: Inside Opponent's Fort
```dart
if (enclosure.owner != aiColor && enclosure.containsPosition(pos))
  → VETO: Cannot place inside opponent's enclosure
```

### Veto 2: One Move From Encirclement
```dart
if (_isOneMoveFromEncirclement(board, pos, aiColor, enclosures))
  → VETO: Position would leave AI trapped with only 1 move before capture
```

This check:
1. Places AI stone at position
2. Finds the connected region
3. Identifies boundary gaps (empty spaces adjacent to the region)
4. For each gap, simulates opponent placing there
5. If opponent placing at ANY single gap would capture AI stones → VETO

### Veto 3: In Danger Zone
```dart
if (_isInDangerZone(board, pos, aiColor))
  → VETO: Position is in an area with limited escape routes
```

Danger zone detection checks:
- **Edge exit count**: How many empty spaces connect this region to the board edge
- **Opponent perimeter ratio**: What percentage of the region's boundary is opponent stones
- **Critical gaps**: Chokepoints near edge exits that opponent could fill

**Thresholds:**
| Edge Exits | Opponent Perimeter | Critical Gaps | Result |
|------------|-------------------|---------------|--------|
| 0 | any | any | DANGER |
| 1-2 | ≥60% | any | DANGER |
| 3-4 | ≥40% | ≥ edge exits | DANGER |
| 5+ | any | any | SAFE |

---

## Step 2: Move Scoring

Each candidate move receives a score from multiple factors. Higher score = better move.

### Base Score Components

| Factor | Method | Weight | Description |
|--------|--------|--------|-------------|
| Strategic Position | `_evaluatePosition` | 1× | Board position quality |
| Liberties | `_evaluateLiberties` | 2× | Empty adjacent spaces |
| Connection | `_evaluateConnection` | 3× | Adjacent friendly stones |
| Territory Control | `_evaluateTerritoryControl` | 5× | Area ownership |
| Capture | `_evaluateCapture` | 10× | Direct captures |
| Encirclement Progress | `_evaluateEncirclementProgress` | 15× | Progress toward completing encirclement |
| Encirclement Block | `_evaluateEncirclementBlock` | 30× | Help endangered stones escape |
| Urgent Defense | `_evaluateUrgentDefense` | 50× | Stones in critical danger |
| Capture Blocking | `_evaluateCaptureBlockingMove` | 100× | Block opponent's capture threat |

### Detailed Scoring Logic

#### 1. Position Evaluation (`_evaluatePosition`)
```dart
Center positions score higher than edges
Score = 1 - (distanceFromCenter / halfBoardSize)
Range: 0.0 to 1.0
```

#### 2. Liberties Evaluation (`_evaluateLiberties`)
```dart
Count empty adjacent positions
Score = emptyCount * 5.0
Range: 0 to 20 (max 4 liberties × 5)
```

#### 3. Connection Evaluation (`_evaluateConnection`)
```dart
Count adjacent friendly stones + count friendly stones at distance 2
Score = (adjacent × 10.0) + (nearbyFriendly × 2.0)
```

#### 4. Territory Control (`_evaluateTerritoryControl`)
```dart
Check 5×5 area around position
friendlyRatio = friendlyStones / totalStones
Score = friendlyRatio × 30.0
```

#### 5. Capture Evaluation (`_evaluateCapture`)
```dart
Simulate placing stone and check for captures
Score = capturedCount × 50.0
BONUS: +200 if completing an encirclement
BONUS: +5 per interior position in new enclosure
```

#### 6. Encirclement Progress (`_evaluateEncirclementProgress`)
```dart
For each opponent stone group:
  1. Count current edge exits (empty spaces reaching board edge)
  2. Simulate placing AI stone
  3. Count new edge exits
  4. If exits reduced: score += 30 + (reduction × 10) + (5 if exits ≤ 3)
```

#### 7. Encirclement Block (`_evaluateEncirclementBlock`)
```dart
Find endangered AI stones (≤3 edge exits, opponent perimeter ≥50%)
For each endangered stone:
  1. Check if move position is adjacent to endangered region
  2. Simulate placing stone
  3. If edge exits increase: score += 30 + (newExits × 5)
```

#### 8. Urgent Defense (`_evaluateUrgentDefense`)
```dart
Find critically endangered AI stones (≤2 edge exits)
For each critical stone:
  1. If move is adjacent to critical region: score += 50
  2. If move creates new escape route: score += 100
  3. If move is at boundary gap: score += 80
```

#### 9. Capture Blocking (`_evaluateCaptureBlockingMove`)
```dart
For each empty position adjacent to AI stones:
  1. Simulate opponent placing there
  2. If opponent would capture AI stones:
     - If our move is at that position: score += 150
     - Bonus: captureCount × 30
```

---

## Step 3: Move Selection

```dart
1. Sort candidates by score (descending)
2. Find all moves within 2 points of best score
3. Randomly select from top candidates
```

This randomization prevents predictable play while still choosing strong moves.

---

## Escape Path Detection Algorithm

The core algorithm for determining if stones can "escape" (reach the board edge):

```dart
_findRegionAndCheckEscape(board, startPos, targetColor):
  1. Initialize: region = {}, toVisit = [startPos], canEscape = false

  2. While toVisit not empty:
     a. Pop current position
     b. Skip if already in region or invalid
     c. Get stone at position

     d. If stone is opponent color:
        - Add to wallPositions (boundary of encirclement)
        - Continue (don't add to region)

     e. Add current to region

     f. If position is on board edge AND empty:
        - canEscape = true

     g. Add adjacent positions to toVisit

  3. Return { region, canEscape, wallPositions }
```

**Key insight**: A stone group can escape if there's a path of empty spaces from the group to the board edge. Opponent stones form walls that block escape.

---

## Critical Gap Detection

Identifies chokepoints that could complete an encirclement:

```dart
_findCriticalGaps(board, escapeResult, targetColor):
  1. For each empty position in the region:
     a. If position is adjacent to wall (opponent stone):
        - Check if filling this gap would block escape
        - If position is on edge OR only path to edge: it's critical

  2. Return set of critical gap positions
```

---

## One-Move-From-Encirclement Detection

Detects if placing a stone would create immediate capture threat:

```dart
_isOneMoveFromEncirclement(board, pos, color, enclosures):
  1. Place AI stone at position
  2. Find connected region
  3. Identify boundary gaps (empty spaces next to region)

  4. For each gap:
     a. Simulate opponent placing at gap
     b. Run capture logic
     c. If ANY stones captured: return true (dangerous!)

  5. Return false (safe)
```

---

## Danger Zone Thresholds

| Condition | Interpretation |
|-----------|---------------|
| 0 edge exits | Completely surrounded - never play here |
| 1-2 exits + 60%+ opponent perimeter | Nearly surrounded, easy to capture |
| 3-4 exits + 40%+ perimeter + critical gaps | Opponent could seal quickly |
| 5+ exits | Generally safe |

---

## Performance Optimizations

1. **Isolate Compute**: AI runs in separate thread
2. **Early Termination**: Escape detection stops once escape found
3. **Veto Before Score**: Dangerous moves rejected before expensive evaluation
4. **Cached Paint Objects**: Board rendering uses pre-allocated paint objects
5. **Limited Search Radius**: Territory control only checks 5×5 area

---

## Scoring Priority Summary

From highest to lowest priority:

1. **Capture Blocking (100×)** - Prevent opponent from capturing our stones
2. **Urgent Defense (50×)** - Save critically endangered stones
3. **Encirclement Block (30×)** - Help stones with limited escape
4. **Encirclement Progress (15×)** - Work toward capturing opponent
5. **Direct Capture (10×)** - Capture opponent stones now
6. **Territory Control (5×)** - Control board area
7. **Connection (3×)** - Stay connected to friendly stones
8. **Liberties (2×)** - Maintain breathing room
9. **Position (1×)** - Prefer center over edges

---

## Future Improvements

Potential enhancements not yet implemented:

- **Lookahead**: Evaluate opponent's best response
- **Pattern Recognition**: Common joseki/fuseki patterns
- **Monte Carlo**: Random playouts for position evaluation
- **Opening Book**: Pre-computed strong opening moves
- **Endgame Scoring**: Accurate territory counting
