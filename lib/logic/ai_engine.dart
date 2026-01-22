import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'capture_logic.dart';
import 'liberty_calculator.dart';

/// Data class for passing AI calculation parameters to isolate
class _AiCalculationParams {
  final Board board;
  final StoneColor aiColor;
  final AiLevel level;
  final Position? opponentLastMove;
  final List<Enclosure> enclosures;

  _AiCalculationParams(this.board, this.aiColor, this.level, this.opponentLastMove, this.enclosures);
}

/// Top-level function for compute() - must be static/top-level
Position? _calculateMoveIsolate(_AiCalculationParams params) {
  final engine = AiEngine._internal();
  return engine._calculateMoveSync(params.board, params.aiColor, params.level, params.opponentLastMove, params.enclosures);
}

/// AI Engine for Go game with 10 difficulty levels
class AiEngine {
  final Random _random = Random();

  /// POI cache for tracking distant opponent activity (persists across moves)
  /// Static so it persists across isolate calls
  static final _POICache _poiCache = _POICache();

  AiEngine();

  /// Internal constructor for isolate use
  AiEngine._internal();

  /// Reset the POI cache (call when starting a new game)
  static void resetPOICache() {
    _poiCache.reset();
  }

  /// Calculate the best move for the AI based on difficulty level (async, runs in isolate)
  /// [opponentLastMove] is used to focus AI moves near the opponent's last play
  /// [enclosures] prevents AI from placing inside opponent's forts
  Future<Position?> calculateMoveAsync(Board board, StoneColor aiColor, AiLevel level, {Position? opponentLastMove, List<Enclosure> enclosures = const []}) async {
    return compute(_calculateMoveIsolate, _AiCalculationParams(board, aiColor, level, opponentLastMove, enclosures));
  }

  /// Synchronous version for internal use
  Position? calculateMove(Board board, StoneColor aiColor, AiLevel level, {Position? opponentLastMove, List<Enclosure> enclosures = const []}) {
    return _calculateMoveSync(board, aiColor, level, opponentLastMove, enclosures);
  }

  /// Internal synchronous calculation
  Position? _calculateMoveSync(Board board, StoneColor aiColor, AiLevel level, Position? opponentLastMove, List<Enclosure> enclosures) {
    // Build per-turn cache to avoid redundant flood-fills
    final cache = _buildTurnCache(board, aiColor, enclosures);

    // Update POI (Points of Interest) for high-level AI (8+)
    // Tracks distant opponent activity to detect strategic build-up
    _updatePOI(board, aiColor, opponentLastMove, level);

    // Get POI candidates for high-level AI
    final poiCandidates = level.level >= 8 ? _getPOICandidates(board, aiColor, enclosures) : <Position>{};

    // CRITICAL: Find positions where opponent could capture our stones
    // Now returns DETAILED info: immediate captures vs encirclement blocks
    // Maps include stones-at-risk count for proper prioritization
    final criticalBlockingDetailed = _findCriticalBlockingPositionsDetailed(board, aiColor, enclosures, cache);
    final immediateCaptureBlocks = criticalBlockingDetailed.immediateCaptureBlocks; // Map<Position, int>
    final encirclementBlocks = criticalBlockingDetailed.encirclementBlocks; // Map<Position, int>
    // Combined set for candidate generation (backwards compatibility)
    final criticalBlockingPositions = {...immediateCaptureBlocks.keys, ...encirclementBlocks.keys};

    // COUNTER-ATTACK: Find positions where we can severely damage opponent's groups
    // When we're being encircled but opponent also has weak groups, attack may be better than defense
    final criticalAttackPositions = level.level >= 4
        ? _findCriticalAttackPositions(board, aiColor, cache)
        : <Position>{};

    // Find chokepoints that reduce opponent's escape robustness
    final chokepoints = _findChokepoints(board, cache, aiColor);

    // NEW: Find encirclement-breaking moves (level 5+)
    // These are positions that would break a forming encirclement from ANY side
    final encirclementBreakingMoves = level.level >= 5
        ? _findEncirclementBreakingMoves(board, aiColor, cache)
        : <Position>{};

    final candidateMoves = _getValidMoves(board, aiColor, enclosures, opponentLastMove, cache, criticalBlockingPositions, chokepoints, poiCandidates, encirclementBreakingMoves);

    // === AI DECISION LOGGING ===
    _logAiDecision('=== AI MOVE ANALYSIS (Level ${level.level}) ===');
    _logAiDecision('Opponent last move: $opponentLastMove');
    _logAiDecision('AI groups: ${cache.aiGroups.length}, Opponent groups: ${cache.opponentGroups.length}');
    _logAiDecision('IMMEDIATE capture blocks: ${immediateCaptureBlocks.length} - ${immediateCaptureBlocks.keys}');
    _logAiDecision('Encirclement blocks: ${encirclementBlocks.length} - ${encirclementBlocks.keys}');
    if (criticalAttackPositions.isNotEmpty) {
      _logAiDecision('Critical ATTACK positions: ${criticalAttackPositions.length} - $criticalAttackPositions');
    }
    _logAiDecision('Chokepoints found: ${chokepoints.length}');
    if (encirclementBreakingMoves.isNotEmpty) {
      _logAiDecision('Encirclement-breaking moves: ${encirclementBreakingMoves.length} - $encirclementBreakingMoves');
    }
    _logAiDecision('Total candidates: ${candidateMoves.length}');

    if (candidateMoves.isEmpty) {
      _logAiDecision('RESULT: No candidates - AI PASS');
      return null; // AI should pass
    }

    // STEP 1: Apply HARD VETO rules before scoring
    // This prevents AI from placing stones that are dead on placement
    // EXCEPTIONS that are NEVER vetoed:
    // 1. Immediate capture blocks - they prevent losing stones
    // 2. Critical attack positions - counter-attacking is strategically valuable
    final validMoves = <Position>[];
    final vetoedMoves = <Position>[];
    for (final pos in candidateMoves) {
      // CRITICAL: Never veto immediate capture blocks - losing stones is worse than any veto reason
      if (immediateCaptureBlocks.containsKey(pos)) {
        validMoves.add(pos);
      }
      // CRITICAL: Never veto attack positions - counter-attacking weak opponent pieces is valuable
      else if (criticalAttackPositions.contains(pos)) {
        validMoves.add(pos);
      }
      else if (!_isVetoedMove(board, pos, aiColor, enclosures)) {
        validMoves.add(pos);
      } else {
        vetoedMoves.add(pos);
      }
    }

    _logAiDecision('After veto: ${validMoves.length} valid, ${vetoedMoves.length} vetoed');

    if (validMoves.isEmpty) {
      _logAiDecision('RESULT: All moves vetoed - AI PASS');
      return null; // All moves vetoed - AI should pass
    }

    // STEP 2: Score remaining valid moves with detailed breakdown
    final scoredMoves = <_ScoredMoveWithReason>[];
    for (final pos in validMoves) {
      final scoreBreakdown = _evaluateMoveWithBreakdown(board, pos, aiColor, level, opponentLastMove, enclosures, cache, immediateCaptureBlocks, encirclementBlocks, criticalAttackPositions, encirclementBreakingMoves);
      scoredMoves.add(_ScoredMoveWithReason(pos, scoreBreakdown.totalScore, scoreBreakdown.reasons));
    }

    // Sort by score (highest first)
    scoredMoves.sort((a, b) => b.score.compareTo(a.score));

    // Log top 5 moves with reasons
    _logAiDecision('--- TOP 5 CANDIDATE MOVES ---');
    for (int i = 0; i < min(5, scoredMoves.length); i++) {
      final move = scoredMoves[i];
      _logAiDecision('${i + 1}. (${move.position.x},${move.position.y}) score=${move.score.toStringAsFixed(1)}');
      for (final reason in move.reasons) {
        _logAiDecision('     $reason');
      }
    }

    // STEP 3: Based on AI level, choose move with some randomness
    // Lower levels make more random moves, higher levels pick better moves
    final selectedMove = _selectMoveByLevelWithLogging(scoredMoves, level);

    // STEP 4: Track our move in POI cache for next turn's proximity calculation
    if (selectedMove != null && level.level >= 8) {
      _poiCache.previousOwnMoves.add(selectedMove);
      if (_poiCache.previousOwnMoves.length > 10) {
        _poiCache.previousOwnMoves.removeAt(0);
      }
    }

    // Find the selected move's details
    final selectedDetails = scoredMoves.firstWhere((m) => m.position == selectedMove, orElse: () => scoredMoves.first);
    _logAiDecision('>>> SELECTED: (${selectedMove?.x},${selectedMove?.y}) score=${selectedDetails.score.toStringAsFixed(1)}');
    _logAiDecision('=== END AI ANALYSIS ===\n');

    return selectedMove;
  }

  /// Log AI decision (can be toggled on/off)
  static bool _enableAiLogging = true;
  void _logAiDecision(String message) {
    if (_enableAiLogging) {
      print('[AI] $message');
    }
  }

  /// Enable or disable AI decision logging
  static void setLoggingEnabled(bool enabled) {
    _enableAiLogging = enabled;
  }

