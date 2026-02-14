import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/game_state.dart';
import '../models/digimon.dart';

class GameService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const String _table = 'games';
  static final Uuid _uuid = Uuid();

  // ─── helpers ──────────────────────────────────────────────────────────────

  /// Convert a GameState to a row map for Supabase insert/upsert.
  static Map<String, dynamic> _toRow(GameState gs) {
    return {
      'game_code': gs.gameCode,
      'host_id': gs.hostId,
      'selected_levels': gs.selectedLevels,
      'available_digimon': jsonEncode(
        gs.availableDigimon.map((p) => p.toJson()).toList(),
      ),
      'players': jsonEncode(gs.players.map((k, v) => MapEntry(k, v.toJson()))),
      'messages': jsonEncode(gs.messages.map((m) => m.toJson()).toList()),
      'current_phase': gs.currentPhase.name,
      'current_player_id': gs.currentPlayerId,
      'winner': gs.winner,
      'last_activity': gs.lastActivity?.millisecondsSinceEpoch,
      'created_at': gs.createdAt.millisecondsSinceEpoch,
      'time_left': gs.timeLeft,
      'current_round': gs.currentRound,
      'max_rounds': gs.maxRounds,
      'last_guess_result': gs.lastGuessResult?.name,
      'current_guess': gs.currentGuess,
      'players_ready_to_play_again': jsonEncode(gs.playersReadyToPlayAgain),
      'players_typing': jsonEncode(gs.playersTyping),
    };
  }

  /// Convert a Supabase row to a GameState-compatible JSON map.
  static Map<String, dynamic> _rowToJson(Map<String, dynamic> row) {
    return {
      'gameCode': row['game_code'],
      'hostId': row['host_id'],
      'selectedLevels': (row['selected_levels'] as List?)?.cast<int>() ?? [],
      'availableDigimon': _decodeJsonField(row['available_digimon'], []),
      'players': _decodeJsonField(row['players'], {}),
      'messages': _decodeJsonField(row['messages'], []),
      'currentPhase': row['current_phase'],
      'currentPlayerId': row['current_player_id'],
      'winner': row['winner'],
      'lastActivity': row['last_activity'],
      'createdAt': row['created_at'],
      'timeLeft': row['time_left'],
      'currentRound': row['current_round'],
      'maxRounds': row['max_rounds'],
      'lastGuessResult': row['last_guess_result'],
      'currentGuess': row['current_guess'],
      'playersReadyToPlayAgain': _decodeJsonField(
        row['players_ready_to_play_again'],
        {},
      ),
      'playersTyping': _decodeJsonField(row['players_typing'], {}),
    };
  }

  /// Safely decode a JSON field that may be a String or already decoded.
  static dynamic _decodeJsonField(dynamic value, dynamic fallback) {
    if (value == null) return fallback;
    if (value is String) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return fallback;
      }
    }
    return value; // already decoded (Map or List)
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  /// Update eliminated Digimon IDs for a player.
  static Future<void> updateEliminatedDigimonIds(
    String gameCode,
    String playerId,
    List<int> eliminatedIds,
  ) async {
    final row = await _db
        .from(_table)
        .select('players')
        .eq('game_code', gameCode)
        .single();
    final players = Map<String, dynamic>.from(
      _decodeJsonField(row['players'], {}),
    );
    if (players.containsKey(playerId)) {
      final player = Map<String, dynamic>.from(players[playerId]);
      player['eliminatedDigimonIds'] = eliminatedIds;
      players[playerId] = player;
    }
    await _db
        .from(_table)
        .update({'players': jsonEncode(players)})
        .eq('game_code', gameCode);
  }

  /// Set typing status for a player.
  static Future<void> setTypingStatus(
    String gameCode,
    String playerId,
    bool isTyping,
  ) async {
    final row = await _db
        .from(_table)
        .select('players_typing')
        .eq('game_code', gameCode)
        .single();
    final typing = Map<String, dynamic>.from(
      _decodeJsonField(row['players_typing'], {}),
    );
    typing[playerId] = isTyping;
    await _db
        .from(_table)
        .update({'players_typing': jsonEncode(typing)})
        .eq('game_code', gameCode);
  }

  /// Clear typing status for a player (set to false).
  static Future<void> clearTypingStatus(
    String gameCode,
    String playerId,
  ) async {
    await setTypingStatus(gameCode, playerId, false);
  }

  /// Clean up games older than 1 hour.
  static Future<void> cleanupOldGames() async {
    try {
      final oneHourAgoMs = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await _db.from(_table).delete().lt('created_at', oneHourAgoMs);
    } catch (e) {
      // Silently ignore cleanup errors
    }
  }

  /// Generate a 6-character game code.
  static String generateGameCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  /// Create a new game.
  static Future<GameState> createGame(
    String hostId,
    String hostName,
    List<int> levels,
  ) async {
    await cleanupOldGames();

    final gameCode = generateGameCode();

    final hostPlayer = Player(
      id: hostId,
      name: hostName,
      role: PlayerRole.host,
    );

    final gameState = GameState(
      gameCode: gameCode,
      hostId: hostId,
      selectedLevels: levels,
      currentPhase: GamePhase.waitingForPlayers,
    );

    gameState.addPlayer(hostPlayer);

    await _db.from(_table).insert(_toRow(gameState));

    return gameState;
  }

  /// Join an existing game.
  static Future<GameState?> joinGame(
    String gameCode,
    String playerId,
    String playerName,
  ) async {
    final rows = await _db
        .from(_table)
        .select()
        .eq('game_code', gameCode)
        .limit(1);

    if (rows.isEmpty) {
      throw Exception('Game not found');
    }

    final gameData = _rowToJson(rows.first);
    final gameState = GameState.fromJson(gameData);

    // Check if game is too old (over 1 hour)
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    if (gameState.createdAt.isBefore(oneHourAgo)) {
      await _db.from(_table).delete().eq('game_code', gameCode);
      throw Exception('Game has expired');
    }

    if (gameState.players.length >= 2) {
      throw Exception('Game is full');
    }

    final guestPlayer = Player(
      id: playerId,
      name: playerName,
      role: PlayerRole.guest,
    );

    gameState.addPlayer(guestPlayer);

    if (gameState.isGameReady) {
      gameState.currentPhase = GamePhase.digimonSelection;
    }

    await _db.from(_table).update(_toRow(gameState)).eq('game_code', gameCode);

    return gameState;
  }

  /// Listen to game changes via Supabase Realtime.
  static Stream<GameState?> listenToGame(String gameCode) {
    final controller = StreamController<GameState?>.broadcast();

    // Fetch initial state
    _db.from(_table).select().eq('game_code', gameCode).limit(1).then((rows) {
      if (rows.isEmpty) {
        controller.add(null);
      } else {
        controller.add(GameState.fromJson(_rowToJson(rows.first)));
      }
    });

    // Subscribe to realtime changes
    final channel = _db.channel('game-$gameCode');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_code',
            value: gameCode,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              controller.add(null);
              return;
            }
            final row = payload.newRecord;
            if (row.isEmpty) {
              controller.add(null);
            } else {
              controller.add(GameState.fromJson(_rowToJson(row)));
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      _db.removeChannel(channel);
    };

    return controller.stream;
  }

  /// Listen to game changes with per-player delay (typing indicator UX).
  static Stream<GameState?> listenToGameWithPlayer(
    String gameCode,
    String? playerId,
  ) {
    final controller = StreamController<GameState?>.broadcast();
    String? lastSeenMessageId;
    bool isFirstUpdate = true;

    final innerSub = listenToGame(gameCode).listen((gameState) async {
      if (gameState == null) {
        controller.add(null);
        return;
      }

      final messages = gameState.questionsAndAnswers;
      final latest = messages.isNotEmpty ? messages.last : null;

      bool shouldDelay = false;
      if (!isFirstUpdate && playerId != null && latest != null) {
        if (latest.senderId != playerId && latest.id != lastSeenMessageId) {
          shouldDelay = true;
        }
      }
      isFirstUpdate = false;

      if (shouldDelay) {
        await Future.delayed(const Duration(seconds: 2));
      }
      if (latest != null) {
        lastSeenMessageId = latest.id;
      }
      controller.add(gameState);
    });

    controller.onCancel = () {
      innerSub.cancel();
    };

    return controller.stream;
  }

  /// Overwrite entire game state.
  static Future<void> updateGame(GameState gameState) async {
    await _db
        .from(_table)
        .update(_toRow(gameState))
        .eq('game_code', gameState.gameCode);
  }

  /// Partially update game fields without overwriting the whole document.
  static Future<void> updateGameState(
    String gameCode,
    Map<String, dynamic> updates,
  ) async {
    // Read current state, apply updates, write back
    final rows = await _db
        .from(_table)
        .select()
        .eq('game_code', gameCode)
        .limit(1);

    if (rows.isEmpty) return;

    final gameJson = _rowToJson(rows.first);

    // Apply each update key to the gameJson (supports nested 'players/$id/...' paths)
    for (final entry in updates.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key.startsWith('players/')) {
        // Handle nested player updates like 'players/$playerId/eliminatedDigimonIds'
        final parts = key.split('/');
        if (parts.length == 3) {
          final playerId = parts[1];
          final field = parts[2];
          final players = Map<String, dynamic>.from(gameJson['players'] ?? {});
          if (players.containsKey(playerId)) {
            final player = Map<String, dynamic>.from(players[playerId]);
            player[field] = value;
            players[playerId] = player;
          }
          gameJson['players'] = players;
        }
      } else {
        gameJson[key] = value;
      }
    }

    gameJson['lastActivity'] = DateTime.now().millisecondsSinceEpoch;

    // Rebuild GameState and write
    final gs = GameState.fromJson(gameJson);
    await _db.from(_table).update(_toRow(gs)).eq('game_code', gameCode);
  }

  /// Set available Digimon for the game.
  static Future<void> setDigimon(String gameCode, List<Digimon> digimon) async {
    await _db
        .from(_table)
        .update({
          'available_digimon': jsonEncode(
            digimon.map((p) => p.toJson()).toList(),
          ),
        })
        .eq('game_code', gameCode);
  }

  /// Choose Digimon for a player.
  static Future<void> chooseDigimon(
    String gameCode,
    String playerId,
    Digimon digimon,
  ) async {
    final row = await _db
        .from(_table)
        .select('players')
        .eq('game_code', gameCode)
        .single();
    final players = Map<String, dynamic>.from(
      _decodeJsonField(row['players'], {}),
    );
    if (players.containsKey(playerId)) {
      final player = Map<String, dynamic>.from(players[playerId]);
      player['chosenDigimon'] = digimon.toJson();
      players[playerId] = player;
    }
    // Update chosen Digimon
    await _db
        .from(_table)
        .update({'players': jsonEncode(players)})
        .eq('game_code', gameCode);

    // After updating, check if all players have chosen a Digimon.
    final allChosen = players.values.every((p) {
      final player = Map<String, dynamic>.from(p as Map);
      return player['chosenDigimon'] != null;
    });

    if (allChosen) {
      // Use the first player's ID as the starting player
      final firstPlayerId = players.keys.first;
      await startGame(gameCode, firstPlayerId);
    }
  }

  /// Send a message/question.
  static Future<void> sendMessage(String gameCode, GameMessage message) async {
    final row = await _db
        .from(_table)
        .select('messages')
        .eq('game_code', gameCode)
        .single();
    final messages = List<dynamic>.from(_decodeJsonField(row['messages'], []));
    messages.add(message.toJson());
    await _db
        .from(_table)
        .update({'messages': jsonEncode(messages)})
        .eq('game_code', gameCode);
  }

  /// Update player's eliminated Digimon.
  static Future<void> updateEliminatedDigimon(
    String gameCode,
    String playerId,
    List<int> eliminatedIds,
  ) async {
    await updateEliminatedDigimonIds(gameCode, playerId, eliminatedIds);
  }

  /// Switch turn.
  static Future<void> switchTurn(
    String gameCode,
    String newCurrentPlayerId,
  ) async {
    final row = await _db
        .from(_table)
        .select('players')
        .eq('game_code', gameCode)
        .single();
    final players = Map<String, dynamic>.from(
      _decodeJsonField(row['players'], {}),
    );
    for (final playerId in players.keys) {
      final player = Map<String, dynamic>.from(players[playerId]);
      player['isCurrentTurn'] = playerId == newCurrentPlayerId;
      players[playerId] = player;
    }
    await _db
        .from(_table)
        .update({
          'current_player_id': newCurrentPlayerId,
          'last_activity': DateTime.now().millisecondsSinceEpoch,
          'players': jsonEncode(players),
        })
        .eq('game_code', gameCode);
  }

  /// Start the game.
  static Future<void> startGame(String gameCode, String firstPlayerId) async {
    // Guard: ensure all players have actually chosen a Digimon before
    // transitioning to inGame. This prevents any early or duplicate
    // calls from starting the game prematurely.
    final row = await _db
        .from(_table)
        .select('players')
        .eq('game_code', gameCode)
        .single();
    final players = Map<String, dynamic>.from(
      _decodeJsonField(row['players'], {}),
    );

    final allChosen = players.values.every((p) {
      final player = Map<String, dynamic>.from(p as Map);
      return player['chosenDigimon'] != null;
    });

    if (!allChosen) {
      return;
    }

    await _db
        .from(_table)
        .update({
          'current_phase': GamePhase.inGame.name,
          'current_player_id': firstPlayerId,
          'last_activity': DateTime.now().millisecondsSinceEpoch,
        })
        .eq('game_code', gameCode);

    await switchTurn(gameCode, firstPlayerId);
  }

  /// Increment a player's score by 1.
  static Future<void> incrementPlayerScore(
    String gameCode,
    String playerId,
  ) async {
    final row = await _db
        .from(_table)
        .select('players')
        .eq('game_code', gameCode)
        .single();
    final players = Map<String, dynamic>.from(
      _decodeJsonField(row['players'], {}),
    );
    if (players.containsKey(playerId)) {
      final player = Map<String, dynamic>.from(players[playerId]);
      player['score'] = ((player['score'] as int?) ?? 0) + 1;
      players[playerId] = player;
    }
    await _db
        .from(_table)
        .update({'players': jsonEncode(players)})
        .eq('game_code', gameCode);
  }

  /// End game.
  static Future<void> endGame(String gameCode, String winnerId) async {
    await _db
        .from(_table)
        .update({
          'current_phase': GamePhase.gameOver.name,
          'winner': winnerId,
          'last_activity': DateTime.now().millisecondsSinceEpoch,
        })
        .eq('game_code', gameCode);
  }

  /// Delete game.
  static Future<void> deleteGame(String gameCode) async {
    await _db.from(_table).delete().eq('game_code', gameCode);
  }

  /// Generate unique message ID.
  static String generateMessageId() {
    return _uuid.v4();
  }

  /// Generate unique player ID.
  static String generatePlayerId() {
    return _uuid.v4();
  }

  /// Check if game exists.
  static Future<bool> gameExists(String gameCode) async {
    final rows = await _db
        .from(_table)
        .select('game_code')
        .eq('game_code', gameCode)
        .limit(1);
    return rows.isNotEmpty;
  }
}
