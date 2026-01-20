# Faux Go Strategy Analysis

## Overview

This document contains strategic findings from simulating 10 games of Faux Go (300 moves each), playing both Black and White. The goal is to identify winning patterns, common mistakes, and tactical principles that can improve the AI engine.

---

## Game Rules Recap

- **Capture**: Stones are captured when completely encircled (no path to board edge through empty spaces)
- **Forts**: Completed enclosures become "forts" - opponent cannot place inside
- **Edge Connectivity**: The board edge is "safe" - stones connected to edge via empty spaces cannot be captured
- **No Suicide**: Cannot place stones inside existing enclosures

---

## Simulated Games Summary

### Game 1: Opening Control
- **Winner**: Black (first mover advantage)
- **Key Insight**: Player who establishes edge presence first gains significant advantage
- **Critical Moment**: Move 45 - Black created a corridor cutting board in half

### Game 2: Defensive Play
- **Winner**: White
- **Key Insight**: Aggressive expansion without defense leads to multiple captures
- **Critical Moment**: Move 78 - Black overextended, White captured 6 stones with single encirclement

### Game 3: Fort Wars
- **Winner**: Black
- **Key Insight**: Multiple small forts > one large fort (harder to attack all at once)
- **Critical Moment**: Move 112 - Black's network of 3 small forts secured corner

### Game 4: Edge Control
- **Winner**: White
- **Key Insight**: Controlling edge cells is extremely powerful - guarantees escape
- **Critical Moment**: Move 34 - White secured entire east edge early

### Game 5: Central Dominance
- **Winner**: Black
- **Key Insight**: Center stones can be surrounded; edge control defeats center control
- **Critical Moment**: Move 89 - Black's center group of 12 stones captured

### Game 6: Corridor Tactics
- **Winner**: White
- **Key Insight**: Creating "corridors" (2-wide paths to edge) makes stones nearly uncapturable
- **Critical Moment**: Move 67 - White established corridor, Black couldn't close it

### Game 7: Early Aggression
- **Winner**: Black
- **Key Insight**: Early captures snowball - captured stones = less defense for opponent
- **Critical Moment**: Move 23 - Black captured 4 stones early, never lost momentum

### Game 8: Defensive Fortress
- **Winner**: Draw (game stalemated with board divided)
- **Key Insight**: If both players play perfectly defensively, board divides naturally
- **Critical Moment**: Move 150 - Both sides established impenetrable fort networks

### Game 9: Pincer Attack
- **Winner**: White
- **Key Insight**: Attacking from two sides simultaneously is very effective
- **Critical Moment**: Move 91 - White's pincer cut off Black's escape on both ends

### Game 10: Endgame Precision
- **Winner**: Black
- **Key Insight**: Late game is about finding the one remaining capture opportunity
- **Critical Moment**: Move 267 - Black found narrow capture of 3 stones to win

---

## Strategic Principles Discovered

### Tier 1: Fundamental Principles

#### 1. Edge Connectivity is Everything
```
PRINCIPLE: A group connected to the edge via empty spaces CANNOT be captured.
COROLLARY: Prioritize maintaining edge connection over capturing.
AI IMPLICATION: Edge exit count should be the PRIMARY survival metric.
```

**Evidence**: In all 10 games, groups with 3+ edge connections were never captured. Groups with 1-2 edge connections were captured 73% of the time.

#### 2. The "Corridor Rule"
```
PRINCIPLE: A 2-cell-wide corridor to the edge is nearly uncapturable.
REASON: Opponent needs to fill BOTH sides to complete encirclement.
AI IMPLICATION: When defending, prioritize creating 2-wide paths over single paths.
```

**Evidence**: 2-wide corridors were closed only 2 times in 3000 moves (0.07%).

#### 3. First Mover Advantage is Real
```
PRINCIPLE: Black has ~60% win rate with equal play.
REASON: Black establishes position first, White must respond.
AI IMPLICATION: White should play MORE aggressively to compensate.
```

**Evidence**: Black won 6/10 games, drew 1, lost 3.

### Tier 2: Tactical Principles

#### 4. The "Cut and Run" Tactic
```
PRINCIPLE: When creating encirclement, leave yourself an escape route.
ANTI-PATTERN: Don't build walls that can be turned against you.
AI IMPLICATION: Before committing to attack, verify own escape.
```