  /// Evaluate a move and return detailed score breakdown for logging
  _ScoreBreakdown _evaluateMoveWithBreakdown(
      Board board, Position pos, StoneColor aiColor, AiLevel level, Position? opponentLastMove, List<Enclosure> enclosures, _TurnCache cache, Map<Position, int> immediateCaptureBlocks, Map<Position, int> encirclementBlocks, Set<Position> criticalAttackPositions, Set<Position> encirclementBreakingMoves) {
    final reasons = <String>[];
    double totalScore = 0.0;
    final levelValue = level.level;

    // Simulate placing the stone
    final result = CaptureLogic.processMove(board, pos, aiColor, existingEnclosures: enclosures);
    if (!result.isValid) {
      reasons.add('INVALID MOVE: -1000');
      return _ScoreBreakdown(-1000, reasons);
    }

    final newBoard = result.newBoard!;
    final capturedCount = result.captureResult?.captureCount ?? 0;
    final newEnclosures = result.captureResult?.newEnclosures ?? [];

    // === GATE CHECK: DOOMED POSITION ===
    // If this position is in an area where opponent can complete encirclement in 1 move,
    // and we can't block it from inside, this is a wasted move - massive penalty
    final doomedCheck = _isPositionDoomed(board, newBoard, pos, aiColor, enclosures);
    if (doomedCheck.isDoomed) {
      // Only allow if this move captures something valuable
      if (capturedCount == 0) {
        totalScore -= 800;
        reasons.add('DOOMED_POSITION(${doomedCheck.reason}): -800');
      }
    }

    // IMMEDIATE CAPTURE BLOCK - HIGHEST PRIORITY
    // These are positions where opponent playing would DIRECTLY capture our stones
    // CRITICAL: Scale by stones at risk - saving 1 stone != saving 5 stones
    // MUST outweigh CRITICAL_ATTACK to prevent AI from attacking while being captured
    if (immediateCaptureBlocks.containsKey(pos)) {
      final stonesAtRisk = immediateCaptureBlocks[pos]!;

      // Base bonus scales with stones at risk:
      // 1 stone: 500, 2 stones: 1000, 3 stones: 1500, 4+ stones: 2000
      // Higher base than CRITICAL_ATTACK (600) to ensure defense takes priority
      final baseBonus = min(2000, 500 * stonesAtRisk);
      totalScore += baseBonus;
      reasons.add('IMMEDIATE_CAPTURE_BLOCK($stonesAtRisk stones): +$baseBonus');

      // Additional bonus if this move improves escape for endangered groups
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount <= 6) {
          final escapeAfter = _checkEscapePathDetailed(newBoard, group.stones.first, aiColor);
          final improvement = escapeAfter.edgeExitCount - group.edgeExitCount;
          if (improvement > 0) {
            final improvementBonus = improvement * 30;
            totalScore += improvementBonus;
            reasons.add('ESCAPE_IMPROVE(+$improvement exits): +$improvementBonus');
            break; // Only count once
          }
        }
      }
    }
    // ENCIRCLEMENT BLOCK - Important but not as urgent as immediate capture
    // These reduce escape routes but don't immediately capture
    // CRITICAL: Scale by stones at risk AND check if blocking is actually effective
    else if (encirclementBlocks.containsKey(pos)) {
      final stonesAtRisk = encirclementBlocks[pos]!;
      final totalGapCount = encirclementBlocks.length;

      // CRITICAL CHECK: Is this blocking move actually effective?
      // If there are adjacent gaps that ALSO block the same group, blocking this one is futile
      // (opponent will just play the adjacent gap next turn)
      int adjacentGapCount = 0;
      for (final adj in pos.adjacentPositions) {
        if (encirclementBlocks.containsKey(adj)) {
          adjacentGapCount++;
        }
      }

      // Also check for nearby gaps (within 2 cells) - these form the encirclement perimeter
      int nearbyGapCount = 0;
      for (final gapPos in encirclementBlocks.keys) {
        if (gapPos == pos) continue;
        final dist = (gapPos.x - pos.x).abs() + (gapPos.y - pos.y).abs();
        if (dist <= 3) nearbyGapCount++;
      }

      // Check urgency based on edge exits of the endangered group
      int minGroupExits = 999;
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount < minGroupExits) {
          minGroupExits = group.edgeExitCount;
        }
      }

      // Base bonus by urgency
      int urgencyBonus;
      if (minGroupExits <= 2) {
        urgencyBonus = 400; // Very urgent - almost captured
      } else if (minGroupExits <= 4) {
        urgencyBonus = 300; // Important
      } else if (minGroupExits <= 6) {
        urgencyBonus = 200; // Moderate
      } else {
        urgencyBonus = 150; // Still useful
      }

      // Scale by stones at risk: multiply by sqrt(stones) to give larger groups more priority
      // but not linearly (to avoid completely ignoring small groups)
      final stoneMultiplier = stonesAtRisk >= 4 ? 2.0 : (stonesAtRisk >= 2 ? 1.5 : 1.0);
      int blockBonus = (urgencyBonus * stoneMultiplier).toInt();

      // HOPELESS CHECK: If there are MANY gaps (8+), blocking is nearly hopeless
      // The encirclement is too wide - opponent can always extend elsewhere
      // AI should focus on escape or counterattack instead
      if (totalGapCount >= 8) {
        // Check if gaps span multiple edges (truly hopeless - can't close from one side)
        final gapsOnMultipleEdges = _gapsSpanMultipleEdges(encirclementBlocks.keys, board.size);
        if (gapsOnMultipleEdges) {
          // Gaps on multiple edges = nearly impossible to close
          blockBonus = (blockBonus * 0.05).toInt(); // Reduce to 5%
          reasons.add('MULTI_EDGE_HOPELESS($totalGapCount gaps): -${(urgencyBonus * stoneMultiplier * 0.95).toInt()}');
        } else {
          // Many gaps but on one side = still very hard
          blockBonus = (blockBonus * 0.10).toInt(); // Reduce to 10%
          reasons.add('HOPELESS_DEFENSE($totalGapCount gaps): -${(urgencyBonus * stoneMultiplier * 0.90).toInt()}');
        }
      } else if (totalGapCount >= 5) {
        // Several gaps = blocking buys some time but not much
        blockBonus = (blockBonus * 0.4).toInt(); // Reduce to 40%
        reasons.add('WIDE_ENCIRCLEMENT($totalGapCount gaps): -${(urgencyBonus * stoneMultiplier * 0.6).toInt()}');
      }
      // FUTILITY CHECK: If there are adjacent gaps, blocking this one won't help
      // Opponent will just play an adjacent position next turn
      else if (adjacentGapCount >= 2) {
        // Multiple adjacent gaps = blocking is nearly useless
        blockBonus = (blockBonus * 0.1).toInt(); // Reduce to 10%
        reasons.add('FUTILE_BLOCK($adjacentGapCount adj gaps): -${(urgencyBonus * stoneMultiplier * 0.9).toInt()}');
      } else if (adjacentGapCount == 1) {
        // One adjacent gap = blocking buys one turn, somewhat useful
        blockBonus = (blockBonus * 0.5).toInt(); // Reduce to 50%
        reasons.add('PARTIAL_BLOCK(1 adj gap): -${(urgencyBonus * stoneMultiplier * 0.5).toInt()}');
      }

      totalScore += blockBonus;
      reasons.add('ENCIRCLEMENT_BLOCK($stonesAtRisk stones): +$blockBonus');

      // Additional bonus if this move improves escape for endangered groups
      // This is MORE valuable than futile blocking - actually increases our exits
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount <= 6) {
          final escapeAfter = _checkEscapePathDetailed(newBoard, group.stones.first, aiColor);
          final improvement = escapeAfter.edgeExitCount - group.edgeExitCount;
          if (improvement > 0) {
            // BOOST: Escape improvement is very valuable when blocking is hopeless
            final hopelessMultiplier = totalGapCount >= 8 ? 3.0 : (totalGapCount >= 5 ? 2.0 : (adjacentGapCount > 0 ? 1.5 : 1.0));
            final improvementBonus = (improvement * 40 * hopelessMultiplier).toInt();
            totalScore += improvementBonus;
            reasons.add('ESCAPE_IMPROVE(+$improvement exits): +$improvementBonus');
            break; // Only count once
          }
        }
      }
    }

    // COUNTER-ATTACK: If this is a critical attack position, give high priority
    // This competes with ENCIRCLEMENT_BLOCK but NOT with IMMEDIATE_CAPTURE_BLOCK
    // Key insight: attacking opponent's weak group may be better than passive defense
    if (criticalAttackPositions.contains(pos) && !immediateCaptureBlocks.containsKey(pos)) {
      // Check if we're also being encircled - if so, counter-attack is even more valuable
      final hasEndangeredGroups = cache.aiGroups.any((g) => g.edgeExitCount <= 4);
      if (hasEndangeredGroups) {
        // We're being encircled - counter-attack is valuable (force opponent to defend)
        totalScore += 900;
        reasons.add('COUNTER_ATTACK: +900');
      } else {
        // We're safe - attack is still good but less urgent
        totalScore += 600;
        reasons.add('CRITICAL_ATTACK: +600');
      }
    }

    // MULTI-THREAT DAMPER: If we have multiple endangered groups, dampen attack urge
    // Don't attack when we need to defend multiple fronts
    final endangeredGroupCount = cache.aiGroups.where((g) => g.edgeExitCount <= 3).length;
    if (endangeredGroupCount >= 2 && criticalAttackPositions.contains(pos)) {
      // Calculate stones at risk
      final stonesAtRisk = cache.aiGroups
          .where((g) => g.edgeExitCount <= 2)
          .fold<int>(0, (sum, g) => sum + g.stones.length);

      // Check if attack would capture more than we'd lose (worthy attack exception)
      bool isWorthyAttack = false;
      int potentialCaptureStones = 0;
      for (final oppGroup in cache.opponentGroups) {
        if (oppGroup.edgeExitCount <= 2 && _isGroupNearPosition(oppGroup, pos, 2)) {
          // Verify we can complete capture soon (within ~2 moves)
          if (oppGroup.edgeExitCount <= 2) {
            potentialCaptureStones += oppGroup.stones.length;
          }
        }
      }
      if (potentialCaptureStones > stonesAtRisk && potentialCaptureStones >= 3) {
        isWorthyAttack = true;
      }

      if (!isWorthyAttack) {
        // Dampen attack bonus when we need to defend multiple fronts
        final dampenFactor = endangeredGroupCount >= 3 ? 0.4 : 0.6;
        final dampenAmount = (600 * (1 - dampenFactor)).toInt();
        totalScore -= dampenAmount;
        reasons.add('MULTI_THREAT_DAMPEN($endangeredGroupCount groups): -$dampenAmount');
      }
    }

    // FOUR-FRONT PROTOCOL: When 4+ groups endangered, enter triage mode
    // Filter out feints first to get real threat count
    int realThreats = 0;
    _GroupInfo? priorityGroup;
    double bestSaveValue = 0;
    for (final group in cache.aiGroups) {
      if (group.edgeExitCount <= 3) {
        // Fast-path: edgeExitCount == 1 is ALWAYS real (dies next turn)
        if (group.edgeExitCount == 1) {
          realThreats++;
          final saveValue = group.stones.length.toDouble() * 2; // High priority
          if (saveValue > bestSaveValue) {
            bestSaveValue = saveValue;
            priorityGroup = group;
          }
        } else if (!_isLikelyFeint(group, board, aiColor.opponent)) {
          realThreats++;
          final saveValue = group.stones.length * group.edgeExitCount.toDouble();
          if (saveValue > bestSaveValue) {
            bestSaveValue = saveValue;
            priorityGroup = group;
          }
        }
      }
    }

    if (realThreats >= 4 && priorityGroup != null) {
      // Enter four-front protocol: prioritize highest value group
      if (_isGroupNearPosition(priorityGroup, pos, 2)) {
        if (immediateCaptureBlocks.containsKey(pos) || encirclementBlocks.containsKey(pos)) {
          totalScore += 300;
          reasons.add('FOUR_FRONT_PRIORITY: +300');
        }
      }
      // Deprioritize non-priority groups
      for (final group in cache.aiGroups) {
        if (group != priorityGroup && group.edgeExitCount <= 2) {
          if (_isGroupNearPosition(group, pos, 2) && !_isGroupNearPosition(priorityGroup, pos, 3)) {
            totalScore -= 100;
            reasons.add('TRIAGE_DEPRIORITIZE: -100');
          }
        }
      }
    }

    // FIVE-FRONT CRISIS MODE: When 5+ real threats, maximize survival value per stone
    if (realThreats >= 5) {
      final totalStonesAtRisk = cache.aiGroups
          .where((g) => g.edgeExitCount <= 3)
          .fold<int>(0, (sum, g) => sum + g.stones.length);

      if (totalStonesAtRisk > 0 && immediateCaptureBlocks.containsKey(pos)) {
        final stonesSaved = immediateCaptureBlocks[pos]!;
        final survivalValue = stonesSaved / totalStonesAtRisk;

        if (survivalValue >= 0.3) {
          totalScore += 500;
          reasons.add('CRISIS_HIGH_VALUE_SAVE: +500');
        } else if (survivalValue >= 0.15) {
          totalScore += 200;
          reasons.add('CRISIS_MED_VALUE_SAVE: +200');
        }
      }

      // In crisis, don't waste moves on low-value saves
      if (encirclementBlocks.containsKey(pos) && !immediateCaptureBlocks.containsKey(pos)) {
        final stonesBlocked = encirclementBlocks[pos]!;
        final blockValue = totalStonesAtRisk > 0 ? stonesBlocked / totalStonesAtRisk : 0.0;
        if (blockValue < 0.2) {
          totalScore -= 150;
          reasons.add('CRISIS_LOW_VALUE_BLOCK: -150');
        }
      }
    }

    // Captures - VERY HIGH PRIORITY
    // Actually capturing stones is almost always the best move
    // Capturing is nearly always beneficial - removes opponent stones permanently
    // Base score must be high enough to compete with IMMEDIATE_CAPTURE_BLOCK
    if (capturedCount > 0) {
      // Base: 500 per stone, with bonus for multiple captures
      // 1 stone: 500, 2 stones: 1150, 3 stones: 1800, 4 stones: 2450
      // This makes captures competitive with defense when stones are at stake
      int captureScore = capturedCount * 500 + (capturedCount > 1 ? (capturedCount - 1) * 150 : 0);

      // SYNERGY BONUS: If this capture ALSO blocks an encirclement or defends our stones,
      // it's doubly valuable - we attack AND defend in one move!
      // This makes capture + defense much better than pure defense
      bool isDefensiveCapture = false;
      int defenseSynergyBonus = 0;

      if (immediateCaptureBlocks.containsKey(pos)) {
        // Capturing WHILE blocking immediate capture = huge synergy
        final stonesDefended = immediateCaptureBlocks[pos]!;
        defenseSynergyBonus = min(1000, stonesDefended * 150);
        isDefensiveCapture = true;
        reasons.add('CAPTURE_DEFENDS($stonesDefended stones): +$defenseSynergyBonus');
      } else if (encirclementBlocks.containsKey(pos)) {
        // Capturing WHILE blocking encirclement = good synergy
        final stonesDefended = encirclementBlocks[pos]!;
        defenseSynergyBonus = min(600, stonesDefended * 80);
        isDefensiveCapture = true;
        reasons.add('CAPTURE_BLOCKS_ENCIRCLE($stonesDefended stones): +$defenseSynergyBonus');
      }

      // CRITICAL CHECK: Does this capture ELIMINATE the threat at a nearby blocking position?
      // If an immediate capture block is needed at an adjacent position, check if capturing here
      // removes the attacker's stones that were creating that threat
      if (!isDefensiveCapture && immediateCaptureBlocks.isNotEmpty) {
        // Check if any immediate capture block position is now safe after this capture
        // (The captured stones might have been the ones creating the threat)
        for (final blockPos in immediateCaptureBlocks.keys) {
          // Check if capture position is within 2 cells of the block position
          final dist = (blockPos.x - pos.x).abs() + (blockPos.y - pos.y).abs();
          if (dist <= 2) {
            // Check if the threat still exists after this capture
            final opponentColor = aiColor.opponent;
            final threatResult = CaptureLogic.processMove(newBoard, blockPos, opponentColor, existingEnclosures: enclosures);
            // If opponent playing at blockPos can no longer capture, our capture eliminated the threat!
            if (!threatResult.isValid || threatResult.captureResult == null || threatResult.captureResult!.captureCount == 0) {
              final stonesDefended = immediateCaptureBlocks[blockPos]!;
              defenseSynergyBonus = min(1200, stonesDefended * 100 + capturedCount * 200);
              isDefensiveCapture = true;
              reasons.add('CAPTURE_ELIMINATES_THREAT($stonesDefended stones saved): +$defenseSynergyBonus');
              break;
            }
          }
        }
      }

      // Additional check: Does this capture break an opponent's attacking formation?
      // If capturing removes stones that were threatening our groups, extra bonus
      if (!isDefensiveCapture && cache.aiGroups.any((g) => g.edgeExitCount <= 4)) {
        // We have endangered groups - check if capture relieves pressure
        // After capture, check if our endangered group has more exits
        for (final group in cache.aiGroups) {
          if (group.edgeExitCount <= 4) {
            final escapeAfter = _checkEscapePathDetailed(newBoard, group.stones.first, aiColor);
            final improvement = escapeAfter.edgeExitCount - group.edgeExitCount;
            if (improvement > 0) {
              defenseSynergyBonus = improvement * 100;
              reasons.add('CAPTURE_RELIEVES_PRESSURE(+$improvement exits): +$defenseSynergyBonus');
              break;
            }
          }
        }
      }

      captureScore += defenseSynergyBonus;
      totalScore += captureScore;
      reasons.add('CAPTURE($capturedCount): +${capturedCount * 500 + (capturedCount > 1 ? (capturedCount - 1) * 150 : 0)}');
    }

    // Enclosure completion
    if (newEnclosures.isNotEmpty) {
      var enclosureScore = 200.0;
      for (final enclosure in newEnclosures) {
        enclosureScore += enclosure.interiorPositions.length * 5;
      }
      totalScore += enclosureScore;
      reasons.add('ENCLOSURE: +${enclosureScore.toInt()}');
    }

    // Proximity
    final proximityScore = _evaluateProximityToOpponent(board, pos, opponentLastMove);
    if (proximityScore != 0) {
      totalScore += proximityScore;
      reasons.add('PROXIMITY: ${proximityScore >= 0 ? '+' : ''}${proximityScore.toInt()}');
    }

    // Blocking expansion
    final blockScore = _evaluateBlockingExpansion(board, pos, aiColor, opponentLastMove) * 25;
    if (blockScore != 0) {
      totalScore += blockScore;
      reasons.add('BLOCK_EXPANSION: +${blockScore.toInt()}');
    }

    // Connection
    final connectScore = _evaluateConnection(board, pos, aiColor) * 5;
    if (connectScore != 0) {
      totalScore += connectScore;
      reasons.add('CONNECTION: +${connectScore.toInt()}');
    }

    // Edge connectivity check
    final escapeAfterMove = _checkEscapePathDetailed(newBoard, pos, aiColor);
    if (escapeAfterMove.edgeExitCount == 0) {
      totalScore -= 500;
      reasons.add('NO_EDGE_ACCESS: -500');
    } else if (escapeAfterMove.edgeExitCount <= 2) {
      final penalty = (3 - escapeAfterMove.edgeExitCount) * 50;
      totalScore -= penalty;
      reasons.add('LOW_EDGE_EXITS(${escapeAfterMove.edgeExitCount}): -$penalty');
    }

    // Wide corridor bonus
    if (escapeAfterMove.wideCorridorCount > 0) {
      final bonus = escapeAfterMove.wideCorridorCount * 20;
      totalScore += bonus;
      reasons.add('WIDE_CORRIDORS(${escapeAfterMove.wideCorridorCount}): +$bonus');
    }

    // ESCAPE CREATION BONUS: If we have endangered groups, prioritize moves that create escape routes
    // This is CRITICAL when blocking is futile - better to escape than waste moves blocking
    bool hasEndangeredGroup = false;
    int bestGroupExitsBefore = 0;
    Position? endangeredGroupStone;
    for (final group in cache.aiGroups) {
      if (group.edgeExitCount <= 6 && group.stones.length >= 3) {
        hasEndangeredGroup = true;
        if (group.edgeExitCount > bestGroupExitsBefore || endangeredGroupStone == null) {
          bestGroupExitsBefore = group.edgeExitCount;
          endangeredGroupStone = group.stones.first;
        }
      }
    }

    if (hasEndangeredGroup && endangeredGroupStone != null) {
      // Check if this move increases escape for our endangered group
      final escapeAfterForGroup = _checkEscapePathDetailed(newBoard, endangeredGroupStone, aiColor);
      final exitImprovement = escapeAfterForGroup.edgeExitCount - bestGroupExitsBefore;

      if (exitImprovement > 0) {
        // This move creates new escape routes! Very valuable.
        // More valuable than futile blocking
        final escapeBonus = exitImprovement * 100;
        totalScore += escapeBonus;
        reasons.add('ESCAPE_CREATION(+$exitImprovement exits): +$escapeBonus');
      } else if (exitImprovement < 0) {
        // This move REDUCES our escape - bad!
        final escapePenalty = (-exitImprovement) * 50;
        totalScore -= escapePenalty;
        reasons.add('ESCAPE_REDUCTION($exitImprovement exits): -$escapePenalty');
      }
    }

    // Surrounded penalty
    final surroundedPenalty = _evaluateSurroundedPenalty(board, pos, aiColor) * 40;
    if (surroundedPenalty > 0) {
      totalScore -= surroundedPenalty;
      reasons.add('SURROUNDED: -${surroundedPenalty.toInt()}');
    }

    // Level 3+ features
    if (levelValue >= 3) {
      final urgentScore = _evaluateUrgentDefense(board, pos, aiColor) * 50;
      if (urgentScore != 0) {
        totalScore += urgentScore;
        reasons.add('URGENT_DEFENSE: +${urgentScore.toInt()}');
      }

      final squeezeScore = _evaluateSqueezeDefense(board, pos, aiColor, cache);
      if (squeezeScore != 0) {
        totalScore += squeezeScore;
        reasons.add('SQUEEZE_DEFENSE: +${squeezeScore.toInt()}');
      }
    }

    // Level 4+ cut scanner
    if (levelValue >= 4) {
      final cutMultiplier = levelValue <= 5 ? 0.5 : (levelValue <= 7 ? 0.7 : 1.0);
      final cutScore = _evaluateCuttingOpportunity(board, pos, aiColor, cache) * cutMultiplier;
      if (cutScore != 0) {
        totalScore += cutScore;
        reasons.add('CUT_OPPORTUNITY: +${cutScore.toInt()}');
      }
    }

    // Anchor formation (opening)
    if (board.stones.length <= 20) {
      final anchorScore = _evaluateAnchorFormation(board, pos, aiColor);
      if (anchorScore != 0) {
        totalScore += anchorScore;
        reasons.add('ANCHOR_FORMATION: +${anchorScore.toInt()}');
      }
    }

    // Level 5+ encirclement breaking (path-traced blocking on ANY side)
    if (levelValue >= 5 && encirclementBreakingMoves.isNotEmpty) {
      final breakingScore = _evaluateEncirclementBreaking(board, pos, aiColor, encirclementBreakingMoves);
      if (breakingScore > 0) {
        totalScore += breakingScore;
        reasons.add('ENCIRCLE_BREAK: +${breakingScore.toInt()}');
      }
    }

    // Level 6+ features
    if (levelValue >= 6) {
      final encircleBlockScore = _evaluateEncirclementBlock(board, pos, aiColor) * 30;
      if (encircleBlockScore != 0) {
        totalScore += encircleBlockScore;
        reasons.add('ENCIRCLE_BLOCK: +${encircleBlockScore.toInt()}');
      }

      final forkScore = _evaluateForkPotential(board, pos, aiColor, cache, enclosures);
      if (forkScore != 0) {
        totalScore += forkScore;
        reasons.add('FORK_POTENTIAL: +${forkScore.toInt()}');
      }
    }

    // Tactical impact check
    final isBlockingMove = immediateCaptureBlocks.containsKey(pos) || encirclementBlocks.containsKey(pos);
    if (capturedCount == 0 && newEnclosures.isEmpty && !isBlockingMove) {
      bool hasImpact = false;
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount <= 3 && _isGroupNearPosition(group, pos, 2)) {
          hasImpact = true;
          break;
        }
      }
      if (!hasImpact) {
        for (final group in cache.opponentGroups) {
          if (group.edgeExitCount <= 4 && _isGroupNearPosition(group, pos, 2)) {
            hasImpact = true;
            break;
          }
        }
      }
      if (!hasImpact) {
        totalScore -= 30;
        reasons.add('NO_TACTICAL_IMPACT: -30');
      }
    }

    return _ScoreBreakdown(totalScore, reasons);
  }

  /// Select move by level with logging
  Position _selectMoveByLevelWithLogging(List<_ScoredMoveWithReason> scoredMoves, AiLevel level) {
    if (scoredMoves.isEmpty) {
      throw StateError('No valid moves available');
    }

    // At very low levels (1-2), occasionally make clearly suboptimal moves
    if (level.level <= 2 && scoredMoves.length > 5) {
      final mistakeChance = level.level == 1 ? 0.30 : 0.15;
      if (_random.nextDouble() < mistakeChance) {
        final bottomHalf = scoredMoves.skip(scoredMoves.length ~/ 2).toList();
        if (bottomHalf.isNotEmpty) {
          final selected = bottomHalf[_random.nextInt(bottomHalf.length)].position;
          _logAiDecision('SELECTION: Deliberate mistake (${(mistakeChance * 100).toInt()}% chance)');
          return selected;
        }
      }
    }

    // CRITICAL: If best move has very high score (critical block, capture, etc.)
    // we should strongly prefer it - don't randomize away from life-saving moves
    final bestScore = scoredMoves[0].score;
    final secondBestScore = scoredMoves.length > 1 ? scoredMoves[1].score : bestScore;

    // If best move is significantly better (>200 points ahead), always take it
    // This protects critical blocks (+1000), captures, etc.
    if (bestScore - secondBestScore > 200) {
      _logAiDecision('SELECTION: Best move (dominant by ${(bestScore - secondBestScore).toInt()} points)');
      return scoredMoves[0].position;
    }

    // NEW: If ANY move has a very high score (500+), only consider high-score moves
    // This handles the case of MULTIPLE critical blocks - we should pick one of them,
    // not randomize across the entire pool which might include low-score moves
    const criticalThreshold = 500.0;
    if (bestScore >= criticalThreshold) {
      // Find all moves within 200 points of the best (all are "critical-tier")
      final criticalMoves = scoredMoves.where((m) => m.score >= bestScore - 200).toList();
      if (criticalMoves.isNotEmpty) {
        // At high levels, pick the best critical move; at lower levels, allow some randomization among critical moves
        if (level.level >= 7 || _random.nextDouble() < level.strength) {
          _logAiDecision('SELECTION: Best critical move (${criticalMoves.length} critical moves found)');
          return criticalMoves[0].position;
        } else {
          final selected = criticalMoves[_random.nextInt(criticalMoves.length)].position;
          _logAiDecision('SELECTION: Random from ${criticalMoves.length} critical moves');
          return selected;
        }
      }
    }

    // Filter to only positive-score moves for the selection pool
    // NEVER select negative-score moves when positive ones exist
    final positiveMoves = scoredMoves.where((m) => m.score > 0).toList();
    final poolMoves = positiveMoves.isNotEmpty ? positiveMoves : scoredMoves;

    // Use much tighter selection pool based on level
    // Level 1-2: top 10 moves, Level 3-5: top 7 moves, Level 6-8: top 5, Level 9-10: top 3
    final maxPool = level.level <= 2 ? 10 : (level.level <= 5 ? 7 : (level.level <= 8 ? 5 : 3));
    final considerCount = min(maxPool, poolMoves.length);
    var topMoves = poolMoves.take(considerCount).toList();

    // NEW: Filter out moves that are drastically worse than the best
    // If best move scores 70, don't include moves scoring 5 in the pool
    // Allow moves within 50% of best score (or at least 30 points)
    if (topMoves.isNotEmpty && topMoves[0].score > 0) {
      final minAcceptableScore = max(topMoves[0].score * 0.5, topMoves[0].score - 50);
      final qualityMoves = topMoves.where((m) => m.score >= minAcceptableScore).toList();
      if (qualityMoves.isNotEmpty) {
        topMoves = qualityMoves;
      }
    }

    if (_random.nextDouble() > level.strength) {
      final selected = topMoves[_random.nextInt(topMoves.length)].position;
      _logAiDecision('SELECTION: Random from top ${topMoves.length} (level randomness)');
      return selected;
    } else {
      _logAiDecision('SELECTION: Best move (strength=${level.strength})');
      return topMoves[0].position;
    }
  }

  /// HARD VETO RULE: Check if a move should be rejected outright
  /// A move is vetoed if:
  /// 0. Dead-on-placement - no edge reach after placement (strongest veto)
  /// 1. The stone would be trapped (no escape path to edge)
  /// 2. The stone is in a "danger zone" - area about to be enclosed
  /// 3. The opponent can complete encirclement with 1 move
  /// 4. Creates small isolated group that opponent can capture in 2-3 moves
  /// UNLESS it satisfies an exception condition
  bool _isVetoedMove(Board board, Position pos, StoneColor aiColor, List<Enclosure> enclosures) {
    // Simulate placing the stone
    final newBoard = board.placeStone(pos, aiColor);

    // Check if the placed stone can reach the board edge through empty spaces
    final escapeResult = _checkEscapePathDetailed(newBoard, pos, aiColor);

    // VETO 0: Dead-on-placement - no edge reach after placement
    // This is the strongest veto - catches "placing inside sealed pocket" instantly
    if (escapeResult.edgeExitCount == 0) {
      // Check for dead-placement exceptions
      if (_hasDeadPlacementException(board, newBoard, pos, aiColor, enclosures)) {
        return false; // Exception applies - allow the move
      }
      return true; // VETO - placing in sealed pocket with no edge reach
    }

    // VETO 1: Already trapped (no escape)
    if (!escapeResult.canEscape) {
      // Stone is trapped - check for exceptions
      if (_hasVetoException(board, newBoard, pos, aiColor, enclosures, escapeResult)) {
        return false; // Exception applies - allow the move
      }
      return true; // VETO - completely trapped
    }

    // VETO 2: Danger zone - area is about to be enclosed
    // If escape path is very narrow (few edge exits AND mostly surrounded by opponent)
    if (_isInDangerZone(board, pos, aiColor, escapeResult)) {
      // Check if this move itself blocks the encirclement
      if (_isBlockingEncirclement(board, pos, aiColor)) {
        return false; // Allow - this move fights back
      }
      return true; // VETO - walking into a trap
    }

    // VETO 3: Check if opponent can complete encirclement with exactly 1 move
    // This catches cases where the region looks safe but is 1 move from being sealed
    if (_isOneMoveFromEncirclement(board, pos, aiColor, escapeResult)) {
      // Only allow if we're actively blocking their wall
      if (_isBlockingEncirclement(board, pos, aiColor)) {
        return false;
      }
      return true; // VETO - opponent can seal us in with one stone
    }

    // VETO 4: Creates small isolated group that can be captured in 2-3 moves
    // Simulates opponent's optimal response
    if (_wouldCreateCaptureableGroup(board, newBoard, pos, aiColor, enclosures)) {
      // Allow if this move captures something
      final captureResult = CaptureLogic.processMove(board, pos, aiColor, existingEnclosures: enclosures);
      if (captureResult.isValid && captureResult.captureResult != null &&
          captureResult.captureResult!.captureCount > 0) {
        return false; // Allow - we're capturing
      }
      return true; // VETO - creating a group that will just get captured
    }

    return false; // Not vetoed
  }

  /// Check if placing at pos would create a small group that opponent can capture in 2-3 moves
  /// This is a forward-looking check to avoid building into traps
  bool _wouldCreateCaptureableGroup(Board originalBoard, Board newBoard, Position pos, StoneColor aiColor, List<Enclosure> enclosures) {
    final opponentColor = aiColor.opponent;

    // Find the group that includes our new stone
    final group = _findConnectedGroup(newBoard, pos, aiColor);

    // Only worry about small groups (1-3 stones)
    if (group.length > 3) return false;

    // Count opponent stones adjacent to our group
    int opponentAdjacent = 0;
    final groupBoundary = <Position>{};

    for (final stone in group) {
      for (final adj in stone.adjacentPositions) {
        if (!newBoard.isValidPosition(adj)) continue;
        if (group.contains(adj)) continue;

        if (newBoard.getStoneAt(adj) == opponentColor) {
          opponentAdjacent++;
        } else if (newBoard.isEmpty(adj)) {
          groupBoundary.add(adj);
        }
      }
    }

    // If we're adjacent to 2+ opponent stones and have small boundary, we're in danger
    if (opponentAdjacent >= 2 && groupBoundary.length <= 4) {
      // Simulate: can opponent capture this group in 2 moves?
      for (final boundaryPos in groupBoundary) {
        // Opponent plays at boundaryPos
        final afterOpponent1 = newBoard.placeStone(boundaryPos, opponentColor);

        // Check if opponent can now capture with one more move
        final remainingBoundary = groupBoundary.where((p) => p != boundaryPos).toList();
        for (final nextPos in remainingBoundary) {
          final captureResult = CaptureLogic.processMove(afterOpponent1, nextPos, opponentColor, existingEnclosures: enclosures);
          if (captureResult.isValid && captureResult.captureResult != null) {
            if (captureResult.captureResult!.captureCount >= group.length) {
              // Opponent can capture our entire new group in 2 moves
              return true;
            }
          }
        }

        // Also check if placing at boundaryPos immediately creates an enclosure
        final captureResult1 = CaptureLogic.processMove(newBoard, boundaryPos, opponentColor, existingEnclosures: enclosures);
        if (captureResult1.isValid && captureResult1.captureResult != null) {
          if (captureResult1.captureResult!.captureCount >= group.length) {
            // Opponent can capture our group in 1 move!
            return true;
          }
        }
      }
    }

    // Check if we're building next to existing opponent stones that are forming a wall
    // Count opponent stones within distance 2
    int nearbyOpponent = 0;
    int nearbyFriendly = 0;
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        final checkPos = Position(pos.x + dx, pos.y + dy);
        if (!newBoard.isValidPosition(checkPos)) continue;
        final stone = newBoard.getStoneAt(checkPos);
        if (stone == opponentColor) nearbyOpponent++;
        if (stone == aiColor && !group.contains(checkPos)) nearbyFriendly++;
      }
    }

    // If heavily outnumbered locally and not connected to other friendly groups
    if (nearbyOpponent >= 4 && nearbyFriendly == 0 && group.length <= 2) {
      return true; // Building into enemy territory without support
    }

    return false;
  }

  /// Find all stones connected to the given position of the same color
  Set<Position> _findConnectedGroup(Board board, Position start, StoneColor color) {
    final group = <Position>{};
    final toVisit = <Position>[start];

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (group.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (board.getStoneAt(current) != color) continue;

      group.add(current);

      for (final adj in current.adjacentPositions) {
        if (!group.contains(adj)) {
          toVisit.add(adj);
        }
      }
    }

    return group;
  }

  /// Check if a dead-on-placement move qualifies for an exception
  /// Exceptions:
  /// 1. Move causes immediate capture
  /// 2. Move connects to an existing friendly region that has edge reach
  /// 3. Move increases edge exits of that region (escape creation)
  bool _hasDeadPlacementException(
    Board originalBoard,
    Board newBoard,
    Position pos,
    StoneColor aiColor,
    List<Enclosure> enclosures,
  ) {
    // Exception 1: Move immediately captures opponent stones
    final captureResult = CaptureLogic.processMove(originalBoard, pos, aiColor, existingEnclosures: enclosures);
    if (captureResult.isValid && captureResult.captureResult != null) {
      if (captureResult.captureResult!.captureCount > 0) {
        // This move captures - check if after capture we have escape
        final boardAfterCapture = captureResult.newBoard!;
        final escapeAfterCapture = _checkEscapePathDetailed(boardAfterCapture, pos, aiColor);
        if (escapeAfterCapture.edgeExitCount > 0) {
          return true; // Capturing creates edge reach
        }
      }
    }

    // Exception 2: Connects to a friendly group that already has edge reach
    for (final adjacent in pos.adjacentPositions) {
      if (!newBoard.isValidPosition(adjacent)) continue;
      if (newBoard.getStoneAt(adjacent) == aiColor) {
        // Found friendly stone - check if that group has edge reach
        final friendlyEdgeReach = _countEdgeExitsForGroup(newBoard, {adjacent});
        if (friendlyEdgeReach > 0) {
          return true; // Connected to a group with edge reach
        }
      }
    }

    // Exception 3: Move increases edge exits of a connected region
    // (Already implicitly covered by exception 2 - if connecting to a group with edge reach,
    // the combined region will have edge reach)

    return false;
  }

  /// Check if opponent can complete an encirclement around this position with exactly 1 move
  /// OPTIMIZED: Early returns and limited simulations for performance
  bool _isOneMoveFromEncirclement(Board board, Position pos, StoneColor aiColor, _EscapeResult escapeResult) {
    final opponentColor = aiColor.opponent;

    // Early return: safe if many exits (3+ is generally safe)
    if (escapeResult.edgeExitCount >= 3) {
      return false;
    }

    // Early return: large regions are safe
    if (escapeResult.emptyRegion.length > 25) {
      return false;
    }

    // Find critical gaps - positions where opponent could seal us in
    // Only look at positions that would actually reduce edge exits
    final criticalGaps = <Position>[];

    for (final emptyPos in escapeResult.emptyRegion) {
      // Only check positions near edge exits (the chokepoints)
      if (!_isOnEdge(emptyPos, board.size) && escapeResult.edgeExitCount > 1) {
        continue; // Skip interior positions if we have multiple exits
      }

      for (final adj in emptyPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (board.getStoneAt(adj) == opponentColor) {
          // This empty position is next to an opponent stone
          // Check if placing an opponent stone at any nearby empty would complete encirclement
          for (final nearEmpty in emptyPos.adjacentPositions) {
            if (!board.isValidPosition(nearEmpty)) continue;
            if (board.isEmpty(nearEmpty) && !escapeResult.emptyRegion.contains(nearEmpty)) {
              // This empty position is outside our region but adjacent to it
              if (!criticalGaps.contains(nearEmpty)) {
                criticalGaps.add(nearEmpty);
              }
            }
          }
        }
      }
    }

    // Limit to 2 simulations max for performance
    final gapsToTest = criticalGaps.take(2);

    // For each critical gap, simulate opponent placing there and check if we'd be trapped
    for (final gap in gapsToTest) {
      // Skip if gap is the same as our intended position
      if (gap == pos) continue;

      // Simulate opponent placing at this gap
      final simulatedBoard = board.placeStone(gap, opponentColor);

      // Safety check: ensure pos is still empty after opponent's move
      if (!simulatedBoard.isEmpty(pos)) continue;

      // Now simulate us placing at our intended position
      final afterOurMove = simulatedBoard.placeStone(pos, aiColor);
      // Check if we can still escape
      final escapeAfter = _checkEscapePathDetailed(afterOurMove, pos, aiColor);

      if (!escapeAfter.canEscape) {
        // Opponent can trap us with one stone - this is dangerous!
        return true;
      }
    }

    return false;
  }

  /// Result of doomed position check
  ({bool isDoomed, String reason}) _isPositionDoomed(Board originalBoard, Board newBoard, Position pos, StoneColor aiColor, List<Enclosure> enclosures) {
    final opponentColor = aiColor.opponent;

    // Check escape path after our move
    final escapeAfter = _checkEscapePathDetailed(newBoard, pos, aiColor);

    // If we have good escape, not doomed
    if (escapeAfter.edgeExitCount >= 3) {
      return (isDoomed: false, reason: '');
    }

    // If large open region, not doomed
    if (escapeAfter.emptyRegion.length > 15) {
      return (isDoomed: false, reason: '');
    }

    // Find all positions where opponent could play to complete encirclement
    // These are empty positions OUTSIDE our escape region that border it
    final encirclementCompletionPoints = <Position>[];

    for (final emptyPos in escapeAfter.emptyRegion) {
      for (final adj in emptyPos.adjacentPositions) {
        if (!newBoard.isValidPosition(adj)) continue;
        if (newBoard.isEmpty(adj) && !escapeAfter.emptyRegion.contains(adj)) {
          // This is an empty position outside our region - potential encirclement point
          if (!encirclementCompletionPoints.contains(adj)) {
            encirclementCompletionPoints.add(adj);
          }
        }
      }
    }

    // If only 1-2 completion points, check if opponent playing there would capture us
    if (encirclementCompletionPoints.length <= 2) {
      for (final completionPoint in encirclementCompletionPoints) {
        // Simulate opponent playing at the completion point
        final afterOpponent = newBoard.placeStone(completionPoint, opponentColor);

        // Check if this creates an enclosure that captures our stone
        final captureResult = CaptureLogic.processMove(
          newBoard, completionPoint, opponentColor,
          existingEnclosures: enclosures
        );

        if (captureResult.isValid && captureResult.captureResult != null) {
          final captured = captureResult.captureResult!.captureCount;
          if (captured > 0) {
            // Opponent can capture us with 1 move - we're doomed!
            return (isDoomed: true, reason: '1 move to capture $captured');
          }
        }

        // Even if not immediate capture, check if we'd be completely sealed
        final escapeAfterOpponent = _checkEscapePathDetailed(afterOpponent, pos, aiColor);
        if (escapeAfterOpponent.edgeExitCount == 0 || !escapeAfterOpponent.canEscape) {
          return (isDoomed: true, reason: '1 move to seal');
        }
      }
    }

    return (isDoomed: false, reason: '');
  }

  /// Check if a position is in a "danger zone" - an area about to be enclosed
  /// Criteria: Limited escape routes AND high opponent presence on perimeter
  /// CRITICAL: Also checks if opponent can close the encirclement in 1-2 moves
  /// ENHANCED: More aggressive detection of forming encirclements
  bool _isInDangerZone(Board board, Position pos, StoneColor aiColor, _EscapeResult escapeResult) {
    final opponentColor = aiColor.opponent;

    // CRITICAL CHECK: Can opponent complete encirclement in 1-2 moves?
    // Find the "critical gaps" - empty positions on edge exits that opponent could fill
    if (escapeResult.edgeExitCount <= 4 && escapeResult.emptyRegion.length < 40) {
      final criticalGaps = _findCriticalGaps(board, escapeResult.emptyRegion, opponentColor);

      // If opponent can close ALL remaining exits with 1-2 moves, this is extremely dangerous
      if (criticalGaps.isNotEmpty && criticalGaps.length >= escapeResult.edgeExitCount) {
        // Opponent can seal this area completely - VETO
        return true;
      }

      // Even if there are a few exits, if most can be closed quickly, it's dangerous
      if (escapeResult.edgeExitCount <= 3 && criticalGaps.isNotEmpty) {
        return true;
      }
    }

    // ENHANCED: Count opponent stones on the perimeter of this region
    // Use a more aggressive threshold for detecting danger
    int opponentPerimeterCount = 0;
    int totalPerimeterCount = 0;
    int aiPerimeterCount = 0;

    for (final emptyPos in escapeResult.emptyRegion) {
      for (final adj in emptyPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        final stone = board.getStoneAt(adj);
        if (stone != null) {
          totalPerimeterCount++;
          if (stone == opponentColor) {
            opponentPerimeterCount++;
          } else {
            aiPerimeterCount++;
          }
        }
      }
    }

    // If opponent controls most of the perimeter, it's a danger zone
    if (totalPerimeterCount > 0) {
      final opponentRatio = opponentPerimeterCount / totalPerimeterCount;

      // ENHANCED THRESHOLDS:
      // Few exits (1-2) with any significant opponent presence = danger
      if (escapeResult.edgeExitCount <= 2) {
        if (opponentRatio > 0.35) return true;  // Lowered from 0.4/0.6
      }

      // Medium exits (3-4) with high opponent presence = danger
      if (escapeResult.edgeExitCount <= 4 && escapeResult.emptyRegion.length < 25) {
        if (opponentRatio > 0.5) return true;  // New check
      }

      // Small region with opponent dominance = danger regardless of exits
      if (escapeResult.emptyRegion.length < 15 && opponentRatio > 0.6) {
        return true;
      }

      // If opponent has way more stones than us on perimeter, we're losing the battle
      if (opponentPerimeterCount > aiPerimeterCount * 2 && escapeResult.edgeExitCount <= 4) {
        return true;
      }
    }

    return false;
  }

  /// Find "critical gaps" - empty positions that are adjacent to edge exits
  /// and could be filled by opponent to seal the escape routes
  List<Position> _findCriticalGaps(Board board, Set<Position> emptyRegion, StoneColor opponentColor) {
    final criticalGaps = <Position>[];

    for (final emptyPos in emptyRegion) {
      // Check if this empty position is on the edge
      if (_isOnEdge(emptyPos, board.size)) {
        // Find adjacent empty positions that are NOT on the edge
        // These are the "chokepoints" that could seal this exit
        for (final adj in emptyPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (board.isEmpty(adj) && !_isOnEdge(adj, board.size)) {
            // This is an interior position adjacent to an edge exit
            // Check if opponent has stones nearby (could place here to seal)
            bool opponentNearby = false;
            for (final adjAdj in adj.adjacentPositions) {
              if (!board.isValidPosition(adjAdj)) continue;
              if (board.getStoneAt(adjAdj) == opponentColor) {
                opponentNearby = true;
                break;
              }
            }
            if (opponentNearby && !criticalGaps.contains(adj)) {
              criticalGaps.add(adj);
            }
          }
        }

        // Also check: is this edge position itself a chokepoint?
        // If opponent has stones on both sides along the edge, placing here seals it
        int opponentAdjacentOnEdge = 0;
        for (final adj in emptyPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (board.getStoneAt(adj) == opponentColor && _isOnEdge(adj, board.size)) {
            opponentAdjacentOnEdge++;
          }
        }
        // If opponent stones flank this edge position, it's a critical gap
        if (opponentAdjacentOnEdge >= 1 && !criticalGaps.contains(emptyPos)) {
          criticalGaps.add(emptyPos);
        }
      }
    }

    return criticalGaps;
  }

  /// Check if placing a stone at this position would block an opponent's encirclement
  bool _isBlockingEncirclement(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;

    // Count adjacent opponent stones - if surrounded by opponent, we're blocking their wall
    int adjacentOpponent = 0;

    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      final stone = board.getStoneAt(adj);
      if (stone == opponentColor) {
        adjacentOpponent++;
      }
    }

    // If we're placing between opponent stones, we're disrupting their wall
    if (adjacentOpponent >= 2) {
      return true;
    }

    // Check if this position is a "gap" in opponent's forming wall
    // Look for opponent stones in a line/curve pattern around this position
    return _isGapInOpponentWall(board, pos, opponentColor);
  }

  /// Check if position is a gap in opponent's wall formation
  bool _isGapInOpponentWall(Board board, Position pos, StoneColor opponentColor) {
    // Check 8 directions for opponent stone patterns
    final directions = [
      [Position(-1, 0), Position(1, 0)],   // horizontal
      [Position(0, -1), Position(0, 1)],   // vertical
      [Position(-1, -1), Position(1, 1)], // diagonal
      [Position(-1, 1), Position(1, -1)], // anti-diagonal
    ];

    for (final pair in directions) {
      bool hasOpponentOnBothSides = true;
      for (final dir in pair) {
        bool foundOpponent = false;
        // Look up to 2 cells in each direction
        for (int dist = 1; dist <= 2; dist++) {
          final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
          if (!board.isValidPosition(checkPos)) break;
          final stone = board.getStoneAt(checkPos);
          if (stone == opponentColor) {
            foundOpponent = true;
            break;
          } else if (stone != null) {
            // Our stone - breaks the opponent's line
            break;
          }
        }
        if (!foundOpponent) {
          hasOpponentOnBothSides = false;
          break;
        }
      }
      if (hasOpponentOnBothSides) {
        return true; // This position is a gap in opponent's wall
      }
    }

    return false;
  }

  /// Flood-fill from the placed stone through empty spaces to check for edge escape
  /// Returns detailed escape result with edge exit count for danger zone detection
  /// Also tracks 2-wide corridors which are nearly impossible to close
  _EscapeResult _checkEscapePathDetailed(Board board, Position startPos, StoneColor aiColor) {
    final visited = <Position>{};
    final toVisit = <Position>[startPos];
    final emptyRegion = <Position>{};
    final edgeExits = <Position>{}; // Track unique edge exit positions
    bool canEscape = false;

    // Start by adding the stone position
    visited.add(startPos);

    // Check adjacent empty positions from the stone
    for (final adjacent in startPos.adjacentPositions) {
      if (board.isValidPosition(adjacent) && board.isEmpty(adjacent)) {
        toVisit.add(adjacent);
      }
    }

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (visited.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;

      // We only traverse through empty spaces
      if (!board.isEmpty(current)) continue;

      visited.add(current);
      emptyRegion.add(current);

      // Check if this empty position is on the board edge
      if (_isOnEdge(current, board.size)) {
        canEscape = true;
        edgeExits.add(current);
      }

      // Add adjacent empty positions
      for (final adjacent in current.adjacentPositions) {
        if (!visited.contains(adjacent) && board.isValidPosition(adjacent)) {
          if (board.isEmpty(adjacent)) {
            toVisit.add(adjacent);
          }
        }
      }
    }

    // Count 2-wide corridors to edge (much harder to close)
    final wideCorridorCount = _countWideCorridors(board, edgeExits);

    return _EscapeResult(
      canEscape: canEscape,
      emptyRegion: emptyRegion,
      edgeExitCount: edgeExits.length,
      wideCorridorCount: wideCorridorCount,
    );
  }

  /// Count 2-wide corridors to edge
  /// A 2-wide corridor exists when two adjacent edge cells are both part of the escape path
  /// BUT only matters when the path is constrained (not wide open board)
  int _countWideCorridors(Board board, Set<Position> edgeExits) {
    // If we have many edge exits (>15), the board is wide open - corridors don't matter
    // Wide corridor concept only applies to constrained escape paths
    if (edgeExits.length > 15) {
      return 0; // Wide open board - no corridor bonus needed
    }

    // If we have very few edge exits (<=3), we might be in a tight spot
    // but pairs can still indicate a 2-wide corridor
    if (edgeExits.isEmpty) return 0;

    int wideCorridorCount = 0;
    final counted = <Position>{};

    for (final edgePos in edgeExits) {
      if (counted.contains(edgePos)) continue;

      // Check if any adjacent edge position is also an exit (forms 2-wide corridor)
      for (final adj in edgePos.adjacentPositions) {
        if (edgeExits.contains(adj) && !counted.contains(adj)) {
          // Both are edge exits and adjacent = 2-wide corridor
          wideCorridorCount++;
          counted.add(edgePos);
          counted.add(adj);
          break;
        }
      }
    }

    // Cap at reasonable maximum - even 5 wide corridors is very safe
    return wideCorridorCount > 5 ? 5 : wideCorridorCount;
  }

  /// Check if the move qualifies for a veto exception
  bool _hasVetoException(
    Board originalBoard,
    Board newBoard,
    Position pos,
    StoneColor aiColor,
    List<Enclosure> enclosures,
    _EscapeResult escapeResult,
  ) {
    // Exception 1: Move immediately captures opponent stones (counter-encirclement)
    final captureResult = CaptureLogic.processMove(originalBoard, pos, aiColor, existingEnclosures: enclosures);
    if (captureResult.isValid && captureResult.captureResult != null) {
      if (captureResult.captureResult!.captureCount > 0) {
        // This move captures - check if after capture we have escape
        final boardAfterCapture = captureResult.newBoard!;
        final escapeAfterCapture = _checkEscapePathDetailed(boardAfterCapture, pos, aiColor);
        if (escapeAfterCapture.canEscape) {
          return true; // Capturing creates escape path
        }
      }
    }

    // Exception 2: Connects to a friendly group that already has an edge path
    for (final adjacent in pos.adjacentPositions) {
      if (!newBoard.isValidPosition(adjacent)) continue;
      if (newBoard.getStoneAt(adjacent) == aiColor) {
        // Found friendly stone - check if that group has escape
        final friendlyEscape = _checkGroupEscapePath(newBoard, adjacent, aiColor);
        if (friendlyEscape) {
          return true; // Connected to a group with escape
        }
      }
    }

    // Exception 3: The move itself creates a new escape path after placement
    // (This is already covered by the main escape check, but we double-check
    // in case the stone placement changes the topology)
    if (escapeResult.canEscape) {
      return true;
    }

    return false;
  }

  /// Check if a group (starting from any stone in it) has an escape path to the edge
  bool _checkGroupEscapePath(Board board, Position groupStone, StoneColor color) {
    // Find all stones in this group
    final group = <Position>{};
    final toVisit = <Position>[groupStone];

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (group.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (board.getStoneAt(current) != color) continue;

      group.add(current);

      for (final adjacent in current.adjacentPositions) {
        if (!group.contains(adjacent)) {
          toVisit.add(adjacent);
        }
      }
    }

    // Now check if any empty space adjacent to this group can reach the edge
    final checkedEmpty = <Position>{};
    for (final stone in group) {
      for (final adjacent in stone.adjacentPositions) {
        if (!board.isValidPosition(adjacent)) continue;
        if (!board.isEmpty(adjacent)) continue;
        if (checkedEmpty.contains(adjacent)) continue;

        // Flood-fill from this empty space
        final escapeCheck = _floodFillToEdge(board, adjacent);
        if (escapeCheck) {
          return true;
        }
        // Mark all visited positions to avoid re-checking
        checkedEmpty.add(adjacent);
      }
    }

    return false;
  }

  /// Simple flood-fill to check if an empty position can reach the board edge
  bool _floodFillToEdge(Board board, Position start) {
    final visited = <Position>{};
    final toVisit = <Position>[start];

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();

      if (visited.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (!board.isEmpty(current)) continue;

      visited.add(current);

      if (_isOnEdge(current, board.size)) {
        return true;
      }

      for (final adjacent in current.adjacentPositions) {
        if (!visited.contains(adjacent)) {
          toVisit.add(adjacent);
        }
      }
    }

    return false;
  }

  /// Check if a position is on the board edge
  bool _isOnEdge(Position pos, int boardSize) {
    return pos.x == 0 || pos.y == 0 || pos.x == boardSize - 1 || pos.y == boardSize - 1;
  }

  /// ENCIRCLEMENT PATH TRACING
  /// When AI stones are being encircled, traces the boundary of the forming encirclement
  /// and finds "gap" positions where placing a stone would break the encirclement.
  /// This allows the AI to find blocking moves on ANY side of the encirclement,
  /// not just near the opponent's last move.

  /// Find all gap positions that would break forming encirclements around endangered AI stones
  /// Returns positions that, if filled by AI, would create new escape routes
  Set<Position> _findEncirclementBreakingMoves(Board board, StoneColor aiColor, _TurnCache cache) {
    final breakingMoves = <Position>{};
    final opponentColor = aiColor.opponent;

    // Check each endangered AI group
    for (final group in cache.aiGroups) {
      // Only care about groups with limited escape routes (being encircled)
      if (group.edgeExitCount > 4) continue;
      if (group.stones.isEmpty) continue;

      // Get the escape result for this group
      final sampleStone = group.stones.first;
      final escapeResult = _checkEscapePathDetailed(board, sampleStone, aiColor);

      // If already has good escapes, skip
      if (escapeResult.edgeExitCount > 4) continue;

      // Trace the encirclement boundary - find opponent stones forming the wall
      final boundary = _traceEncirclementBoundary(
        board, escapeResult.emptyRegion, group.stones, aiColor);

      // Find gaps in the boundary - empty positions adjacent to opponent walls
      // that would create new escape routes if filled by AI
      for (final boundaryPos in boundary.opponentWallPositions) {
        // Check each empty position adjacent to this wall stone
        for (final adj in boundaryPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (!board.isEmpty(adj)) continue;

          // Skip if already in the escape region (wouldn't add new escapes)
          if (escapeResult.emptyRegion.contains(adj)) continue;

          // Check if placing here would create new escape routes
          final testBoard = board.placeStone(adj, aiColor);
          final escapeAfter = _checkEscapePathDetailed(testBoard, sampleStone, aiColor);

          // If this move opens up more escape routes, it's a breaking move!
          // Relaxed threshold: ANY improvement counts, not just +2 or more
          if (escapeAfter.edgeExitCount > escapeResult.edgeExitCount) {
            breakingMoves.add(adj);
          }
        }
      }

      // Also check positions that would connect our group to edge directly
      for (final emptyPos in boundary.edgeAdjacentEmpties) {
        if (board.isEmpty(emptyPos)) {
          // Verify this move helps
          final testBoard = board.placeStone(emptyPos, aiColor);
          final escapeAfter = _checkEscapePathDetailed(testBoard, sampleStone, aiColor);
          if (escapeAfter.edgeExitCount > escapeResult.edgeExitCount) {
            breakingMoves.add(emptyPos);
          }
        }
      }
    }

    return breakingMoves;
  }

  /// Trace the boundary of an encirclement around AI stones
  /// Returns the opponent stones forming the wall plus any empty positions on the edge
  _EncirclementBoundary _traceEncirclementBoundary(
    Board board,
    Set<Position> emptyRegion,
    Set<Position> aiStones,
    StoneColor aiColor,
  ) {
    final opponentColor = aiColor.opponent;
    final opponentWall = <Position>{};
    final edgeAdjacentEmpties = <Position>{};

    // Find all opponent stones adjacent to the escape region
    // These form the "wall" of the encirclement
    for (final emptyPos in emptyRegion) {
      for (final adj in emptyPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) {
          // Off-board = edge, check if this empty is adjacent to edge
          if (_isOnEdge(emptyPos, board.size)) {
            edgeAdjacentEmpties.add(emptyPos);
          }
          continue;
        }

        if (board.getStoneAt(adj) == opponentColor) {
          opponentWall.add(adj);
        }
      }
    }

    // Also trace along the AI stones to find adjacent opponent stones
    for (final aiPos in aiStones) {
      for (final adj in aiPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (board.getStoneAt(adj) == opponentColor) {
          opponentWall.add(adj);
        }
      }
    }

    // Find empty positions adjacent to the wall that are NOT in the escape region
    // These are potential "other side" blocking positions
    final outerEmpties = <Position>{};
    for (final wallPos in opponentWall) {
      for (final adj in wallPos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (!board.isEmpty(adj)) continue;
        if (emptyRegion.contains(adj)) continue; // Already inside
        if (aiStones.contains(adj)) continue;
        outerEmpties.add(adj);
      }
    }

    // Also add edge-adjacent empties that are outside the current escape region
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        if (!_isOnEdge(pos, board.size)) continue;
        if (!board.isEmpty(pos)) continue;
        if (emptyRegion.contains(pos)) continue;

        // Check if this edge position connects to any opponent wall stone
        for (final adj in pos.adjacentPositions) {
          if (opponentWall.contains(adj)) {
            edgeAdjacentEmpties.add(pos);
            break;
          }
        }
      }
    }

    return _EncirclementBoundary(
      opponentWallPositions: opponentWall,
      edgeAdjacentEmpties: edgeAdjacentEmpties,
      outerEmpties: outerEmpties,
    );
  }

  /// Evaluate if a move is a strategic encirclement-breaking move
  /// High bonus for moves that break encirclements even if far from opponent's last move
  double _evaluateEncirclementBreaking(
    Board board,
    Position pos,
    StoneColor aiColor,
    Set<Position> encirclementBreakingMoves,
  ) {
    if (!encirclementBreakingMoves.contains(pos)) return 0;

    // This is a move that breaks an encirclement!
    // Give it a strong bonus to override the proximity penalty
    // Proximity penalty at distance 5+ is -30, so we need at least +35 to overcome it

    // Check how much this move improves our escape
    double breakingBonus = 80; // Strong base bonus

    // Additional bonus based on how many escape routes it creates
    final aiGroups = <Position>[];
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final p = Position(x, y);
        if (board.getStoneAt(p) == aiColor) aiGroups.add(p);
      }
    }

    if (aiGroups.isNotEmpty) {
      for (final aiStone in aiGroups) {
        final escapeBefore = _checkEscapePathDetailed(board, aiStone, aiColor);
        if (escapeBefore.edgeExitCount <= 3) {
          // This group is endangered - check if our move helps
          final testBoard = board.placeStone(pos, aiColor);
          final escapeAfter = _checkEscapePathDetailed(testBoard, aiStone, aiColor);

          // Bonus scales with improvement
          final improvement = escapeAfter.edgeExitCount - escapeBefore.edgeExitCount;
          if (improvement > 0) {
            breakingBonus += improvement * 15;
          }
        }
      }
    }

    return breakingBonus;
  }

  /// Get valid move positions - optimized with deduplication grid and cache-aware filtering
  /// Generates candidates from:
  /// 1. CRITICAL: Positions where opponent could capture our stones (must block!)
  /// 2. Encirclement-breaking moves (positions that break encirclement from ANY side)
  /// 3. Chokepoints that reduce opponent's escape robustness
  /// 4. All empty cells within radius 2 of any stone
  /// 5. Boundary gaps of endangered AI regions (edgeExits <= 3)
  /// 6. Boundary gaps of low-exit opponent regions (attack targets, edgeExits <= 4)
  List<Position> _getValidMoves(Board board, StoneColor color, List<Enclosure> enclosures, Position? opponentLastMove, _TurnCache cache, Set<Position> criticalBlockingPositions, Set<Position> chokepoints, Set<Position> poiCandidates, Set<Position> encirclementBreakingMoves) {
    final validMoves = <Position>[];
    // Deduplication grid to avoid adding same position multiple times
    final considered = List.generate(board.size, (_) => List.filled(board.size, false));

    // Helper to add candidate if not already considered
    // Also rejects moves inside ANY enclosure (both players)
    void addCandidate(Position pos) {
      if (!board.isValidPosition(pos)) return;
      if (considered[pos.x][pos.y]) return;
      considered[pos.x][pos.y] = true;

      // BLOCK: Don't allow moves inside any enclosure (useless moves)
      for (final enclosure in enclosures) {
        if (enclosure.containsPosition(pos)) {
          return; // Skip - inside an enclosure
        }
      }

      if (board.isEmpty(pos) && _isValidMoveQuick(board, pos, color, enclosures)) {
        validMoves.add(pos);
      }
    }

    // Helper to add candidates in radius
    void addCandidatesInRadius(Position center, int radius) {
      for (int dx = -radius; dx <= radius; dx++) {
        for (int dy = -radius; dy <= radius; dy++) {
          addCandidate(Position(center.x + dx, center.y + dy));
        }
      }
    }

    // 0. CRITICAL: Always include positions where opponent could capture our stones
    // These must be considered regardless of other filters
    for (final criticalPos in criticalBlockingPositions) {
      addCandidate(criticalPos);
    }

    // 0.5. Encirclement-breaking moves: Positions that break forming encirclements
    // These can be on ANY side of the encirclement, not just near opponent's last move
    for (final breakingPos in encirclementBreakingMoves) {
      addCandidate(breakingPos);
    }

    // 0.6. POI candidates: Distant sectors with opponent activity (levels 8+)
    // Contest opponent's strategic build-up in areas we're not focused on
    for (final poiPos in poiCandidates) {
      addCandidate(poiPos);
    }

    // 1. Chokepoints that reduce opponent's escape robustness (high-value targets)
    for (final chokepoint in chokepoints) {
      addCandidate(chokepoint);
    }

    // If board is empty or nearly empty, start near opponent's move
    if (board.stones.length < 4) {
      if (opponentLastMove != null) {
        // Start near opponent's first move (within 3 cells)
        addCandidatesInRadius(opponentLastMove, 3);
      } else {
        // No opponent move yet - fallback to center
        final center = board.size ~/ 2;
        addCandidatesInRadius(Position(center, center), 3);
      }
      return validMoves;
    }

    // 2. All empty cells within radius 2 of any stone
    for (final stonePos in board.stones.keys) {
      addCandidatesInRadius(stonePos, 2);
    }

    // 3. Boundary gaps of endangered AI regions (edgeExits <= 3)
    for (final group in cache.aiGroups) {
      if (group.edgeExitCount <= 3) {
        for (final gap in group.boundaryEmpties) {
          addCandidate(gap);
        }
      }
    }

    // 4. Boundary gaps of low-exit opponent regions (attack targets, edgeExits <= 4)
    for (final group in cache.opponentGroups) {
      if (group.edgeExitCount <= 4) {
        for (final gap in group.boundaryEmpties) {
          addCandidate(gap);
        }
      }
    }

    // 5. STRATEGIC EXPANSION for levels 6+: Add distant edge positions
    // This prevents the AI from clustering all stones near opponent's fort
    // Instead, it should establish presence in multiple areas of the board
    if (board.stones.length >= 6) {
      // Find quadrants where AI has no presence
      final aiQuadrants = <int>{};
      final opponentQuadrants = <int>{};

      for (final entry in board.stones.entries) {
        final quad = _getQuadrant(entry.key, board.size);
        if (entry.value == color) {
          aiQuadrants.add(quad);
        } else {
          opponentQuadrants.add(quad);
        }
      }

      // Add edge positions in quadrants where AI is NOT present
      // This encourages territorial balance
      for (int quad = 0; quad < 4; quad++) {
        if (!aiQuadrants.contains(quad)) {
          // Add some edge positions in this quadrant
          final quadPositions = _getQuadrantEdgePositions(board.size, quad);
          for (final pos in quadPositions.take(8)) {
            addCandidate(pos);
          }
        }
      }

      // Also add general edge positions for strategic anchoring
      // AI should always consider establishing edge presence
      final edgePositions = _getStrategicEdgePositions(board);
      for (final pos in edgePositions.take(12)) {
        addCandidate(pos);
      }
    }

    return validMoves;
  }

  /// Get quadrant (0-3) for a position
  int _getQuadrant(Position pos, int boardSize) {
    final midX = boardSize ~/ 2;
    final midY = boardSize ~/ 2;
    if (pos.x < midX) {
      return pos.y < midY ? 0 : 2;
    } else {
      return pos.y < midY ? 1 : 3;
    }
  }

  /// Get edge positions in a specific quadrant
  List<Position> _getQuadrantEdgePositions(int boardSize, int quadrant) {
    final positions = <Position>[];
    final midX = boardSize ~/ 2;
    final midY = boardSize ~/ 2;

    int xStart, xEnd, yStart, yEnd;
    switch (quadrant) {
      case 0: // top-left
        xStart = 0; xEnd = midX; yStart = 0; yEnd = midY;
        break;
      case 1: // top-right
        xStart = midX; xEnd = boardSize; yStart = 0; yEnd = midY;
        break;
      case 2: // bottom-left
        xStart = 0; xEnd = midX; yStart = midY; yEnd = boardSize;
        break;
      case 3: // bottom-right
        xStart = midX; xEnd = boardSize; yStart = midY; yEnd = boardSize;
        break;
      default:
        return positions;
    }

    // Add edge positions in this quadrant (prioritize 2 cells from edge for stability)
    for (int x = xStart; x < xEnd; x++) {
      for (int y = yStart; y < yEnd; y++) {
        final pos = Position(x, y);
        if (_distanceFromEdge(pos, boardSize) <= 2) {
          positions.add(pos);
        }
      }
    }

    // Shuffle for variety
    positions.shuffle(Random());
    return positions;
  }

  /// Get strategic edge positions across the board
  List<Position> _getStrategicEdgePositions(Board board) {
    final positions = <Position>[];
    final size = board.size;

    // Add positions 2 cells from each edge (anchor positions)
    // These are strategically valuable as starting points for territory
    for (int i = 2; i < size - 2; i += 3) {
      // Top edge area
      if (board.isEmpty(Position(i, 1))) positions.add(Position(i, 1));
      if (board.isEmpty(Position(i, 2))) positions.add(Position(i, 2));
      // Bottom edge area
      if (board.isEmpty(Position(i, size - 2))) positions.add(Position(i, size - 2));
      if (board.isEmpty(Position(i, size - 3))) positions.add(Position(i, size - 3));
      // Left edge area
      if (board.isEmpty(Position(1, i))) positions.add(Position(1, i));
      if (board.isEmpty(Position(2, i))) positions.add(Position(2, i));
      // Right edge area
      if (board.isEmpty(Position(size - 2, i))) positions.add(Position(size - 2, i));
      if (board.isEmpty(Position(size - 3, i))) positions.add(Position(size - 3, i));
    }

    positions.shuffle(Random());
    return positions;
  }

  /// Quick move validation - checks if position is empty and not inside opponent's enclosure
  /// Full capture simulation happens only during scoring
  bool _isValidMoveQuick(Board board, Position pos, StoneColor color, List<Enclosure> enclosures) {
    // Basic validation: position must be empty and on board
    if (!board.isValidPosition(pos) || !board.isEmpty(pos)) {
      return false;
    }
    // Check if position is inside opponent's enclosure (fort)
    for (final enclosure in enclosures) {
      if (enclosure.owner != color && enclosure.containsPosition(pos)) {
        return false;
      }
    }
    // For now, accept all empty positions in candidate set
    // The full processMove in _evaluateMove will catch any invalid moves
    return true;
  }

  /// Evaluate a move and return a score
  /// OPTIMIZED: Difficulty-based feature gating to reduce computation at lower levels
  double _evaluateMove(
      Board board, Position pos, StoneColor aiColor, AiLevel level, Position? opponentLastMove, List<Enclosure> enclosures, _TurnCache cache, Set<Position> criticalBlockingPositions) {
    double score = 0.0;
    final levelValue = level.level; // 1-10

    // Simulate placing the stone
    final result = CaptureLogic.processMove(board, pos, aiColor, existingEnclosures: enclosures);
    if (!result.isValid) return -1000; // Invalid move

    final newBoard = result.newBoard!;
    final capturedCount = result.captureResult?.captureCount ?? 0;
    final newEnclosures = result.captureResult?.newEnclosures ?? [];

    // === ALWAYS COMPUTED (all levels) ===

    // 0. CRITICAL DEFENSE: If this position blocks opponent capture, MASSIVE bonus
    // This is computed at ALL levels because survival is paramount
    if (criticalBlockingPositions.contains(pos)) {
      score += 1000; // Highest priority - must block capture threats
    }

    // 1. Capture bonus (high priority) - always important
    score += capturedCount * 80;

    // 1.5 HIGHEST PRIORITY: Complete encirclement when possible!
    if (newEnclosures.isNotEmpty) {
      score += 200;
      for (final enclosure in newEnclosures) {
        score += enclosure.interiorPositions.length * 5;
      }
    }

    // 2. Proximity to opponent's last move (keeps game focused) - always important
    score += _evaluateProximityToOpponent(board, pos, opponentLastMove);

    // 2.5 BLOCKING: Bonus for blocking opponent's expansion direction
    // If opponent just placed, we should block their natural extension
    score += _evaluateBlockingExpansion(board, pos, aiColor, opponentLastMove) * 25;

    // 9. Connection bonus (connect own groups) - simple, always useful
    score += _evaluateConnection(board, pos, aiColor) * 5;

    // 9.5 Connection strength - prefer 2+ connection points, penalize single connections
    score += _evaluateConnectionStrength(board, pos, aiColor, cache) * 1;

    // 7. Center bonus - simple calculation, always useful
    score += _evaluateCenterBonus(board, pos) * 1;

    // === LEVEL 3+: Add urgent defense and capture blocking ===
    if (levelValue >= 3) {
      // 11.5 URGENT: Check if we MUST block to survive
      score += _evaluateUrgentDefense(board, pos, aiColor) * 50;

      // 11.6 CRITICAL: Check if opponent could capture our stones (detailed check)
      score += _evaluateCaptureBlockingMove(board, pos, aiColor, enclosures, criticalBlockingPositions) * 1;

      // 11.7 SACRIFICE EVALUATION: Don't waste moves saving small doomed groups
      // Sometimes it's better to sacrifice 1-2 stones to capture 3+
      score += _evaluateSacrificeValue(board, pos, aiColor, cache, enclosures);

      // Local empties (renamed from liberties) - minor tiebreaker
      score += _evaluateLocalEmpties(newBoard, pos, aiColor) * 1;

      // 5. Contest opponent stones nearby
      score += _evaluateContestOpponent(board, pos, aiColor) * 8;
    }

    // === ALL LEVELS: Penalty for placing in contested/surrounded positions ===
    // CRITICAL: Penalize moves where we're being surrounded - this is survival!
    score -= _evaluateSurroundedPenalty(board, pos, aiColor) * 40;

    // === ALL LEVELS: CRITICAL - Check edge connectivity after placement ===
    // In Edgeline, a group without edge connectivity is DEAD
    // This is the most important survival check
    final escapeAfterMove = _checkEscapePathDetailed(newBoard, pos, aiColor);
    if (escapeAfterMove.edgeExitCount == 0) {
      // NO EDGE ACCESS = certain death, massive penalty
      score -= 500;
    } else if (escapeAfterMove.edgeExitCount <= 2) {
      // Very limited escape = high risk
      score -= (3 - escapeAfterMove.edgeExitCount) * 50;
    } else if (escapeAfterMove.edgeExitCount <= 4) {
      // Limited escape = moderate risk
      score -= (5 - escapeAfterMove.edgeExitCount) * 15;
    }
    // Bonus for wide corridors (2-wide = nearly uncapturable)
    if (escapeAfterMove.wideCorridorCount > 0) {
      score += escapeAfterMove.wideCorridorCount * 20;
    }

    // === LEVEL 3+: Squeeze Detection - defend corridor width ===
    if (levelValue >= 3) {
      // CRITICAL: Detect when opponent is narrowing our corridors from 2-wide to 1-wide
      // This is the #1 cause of unexpected captures in simulation
      score += _evaluateSqueezeDefense(board, pos, aiColor, cache);
    }

    // === LEVEL 4+: Active Cut Scanner - find cutting opportunities ===
    if (levelValue >= 4) {
      // OFFENSIVE: Actively look for moves that cut opponent from edge
      // Cutting was the winning move in 84% of simulated games
      // Scale down at levels 4-7 to prevent first-mover advantage
      // (Level 8+ has POI which provides counterbalance)
      final cutMultiplier = levelValue <= 5 ? 0.5 : (levelValue <= 7 ? 0.7 : 1.0);
      score += _evaluateCuttingOpportunity(board, pos, aiColor, cache) * cutMultiplier;
    }

    // === ALL LEVELS: Opening Anchor Formation (first 20 stones on board) ===
    if (board.stones.length <= 20) {
      // Form stable 2x2 anchor near edge - players who do this win 71% of the time
      score += _evaluateAnchorFormation(board, pos, aiColor);
    }

    // === LEVEL 6+: Add encirclement progress and blocking ===
    if (levelValue >= 6) {
      // 11. Bonus for blocking opponent's encirclement attempts
      score += _evaluateEncirclementBlock(board, pos, aiColor) * 30;

      // 12. Bonus for progressing our own encirclement (uses cache)
      score += _evaluateEncirclementProgress(board, pos, aiColor, cache) * 15;

      // 13. NEW: Escape robustness reduction - reward moves that create chokepoints
      score += _evaluateEscapeRobustnessReduction(board, pos, aiColor, cache) * 20;

      // 14. FORK DETECTION: Bonus for moves that create multiple simultaneous threats
      // Fork moves force opponent to choose which threat to address
      score += _evaluateForkPotential(board, pos, aiColor, cache, enclosures) * 1;

      // 15. MOAT PRINCIPLE: Penalty for moves directly adjacent to opponent walls
      // Better to maintain 1-cell gap (moat) for flexibility
      score -= _evaluateMoatPenalty(board, pos, aiColor) * 30;

      // 17. Multi-region awareness - don't cluster all stones in one area
      score += _evaluateMultiRegionPresence(board, pos, aiColor, cache);

      // 6. Expand territory
      score += _evaluateExpansion(board, pos, aiColor) * 3;

      // 8. Avoid self-atari
      score -= _evaluateSelfAtari(newBoard, pos, aiColor) * 20;
    }

    // === LEVEL 9+: Full evaluation with expansion path analysis ===
    // At highest levels, let the natural game flow determine outcomes
    // Previous bonuses were favoring Black (first mover) excessively
    if (levelValue >= 9) {
      // Light penalties only - avoid stalemates but don't over-constrain
      score -= _evaluateExpansionPathPenalty(newBoard, pos, aiColor) * 1;
      score -= _evaluateIsolatedCenterPenalty(board, pos, aiColor) * 3;
    }

    // === LEVEL 8+: Boost offensive play and POI awareness ===
    if (levelValue >= 8) {
      // High-level AI should be more aggressive, not more passive
      // Bonus for moves that threaten opponent groups
      // Reduced from 15/35 to 10/20 to prevent over-extension causing draws
      for (final group in cache.opponentGroups) {
        if (group.edgeExitCount <= 5 && _isGroupNearPosition(group, pos, 2)) {
          score += 10; // Encourage attacking vulnerable groups
          if (group.edgeExitCount <= 3) {
            score += 15; // Extra bonus for very vulnerable groups
          }
        }
      }

      // POI (Points of Interest) bonus: Contest distant opponent build-up
      // When opponent is building in a sector we're not focused on, respond strategically
      // Reduced from 30+weight*20 to 15+weight*10 to prevent over-response to distant moves
      final hotSectors = _poiCache.getHotSectors(threshold: 1.0);
      for (final sector in hotSectors.take(3)) {
        final sectorId = _POICache.getSectorId(pos, board.size);
        if (sectorId == sector.key) {
          // This move is in a hot sector - boost score based on sector weight
          score += 15 + sector.value * 10;

          // Extra bonus if adjacent to opponent stones (contesting their territory)
          // Reduced from 25 to 15
          for (final adj in pos.adjacentPositions) {
            if (board.isValidPosition(adj) && board.getStoneAt(adj) == aiColor.opponent) {
              score += 15;
              break;
            }
          }
        }
      }
    }

    // === TACTICAL IMPACT GATING ===
    // Penalize moves with zero tactical impact (not near any group, not blocking, not capturing)
    if (capturedCount == 0 && newEnclosures.isEmpty && !criticalBlockingPositions.contains(pos)) {
      // Check if this move has any strategic value
      bool hasImpact = false;

      // Near our endangered groups?
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount <= 3 && _isGroupNearPosition(group, pos, 2)) {
          hasImpact = true;
          break;
        }
      }

      // Near opponent groups we could attack?
      if (!hasImpact) {
        for (final group in cache.opponentGroups) {
          if (group.edgeExitCount <= 4 && _isGroupNearPosition(group, pos, 2)) {
            hasImpact = true;
            break;
          }
        }
      }

      // If no tactical impact, apply penalty
      if (!hasImpact) {
        score -= 30;
      }
    }

    // === PROACTIVE/REACTIVE BALANCE (Level 6+) ===
    // If the game state is too defensive, boost attack moves to maintain tempo
    if (levelValue >= 6) {
      score += _evaluateProactiveBonus(board, pos, aiColor, cache, criticalBlockingPositions);
    }

    return score;
  }

  /// Evaluate proactive/reactive balance
  /// If AI is playing too defensively (no attack pressure), boost offensive moves
  /// Target: ~60% reactive, ~40% proactive moves
  double _evaluateProactiveBonus(Board board, Position pos, StoneColor aiColor, _TurnCache cache, Set<Position> criticalBlockingPositions) {
    // Count attackable opponent groups vs endangered AI groups
    int attackableOpponentGroups = 0;
    int endangeredAiGroups = 0;

    for (final group in cache.opponentGroups) {
      if (group.edgeExitCount <= 4) {
        attackableOpponentGroups++;
      }
    }

    for (final group in cache.aiGroups) {
      if (group.edgeExitCount <= 3) {
        endangeredAiGroups++;
      }
    }

    // ENDGAME AGGRESSION: After move 180, boost offensive play to maintain tempo
    if (board.stones.length >= 180 && endangeredAiGroups <= 1) {
      // Late game - territory is mostly defined, need to be aggressive
      for (final group in cache.opponentGroups) {
        if (group.edgeExitCount <= 4 && _isGroupNearPosition(group, pos, 2)) {
          return 45; // Boosted from 25 to 45 in endgame
        }
      }
    }

    // ENDGAME PASSIVE PENALTY: After move 180, penalize purely defensive moves
    if (board.stones.length >= 180 && endangeredAiGroups <= 1) {
      bool pureDefense = true;
      for (final group in cache.opponentGroups) {
        if (_isGroupNearPosition(group, pos, 3)) {
          pureDefense = false;
          break;
        }
      }
      if (pureDefense && !criticalBlockingPositions.contains(pos)) {
        return -20; // Penalty for passive late-game play
      }
    }

    // If we have more attackable targets than endangered groups, boost offense
    if (attackableOpponentGroups > endangeredAiGroups && endangeredAiGroups <= 1) {
      // Check if this move is offensive (attacks opponent group)
      bool isOffensiveMove = false;
      for (final group in cache.opponentGroups) {
        if (group.edgeExitCount <= 4 && _isGroupNearPosition(group, pos, 2)) {
          isOffensiveMove = true;
          break;
        }
      }

      // Also offensive if it's NOT a critical blocking position (not purely defensive)
      if (!criticalBlockingPositions.contains(pos) && isOffensiveMove) {
        return 25; // Boost offensive moves when we have the tempo
      }
    }

    // If too many endangered groups, don't penalize defense
    if (endangeredAiGroups >= 2) {
      return 0; // Defense is appropriate
    }

    // No endangered groups and no attack happening - penalize pure defense
    if (endangeredAiGroups == 0 && attackableOpponentGroups > 0) {
      // Check if this is a purely defensive move (near our safe groups)
      bool isPureDefense = true;
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount > 5 && _isGroupNearPosition(group, pos, 1)) {
          // Near a safe group - this is a passive move
          isPureDefense = true;
        }
      }
      for (final group in cache.opponentGroups) {
        if (_isGroupNearPosition(group, pos, 2)) {
          isPureDefense = false; // Near opponent - not pure defense
          break;
        }
      }

      if (isPureDefense) {
        return -15; // Slight penalty for passive play when attack is available
      }
    }

    return 0;
  }

  /// SQUEEZE DETECTION: Detect when opponent is narrowing our corridors
  /// This is the #1 cause of unexpected captures - corridor goes from 2-wide to 1-wide
  /// Returns high score for moves that defend corridor width
  double _evaluateSqueezeDefense(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    final opponentColor = aiColor.opponent;
    double score = 0;

    for (final group in cache.aiGroups) {
      // Only care about groups that have wide corridors (worth defending)
      // or groups with limited exits that could be squeezed further
      if (group.edgeExitCount > 8) continue; // Very safe, skip

      // Check if opponent could narrow our escape at any boundary position
      for (final boundaryPos in group.boundaryEmpties) {
        // Simulate opponent placing at this boundary
        final simBoard = board.placeStone(boundaryPos, opponentColor);
        final escapeAfter = _checkEscapePathDetailed(simBoard, group.stones.first, aiColor);

        // SQUEEZE DETECTED: opponent could reduce our corridor width or exits significantly
        bool isSqueezeMove = false;

        // Check if wide corridor would become narrow
        if (group.wideCorridorCount > 0 && escapeAfter.wideCorridorCount < group.wideCorridorCount) {
          isSqueezeMove = true;
        }

        // Check if exits would drop significantly (by 2 or more)
        if (escapeAfter.edgeExitCount <= group.edgeExitCount - 2) {
          isSqueezeMove = true;
        }

        // Check if we'd go from safe (3+) to dangerous (1-2)
        if (group.edgeExitCount >= 3 && escapeAfter.edgeExitCount <= 2) {
          isSqueezeMove = true;
        }

        if (isSqueezeMove) {
          // This is a squeeze position! Check if OUR move defends it
          // Reduced from 150/75/50 to 80/40/25 to reduce first-mover advantage
          if (pos == boundaryPos) {
            // We're blocking the squeeze directly!
            score += 80;
            continue; // No further simulation needed
          } else if (_areAdjacent(pos, boundaryPos)) {
            // We're reinforcing near the squeeze point
            score += 40;
          } else {
            // Check if our move elsewhere would prevent the squeeze effect
            final boardWithOurMove = board.placeStone(pos, aiColor);
            // Safety: ensure boundaryPos is still empty after our move
            if (!boardWithOurMove.isEmpty(boundaryPos)) continue;
            final simAfterUs = boardWithOurMove.placeStone(boundaryPos, opponentColor);
            final escapeWithDefense = _checkEscapePathDetailed(simAfterUs, group.stones.first, aiColor);

            if (escapeWithDefense.edgeExitCount > escapeAfter.edgeExitCount ||
                escapeWithDefense.wideCorridorCount > escapeAfter.wideCorridorCount) {
              score += 25; // Our move helps defend against squeeze
            }
          }
        }
      }
    }

    return score;
  }

  /// ACTIVE CUT SCANNER: Find moves that cut opponent's groups from the edge
  /// Cutting was the winning move in 84% of simulated games
  /// Returns high score for moves that would cut opponent's edge access
  double _evaluateCuttingOpportunity(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    final opponentColor = aiColor.opponent;
    double score = 0;

    for (final group in cache.opponentGroups) {
      // Only target groups that can realistically be cut
      if (group.edgeExitCount > 8) continue; // Too safe
      if (group.edgeExitCount == 0) continue; // Already cut

      // Check if placing at pos would cut this group
      final simBoard = board.placeStone(pos, aiColor);
      final escapeAfter = _checkEscapePathDetailed(simBoard, group.stones.first, opponentColor);

      // Calculate cut effectiveness
      final exitReduction = group.edgeExitCount - escapeAfter.edgeExitCount;

      if (exitReduction > 0) {
        // We're reducing their exits!

        // COMPLETE CUT: Reduced to 0 exits = certain capture
        if (escapeAfter.edgeExitCount == 0) {
          score += 300 + (group.stones.length * 20); // Massive bonus for complete cut
        }
        // NEAR CUT: Reduced to 1-2 exits = very vulnerable
        else if (escapeAfter.edgeExitCount <= 2 && group.edgeExitCount > 2) {
          score += 150 + (group.stones.length * 10);
        }
        // SIGNIFICANT CUT: Reduced by 3+ exits
        else if (exitReduction >= 3) {
          score += 80 + (exitReduction * 15);
        }
        // MODERATE CUT: Reduced by 1-2 exits
        else {
          score += exitReduction * 25;
        }

        // Bonus for cutting larger groups (more stones at stake)
        score += group.stones.length * 5;

        // Extra bonus if this also reduces their wide corridors
        if (group.wideCorridorCount > 0 && escapeAfter.wideCorridorCount < group.wideCorridorCount) {
          score += 50; // Breaking their safe corridor
        }
      }
    }

    return score;
  }

  /// OPENING ANCHOR FORMATION: Form stable 2x2 pattern near edge in opening
  /// Players who establish an edge anchor in moves 1-10 win 71% of the time
  /// BALANCED: Only active for first 8 stones, reduced bonuses to not overshadow engagement
  double _evaluateAnchorFormation(Board board, Position pos, StoneColor aiColor) {
    // Only apply anchor logic for the very first few moves (12 stones = 6 moves each)
    // After that, engagement with opponent is more important
    if (board.stones.length > 12) {
      return 0; // Don't encourage edge-only play after opening
    }

    double score = 0;
    final distFromEdge = _distanceFromEdge(pos, board.size);

    // Mild preference for edge positions in very early opening only
    if (distFromEdge == 0) {
      score += 15; // On edge - good (was 40)
    } else if (distFromEdge == 1) {
      score += 10; // One off edge (was 30)
    }
    // REMOVED: No penalty for interior positions - let engagement bonuses handle it

    // CORNER BONUS: Corners provide 2-edge escape potential, strategically valuable
    bool isCorner = (pos.x <= 2 && pos.y <= 2) ||
                    (pos.x <= 2 && pos.y >= board.size - 3) ||
                    (pos.x >= board.size - 3 && pos.y <= 2) ||
                    (pos.x >= board.size - 3 && pos.y >= board.size - 3);

    if (isCorner) {
      // Check if we already have a stone in any corner quadrant
      bool alreadyHaveCorner = false;
      for (final entry in board.stones.entries) {
        if (entry.value == aiColor) {
          bool stoneInCorner = (entry.key.x <= 4 && entry.key.y <= 4) ||
                               (entry.key.x <= 4 && entry.key.y >= board.size - 5) ||
                               (entry.key.x >= board.size - 5 && entry.key.y <= 4) ||
                               (entry.key.x >= board.size - 5 && entry.key.y >= board.size - 5);
          if (stoneInCorner) {
            alreadyHaveCorner = true;
            break;
          }
        }
      }

      if (!alreadyHaveCorner) {
        score += 20; // Corner bonus only if no corner presence yet
      }
    }

    // Check if we're forming a 2x2 anchor pattern
    int adjacentFriendly = 0;
    bool hasEdgeAdjacent = false;

    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (board.getStoneAt(adj) == aiColor) {
        adjacentFriendly++;
        if (_distanceFromEdge(adj, board.size) <= 1) {
          hasEdgeAdjacent = true;
        }
      }
    }

    // Forming anchor pattern near edge (much reduced bonuses)
    if (distFromEdge <= 1 && adjacentFriendly >= 1 && hasEdgeAdjacent) {
      score += 20; // Forming anchor with edge connection (was 60)
    }

    return score;
  }

  /// MULTI-REGION PRESENCE: Encourage presence in multiple board regions
  /// Prevents "tunnel vision" on one area while opponent builds freely elsewhere
  double _evaluateMultiRegionPresence(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    // Divide board into 4 quadrants
    final mid = board.size ~/ 2;
    final quadrantPresence = [false, false, false, false]; // TL, TR, BL, BR

    for (final group in cache.aiGroups) {
      for (final stone in group.stones) {
        final qIdx = (stone.x < mid ? 0 : 1) + (stone.y < mid ? 0 : 2);
        quadrantPresence[qIdx] = true;
      }
    }

    final presentCount = quadrantPresence.where((q) => q).length;
    final posQuadrant = (pos.x < mid ? 0 : 1) + (pos.y < mid ? 0 : 2);

    // If we're only in 1-2 quadrants, bonus for expanding to new regions
    if (presentCount <= 2 && !quadrantPresence[posQuadrant]) {
      // Check that we're not abandoning a fight
      bool activeConflictNearby = false;
      for (final group in cache.aiGroups) {
        if (group.edgeExitCount <= 4) {
          activeConflictNearby = true;
          break;
        }
      }

      if (!activeConflictNearby) {
        return 35; // Good to expand to new region
      } else {
        return 10; // Slight bonus even with active conflict
      }
    }

    // Slight penalty for clustering more in already-heavy quadrant
    if (presentCount >= 2 && quadrantPresence[posQuadrant]) {
      // Count stones in this quadrant
      int stonesInQuadrant = 0;
      for (final group in cache.aiGroups) {
        for (final stone in group.stones) {
          final sQuad = (stone.x < mid ? 0 : 1) + (stone.y < mid ? 0 : 2);
          if (sQuad == posQuadrant) stonesInQuadrant++;
        }
      }

      // If heavily concentrated (>60% of stones), slight penalty
      final totalStones = cache.aiGroups.fold<int>(0, (sum, g) => sum + g.stones.length);
      if (totalStones > 0 && stonesInQuadrant / totalStones > 0.6) {
        return -10;
      }
    }

    return 0;
  }

  /// Helper: check if two positions are adjacent
  bool _areAdjacent(Position a, Position b) {
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    return (dx + dy) == 1;
  }

  /// Helper: Check if gaps span multiple edges of the board
  /// Used to detect truly hopeless defense situations
  bool _gapsSpanMultipleEdges(Iterable<Position> gaps, int boardSize) {
    bool hasTop = false, hasBottom = false, hasLeft = false, hasRight = false;
    for (final gap in gaps) {
      if (gap.y <= 3) hasTop = true;
      if (gap.y >= boardSize - 4) hasBottom = true;
      if (gap.x <= 3) hasLeft = true;
      if (gap.x >= boardSize - 4) hasRight = true;
    }
    int edgeCount = (hasTop ? 1 : 0) + (hasBottom ? 1 : 0) + (hasLeft ? 1 : 0) + (hasRight ? 1 : 0);
    return edgeCount >= 2;
  }

  /// Helper: Check if an attack on a group is likely a feint (not committed)
  /// A feint is when opponent has stones near our group but isn't tightening encirclement
  bool _isLikelyFeint(_GroupInfo group, Board board, StoneColor opponentColor) {
    // Check if opponent stones near this group have been static (no recent additions)
    int opponentAdjacent = 0;
    int opponentAdjacentWithEscape = 0;

    for (final boundary in group.boundaryEmpties) {
      for (final adj in boundary.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (board.getStoneAt(adj) == opponentColor) {
          opponentAdjacent++;
          // Check if this opponent stone itself has good escape
          final oppEscape = _checkEscapePathDetailed(board, adj, opponentColor);
          if (oppEscape.edgeExitCount >= 4) {
            opponentAdjacentWithEscape++;
          }
        }
      }
    }

    // If opponent stones near us are well-connected (not committed to attack), likely feint
    if (opponentAdjacent > 0 && opponentAdjacentWithEscape == opponentAdjacent) {
      return true; // All threatening stones have escape = likely feint
    }

    return false;
  }

  /// Evaluate if this move progresses toward completing an encirclement of opponent stones
  /// Rewards moves that reduce opponent's escape routes
  /// OPTIMIZED: Uses cache and only considers groups near the candidate move
  double _evaluateEncirclementProgress(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    final opponentColor = aiColor.opponent;
    double progressScore = 0;

    // Only consider opponent groups within distance 4 of the move
    // or groups whose boundary empties include pos or adjacent to pos
    for (final group in cache.opponentGroups) {
      if (!_isGroupNearPosition(group, pos, 4)) continue;

      // Skip groups that are already very safe (many exits)
      if (group.edgeExitCount > 6) continue;

      // Use cached edge exit count as "before" value
      final exitsBefore = group.edgeExitCount;

      // Simulate our move
      final newBoard = board.placeStone(pos, aiColor);

      // Pick a representative stone from the group
      final oppStone = group.stones.first;

      // Check escape after our move
      final escapeAfter = _checkEscapePathDetailed(newBoard, oppStone, opponentColor);

      // Reward reducing edge exits (tightening the encirclement)
      if (escapeAfter.edgeExitCount < exitsBefore) {
        progressScore += (exitsBefore - escapeAfter.edgeExitCount) * 3;

        // Extra bonus if we're getting close to completing (few exits left)
        if (escapeAfter.edgeExitCount <= 2) {
          progressScore += 5;
        }
        if (escapeAfter.edgeExitCount == 1) {
          progressScore += 10; // Very close to completing!
        }
      }
    }

    return progressScore;
  }

  /// Evaluate fork potential - moves that create multiple simultaneous threats
  /// Fork moves force opponent to choose which threat to address, guaranteeing one succeeds
  /// Returns high score (200+) for true forks with 2+ independent threats
  double _evaluateForkPotential(Board board, Position pos, StoneColor aiColor, _TurnCache cache, List<Enclosure> enclosures) {
    final opponentColor = aiColor.opponent;
    double forkScore = 0;
    int threatCount = 0;

    // Simulate placing our stone
    final newBoard = board.placeStone(pos, aiColor);

    // THREAT TYPE 1: Check if this move threatens to complete encirclements on multiple groups
    final threatenedGroups = <_GroupInfo>[];
    for (final group in cache.opponentGroups) {
      if (!_isGroupNearPosition(group, pos, 3)) continue;
      if (group.edgeExitCount > 5) continue; // Too safe to threaten

      // Check if our move significantly reduces their escape
      final oppStone = group.stones.first;
      final escapeAfter = _checkEscapePathDetailed(newBoard, oppStone, opponentColor);

      // If we reduced them to 1-2 exits, this is a threat
      if (escapeAfter.edgeExitCount <= 2 && escapeAfter.edgeExitCount < group.edgeExitCount) {
        threatenedGroups.add(group);
        threatCount++;
      }
    }

    // THREAT TYPE 2: Check if this move creates capture threats on adjacent groups
    for (final adj in pos.adjacentPositions) {
      if (!newBoard.isValidPosition(adj)) continue;
      if (newBoard.getStoneAt(adj) != opponentColor) continue;

      // Check if we can capture this group in the next move
      for (final capturePos in adj.adjacentPositions) {
        if (!newBoard.isValidPosition(capturePos)) continue;
        if (!newBoard.isEmpty(capturePos)) continue;

        final captureResult = CaptureLogic.processMove(newBoard, capturePos, aiColor, existingEnclosures: enclosures);
        if (captureResult.isValid && captureResult.captureResult != null &&
            captureResult.captureResult!.captureCount > 0) {
          threatCount++;
          break; // One capture threat per adjacent group
        }
      }
    }

    // THREAT TYPE 3: Check if we're threatening to cut opponent's connection
    // (Placing between two opponent groups that were connected)
    int opponentGroupsNearby = 0;
    for (final group in cache.opponentGroups) {
      for (final adj in pos.adjacentPositions) {
        if (group.stones.contains(adj)) {
          opponentGroupsNearby++;
          break;
        }
      }
    }
    if (opponentGroupsNearby >= 2) {
      threatCount++; // Threatening to cut connection
    }

    // Calculate fork bonus
    if (threatCount >= 2) {
      forkScore = 200; // Base fork bonus
      forkScore += (threatCount - 2) * 50; // Extra for each threat beyond 2

      // Extra bonus if threatening multiple distinct groups
      if (threatenedGroups.length >= 2) {
        forkScore += 100;
      }
    } else if (threatCount == 1) {
      forkScore = 30; // Single threat is still good
    }

    return forkScore;
  }

  /// Evaluate moat penalty - moves directly adjacent to opponent walls are vulnerable
  /// Better to maintain 1-cell gap (moat) for flexibility and safety
  double _evaluateMoatPenalty(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double penalty = 0;

    // Count opponent stones directly adjacent (within 1 cell)
    int directlyAdjacent = 0;

    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (board.getStoneAt(adj) == opponentColor) {
        directlyAdjacent++;
      }
    }

    // Penalty for being directly adjacent to opponent wall (no moat)
    // Exception: If we're blocking or capturing, adjacency is good
    if (directlyAdjacent >= 2) {
      // Check if this is a "wall following" pattern - bad
      bool isWallFollowing = false;

      // Look for opponent stones in a line that we're following
      for (int i = 0; i < 4; i++) {
        final dirs = [Position(1, 0), Position(0, 1), Position(-1, 0), Position(0, -1)];
        final dir = dirs[i];
        final checkPos1 = Position(pos.x + dir.x, pos.y + dir.y);
        final checkPos2 = Position(pos.x - dir.x, pos.y - dir.y);

        if (board.isValidPosition(checkPos1) && board.isValidPosition(checkPos2)) {
          // If opponent has stones on one side and we're building parallel
          final stone1 = board.getStoneAt(checkPos1);
          final stone2 = board.getStoneAt(checkPos2);
          if (stone1 == opponentColor && stone2 == opponentColor) {
            isWallFollowing = true;
            break;
          }
        }
      }

      if (isWallFollowing) {
        penalty += 3; // Strong penalty for wall following
      } else if (directlyAdjacent >= 3) {
        penalty += 2; // Penalty for being too embedded in opponent territory
      }
    }

    return penalty;
  }

  /// Check if a group is within a certain distance of a position
  bool _isGroupNearPosition(_GroupInfo group, Position pos, int maxDistance) {
    // Check if any stone in the group is within distance
    for (final stone in group.stones) {
      final dx = (stone.x - pos.x).abs();
      final dy = (stone.y - pos.y).abs();
      if (dx <= maxDistance && dy <= maxDistance) {
        return true;
      }
    }
    // Also check if pos is in boundary empties
    if (group.boundaryEmpties.contains(pos)) {
      return true;
    }
    // Check if pos is adjacent to boundary empties
    for (final adj in pos.adjacentPositions) {
      if (group.boundaryEmpties.contains(adj)) {
        return true;
      }
    }
    return false;
  }

  /// Evaluate if this move blocks an opponent's encirclement attempt on our stones
  /// CRITICAL: High priority for saving our stones from being surrounded
  /// This function should ONLY give bonuses for moves that actually help endangered stones
  double _evaluateEncirclementBlock(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double blockScore = 0;

    // CRITICAL CHECK: Are any of our stones about to be encircled?
    final endangeredStones = _findEndangeredStones(board, aiColor);

    // If no endangered stones, this function should return 0
    // We don't want to give bonuses for random moves
    if (endangeredStones.isEmpty) {
      return 0;
    }

    // Check escape path for THIS move position
    final newBoard = board.placeStone(pos, aiColor);
    final escapeAfterMove = _checkEscapePathDetailed(newBoard, pos, aiColor);

    // Calculate distance to nearest endangered stone
    int minDistanceToEndangered = 999;
    for (final endangered in endangeredStones) {
      final dist = (pos.x - endangered.x).abs() + (pos.y - endangered.y).abs();
      if (dist < minDistanceToEndangered) {
        minDistanceToEndangered = dist;
      }
    }

    // CRITICAL: If this move is far from endangered stones (>5 cells), it doesn't help them
    // Don't give any encirclement bonus for distant moves
    if (minDistanceToEndangered > 5) {
      return 0;
    }

    // Check if this move helps any endangered stones escape
    bool connectsToEndangered = false;
    bool improvedEscape = false;
    int totalEscapeImprovement = 0;

    for (final endangeredPos in endangeredStones) {
      // Check escape before and after our move
      final escapeBefore = _checkEscapePathDetailed(board, endangeredPos, aiColor);
      final escapeAfter = _checkEscapePathDetailed(newBoard, endangeredPos, aiColor);

      // Track if we're connecting to endangered stones
      for (final adj in pos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (board.getStoneAt(adj) == aiColor && endangeredStones.contains(adj)) {
          connectsToEndangered = true;
        }
      }

      // Track if we improved escape for this endangered group
      if (escapeAfter.edgeExitCount > escapeBefore.edgeExitCount) {
        improvedEscape = true;
        totalEscapeImprovement += (escapeAfter.edgeExitCount - escapeBefore.edgeExitCount);
        // Huge bonus for opening escape routes - this is the REAL goal
        blockScore += 25 * (escapeAfter.edgeExitCount - escapeBefore.edgeExitCount);
      }
    }

    // CRITICAL: If this move has NO edge access, it's placing inside an encirclement
    if (escapeAfterMove.edgeExitCount == 0) {
      blockScore -= 50; // Strong penalty for moves with no edge access
    }

    // CRITICAL FIX: Connecting to endangered stones WITHOUT improving escape is BAD
    if (connectsToEndangered && !improvedEscape) {
      if (escapeAfterMove.edgeExitCount <= 2) {
        blockScore -= 30; // Penalty for reinforcing a trap without escape
      }
    }

    // Only give edge bonus if this move is NEAR endangered stones AND on edge
    // This helps create escape routes, not random edge development
    if (minDistanceToEndangered <= 3) {
      if (_isOnEdge(pos, board.size)) {
        blockScore += 15; // Bonus for edge moves near endangered stones
      }
    }

    // Check if we're filling a gap in opponent's wall (disrupting their encirclement)
    if (_isGapInOpponentWall(board, pos, opponentColor)) {
      blockScore += 12; // Strong bonus for blocking a wall gap
    }

    // Bonus for disrupting opponent formations (only if near endangered stones)
    if (minDistanceToEndangered <= 4) {
      int adjacentOpponent = 0;
      for (final adj in pos.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        if (board.getStoneAt(adj) == opponentColor) {
          adjacentOpponent++;
        }
      }
      if (adjacentOpponent >= 2) {
        blockScore += adjacentOpponent * 3; // Bonus for breaking opponent wall
      }
    }

    return blockScore;
  }

  /// Check if position is near the board edge (within distance cells)
  bool _isNearEdge(Position pos, int boardSize, int distance) {
    return pos.x < distance || pos.y < distance ||
           pos.x >= boardSize - distance || pos.y >= boardSize - distance;
  }

  /// Evaluate sacrifice decision - sometimes losing 1-2 stones enables capturing 3+
  /// Returns negative score if we should NOT try to save a group (sacrifice is better)
  /// Returns positive score if saving the group is worthwhile
  double _evaluateSacrificeValue(Board board, Position savePos, StoneColor aiColor, _TurnCache cache, List<Enclosure> enclosures) {
    // Find the group we'd be trying to save with this move
    _GroupInfo? targetGroup;
    for (final group in cache.aiGroups) {
      if (group.edgeExitCount <= 3 && _isGroupNearPosition(group, savePos, 2)) {
        targetGroup = group;
        break;
      }
    }

    if (targetGroup == null) return 0; // Not a defensive move

    final groupSize = targetGroup.stones.length;

    // Only consider sacrifice if opponent is actively threatening
    bool opponentThreatening = false;
    for (final adj in targetGroup.boundaryEmpties) {
      for (final adjAdj in adj.adjacentPositions) {
        if (!board.isValidPosition(adjAdj)) continue;
        if (board.getStoneAt(adjAdj) == aiColor.opponent) {
          opponentThreatening = true;
          break;
        }
      }
      if (opponentThreatening) break;
    }

    if (!opponentThreatening) {
      return 0; // Don't sacrifice if opponent isn't actively attacking this group
    }

    // GLOBAL AWARENESS: Check if opponent is building elsewhere while we save this group
    int opponentMomentum = 0;
    for (final oppGroup in cache.opponentGroups) {
      // Count opponent groups that are expanding (have good escape and room to grow)
      if (oppGroup.edgeExitCount >= 5 && oppGroup.stones.length >= 4) {
        if (oppGroup.boundaryEmpties.length >= 6) {
          opponentMomentum++;
        }
      }
    }

    // Extended sacrifice evaluation to 3-4 stone groups
    if (groupSize <= 4 && targetGroup.edgeExitCount <= 2) {
      // Estimate cost to save this group
      int movesToSave = 0;
      if (targetGroup.edgeExitCount == 1) {
        movesToSave = groupSize + 2; // More stones = more moves needed
      } else if (targetGroup.edgeExitCount == 2) {
        movesToSave = groupSize;
      } else {
        movesToSave = groupSize > 1 ? groupSize - 1 : 1;
      }

      // If cost to save >= group size + 1, consider sacrificing
      if (movesToSave >= groupSize + 1) {
        int potentialCaptures = 0;
        for (final oppGroup in cache.opponentGroups) {
          if (oppGroup.edgeExitCount <= 2) {
            potentialCaptures += oppGroup.stones.length;
          }
        }

        if (potentialCaptures >= groupSize) {
          // Stronger sacrifice signal for larger groups
          return -40 - (groupSize * 10);
        }
      }

      // If opponent has 2+ expanding groups while we're saving a small group, reconsider
      if (opponentMomentum >= 2 && groupSize <= 3) {
        return -30; // Don't waste moves on small saves when opponent is building momentum
      }
    }

    // Larger groups (5+) are worth saving
    if (groupSize >= 5) {
      return groupSize * 10; // Worth saving
    }

    // Medium groups (3-4) - context dependent
    if (groupSize >= 3) {
      // Worth saving if opponent momentum is low
      if (opponentMomentum < 2) {
        return groupSize * 8;
      }
    }

    return 0;
  }

  /// Find AI stones that are in danger of being encircled (few escape routes)
  /// Also returns info about whether groups are worth saving (sacrifice evaluation)
  Set<Position> _findEndangeredStones(Board board, StoneColor aiColor) {
    final endangered = <Position>{};
    final checked = <Position>{};

    // Check all AI stones
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        if (board.getStoneAt(pos) != aiColor) continue;
        if (checked.contains(pos)) continue;

        // Check escape path for this stone
        final escapeResult = _checkEscapePathDetailed(board, pos, aiColor);

        // Mark all stones in this region as checked
        checked.add(pos);

        // If escape routes are limited, these stones are endangered
        if (escapeResult.edgeExitCount <= 3) {
          endangered.add(pos);

          // Also add all connected AI stones to endangered list
          for (final adj in pos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (board.getStoneAt(adj) == aiColor) {
              endangered.add(adj);
            }
          }
        }
      }
    }

    return endangered;
  }

  /// Evaluate URGENT defensive moves - when opponent is about to complete encirclement
  /// Returns very high score for moves that are the ONLY way to prevent capture
  double _evaluateUrgentDefense(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double urgentScore = 0;

    // Find all AI stones and check if any group has very limited escape
    final aiStones = <Position>[];
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final p = Position(x, y);
        if (board.getStoneAt(p) == aiColor) {
          aiStones.add(p);
        }
      }
    }

    if (aiStones.isEmpty) return 0;

    // Check each AI stone group for danger
    final checkedGroups = <Position>{};
    for (final stone in aiStones) {
      if (checkedGroups.contains(stone)) continue;

      final escapeResult = _checkEscapePathDetailed(board, stone, aiColor);
      checkedGroups.addAll(escapeResult.emptyRegion);
      checkedGroups.add(stone);

      // If this group has limited escape exits (1-4), check if our move helps
      // WIDENED from 2 to 4 to catch forming encirclements earlier
      if (escapeResult.edgeExitCount <= 4 && escapeResult.emptyRegion.length < 20) {
        // This group is in CRITICAL danger!
        // Check if placing at pos would help

        // Option 1: pos is adjacent to an escape route and blocks opponent from sealing it
        for (final emptyPos in escapeResult.emptyRegion) {
          if (_isOnEdge(emptyPos, board.size)) {
            // This is an edge escape - check if pos is adjacent to it
            final dist = (pos.x - emptyPos.x).abs() + (pos.y - emptyPos.y).abs();
            if (dist <= 2) {
              // Check if pos would block opponent from sealing this escape
              bool adjacentToOpponent = false;
              for (final adj in pos.adjacentPositions) {
                if (board.getStoneAt(adj) == opponentColor) {
                  adjacentToOpponent = true;
                  break;
                }
              }
              if (adjacentToOpponent) {
                urgentScore += 8; // Critical defensive move
              }
            }
          }
        }

        // Option 2: This move directly improves the endangered group's escape
        final newBoard = board.placeStone(pos, aiColor);
        final escapeAfter = _checkEscapePathDetailed(newBoard, stone, aiColor);

        if (escapeAfter.edgeExitCount > escapeResult.edgeExitCount) {
          urgentScore += 10; // This move opens more escapes - vital!
        }

        // If we'd be completely trapped without this move but saved with it
        if (!escapeResult.canEscape || escapeResult.edgeExitCount == 1) {
          if (escapeAfter.canEscape && escapeAfter.edgeExitCount >= 2) {
            urgentScore += 15; // Life-saving move!
          }
        }
      }
    }

    return urgentScore;
  }

  /// CRITICAL: Check if this position blocks opponent from capturing our stones
  /// Simulates: "If opponent placed here instead, would they capture our stones?"
  /// If yes, this is a MUST-BLOCK position
  double _evaluateCaptureBlockingMove(Board board, Position pos, StoneColor aiColor, List<Enclosure> enclosures, Set<Position> criticalBlockingPositions) {
    final opponentColor = aiColor.opponent;
    double blockingScore = 0;

    // HIGHEST PRIORITY: If this position is in the pre-computed critical blocking set
    // These are positions where opponent could capture our stones
    if (criticalBlockingPositions.contains(pos)) {
      blockingScore += 500; // Massive bonus - must block!
    }

    // Simulate opponent placing at this position
    final opponentMoveResult = CaptureLogic.processMove(board, pos, opponentColor, existingEnclosures: enclosures);

    if (opponentMoveResult.isValid && opponentMoveResult.captureResult != null) {
      final wouldCapture = opponentMoveResult.captureResult!.captureCount;

      if (wouldCapture > 0) {
        // CRITICAL: Opponent could capture our stones here!
        // We MUST block this position
        blockingScore += 50 + (wouldCapture * 20); // Increased from 10 + 5*stones
      }

      // Also check if opponent would create a new enclosure (fort) that traps us
      final wouldCreateEnclosure = opponentMoveResult.captureResult!.newEnclosures.isNotEmpty;
      if (wouldCreateEnclosure) {
        blockingScore += 30; // Increased from 8
      }
    }

    // Also check adjacent positions - would opponent placing nearby capture us?
    // This is for "almost complete" encirclements
    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (!board.isEmpty(adj)) continue;

      final adjMoveResult = CaptureLogic.processMove(board, adj, opponentColor, existingEnclosures: enclosures);
      if (adjMoveResult.isValid && adjMoveResult.captureResult != null) {
        final wouldCapture = adjMoveResult.captureResult!.captureCount;
        if (wouldCapture > 0) {
          // Opponent could capture nearby - check if our move at pos prevents this
          final boardWithOurMove = board.placeStone(pos, aiColor);
          final afterOurMove = CaptureLogic.processMove(boardWithOurMove, adj, opponentColor, existingEnclosures: enclosures);

          if (!afterOurMove.isValid ||
              afterOurMove.captureResult == null ||
              afterOurMove.captureResult!.captureCount < wouldCapture) {
            // Our move prevents or reduces the capture!
            blockingScore += 20 + (wouldCapture * 10); // Increased from 5 + 2*stones
          }
        }
      }
    }

    return blockingScore;
  }

  /// Find all positions where opponent could capture our stones on their next move
  /// Returns a record with two sets:
  /// - immediateCaptureBlocks: positions where opponent playing would ACTUALLY CAPTURE stones
  ///   (CaptureLogic.processMove returns captureCount > 0 or creates enclosure)
  /// - encirclementBlocks: positions that would reduce escape but not immediately capture
  ({Map<Position, int> immediateCaptureBlocks, Map<Position, int> encirclementBlocks}) _findCriticalBlockingPositionsDetailed(Board board, StoneColor aiColor, List<Enclosure> enclosures, _TurnCache cache) {
    // Maps position -> stones at risk (for proper prioritization)
    final immediateCaptureBlocks = <Position, int>{};
    final encirclementBlocks = <Position, int>{};
    final opponentColor = aiColor.opponent;

    // Check all boundary empties of AI groups - these are potential capture points
    for (final group in cache.aiGroups) {
      final groupSize = group.stones.length;

      // Check each boundary empty to see if opponent placing there would ACTUALLY CAPTURE
      // This is the STRICTEST check - only positions where CaptureLogic triggers capture
      for (final emptyPos in group.boundaryEmpties) {
        final opponentMoveResult = CaptureLogic.processMove(board, emptyPos, opponentColor, existingEnclosures: enclosures);

        if (opponentMoveResult.isValid && opponentMoveResult.captureResult != null) {
          final captureCount = opponentMoveResult.captureResult!.captureCount;
          if (captureCount > 0) {
            // Opponent could ACTUALLY CAPTURE here - IMMEDIATE threat!
            // Track actual capture count, or group size if creating enclosure
            final stonesAtRisk = captureCount > 0 ? captureCount : groupSize;
            // Keep the maximum if already tracked
            if (!immediateCaptureBlocks.containsKey(emptyPos) || immediateCaptureBlocks[emptyPos]! < stonesAtRisk) {
              immediateCaptureBlocks[emptyPos] = stonesAtRisk;
            }
          }
          if (opponentMoveResult.captureResult!.newEnclosures.isNotEmpty) {
            // Opponent could create an enclosure with capture - also immediate threat!
            // Enclosure typically traps all stones in the group
            if (!immediateCaptureBlocks.containsKey(emptyPos) || immediateCaptureBlocks[emptyPos]! < groupSize) {
              immediateCaptureBlocks[emptyPos] = groupSize;
            }
          }
        }
      }

      // CRITICAL: Also check positions that complete opponent's enclosure WALL
      // These might not be adjacent to our stones but still cause capture
      // Run for ALL groups, not just endangered ones - CaptureLogic will only
      // return captures if the wall is actually forming around our stones
      final wallGapCaptures = _findWallGapCapturePositionsWithCount(board, group, opponentColor, enclosures);
      for (final entry in wallGapCaptures.entries) {
        if (!immediateCaptureBlocks.containsKey(entry.key) || immediateCaptureBlocks[entry.key]! < entry.value) {
          immediateCaptureBlocks[entry.key] = entry.value;
        }
      }

      // Check if boundary empties would severely reduce escape
      // These are encirclement blocks, NOT immediate capture blocks
      // The distinction is crucial: "sealing" != "capturing"
      for (final emptyPos in group.boundaryEmpties) {
        // Skip if already marked as immediate capture
        if (immediateCaptureBlocks.containsKey(emptyPos)) continue;

        // Simulate opponent placing at this boundary position
        final simulatedBoard = board.placeStone(emptyPos, opponentColor);

        // Check escape from any stone in our group after opponent's move
        final sampleStone = group.stones.first;
        final escapeAfter = _checkEscapePathDetailed(simulatedBoard, sampleStone, aiColor);

        // Sealing (edgeExitCount == 0) is SERIOUS but not same as immediate capture
        // It's an encirclement block with high urgency
        if (!escapeAfter.canEscape || escapeAfter.edgeExitCount == 0) {
          if (!encirclementBlocks.containsKey(emptyPos) || encirclementBlocks[emptyPos]! < groupSize) {
            encirclementBlocks[emptyPos] = groupSize;
          }
        }
        // Leave only 1-2 exits = also dangerous
        else if (escapeAfter.edgeExitCount <= 2 && group.edgeExitCount > 2) {
          if (!encirclementBlocks.containsKey(emptyPos) || encirclementBlocks[emptyPos]! < groupSize) {
            encirclementBlocks[emptyPos] = groupSize;
          }
        }
      }

      // ENHANCED: Detect forming encirclements EARLIER (edgeExits <= 6)
      // Also look at positions that significantly reduce our escape options
      if (group.edgeExitCount <= 6) {
        // Find positions that could complete or progress the encirclement
        for (final stone in group.stones) {
          for (final adj in stone.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (!board.isEmpty(adj)) continue;
            if (immediateCaptureBlocks.containsKey(adj)) continue;
            if (encirclementBlocks.containsKey(adj)) continue;

            // Check if opponent placing here would reduce our escape
            final simulatedBoard = board.placeStone(adj, opponentColor);
            final escapeAfter = _checkEscapePathDetailed(simulatedBoard, stone, aiColor);

            // Sealing = encirclement block (high priority)
            if (!escapeAfter.canEscape || escapeAfter.edgeExitCount == 0) {
              encirclementBlocks[adj] = groupSize;
            }
            // Losing 2+ exits is serious
            else if (escapeAfter.edgeExitCount < group.edgeExitCount - 1) {
              encirclementBlocks[adj] = groupSize;
            }
          }
        }

        // ADDITIONAL: Find gaps in opponent's wall around our group
        // These are empty positions between opponent stones that form a wall
        final wallGaps = _findWallGapsAroundGroup(board, group, opponentColor);
        for (final gap in wallGaps) {
          if (!immediateCaptureBlocks.containsKey(gap) && !encirclementBlocks.containsKey(gap)) {
            encirclementBlocks[gap] = groupSize;
          }
        }
      }
    }

    return (immediateCaptureBlocks: immediateCaptureBlocks, encirclementBlocks: encirclementBlocks);
  }

  /// Find positions where opponent filling a gap in their wall would capture AI stones
  /// This catches enclosure completions that aren't adjacent to AI stones
  ///
  /// CRITICAL FIX: The "nearOpponent" check was too restrictive. An encirclement-completing
  /// move might not be directly adjacent to opponent stones - it could be a gap in the
  /// ring that, when filled by opponent, completes the encirclement.
  /// Example: Opponent stones at (6,10) and (6,12), gap at (5,11) - position (5,11) is
  /// NOT adjacent to any opponent stone but filling it completes the encirclement.
  Set<Position> _findWallGapCapturePositions(Board board, _GroupInfo group, StoneColor opponentColor, List<Enclosure> enclosures) {
    final capturePositions = <Position>{};

    // Strategy: Find empty positions that could complete an encirclement around our group
    // The key insight is that a capture-completing position may not be directly adjacent
    // to opponent stones, but it WILL be in the "escape zone" boundary of our group

    // Get all positions within a certain radius of our group
    // Radius of 5 covers most encirclement shapes
    final searchRadius = 5;
    final positionsToCheck = <Position>{};

    // APPROACH 1: Check positions near opponent stones (original logic, but relaxed)
    // Now checks for positions within 2 cells of opponent stones, not just adjacent
    for (final stone in group.stones) {
      for (int dx = -searchRadius; dx <= searchRadius; dx++) {
        for (int dy = -searchRadius; dy <= searchRadius; dy++) {
          final checkPos = Position(stone.x + dx, stone.y + dy);
          if (!board.isValidPosition(checkPos)) continue;
          if (!board.isEmpty(checkPos)) continue;

          // Check if position is within 2 cells of any opponent stone
          // This catches gaps in encirclement rings that aren't directly adjacent
          bool nearOpponent = false;
          for (int odx = -2; odx <= 2; odx++) {
            for (int ody = -2; ody <= 2; ody++) {
              if (odx == 0 && ody == 0) continue;
              final nearPos = Position(checkPos.x + odx, checkPos.y + ody);
              if (board.isValidPosition(nearPos) && board.getStoneAt(nearPos) == opponentColor) {
                nearOpponent = true;
                break;
              }
            }
            if (nearOpponent) break;
          }
          if (nearOpponent) {
            positionsToCheck.add(checkPos);
          }
        }
      }
    }

    // APPROACH 2: For endangered groups (low edge exits), also check the escape boundary
    // These are positions that, if filled, would reduce our escape routes
    if (group.edgeExitCount <= 6) {
      // Get the empty region accessible from our group (the escape zone)
      final sampleStone = group.stones.first;
      final escapeResult = _checkEscapePathDetailed(board, sampleStone, opponentColor.opponent);

      // Check positions on the BOUNDARY of this escape zone
      // (adjacent to the escape zone but not inside it)
      for (final emptyPos in escapeResult.emptyRegion) {
        for (final adj in emptyPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (!board.isEmpty(adj)) continue;
          if (escapeResult.emptyRegion.contains(adj)) continue; // Inside escape zone

          // This position is outside our escape zone - could be an encirclement completion point
          positionsToCheck.add(adj);
        }
      }
    }

    // Test each potential wall gap position
    for (final pos in positionsToCheck) {
      // Skip if already checked as boundary empty
      if (group.boundaryEmpties.contains(pos)) continue;

      final opponentMoveResult = CaptureLogic.processMove(
        board,
        pos,
        opponentColor,
        existingEnclosures: enclosures,
      );

      if (opponentMoveResult.isValid && opponentMoveResult.captureResult != null) {
        if (opponentMoveResult.captureResult!.captureCount > 0) {
          // Opponent playing here would capture!
          capturePositions.add(pos);
        }
        if (opponentMoveResult.captureResult!.newEnclosures.isNotEmpty) {
          // Opponent would create an enclosure
          capturePositions.add(pos);
        }
      }
    }

    return capturePositions;
  }

  /// Version that returns Map<Position, int> with capture counts
  Map<Position, int> _findWallGapCapturePositionsWithCount(Board board, _GroupInfo group, StoneColor opponentColor, List<Enclosure> enclosures) {
    final capturePositions = <Position, int>{};

    // Strategy: Find empty positions that could complete an encirclement around our group
    // The key insight is that a capture-completing position may not be directly adjacent
    // to opponent stones, but it WILL be in the "escape zone" boundary of our group

    // Get all positions within a certain radius of our group
    // Radius of 5 covers most encirclement shapes
    final searchRadius = 5;
    final positionsToCheck = <Position>{};

    // APPROACH 1: Check positions near opponent stones (original logic, but relaxed)
    // Now checks for positions within 2 cells of opponent stones, not just adjacent
    for (final stone in group.stones) {
      for (int dx = -searchRadius; dx <= searchRadius; dx++) {
        for (int dy = -searchRadius; dy <= searchRadius; dy++) {
          final checkPos = Position(stone.x + dx, stone.y + dy);
          if (!board.isValidPosition(checkPos)) continue;
          if (!board.isEmpty(checkPos)) continue;

          // Check if position is within 2 cells of any opponent stone
          // This catches gaps in encirclement rings that aren't directly adjacent
          bool nearOpponent = false;
          for (int odx = -2; odx <= 2; odx++) {
            for (int ody = -2; ody <= 2; ody++) {
              if (odx == 0 && ody == 0) continue;
              final nearPos = Position(checkPos.x + odx, checkPos.y + ody);
              if (board.isValidPosition(nearPos) && board.getStoneAt(nearPos) == opponentColor) {
                nearOpponent = true;
                break;
              }
            }
            if (nearOpponent) break;
          }
          if (nearOpponent) {
            positionsToCheck.add(checkPos);
          }
        }
      }
    }

    // APPROACH 2: For endangered groups (low edge exits), also check the escape boundary
    // These are positions that, if filled, would reduce our escape routes
    if (group.edgeExitCount <= 6) {
      // Get the empty region accessible from our group (the escape zone)
      final sampleStone = group.stones.first;
      final escapeResult = _checkEscapePathDetailed(board, sampleStone, opponentColor.opponent);

      // Check positions on the BOUNDARY of this escape zone
      // (adjacent to the escape zone but not inside it)
      for (final emptyPos in escapeResult.emptyRegion) {
        for (final adj in emptyPos.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (!board.isEmpty(adj)) continue;
          if (escapeResult.emptyRegion.contains(adj)) continue; // Inside escape zone

          // This position is outside our escape zone - could be an encirclement completion point
          positionsToCheck.add(adj);
        }
      }
    }

    // Test each potential wall gap position
    for (final pos in positionsToCheck) {
      // Skip if already checked as boundary empty
      if (group.boundaryEmpties.contains(pos)) continue;

      final opponentMoveResult = CaptureLogic.processMove(
        board,
        pos,
        opponentColor,
        existingEnclosures: enclosures,
      );

      if (opponentMoveResult.isValid && opponentMoveResult.captureResult != null) {
        final captureCount = opponentMoveResult.captureResult!.captureCount;
        if (captureCount > 0) {
          // Opponent playing here would capture! Track the count.
          if (!capturePositions.containsKey(pos) || capturePositions[pos]! < captureCount) {
            capturePositions[pos] = captureCount;
          }
        }
        if (opponentMoveResult.captureResult!.newEnclosures.isNotEmpty) {
          // Opponent would create an enclosure - use group size as estimate
          if (!capturePositions.containsKey(pos) || capturePositions[pos]! < group.stones.length) {
            capturePositions[pos] = group.stones.length;
          }
        }
      }
    }

    return capturePositions;
  }

  /// Legacy wrapper - returns all critical positions combined
  Set<Position> _findCriticalBlockingPositions(Board board, StoneColor aiColor, List<Enclosure> enclosures, _TurnCache cache) {
    final detailed = _findCriticalBlockingPositionsDetailed(board, aiColor, enclosures, cache);
    return {...detailed.immediateCaptureBlocks.keys, ...detailed.encirclementBlocks.keys};
  }

  /// Find critical ATTACK positions - places where AI can severely damage opponent's vulnerable groups
  /// This enables counter-attacks when being encircled, rather than purely passive defense
  /// Key insight: if opponent has a thin line or weak group, attacking it may be better than blocking
  Set<Position> _findCriticalAttackPositions(Board board, StoneColor aiColor, _TurnCache cache) {
    final attackPositions = <Position>{};
    final opponentColor = aiColor.opponent;

    // === PHASE 1: Attack isolated/vulnerable groups ===
    for (final group in cache.opponentGroups) {
      // SINGLE STONE ATTACK: Isolated single stones are prime targets
      // They can be cut off from support or pressured into weak positions
      if (group.stones.length == 1) {
        final stone = group.stones.first;

        // Check how connected this stone is to other opponent stones
        int nearbyOpponentStones = 0;
        for (int dx = -2; dx <= 2; dx++) {
          for (int dy = -2; dy <= 2; dy++) {
            if (dx == 0 && dy == 0) continue;
            final checkPos = Position(stone.x + dx, stone.y + dy);
            if (board.isValidPosition(checkPos) && board.getStoneAt(checkPos) == opponentColor) {
              nearbyOpponentStones++;
            }
          }
        }

        // If truly isolated (0-1 nearby stones), it's a great attack target
        // Find positions that would pressure/surround it
        if (nearbyOpponentStones <= 1) {
          for (final emptyPos in group.boundaryEmpties) {
            // Simulate and check if it reduces escape
            final simBoard = board.placeStone(emptyPos, aiColor);
            final escapeAfter = _checkEscapePathDetailed(simBoard, stone, opponentColor);

            // Critical: would seal the stone
            if (!escapeAfter.canEscape || escapeAfter.edgeExitCount == 0) {
              attackPositions.add(emptyPos);
            } else if (escapeAfter.edgeExitCount <= 3) {
              // Significant pressure on isolated stone
              attackPositions.add(emptyPos);
            }
          }
        }
        continue; // Move to next group
      }

      // MULTI-STONE GROUPS: Target those with limited escape
      if (group.edgeExitCount > 8) continue; // Very safe, not worth urgent attack

      // Check boundary positions for critical attack opportunities
      for (final emptyPos in group.boundaryEmpties) {
        // Simulate placing our stone here
        final simBoard = board.placeStone(emptyPos, aiColor);
        final escapeAfter = _checkEscapePathDetailed(simBoard, group.stones.first, opponentColor);

        // CRITICAL ATTACK: Move would seal opponent completely (capture imminent)
        if (!escapeAfter.canEscape || escapeAfter.edgeExitCount == 0) {
          attackPositions.add(emptyPos);
          continue;
        }

        // SEVERE ATTACK: Move would reduce opponent to 1-2 exits (very vulnerable)
        if (escapeAfter.edgeExitCount <= 2 && group.edgeExitCount > 2) {
          attackPositions.add(emptyPos);
          continue;
        }

        // SIGNIFICANT ATTACK: Move would reduce exits by 2+ (meaningful pressure)
        final exitReduction = group.edgeExitCount - escapeAfter.edgeExitCount;
        if (exitReduction >= 2) {
          attackPositions.add(emptyPos);
          continue;
        }
      }

      // Also check positions that would CUT the opponent's group
      // Look for "thin connections" - places where opponent stones are connected by a single empty cell
      for (final stone in group.stones) {
        for (final adj in stone.adjacentPositions) {
          if (!board.isValidPosition(adj)) continue;
          if (!board.isEmpty(adj)) continue;

          // Check if this empty cell is a bridge between opponent stones
          int connectedOpponentStones = 0;
          for (final adjAdj in adj.adjacentPositions) {
            if (!board.isValidPosition(adjAdj)) continue;
            if (board.getStoneAt(adjAdj) == opponentColor) {
              connectedOpponentStones++;
            }
          }

          // Bridge cut: opponent has 2+ stones connected through this point
          // Placing here would split their formation
          if (connectedOpponentStones >= 2) {
            // Verify this actually reduces escape
            final simBoard = board.placeStone(adj, aiColor);
            final escapeAfter = _checkEscapePathDetailed(simBoard, stone, opponentColor);
            if (escapeAfter.edgeExitCount < group.edgeExitCount) {
              attackPositions.add(adj);
            }
          }
        }
      }
    }

    // === PHASE 2: Find thin connection cuts between different groups ===
    // When opponent is building an encirclement path, they often have thin chains
    // between groups - cutting these disrupts the encirclement
    final opponentGroups = cache.opponentGroups.toList();
    for (int i = 0; i < opponentGroups.length; i++) {
      for (int j = i + 1; j < opponentGroups.length; j++) {
        final group1 = opponentGroups[i];
        final group2 = opponentGroups[j];

        // Find empty cells that are adjacent to both groups (thin bridges)
        for (final empty1 in group1.boundaryEmpties) {
          if (group2.boundaryEmpties.contains(empty1)) {
            // This empty cell touches both groups - it's a potential cut point!
            // Check how valuable cutting here would be
            int adjacentToGroup1 = 0;
            int adjacentToGroup2 = 0;
            for (final adj in empty1.adjacentPositions) {
              if (group1.stones.contains(adj)) adjacentToGroup1++;
              if (group2.stones.contains(adj)) adjacentToGroup2++;
            }

            // If this is the ONLY connection between the groups, it's critical
            if (adjacentToGroup1 >= 1 && adjacentToGroup2 >= 1) {
              attackPositions.add(empty1);
            }
          }

          // Also check diagonal bridges (empty cells 1 apart that both touch)
          for (final adj in empty1.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (!board.isEmpty(adj)) continue;
            if (group2.boundaryEmpties.contains(adj)) {
              // empty1 touches group1, adj touches group2, and they're adjacent
              // Either position could cut the thin bridge
              attackPositions.add(empty1);
              attackPositions.add(adj);
            }
          }
        }
      }
    }

    return attackPositions;
  }

  /// Find gaps in opponent's wall formation around an AI group
  /// These are empty positions that, if filled by us, would break the encirclement
  Set<Position> _findWallGapsAroundGroup(Board board, _GroupInfo group, StoneColor opponentColor) {
    final gaps = <Position>{};

    // Look at all positions within distance 2 of any stone in the group
    for (final stone in group.stones) {
      for (int dx = -2; dx <= 2; dx++) {
        for (int dy = -2; dy <= 2; dy++) {
          if (dx == 0 && dy == 0) continue;
          final checkPos = Position(stone.x + dx, stone.y + dy);
          if (!board.isValidPosition(checkPos)) continue;
          if (!board.isEmpty(checkPos)) continue;

          // Count opponent stones adjacent to this empty position
          int adjacentOpponent = 0;
          bool adjacentToOurGroup = false;

          for (final adj in checkPos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            final adjStone = board.getStoneAt(adj);
            if (adjStone == opponentColor) {
              adjacentOpponent++;
            }
            if (group.stones.contains(adj)) {
              adjacentToOurGroup = true;
            }
          }

          // This is a wall gap if:
          // 1. It's adjacent to 2+ opponent stones (they're forming a wall)
          // 2. It's near our group (either adjacent or within 1 cell)
          if (adjacentOpponent >= 2) {
            // Check if it's near our group
            if (adjacentToOurGroup || group.boundaryEmpties.contains(checkPos)) {
              gaps.add(checkPos);
            } else {
              // Check if it's 1 cell away from our boundary
              for (final adj in checkPos.adjacentPositions) {
                if (group.boundaryEmpties.contains(adj)) {
                  gaps.add(checkPos);
                  break;
                }
              }
            }
          }
        }
      }
    }

    return gaps;
  }

  /// Penalize moves placed in regions with fewer than 2 empty expansion paths
  /// This makes AI avoid cramped positions that are strategically weak
  double _evaluateExpansionPathPenalty(Board board, Position pos, StoneColor aiColor) {
    // Count distinct expansion directions (empty paths leading away)
    int expansionDirections = 0;

    // Check each orthogonal direction for open paths
    final directions = [
      Position(1, 0),   // right
      Position(-1, 0),  // left
      Position(0, 1),   // down
      Position(0, -1),  // up
    ];

    for (final dir in directions) {
      // Look up to 3 cells in each direction for open space
      bool hasOpenPath = false;
      for (int dist = 1; dist <= 3; dist++) {
        final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
        if (!board.isValidPosition(checkPos)) break;

        final stone = board.getStoneAt(checkPos);
        if (stone == null) {
          // Empty space - this direction has potential
          hasOpenPath = true;
          break;
        } else if (stone != aiColor) {
          // Opponent stone blocks this direction
          break;
        }
        // Own stone - continue checking
      }
      if (hasOpenPath) expansionDirections++;
    }

    // Penalize positions with fewer than 2 expansion paths
    if (expansionDirections < 2) {
      return 3.0 - expansionDirections; // 3 penalty for 0 paths, 2 for 1 path
    }

    return 0;
  }

  /// Evaluate proximity to opponent's last move - AI MUST respond nearby
  /// This is the most important factor for keeping the game focused
  double _evaluateProximityToOpponent(Board board, Position pos, Position? opponentLastMove) {
    if (opponentLastMove == null) return 0;

    // Calculate Chebyshev distance (max of dx, dy) - this is "grid distance"
    final dx = (pos.x - opponentLastMove.x).abs();
    final dy = (pos.y - opponentLastMove.y).abs();
    final distance = max(dx, dy); // Chebyshev distance (1-2 grid cells)

    // VERY strong bonus for moves within 1-2 cells of opponent's last move
    // and PENALTY for moves further away
    if (distance <= 1) {
      return 50; // Adjacent - highest priority
    } else if (distance <= 2) {
      return 35; // 2 cells away - very good
    } else if (distance <= 3) {
      return 10; // 3 cells - acceptable
    } else if (distance <= 4) {
      return -10; // Starting to get far - slight penalty
    } else {
      return -30; // Too far - strong penalty to discourage
    }
  }

  /// Evaluate moves that contest opponent's territory/stones
  double _evaluateContestOpponent(Board board, Position pos, StoneColor aiColor) {
    double contestScore = 0;
    final opponentColor = aiColor.opponent;

    // Check for opponent stones within a radius of 2 (tight focus)
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nearPos = Position(pos.x + dx, pos.y + dy);
        if (!board.isValidPosition(nearPos)) continue;

        if (board.getStoneAt(nearPos) == opponentColor) {
          final distance = max(dx.abs(), dy.abs()); // Chebyshev distance
          // Bonus for being near opponent stones (to contest them)
          if (distance == 1) {
            contestScore += 5; // Adjacent - direct contest
          } else if (distance == 2) {
            contestScore += 2; // 2 cells away
          }
        }
      }
    }

    return contestScore;
  }

  /// Evaluate local empty adjacencies (minor tiebreaker)
  /// In Edgeline, adjacent empties are weak compared to edge-reachability
  /// This is kept as a minor signal, not a major scoring factor
  double _evaluateLocalEmpties(Board board, Position pos, StoneColor aiColor) {
    double score = 0;
    final opponentColor = aiColor.opponent;
    final calculator = LibertyCalculator(board);

    // Check adjacent opponent groups - minor bonus for reducing their local empties
    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) != opponentColor) continue;

      final group = calculator.findGroup(adjacent);
      final liberties = calculator.getGroupLiberties(group);

      // Minor bonus for reducing opponent's local empties (tiebreaker only)
      if (liberties.length == 1) {
        score += group.length * 1.0; // Reduced from 5
      } else if (liberties.length == 2) {
        score += group.length * 0.5; // Reduced from 2
      }
    }

    // Check if this move helps our own groups' local empties
    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) != aiColor) continue;

      final group = calculator.findGroup(adjacent);
      final liberties = calculator.getGroupLiberties(group);

      // Minor bonus for adding local empties to our groups
      if (liberties.length == 1) {
        score += group.length * 2.0; // Reduced from 10
      } else if (liberties.length == 2) {
        score += group.length * 0.5; // Reduced from 3
      }
    }

    return score;
  }

  /// Evaluate expansion value
  double _evaluateExpansion(Board board, Position pos, StoneColor aiColor) {
    double expansionScore = 0;

    // Prefer moves near own stones (within 2 cells)
    for (int dx = -2; dx <= 2; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        if (dx == 0 && dy == 0) continue;
        final nearPos = Position(pos.x + dx, pos.y + dy);
        if (!board.isValidPosition(nearPos)) continue;

        if (board.getStoneAt(nearPos) == aiColor) {
          final distance = max(dx.abs(), dy.abs()); // Chebyshev distance
          if (distance == 2) {
            expansionScore += 3; // Good expansion distance
          } else if (distance == 1) {
            expansionScore += 1; // Adjacent - connected
          }
        }
      }
    }

    return expansionScore;
  }

  /// CRITICAL: Penalize moves in positions where we're being surrounded
  /// Checks if opponent has stones on multiple sides forming an encirclement
  double _evaluateSurroundedPenalty(Board board, Position pos, StoneColor aiColor) {
    final opponentColor = aiColor.opponent;
    double penalty = 0;

    // Count opponent stones in each direction (8 directions)
    // If opponent has presence on 3+ sides, we're being surrounded
    int sidesWithOpponent = 0;
    int totalOpponentNearby = 0;

    // Check 8 directions in groups of 2 (opposite sides)
    final directionPairs = [
      [Position(-1, 0), Position(1, 0)],   // left/right
      [Position(0, -1), Position(0, 1)],   // up/down
      [Position(-1, -1), Position(1, 1)], // diagonals
      [Position(-1, 1), Position(1, -1)], // diagonals
    ];

    for (final pair in directionPairs) {
      for (final dir in pair) {
        // Look up to 2 cells in each direction
        bool foundOpponent = false;
        for (int dist = 1; dist <= 2; dist++) {
          final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
          if (!board.isValidPosition(checkPos)) break;

          final stone = board.getStoneAt(checkPos);
          if (stone == opponentColor) {
            foundOpponent = true;
            totalOpponentNearby++;
            break;
          } else if (stone == aiColor) {
            // Our stone - friendly, stop looking
            break;
          }
        }
        if (foundOpponent) sidesWithOpponent++;
      }
    }

    // Strong penalty if opponent has stones on 3+ sides (forming encirclement)
    if (sidesWithOpponent >= 4) {
      penalty += 8; // Heavily surrounded
    } else if (sidesWithOpponent >= 3) {
      penalty += 4; // Mostly surrounded
    }

    // Additional penalty based on total opponent presence nearby
    if (totalOpponentNearby >= 5) {
      penalty += 3;
    } else if (totalOpponentNearby >= 4) {
      penalty += 2;
    }

    // Check for "pincer" patterns - opponent on opposite sides
    for (final pair in directionPairs) {
      bool hasOpponentOnBothEnds = true;
      for (final dir in pair) {
        bool found = false;
        for (int dist = 1; dist <= 2; dist++) {
          final checkPos = Position(pos.x + dir.x * dist, pos.y + dir.y * dist);
          if (!board.isValidPosition(checkPos)) break;
          if (board.getStoneAt(checkPos) == opponentColor) {
            found = true;
            break;
          } else if (board.getStoneAt(checkPos) != null) {
            break;
          }
        }
        if (!found) {
          hasOpponentOnBothEnds = false;
          break;
        }
      }
      if (hasOpponentOnBothEnds) {
        penalty += 3; // We're in a pincer (opponent on opposite sides)
      }
    }

    return penalty;
  }

  /// Evaluate blocking opponent's expansion direction
  /// When opponent places a stone, they're likely trying to extend in a direction
  /// We should place stones that block their natural expansion path
  double _evaluateBlockingExpansion(Board board, Position pos, StoneColor aiColor, Position? opponentLastMove) {
    if (opponentLastMove == null) return 0;

    final opponentColor = aiColor.opponent;
    double blockingScore = 0;

    // Find the direction opponent is expanding (from their previous stones to their last move)
    // Look for opponent stones adjacent to their last move
    final expansionDirections = <Position>[];

    for (final adj in opponentLastMove.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (board.getStoneAt(adj) == opponentColor) {
        // Opponent has a stone here - the expansion direction is AWAY from this stone
        // Direction = lastMove - adjacentStone (normalized)
        final dx = opponentLastMove.x - adj.x;
        final dy = opponentLastMove.y - adj.y;
        expansionDirections.add(Position(dx, dy));
      }
    }

    if (expansionDirections.isEmpty) {
      // No adjacent opponent stones - this might be a new group
      // In this case, prefer positions that are directly adjacent to opponent's last move
      // to contest the space
      final dx = (pos.x - opponentLastMove.x).abs();
      final dy = (pos.y - opponentLastMove.y).abs();
      if (dx <= 1 && dy <= 1 && (dx + dy) > 0) {
        blockingScore += 2; // Directly adjacent to opponent's new stone
      }
      return blockingScore;
    }

    // Check if our move blocks the opponent's expansion direction
    for (final dir in expansionDirections) {
      // The "blocking position" is where opponent would naturally extend next
      // That's: opponentLastMove + direction
      final naturalExtension = Position(
        opponentLastMove.x + dir.x,
        opponentLastMove.y + dir.y,
      );

      // If we're placing at the natural extension point, big bonus!
      if (pos == naturalExtension) {
        blockingScore += 4; // Directly blocking their expansion
      }

      // If we're placing adjacent to the natural extension, still good
      final dx = (pos.x - naturalExtension.x).abs();
      final dy = (pos.y - naturalExtension.y).abs();
      if (dx <= 1 && dy <= 1 && (dx + dy) > 0) {
        blockingScore += 2; // Near their expansion path
      }

      // Also check if we're blocking the continuation of the line
      // E.g., if opponent is building a line, block further along it
      final furtherExtension = Position(
        opponentLastMove.x + dir.x * 2,
        opponentLastMove.y + dir.y * 2,
      );
      if (board.isValidPosition(furtherExtension) && board.isEmpty(furtherExtension)) {
        if (pos == furtherExtension) {
          blockingScore += 3; // Blocking further extension
        }
      }
    }

    // ADDITIONAL: Check if opponent is building toward edge (dangerous for us)
    // If their expansion leads toward cutting off our escape, prioritize blocking
    for (final dir in expansionDirections) {
      // Check if this direction leads toward us
      final towardUs = Position(
        opponentLastMove.x + dir.x,
        opponentLastMove.y + dir.y,
      );

      // See if there are any AI stones in this direction
      for (int dist = 1; dist <= 3; dist++) {
        final checkPos = Position(
          opponentLastMove.x + dir.x * dist,
          opponentLastMove.y + dir.y * dist,
        );
        if (!board.isValidPosition(checkPos)) break;

        if (board.getStoneAt(checkPos) == aiColor) {
          // Opponent is expanding toward our stones!
          // Blocking this is important
          if (pos == towardUs) {
            blockingScore += 3; // Critical - blocking attack toward our group
          }
          break;
        }
        if (board.getStoneAt(checkPos) == opponentColor) {
          break; // Their stone - stop looking
        }
      }
    }

    return blockingScore;
  }

  /// Evaluate position value based on board location
  /// KEY INSIGHT: In Edgeline, EDGE CONNECTIVITY is everything
  /// Positions on or very near the edge are safe; interior positions are vulnerable
  double _evaluateCenterBonus(Board board, Position pos) {
    double score = 0;

    // Calculate distance from nearest edge
    final distFromEdge = _distanceFromEdge(pos, board.size);

    // EDGE CELLS: Direct edge = guaranteed safety (highest value)
    if (distFromEdge == 0) {
      score += 25; // Very strong - this is the safest position

      // CORNER CELLS: Access to TWO edges = even better
      final isCornerEdge = (pos.x == 0 || pos.x == board.size - 1) &&
                           (pos.y == 0 || pos.y == board.size - 1);
      if (isCornerEdge) {
        score += 10; // Corner edge cell bonus
      }
    }
    // ONE CELL FROM EDGE: Can easily create 2-wide corridor
    else if (distFromEdge == 1) {
      score += 15;

      // Near corner (within 3 of two edges) - access to two escape directions
      final nearTwoEdges = (pos.x <= 3 || pos.x >= board.size - 4) &&
                           (pos.y <= 3 || pos.y >= board.size - 4);
      if (nearTwoEdges) {
        score += 5;
      }
    }
    // TWO CELLS FROM EDGE: Still reasonable access
    else if (distFromEdge == 2) {
      score += 8;
    }
    // THREE+ CELLS FROM EDGE: Interior positions - vulnerable
    else {
      // Mild penalty for deep interior - these need careful planning
      score -= (distFromEdge - 2) * 2;
    }

    return score;
  }

  /// Evaluate self-atari risk
  double _evaluateSelfAtari(Board board, Position pos, StoneColor aiColor) {
    final calculator = LibertyCalculator(board);
    final group = calculator.findGroup(pos);
    final liberties = calculator.getGroupLiberties(group);

    if (liberties.length == 1) {
      return group.length * 5; // Bad - putting ourselves in atari
    } else if (liberties.length == 2) {
      return group.length * 1; // Slightly risky
    }

    return 0;
  }

  /// Evaluate connection value with strength tracking
  /// 2+ connections between groups = very stable (+40)
  /// Single connection = cutting risk (-30)
  double _evaluateConnection(Board board, Position pos, StoneColor aiColor) {
    double connectionScore = 0;
    int ownAdjacent = 0;

    for (final adjacent in pos.adjacentPositions) {
      if (!board.isValidPosition(adjacent)) continue;
      if (board.getStoneAt(adjacent) == aiColor) {
        ownAdjacent++;
      }
    }

    // Bonus for connecting groups (but not too many adjacent - that's inefficient)
    if (ownAdjacent == 1 || ownAdjacent == 2) {
      connectionScore = 3;
    }

    return connectionScore;
  }

  /// Evaluate connection strength between groups
  /// Multiple connection points = robust, single connection = vulnerable to cutting
  double _evaluateConnectionStrength(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    double score = 0;

    // Check if this move creates/strengthens connections between AI groups
    final adjacentGroups = <_GroupInfo>{};
    for (final adj in pos.adjacentPositions) {
      if (!board.isValidPosition(adj)) continue;
      if (board.getStoneAt(adj) != aiColor) continue;

      // Find which group this adjacent stone belongs to
      for (final group in cache.aiGroups) {
        if (group.stones.contains(adj)) {
          adjacentGroups.add(group);
          break;
        }
      }
    }

    // If connecting 2+ different groups, check connection strength
    if (adjacentGroups.length >= 2) {
      // Great - connecting multiple groups!
      score += 40;

      // Check if there are OTHER connection points between these groups
      // (besides the one we're creating)
      bool hasAlternateConnection = false;
      final groupList = adjacentGroups.toList();
      for (int i = 0; i < groupList.length - 1; i++) {
        for (int j = i + 1; j < groupList.length; j++) {
          if (_haveAlternateConnection(board, groupList[i], groupList[j], pos)) {
            hasAlternateConnection = true;
            break;
          }
        }
        if (hasAlternateConnection) break;
      }

      if (!hasAlternateConnection) {
        // This would be the ONLY connection point - risky
        score -= 20; // Penalize creating single-point connections
      }
    } else if (adjacentGroups.length == 1) {
      // Extending a group - check if current group has good connection strength
      final group = adjacentGroups.first;

      // Check if this group has other nearby friendly groups with weak connections
      for (final otherGroup in cache.aiGroups) {
        if (otherGroup == group) continue;

        // Check distance between groups
        for (final stone in group.stones) {
          for (final otherStone in otherGroup.stones) {
            final dist = (stone.x - otherStone.x).abs() + (stone.y - otherStone.y).abs();
            if (dist == 2) {
              // Groups are 2 apart - could be connected by single point
              // Check if there's only one empty between them
              final midX = (stone.x + otherStone.x) ~/ 2;
              final midY = (stone.y + otherStone.y) ~/ 2;
              final midPos = Position(midX, midY);
              if (board.isEmpty(midPos)) {
                // Single connection point exists - vulnerable
                if (pos == midPos) {
                  // We're creating the connection - add bonus but note weakness
                  score += 15;
                }
              }
            }
          }
        }
      }
    }

    return score;
  }

  /// Evaluate isolated center penalty - center groups without edge connectivity plan are very vulnerable
  /// In Edgeline, edge connectivity is EVERYTHING - isolated center groups get captured
  double _evaluateIsolatedCenterPenalty(Board board, Position pos, StoneColor aiColor) {
    // Only penalize moves that are far from the edge
    final distFromEdge = _distanceFromEdge(pos, board.size);
    if (distFromEdge < 3) return 0; // Close enough to edge

    // Check if placing here would create or extend an isolated center group
    final newBoard = board.placeStone(pos, aiColor);
    final escapeResult = _checkEscapePathDetailed(newBoard, pos, aiColor);

    // If the group has limited edge exits and is in the center, it's dangerous
    if (escapeResult.edgeExitCount <= 3) {
      // Calculate how isolated this position is
      double penalty = 0;

      // Distance from edge contributes to penalty
      penalty += distFromEdge * 0.5;

      // Very few edge exits = high vulnerability
      if (escapeResult.edgeExitCount <= 1) {
        penalty += 3;
      } else if (escapeResult.edgeExitCount <= 2) {
        penalty += 2;
      }

      // If no friendly stones nearby to help, extra penalty
      int friendlyNearby = 0;
      for (int dx = -2; dx <= 2; dx++) {
        for (int dy = -2; dy <= 2; dy++) {
          final checkPos = Position(pos.x + dx, pos.y + dy);
          if (board.isValidPosition(checkPos) && board.getStoneAt(checkPos) == aiColor) {
            friendlyNearby++;
          }
        }
      }

      if (friendlyNearby == 0) {
        penalty += 2; // Completely isolated in center
      }

      return penalty;
    }

    return 0;
  }

  /// Calculate distance from nearest edge
  int _distanceFromEdge(Position pos, int boardSize) {
    final distX = min(pos.x, boardSize - 1 - pos.x);
    final distY = min(pos.y, boardSize - 1 - pos.y);
    return min(distX, distY);
  }

  /// Check if two groups have an alternate connection point (besides excludePos)
  bool _haveAlternateConnection(Board board, _GroupInfo group1, _GroupInfo group2, Position excludePos) {
    // Check if any stone in group1 is adjacent to group2 or shares an empty neighbor
    for (final stone1 in group1.stones) {
      for (final stone2 in group2.stones) {
        // Direct adjacency
        final dist = (stone1.x - stone2.x).abs() + (stone1.y - stone2.y).abs();
        if (dist == 1) {
          return true; // Already directly connected
        }

        // Connected through a different empty cell
        if (dist == 2) {
          for (final adj in stone1.adjacentPositions) {
            if (adj == excludePos) continue;
            if (!board.isValidPosition(adj)) continue;
            if (board.isEmpty(adj) && stone2.adjacentPositions.contains(adj)) {
              return true; // Alternative connection point exists
            }
          }
        }
      }
    }

    return false;
  }

  /// Calculate minimum cut to edge using articulation point heuristic
  /// Returns estimated min-cut (1, 2, or 3+ meaning safe)
  /// Uses a local window around the target region for performance
  ///
  /// This measures "robustness" - how many independent paths exist to the edge
  /// A min-cut of 1 means there's a single chokepoint that can be blocked
  int _minCutToEdgeLocal(Board board, Set<Position> targetStones, int windowRadius) {
    if (targetStones.isEmpty) return 3;

    // Find the bounding box of target stones
    int minX = board.size, maxX = 0, minY = board.size, maxY = 0;
    for (final stone in targetStones) {
      if (stone.x < minX) minX = stone.x;
      if (stone.x > maxX) maxX = stone.x;
      if (stone.y < minY) minY = stone.y;
      if (stone.y > maxY) maxY = stone.y;
    }

    // Expand window by radius
    final windowMinX = (minX - windowRadius).clamp(0, board.size - 1);
    final windowMaxX = (maxX + windowRadius).clamp(0, board.size - 1);
    final windowMinY = (minY - windowRadius).clamp(0, board.size - 1);
    final windowMaxY = (maxY + windowRadius).clamp(0, board.size - 1);

    // Build local empty graph within window
    final emptyInWindow = <Position>{};
    for (int x = windowMinX; x <= windowMaxX; x++) {
      for (int y = windowMinY; y <= windowMaxY; y++) {
        final pos = Position(x, y);
        if (board.isEmpty(pos)) {
          emptyInWindow.add(pos);
        }
      }
    }

    if (emptyInWindow.isEmpty) return 0; // Completely surrounded

    // Find empty positions adjacent to target stones (starting points)
    final startPoints = <Position>{};
    for (final stone in targetStones) {
      for (final adj in stone.adjacentPositions) {
        if (emptyInWindow.contains(adj)) {
          startPoints.add(adj);
        }
      }
    }

    if (startPoints.isEmpty) return 0; // No adjacent empties

    // Find edge positions in window (end points)
    final edgePositions = <Position>{};
    for (final pos in emptyInWindow) {
      if (_isOnEdge(pos, board.size)) {
        edgePositions.add(pos);
      }
    }

    // If window touches edge and has direct path, check articulation points
    if (edgePositions.isEmpty) {
      // Window doesn't reach edge - need to check if paths exist outside window
      // For now, estimate based on openings at window boundary
      int boundaryOpenings = 0;
      for (final pos in emptyInWindow) {
        if (pos.x == windowMinX || pos.x == windowMaxX ||
            pos.y == windowMinY || pos.y == windowMaxY) {
          // Check if adjacent position outside window is empty
          for (final adj in pos.adjacentPositions) {
            if (!board.isValidPosition(adj)) continue;
            if (adj.x < windowMinX || adj.x > windowMaxX ||
                adj.y < windowMinY || adj.y > windowMaxY) {
              if (board.isEmpty(adj)) {
                boundaryOpenings++;
              }
            }
          }
        }
      }
      return boundaryOpenings.clamp(0, 3);
    }

    // Use articulation point heuristic to estimate min-cut
    // Count independent paths from startPoints to edgePositions
    return _countIndependentPaths(board, startPoints, edgePositions, emptyInWindow);
  }

  /// Count independent paths using iterative path removal
  /// Returns min(pathCount, 3) for efficiency
  int _countIndependentPaths(Board board, Set<Position> starts, Set<Position> ends, Set<Position> validPositions) {
    if (starts.isEmpty || ends.isEmpty) return 0;

    // Check if any start is directly an edge
    for (final start in starts) {
      if (ends.contains(start)) return 3; // Direct edge access = very safe
    }

    int pathCount = 0;
    final blocked = <Position>{};

    // Find up to 3 independent paths
    for (int i = 0; i < 3; i++) {
      final path = _findPathBFS(starts, ends, validPositions, blocked);
      if (path == null) break;

      pathCount++;

      // Block the narrowest point of this path (articulation point approximation)
      // Find the position in path with fewest unblocked neighbors
      Position? chokePoint;
      int minNeighbors = 5;

      for (final pos in path) {
        if (starts.contains(pos) || ends.contains(pos)) continue;

        int neighborCount = 0;
        for (final adj in pos.adjacentPositions) {
          if (validPositions.contains(adj) && !blocked.contains(adj)) {
            neighborCount++;
          }
        }

        if (neighborCount < minNeighbors) {
          minNeighbors = neighborCount;
          chokePoint = pos;
        }
      }

      if (chokePoint != null) {
        blocked.add(chokePoint);
      } else if (path.isNotEmpty) {
        // Block middle of path if no clear chokepoint
        blocked.add(path.elementAt(path.length ~/ 2));
      }
    }

    return pathCount;
  }

  /// BFS to find a path from any start to any end, avoiding blocked positions
  Set<Position>? _findPathBFS(Set<Position> starts, Set<Position> ends, Set<Position> valid, Set<Position> blocked) {
    final visited = <Position>{};
    final parent = <Position, Position?>{};
    final queue = <Position>[];

    for (final start in starts) {
      if (!blocked.contains(start) && valid.contains(start)) {
        queue.add(start);
        visited.add(start);
        parent[start] = null;
      }
    }

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      if (ends.contains(current)) {
        // Reconstruct path
        final path = <Position>{};
        Position? node = current;
        while (node != null) {
          path.add(node);
          node = parent[node];
        }
        return path;
      }

      for (final adj in current.adjacentPositions) {
        if (!visited.contains(adj) && valid.contains(adj) && !blocked.contains(adj)) {
          visited.add(adj);
          parent[adj] = current;
          queue.add(adj);
        }
      }
    }

    return null; // No path found
  }

  /// Evaluate escape robustness reduction - how much does this move reduce opponent's escape paths
  /// High weight for moves that reduce min-cut from 2+ to 1 (creating chokepoint)
  double _evaluateEscapeRobustnessReduction(Board board, Position pos, StoneColor aiColor, _TurnCache cache) {
    double score = 0;

    // Only evaluate groups that are already somewhat constrained
    for (final group in cache.opponentGroups) {
      if (!_isGroupNearPosition(group, pos, 3)) continue;
      if (group.edgeExitCount > 8) continue; // Already very safe, skip

      // Calculate min-cut before our move
      final minCutBefore = _minCutToEdgeLocal(board, group.stones, 6);

      // Skip if already very robust
      if (minCutBefore >= 3) continue;

      // Simulate our move
      final newBoard = board.placeStone(pos, aiColor);

      // Calculate min-cut after our move
      final minCutAfter = _minCutToEdgeLocal(newBoard, group.stones, 6);

      // Reward reducing robustness
      if (minCutAfter < minCutBefore) {
        final reduction = minCutBefore - minCutAfter;
        score += reduction * 15;

        // Extra bonus for creating single chokepoint
        if (minCutAfter == 1) {
          score += 25;
        }

        // Massive bonus for completely blocking
        if (minCutAfter == 0) {
          score += 50;
        }
      }
    }

    return score;
  }

  /// Find chokepoint positions for opponent groups (for targeted candidate generation)
  Set<Position> _findChokepoints(Board board, _TurnCache cache, StoneColor aiColor) {
    final chokepoints = <Position>{};

    for (final group in cache.opponentGroups) {
      // Only target groups that can potentially be captured
      if (group.edgeExitCount > 6) continue;

      final minCut = _minCutToEdgeLocal(board, group.stones, 6);
      if (minCut >= 3) continue; // Too robust to target

      // Find positions that would reduce min-cut
      for (final emptyPos in group.boundaryEmpties) {
        final newBoard = board.placeStone(emptyPos, aiColor);
        final newMinCut = _minCutToEdgeLocal(newBoard, group.stones, 6);

        if (newMinCut < minCut) {
          chokepoints.add(emptyPos);
        }
      }

      // Also check positions near the escape corridors
      // These are empty positions that are on the path to edge
      for (final stone in group.stones) {
        for (int dx = -3; dx <= 3; dx++) {
          for (int dy = -3; dy <= 3; dy++) {
            final checkPos = Position(stone.x + dx, stone.y + dy);
            if (!board.isValidPosition(checkPos)) continue;
            if (!board.isEmpty(checkPos)) continue;

            // Check if this position is in a corridor (has limited neighbors)
            int emptyNeighbors = 0;
            for (final adj in checkPos.adjacentPositions) {
              if (board.isValidPosition(adj) && board.isEmpty(adj)) {
                emptyNeighbors++;
              }
            }

            // Narrow corridor = potential chokepoint
            if (emptyNeighbors <= 2) {
              final newBoard = board.placeStone(checkPos, aiColor);
              final newMinCut = _minCutToEdgeLocal(newBoard, group.stones, 6);
              if (newMinCut < minCut) {
                chokepoints.add(checkPos);
              }
            }
          }
        }
      }
    }

    return chokepoints;
  }

  /// Select a move based on AI level
  Position _selectMoveByLevel(List<_ScoredMove> scoredMoves, AiLevel level) {
    if (scoredMoves.isEmpty) {
      throw StateError('No valid moves available');
    }

    // At very low levels (1-2), occasionally make clearly suboptimal moves
    // This makes the AI feel more "beginner-like"
    if (level.level <= 2 && scoredMoves.length > 5) {
      // 30% chance at level 1, 15% chance at level 2 to pick from bottom half
      final mistakeChance = level.level == 1 ? 0.30 : 0.15;
      if (_random.nextDouble() < mistakeChance) {
        final bottomHalf = scoredMoves.skip(scoredMoves.length ~/ 2).toList();
        if (bottomHalf.isNotEmpty) {
          return bottomHalf[_random.nextInt(bottomHalf.length)].position;
        }
      }
    }

    // Determine how many top moves to consider based on level
    // Higher levels consider fewer moves (more focused on best)
    // Lower levels consider more moves (more random)
    final considerCount = max(1, (scoredMoves.length * (1.1 - level.strength)).round());
    final topMoves = scoredMoves.take(considerCount).toList();

    // Add randomness based on level
    // Level 1: Very random, Level 10: Almost always best move
    if (_random.nextDouble() > level.strength) {
      // Random selection from top moves
      return topMoves[_random.nextInt(topMoves.length)].position;
    } else {
      // Pick best move (with small chance of second best for variety)
      if (topMoves.length > 1 && _random.nextDouble() < 0.1) {
        return topMoves[1].position;
      }
      return topMoves[0].position;
    }
  }

  /// Build per-turn cache of group information to avoid redundant flood-fills
  _TurnCache _buildTurnCache(Board board, StoneColor aiColor, List<Enclosure> enclosures) {
    final aiGroups = <_GroupInfo>[];
    final opponentGroups = <_GroupInfo>[];
    final forbiddenPositions = <Position>{};
    final checkedAi = <Position>{};
    final checkedOpponent = <Position>{};
    final opponentColor = aiColor.opponent;

    // Build forbidden positions from enclosures
    for (final enclosure in enclosures) {
      if (enclosure.owner != aiColor) {
        forbiddenPositions.addAll(enclosure.interiorPositions);
      }
    }

    // Find all AI groups
    for (int x = 0; x < board.size; x++) {
      for (int y = 0; y < board.size; y++) {
        final pos = Position(x, y);
        final stone = board.getStoneAt(pos);

        if (stone == aiColor && !checkedAi.contains(pos)) {
          final groupInfo = _buildGroupInfo(board, pos, aiColor, opponentColor);
          aiGroups.add(groupInfo);
          checkedAi.addAll(groupInfo.stones);
        } else if (stone == opponentColor && !checkedOpponent.contains(pos)) {
          final groupInfo = _buildGroupInfo(board, pos, opponentColor, aiColor);
          opponentGroups.add(groupInfo);
          checkedOpponent.addAll(groupInfo.stones);
        }
      }
    }

    return _TurnCache(
      aiGroups: aiGroups,
      opponentGroups: opponentGroups,
      forbiddenPositions: forbiddenPositions,
    );
  }

  /// Update the POI (Points of Interest) cache based on opponent's latest move
  /// Tracks distant opponent activity to detect build-up in sectors we're not focused on
  /// Only active for levels 8+ where strategic awareness matters
  void _updatePOI(Board board, StoneColor aiColor, Position? opponentLastMove, AiLevel level) {
    // Only enable POI for high-level AI (8+)
    if (level.level < 8) return;

    const int sectorSize = 5;
    const double decayRate = 0.9;
    const int maxPOIs = 10;

    // Increment move count
    _poiCache.moveCount++;

    // If no opponent move, just decay existing weights
    if (opponentLastMove == null) {
      _decayPOIWeights(decayRate);
      return;
    }

    // Calculate proximity zone from PREVIOUS opponent moves (excluding the latest)
    // This is where we were focused BEFORE the opponent's new move
    final proximityZone = <Position>{};

    // Previous opponent moves (up to 4)
    final previousMoves = _poiCache.previousOpponentMoves.length > 1
        ? _poiCache.previousOpponentMoves.take(_poiCache.previousOpponentMoves.length - 1).toList()
        : <Position>[];
    final last4Previous = previousMoves.length >= 4
        ? previousMoves.skip(previousMoves.length - 4).toList()
        : previousMoves;

    for (final move in last4Previous) {
      for (int dx = -4; dx <= 4; dx++) {
        for (int dy = -4; dy <= 4; dy++) {
          final pos = Position(move.x + dx, move.y + dy);
          if (board.isValidPosition(pos)) proximityZone.add(pos);
        }
      }
    }

    // Also include our own recent moves as "proximity" (we're engaged here)
    final ownLast3 = _poiCache.previousOwnMoves.length >= 3
        ? _poiCache.previousOwnMoves.skip(_poiCache.previousOwnMoves.length - 3).toList()
        : _poiCache.previousOwnMoves.toList();
    for (final move in ownLast3) {
      for (int dx = -3; dx <= 3; dx++) {
        for (int dy = -3; dy <= 3; dy++) {
          final pos = Position(move.x + dx, move.y + dy);
          if (board.isValidPosition(pos)) proximityZone.add(pos);
        }
      }
    }

    // Decay all existing weights
    _decayPOIWeights(decayRate);

    // Check if opponent's LATEST move is OUTSIDE proximity zone
    // (outside where we and opponent were previously focused)
    if (!proximityZone.contains(opponentLastMove)) {
      // This is a distant move - add to POI
      final sectorId = _POICache.getSectorId(opponentLastMove, board.size, sectorSize: sectorSize);

      // Increase weight
      _poiCache.sectorWeights[sectorId] = (_poiCache.sectorWeights[sectorId] ?? 0) + 1.0;
      _poiCache.sectorLastActivity[sectorId] = _poiCache.moveCount;

      // Check if this stone connects to existing opponent stones (group bonus)
      for (final adj in opponentLastMove.adjacentPositions) {
        if (board.isValidPosition(adj) && board.getStoneAt(adj) == aiColor.opponent) {
          _poiCache.sectorWeights[sectorId] = _poiCache.sectorWeights[sectorId]! + 0.5;
          break;
        }
      }
    }

    // Update previous moves for next turn
    _poiCache.previousOpponentMoves.add(opponentLastMove);
    if (_poiCache.previousOpponentMoves.length > 10) {
      _poiCache.previousOpponentMoves.removeAt(0);
    }

    // Prune to top POIs by weight
    if (_poiCache.sectorWeights.length > maxPOIs) {
      final sorted = _poiCache.sectorWeights.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final toKeep = sorted.take(maxPOIs).map((e) => e.key).toSet();
      _poiCache.sectorWeights.removeWhere((k, _) => !toKeep.contains(k));
      _poiCache.sectorLastActivity.removeWhere((k, _) => !toKeep.contains(k));
    }
  }

  /// Decay all POI weights and remove negligible ones
  void _decayPOIWeights(double decayRate) {
    for (final sectorId in _poiCache.sectorWeights.keys.toList()) {
      _poiCache.sectorWeights[sectorId] = _poiCache.sectorWeights[sectorId]! * decayRate;
      // Remove if weight is negligible
      if (_poiCache.sectorWeights[sectorId]! < 0.1) {
        _poiCache.sectorWeights.remove(sectorId);
        _poiCache.sectorLastActivity.remove(sectorId);
      }
    }
  }

  /// Get POI candidate positions for high-level AI
  /// Returns positions in hot sectors that should be considered for contesting
  Set<Position> _getPOICandidates(Board board, StoneColor aiColor, List<Enclosure> enclosures) {
    final candidates = <Position>{};

    // Get hot sectors with moderate weight threshold
    final hotSectors = _poiCache.getHotSectors(threshold: 1.0);

    for (final sector in hotSectors.take(3)) {
      // Find positions in this sector to contest opponent's build-up
      final positions = _POICache.getPositionsInSector(sector.key, board.size);

      for (final pos in positions) {
        if (!board.isEmpty(pos)) continue;
        if (enclosures.any((e) => e.containsPosition(pos))) continue;

        // Prefer positions adjacent to opponent stones (contest their territory)
        bool adjacentToOpponent = false;
        for (final adj in pos.adjacentPositions) {
          if (board.isValidPosition(adj) && board.getStoneAt(adj) == aiColor.opponent) {
            adjacentToOpponent = true;
            break;
          }
        }

        // Add if adjacent to opponent or near edge
        if (adjacentToOpponent || _distanceFromEdge(pos, board.size) <= 2) {
          candidates.add(pos);
        }
      }
    }

    return candidates;
  }

  /// Build information about a single connected group
  _GroupInfo _buildGroupInfo(Board board, Position startPos, StoneColor groupColor, StoneColor opponentColor) {
    final stones = <Position>{};
    final boundaryEmpties = <Position>{};
    final toVisit = <Position>[startPos];
    int opponentPerimeterCount = 0;
    int totalPerimeterCount = 0;

    // Find all stones in this group
    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (stones.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (board.getStoneAt(current) != groupColor) continue;

      stones.add(current);

      for (final adj in current.adjacentPositions) {
        if (!board.isValidPosition(adj)) continue;
        final adjStone = board.getStoneAt(adj);
        if (adjStone == groupColor && !stones.contains(adj)) {
          toVisit.add(adj);
        } else if (adjStone == null) {
          boundaryEmpties.add(adj);
        } else if (adjStone == opponentColor) {
          opponentPerimeterCount++;
        }
        if (adjStone != null) {
          totalPerimeterCount++;
        }
      }
    }

    // Calculate edge exit count for this group
    final edgeExitCount = _countEdgeExitsForGroup(board, stones);

    final opponentPerimeterRatio = totalPerimeterCount > 0
        ? opponentPerimeterCount / totalPerimeterCount
        : 0.0;

    return _GroupInfo(
      stones: stones,
      boundaryEmpties: boundaryEmpties,
      edgeExitCount: edgeExitCount,
      opponentPerimeterRatio: opponentPerimeterRatio,
    );
  }

  /// Count edge exits reachable from a group through empty spaces
  int _countEdgeExitsForGroup(Board board, Set<Position> groupStones) {
    final visited = <Position>{};
    final edgeExits = <Position>{};
    final toVisit = <Position>[];

    // Start from all boundary empties of the group
    for (final stone in groupStones) {
      for (final adj in stone.adjacentPositions) {
        if (board.isValidPosition(adj) && board.isEmpty(adj)) {
          toVisit.add(adj);
        }
      }
    }

    while (toVisit.isNotEmpty) {
      final current = toVisit.removeLast();
      if (visited.contains(current)) continue;
      if (!board.isValidPosition(current)) continue;
      if (!board.isEmpty(current)) continue;

      visited.add(current);

      if (_isOnEdge(current, board.size)) {
        edgeExits.add(current);
      }

      for (final adj in current.adjacentPositions) {
        if (!visited.contains(adj) && board.isValidPosition(adj) && board.isEmpty(adj)) {
          toVisit.add(adj);
        }
      }
    }

    return edgeExits.length;
  }
}

