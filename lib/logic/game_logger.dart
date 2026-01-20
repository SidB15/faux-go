import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Represents a single move in the game log
class MoveLogEntry {
  final int moveNumber;
  final StoneColor player;
  final Position position;
  final int capturedCount;
  final int blackTotalCaptures;
  final int whiteTotalCaptures;
  final int enclosuresCreated;
  final DateTime timestamp;
  final bool isAiMove;

  /// Board state snapshot (sparse - only stone positions)
  final Map<String, String> boardSnapshot;

  MoveLogEntry({
    required this.moveNumber,
    required this.player,
    required this.position,
    required this.capturedCount,
    required this.blackTotalCaptures,
    required this.whiteTotalCaptures,
    required this.enclosuresCreated,
    required this.timestamp,
    required this.isAiMove,
    required this.boardSnapshot,
  });

  Map<String, dynamic> toJson() => {
    'moveNumber': moveNumber,
    'player': player.name,
    'position': {'x': position.x, 'y': position.y},
    'capturedCount': capturedCount,
    'blackTotalCaptures': blackTotalCaptures,
    'whiteTotalCaptures': whiteTotalCaptures,
    'enclosuresCreated': enclosuresCreated,
    'timestamp': timestamp.toIso8601String(),
    'isAiMove': isAiMove,
    'boardSnapshot': boardSnapshot,
  };

  factory MoveLogEntry.fromJson(Map<String, dynamic> json) {
    return MoveLogEntry(
      moveNumber: json['moveNumber'],
      player: StoneColor.values.byName(json['player']),
      position: Position(json['position']['x'], json['position']['y']),
      capturedCount: json['capturedCount'],
      blackTotalCaptures: json['blackTotalCaptures'],
      whiteTotalCaptures: json['whiteTotalCaptures'],
      enclosuresCreated: json['enclosuresCreated'],
      timestamp: DateTime.parse(json['timestamp']),
      isAiMove: json['isAiMove'],
      boardSnapshot: Map<String, String>.from(json['boardSnapshot']),
    );
  }
}

/// Complete game log
class GameLog {
  final String gameId;
  final DateTime startTime;
  DateTime? endTime;
  final GameSettings settings;
  final List<MoveLogEntry> moves;
  StoneColor? winner;
  String? endReason;

  GameLog({
    required this.gameId,
    required this.startTime,
    required this.settings,
    List<MoveLogEntry>? moves,
    this.endTime,
    this.winner,
    this.endReason,
  }) : moves = moves ?? [];

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'settings': {
      'mode': settings.mode.name,
      'targetValue': settings.targetValue,
      'opponentType': settings.opponentType.name,
      'aiLevel': settings.aiLevel.level,
    },
    'moves': moves.map((m) => m.toJson()).toList(),
    'winner': winner?.name,
    'endReason': endReason,
    'summary': _generateSummary(),
  };

  Map<String, dynamic> _generateSummary() {
    final humanMoves = moves.where((m) => !m.isAiMove).toList();
    final aiMoves = moves.where((m) => m.isAiMove).toList();

    int humanCaptures = 0;
    int aiCaptures = 0;

    for (final move in moves) {
      if (move.isAiMove) {
        aiCaptures += move.capturedCount;
      } else {
        humanCaptures += move.capturedCount;
      }
    }

    return {
      'totalMoves': moves.length,
      'humanMoves': humanMoves.length,
      'aiMoves': aiMoves.length,
      'humanCaptures': humanCaptures,
      'aiCaptures': aiCaptures,
      'humanEnclosures': moves.where((m) => !m.isAiMove && m.enclosuresCreated > 0).length,
      'aiEnclosures': moves.where((m) => m.isAiMove && m.enclosuresCreated > 0).length,
      'gameDurationSeconds': endTime != null
          ? endTime!.difference(startTime).inSeconds
          : DateTime.now().difference(startTime).inSeconds,
    };
  }

  factory GameLog.fromJson(Map<String, dynamic> json) {
    final settingsJson = json['settings'];
    return GameLog(
      gameId: json['gameId'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      settings: GameSettings(
        mode: GameMode.values.byName(settingsJson['mode']),
        targetValue: settingsJson['targetValue'],
        opponentType: OpponentType.values.byName(settingsJson['opponentType']),
        aiLevel: settingsJson['aiLevel'] != null
            ? AiLevel.values.firstWhere((l) => l.level == settingsJson['aiLevel'])
            : AiLevel.level5,
      ),
      moves: (json['moves'] as List).map((m) => MoveLogEntry.fromJson(m)).toList(),
      winner: json['winner'] != null ? StoneColor.values.byName(json['winner']) : null,
      endReason: json['endReason'],
    );
  }
}

/// Service for logging games
class GameLogger {
  GameLog? _currentLog;

  static final GameLogger _instance = GameLogger._internal();
  factory GameLogger() => _instance;
  GameLogger._internal();

  /// Start logging a new game
  void startGame(GameSettings settings) {
    final gameId = '${DateTime.now().millisecondsSinceEpoch}';
    _currentLog = GameLog(
      gameId: gameId,
      startTime: DateTime.now(),
      settings: settings,
    );
    debugPrint('[GameLogger] Started logging game $gameId');
  }