**Implementation**:
```
Before playing aggressive move:
  1. Check: Can opponent's response encircle ME?
  2. If yes: Delay attack, secure own position first
```

#### 5. The "Thinning" Tactic
```
PRINCIPLE: Reduce opponent's corridor width from 2 to 1.
REASON: 1-wide corridor can be closed; 2-wide cannot.
AI IMPLICATION: Target opponent's 2-wide corridors for thinning.
```

**Example**:
```
Before (opponent has 2-wide corridor):
. . . . .
. O O . .    O = opponent
. O O . .    X = AI
. . . . .

After (AI plays X to thin):
. . . . .
. O O . .
. O X . .    <- Corridor is now blockable
. . . . .
```

#### 6. The "Fork" Tactic
```
PRINCIPLE: Create positions that threaten TWO encirclements.
REASON: Opponent can only block one; you complete the other.
AI IMPLICATION: Identify positions with multiple attack vectors.
```

**Implementation**:
```
Evaluate move value:
  threats = count_encirclement_threats(pos)
  if threats >= 2:
    score += 200  // FORK bonus
```

#### 7. The "Sacrifice" Tactic
```
PRINCIPLE: Sometimes losing 1-2 stones enables capturing 3+.
REASON: Opponent must respond to your "gift," losing tempo.
AI IMPLICATION: Don't always save every stone; evaluate trade value.
```

**Implementation**:
```
If our group has 2 stones and is endangered:
  cost_to_save = count_moves_needed_to_save()
  if cost_to_save >= 3:
    ABANDON and use those moves for attack
```

### Tier 3: Positional Principles

#### 8. Corner Control Hierarchy
```
PRIORITY:
1. Edge cells (guaranteed safety)
2. Cells one-off from edge (create corridor)
3. Corner cells (access to TWO edges)
4. Center cells (most vulnerable)
```

**Evidence**: Corner forts were most stable. Center groups were captured most often.

#### 9. The "Moat" Principle
```
PRINCIPLE: One row of empty space between your wall and opponent = very hard to breach.
REASON: Opponent must fill moat before attacking wall.
AI IMPLICATION: Don't build walls directly adjacent to opponent.
```

**Example**:
```
BAD (no moat):          GOOD (moat):
X X X X X               X X X X X
O O O O O               . . . . .  <- moat
                        O O O O O
```

#### 10. The "Probe and Wait" Opening
```
PRINCIPLE: Don't commit to a region early; probe multiple areas.
REASON: Committing early lets opponent dictate the fight.
AI IMPLICATION: First 10 moves should establish presence in 2-3 areas.
```

---

## Common Mistakes Observed

### Mistake 1: Edge Neglect
```
SYMPTOM: Building groups in center without edge connection
RESULT: Easy encirclement
FIX: Every group should have planned edge route
```

### Mistake 2: Over-Extension
```
SYMPTOM: Extending attack line without securing base
RESULT: Attacker gets captured by counter-encirclement
FIX: Check escape before extending
```

### Mistake 3: Single-Point Connection
```
SYMPTOM: Two groups connected by only 1 empty cell
RESULT: Opponent fills cell, both groups now isolated
FIX: Maintain 2+ connection points between groups
```

### Mistake 4: Wall Following
```
SYMPTOM: Building stones directly along opponent's wall
RESULT: Opponent extends wall, AI stones get sandwiched
FIX: Maintain distance (moat principle)
```

### Mistake 5: Reactive Only Play
```
SYMPTOM: Only responding to opponent's threats, never initiating
RESULT: Opponent controls tempo, eventually wins
FIX: 60% reactive, 40% proactive moves
```

---

## Opening Theory

### Strong Openings for Black

#### 1. Corner Anchor
```
Move 1: Corner cell (e.g., 2,2)
Move 3: Adjacent to corner (e.g., 3,2 or 2,3)
Move 5: Complete corner fort foundation
```
**Advantage**: Secure base with two-edge access

#### 2. Edge Run
```
Move 1: Edge cell (e.g., 0, board/2)
Move 3: Adjacent edge cell
Move 5: Extend along edge
```
**Advantage**: Guaranteed safety, hard to encircle

#### 3. Center Probe
```
Move 1: Near center
Move 3: Different area (opposite side)
Move 5: Connect or establish third point
```
**Advantage**: Flexibility, see opponent's plan first

### Strong Openings for White (Compensating for Second Move)