class _ScoredMove {
  final Position position;
  final double score;

  _ScoredMove(this.position, this.score);
}

/// Scored move with reasoning for logging
class _ScoredMoveWithReason {
  final Position position;
  final double score;
  final List<String> reasons;

  _ScoredMoveWithReason(this.position, this.score, this.reasons);
}

/// Score breakdown for detailed logging
class _ScoreBreakdown {
  final double totalScore;
  final List<String> reasons;

  _ScoreBreakdown(this.totalScore, this.reasons);
}

/// Result of escape path check
class _EscapeResult {
  final bool canEscape;
  final Set<Position> emptyRegion;
  final int edgeExitCount; // Number of unique edge positions reachable
  final int wideCorridorCount; // Number of 2-wide corridors to edge (much harder to close)

  _EscapeResult({
    required this.canEscape,
    required this.emptyRegion,
    required this.edgeExitCount,
    this.wideCorridorCount = 0,
  });

  /// Effective exits: narrow exits + (wide corridors * 2)
  /// Wide corridors are nearly uncapturable so count double
  int get effectiveExits => edgeExitCount + wideCorridorCount;
}

/// Information about a stone group for caching
class _GroupInfo {
  final Set<Position> stones;
  final Set<Position> boundaryEmpties;
  final int edgeExitCount;
  final int wideCorridorCount; // 2-wide corridors (much harder to close)
  final double opponentPerimeterRatio;
  final int connectionPoints; // Number of distinct connections to other friendly groups