  /// Log a move
  void logMove({
    required int moveNumber,
    required StoneColor player,
    required Position position,
    required int capturedCount,
    required int blackTotalCaptures,
    required int whiteTotalCaptures,
    required int enclosuresCreated,
    required bool isAiMove,
    required Board board,
  }) {
    if (_currentLog == null) return;

    // Create sparse board snapshot
    final boardSnapshot = <String, String>{};
    for (final entry in board.stones.entries) {
      boardSnapshot['${entry.key.x},${entry.key.y}'] = entry.value.name;
    }

    final entry = MoveLogEntry(
      moveNumber: moveNumber,
      player: player,
      position: position,
      capturedCount: capturedCount,
      blackTotalCaptures: blackTotalCaptures,
      whiteTotalCaptures: whiteTotalCaptures,
      enclosuresCreated: enclosuresCreated,
      timestamp: DateTime.now(),
      isAiMove: isAiMove,
      boardSnapshot: boardSnapshot,
    );

    _currentLog!.moves.add(entry);

    debugPrint('[GameLogger] Move $moveNumber: ${player.name} at (${position.x}, ${position.y}) '
        '${isAiMove ? "[AI]" : "[Human]"} captured: $capturedCount');
  }

  /// Log a pass
  void logPass({
    required int moveNumber,
    required StoneColor player,
    required bool isAiMove,
  }) {
    if (_currentLog == null) return;
    debugPrint('[GameLogger] Move $moveNumber: ${player.name} passed ${isAiMove ? "[AI]" : "[Human]"}');
  }

  /// End the game and save the log
  Future<String?> endGame({
    StoneColor? winner,
    required String endReason,
  }) async {
    if (_currentLog == null) return null;

    _currentLog!.endTime = DateTime.now();
    _currentLog!.winner = winner;
    _currentLog!.endReason = endReason;

    final filePath = await _saveLog();

    debugPrint('[GameLogger] Game ended. Winner: ${winner?.name ?? "none"}. Reason: $endReason');
    debugPrint('[GameLogger] Log saved to: $filePath');

    _currentLog = null;
    return filePath;
  }

  /// Save the log to a file
  Future<String?> _saveLog() async {
    if (_currentLog == null) return null;

    try {
      final directory = await _getLogDirectory();
      final fileName = 'game_${_currentLog!.gameId}.json';
      final file = File('${directory.path}/$fileName');

      final jsonString = const JsonEncoder.withIndent('  ').convert(_currentLog!.toJson());
      await file.writeAsString(jsonString);

      return file.path;
    } catch (e) {
      debugPrint('[GameLogger] Error saving log: $e');
      return null;
    }
  }

  /// Get the directory for storing logs
  Future<Directory> _getLogDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${appDir.path}/simply_go_logs');

    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    return logDir;
  }

  /// Get all saved game logs
  static Future<List<GameLog>> loadAllLogs() async {
    final logs = <GameLog>[];

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDir.path}/simply_go_logs');

      if (!await logDir.exists()) {
        return logs;
      }

      await for (final file in logDir.list()) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final content = await file.readAsString();
            final json = jsonDecode(content);
            logs.add(GameLog.fromJson(json));
          } catch (e) {
            debugPrint('[GameLogger] Error loading log ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[GameLogger] Error loading logs: $e');
    }

    // Sort by start time, newest first
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    return logs;
  }

  /// Export all logs (including current in-progress game) to a single analysis file
  static Future<String?> exportAllLogsForAnalysis() async {
    try {
      final logs = await loadAllLogs();

      // Also include current in-progress game if exists
      final currentLog = _instance._currentLog;
      final allLogs = [...logs];
      if (currentLog != null && currentLog.moves.isNotEmpty) {
        // Don't duplicate if somehow already in saved logs
        if (!logs.any((l) => l.gameId == currentLog.gameId)) {
          allLogs.insert(0, currentLog); // Add current game at start
        }
      }

      if (allLogs.isEmpty) return null;

      final appDir = await getApplicationDocumentsDirectory();

      // Ensure directory exists
      final logDir = Directory('${appDir.path}/simply_go_logs');
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      final exportFile = File('${appDir.path}/simply_go_logs/analysis_export_${DateTime.now().millisecondsSinceEpoch}.json');

      final exportData = {
        'exportTime': DateTime.now().toIso8601String(),
        'totalGames': allLogs.length,
        'includesCurrentGame': currentLog != null && currentLog.moves.isNotEmpty,
        'games': allLogs.map((l) => l.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      await exportFile.writeAsString(jsonString);

      debugPrint('[GameLogger] Exported ${allLogs.length} games to ${exportFile.path}');
      return exportFile.path;
    } catch (e) {
      debugPrint('[GameLogger] Error exporting logs: $e');
      return null;
    }
  }

  /// Check if there's a current game in progress with moves
  static bool get hasCurrentGame => _instance._currentLog != null && _instance._currentLog!.moves.isNotEmpty;

  /// Get move count of current game (for UI feedback)
  static int get currentGameMoveCount => _instance._currentLog?.moves.length ?? 0;

  /// Get the log directory path for user reference
  static Future<String> getLogDirectoryPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/simply_go_logs';
  }
}