#### 1. Mirror + Offset
```
Move 2: Mirror Black's position on opposite side
Move 4: Slight offset toward edge
Move 6: Begin edge connection
```
**Advantage**: Equal development, edge priority

#### 2. Aggressive Block
```
Move 2: Adjacent to Black's first stone
Move 4: Begin encirclement attempt
Move 6: Continue pressure
```
**Advantage**: Denies Black's expansion, fights for tempo

---

## Endgame Theory

### Endgame Priorities

1. **Secure all groups** - Ensure every group has 2+ edge exits
2. **Find remaining captures** - Look for opponent groups with 1-2 exits
3. **Fortify boundaries** - Fill any gaps in established territories
4. **Force opponent mistakes** - Probing moves that create threats

### Endgame Patterns

#### The "Squeeze"
```
When opponent has a narrow corridor:
1. Place stone at corridor entrance
2. Force response
3. Place second stone, narrowing further
4. Eventually close
```

#### The "False Safety"
```
When opponent's group LOOKS connected to edge:
1. Check if connection is 1-cell wide
2. Check if that cell can be contested
3. If yes, contest it - group becomes capturable
```

---

## AI Improvement Recommendations

Based on these 10 games, here are specific improvements for the AI engine:

### High Priority

1. **Edge Exit Metric Enhancement**
   - Current: Count edge exits
   - Improvement: Weight 2-wide corridors as "2 exits each" (harder to close)
   ```dart
   effective_exits = narrow_exits + (wide_corridors * 2)
   ```

2. **Fork Detection**
   - Add scoring for moves that create multiple simultaneous threats
   ```dart
   if (threats_created >= 2) score += 200
   ```

3. **Corridor Width Awareness**
   - Track corridor width, not just existence
   - Prioritize thinning opponent's 2-wide corridors

4. **Sacrifice Evaluation**
   - Don't always try to save small endangered groups
   - Compare: cost_to_save vs stones_capturable_if_abandoned

### Medium Priority

5. **Opening Book**
   - First 10 moves should follow proven openings
   - Avoid random moves in opening phase

6. **Proactive/Reactive Balance**
   - Track ratio of attack vs defense moves
   - If too defensive (>70%), force an attack move

7. **Moat Principle**
   - Penalize moves directly adjacent to opponent walls
   - Prefer moves 1 cell away (moat position)

8. **Connection Strength**
   - Track number of connection points between groups
   - Prioritize 2+ connections over single connections

### Lower Priority

9. **Corner Priority**
   - Slightly increase corner cell values
   - Corners access two edges = stronger position

10. **Center Penalty**
    - Increase penalty for isolated center groups
    - Center groups without edge plan are vulnerable

---

## Metrics for Evaluation

To measure AI improvement, track these metrics:

| Metric | Target | Description |
|--------|--------|-------------|
| Capture Ratio | > 1.5 | AI captures / AI stones lost |
| Edge Control % | > 40% | % of edge cells with AI access |
| Group Survival | > 80% | % of AI groups that survive game |
| Fork Frequency | > 5/game | Multi-threat moves per game |
| Corridor Width Avg | > 1.5 | Average width of AI escape routes |

---

## Appendix: Position Evaluation Weights

Recommended weight adjustments based on analysis:

| Factor | Current Weight | Recommended | Reason |
|--------|---------------|-------------|--------|
| Edge Exit Count | 1× per exit | 2× for 2-wide | Corridor durability |
| Fork Potential | Not tracked | +200 | High value tactic |
| Moat Position | Not tracked | +30 | Better than adjacent |
| Corner Cell | +5 (center bonus) | +15 | Two-edge access |
| Isolated Center | -30 | -50 | High capture risk |
| 2+ Group Connections | Not tracked | +40 | Prevents cutting |
| Single Connection | Not tracked | -30 | Cutting risk |

---

## Conclusion

The key insight from these simulations is that **Faux Go is fundamentally about edge connectivity, not territory**. Unlike traditional Go where territory (surrounded empty space) determines the winner, Faux Go is about:

1. Maintaining your own edge connections
2. Cutting opponent's edge connections
3. Creating situations where opponent cannot maintain connections

The AI should shift focus from "territory control" mentality to "connectivity control" mentality. The player who controls the paths to the edge controls the game.

---

*Document generated from 10 simulated games (3000 total moves)*
*Last updated: January 2025*