  _GroupInfo({
    required this.stones,
    required this.boundaryEmpties,
    required this.edgeExitCount,
    required this.opponentPerimeterRatio,
    this.wideCorridorCount = 0,
    this.connectionPoints = 0,
  });

  /// Effective exits: narrow exits + (wide corridors * 2)
  int get effectiveExits => edgeExitCount + wideCorridorCount;
}

/// Per-turn cache to avoid redundant flood-fills
class _TurnCache {
  final List<_GroupInfo> aiGroups;
  final List<_GroupInfo> opponentGroups;
  final Set<Position> forbiddenPositions; // Inside opponent forts

  _TurnCache({
    required this.aiGroups,
    required this.opponentGroups,
    required this.forbiddenPositions,
  });
}

/// Result of tracing an encirclement boundary
/// Used to find "gap" positions that could break the encirclement
class _EncirclementBoundary {
  final Set<Position> opponentWallPositions; // Opponent stones forming the wall
  final Set<Position> edgeAdjacentEmpties; // Empty edge positions near the wall
  final Set<Position> outerEmpties; // Empty positions on the "outer" side of the wall

  _EncirclementBoundary({
    required this.opponentWallPositions,
    required this.edgeAdjacentEmpties,
    required this.outerEmpties,
  });
}

/// POI (Points of Interest) Cache for tracking distant opponent activity
/// Persists across turns to detect opponent build-up in sectors we're not focused on
class _POICache {
  /// Sector weights - higher weight means more opponent activity in that sector
  final Map<int, double> sectorWeights = {};

  /// Track when each sector was last active
  final Map<int, int> sectorLastActivity = {};

  /// Previous opponent moves (to detect new distant moves)
  final List<Position> previousOpponentMoves = [];

  /// Previous own moves (to track where we're focused)
  final List<Position> previousOwnMoves = [];

  /// Move count for tracking
  int moveCount = 0;

  /// Clear the cache (call when starting new game)
  void reset() {
    sectorWeights.clear();
    sectorLastActivity.clear();
    previousOpponentMoves.clear();
    previousOwnMoves.clear();
    moveCount = 0;
  }

  /// Get sector ID for a position
  static int getSectorId(Position pos, int boardSize, {int sectorSize = 5}) {
    final sectorsPerRow = (boardSize + sectorSize - 1) ~/ sectorSize;
    final sectorX = pos.x ~/ sectorSize;
    final sectorY = pos.y ~/ sectorSize;
    return sectorY * sectorsPerRow + sectorX;
  }

  /// Get positions in a sector
  static List<Position> getPositionsInSector(int sectorId, int boardSize, {int sectorSize = 5}) {
    final sectorsPerRow = (boardSize + sectorSize - 1) ~/ sectorSize;
    final sectorX = sectorId % sectorsPerRow;
    final sectorY = sectorId ~/ sectorsPerRow;

    final positions = <Position>[];
    for (int dx = 0; dx < sectorSize; dx++) {
      for (int dy = 0; dy < sectorSize; dy++) {
        final x = sectorX * sectorSize + dx;
        final y = sectorY * sectorSize + dy;
        if (x < boardSize && y < boardSize) {
          positions.add(Position(x, y));
        }
      }
    }
    return positions;
  }

  /// Get hot sectors (sectors with significant opponent activity)
  List<MapEntry<int, double>> getHotSectors({double threshold = 1.0}) {
    return sectorWeights.entries
        .where((e) => e.value >= threshold)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }
}
