import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/digimon.dart';

class DigimonService {
  static const String baseUrl = 'https://digi-api.com/api/v1';
  static const int maxDigimonId = 1488;

  static final Random _random = Random();

  /// Digimon levels for filtering.
  static const List<String> allLevels = [
    'Baby I',
    'Baby II',
    'Child',
    'Adult',
    'Perfect',
    'Ultimate',
    'Armor',
    'Hybrid',
  ];

  /// Map from level index (1-based) to level name, used for selection UI.
  static const Map<int, String> levelMap = {
    1: 'Baby I',
    2: 'Baby II',
    3: 'Child',
    4: 'Adult',
    5: 'Perfect',
    6: 'Ultimate',
    7: 'Armor',
    8: 'Hybrid',
  };

  static Future<Digimon> getRandomDigimon() async {
    try {
      final int randomId = _random.nextInt(maxDigimonId) + 1;

      final response = await http.get(
        Uri.parse('$baseUrl/digimon/$randomId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return Digimon.fromApiJson(data);
      } else {
        throw Exception('Failed to load Digimon: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching Digimon: $e');
    }
  }

  static Future<Digimon> getDigimonByName(String name) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/digimon/${Uri.encodeComponent(name)}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return Digimon.fromApiJson(data);
      } else {
        throw Exception('Digimon not found: $name');
      }
    } catch (e) {
      throw Exception('Error fetching Digimon by name: $e');
    }
  }

  static Future<Digimon?> getDigimonById(int id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/digimon/$id'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException('Request timed out'),
          );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return Digimon.fromApiJson(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch a list of Digimon IDs from the list endpoint, optionally filtered by level.
  static Future<List<Map<String, dynamic>>> _fetchDigimonList({
    String? level,
    int pageSize = 200,
    int page = 0,
  }) async {
    final params = <String, String>{'pageSize': '$pageSize', 'page': '$page'};
    if (level != null) {
      params['level'] = level;
    }

    final uri = Uri.parse('$baseUrl/digimon').replace(queryParameters: params);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>? ?? [];
      return content.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Get multiple random Digimon by selected levels.
  /// [selectedLevels] is a list of level indices (1-based) matching [levelMap].
  static Future<List<Digimon>> getDigimonByLevels(
    List<int> selectedLevels,
    int count,
  ) async {
    // Gather all candidate Digimon from the list endpoint by level
    List<Map<String, dynamic>> allCandidates = [];

    for (int levelIdx in selectedLevels) {
      final levelName = levelMap[levelIdx];
      if (levelName == null) continue;

      try {
        // Fetch all Digimon for this level (up to 500)
        final candidates = await _fetchDigimonList(
          level: levelName,
          pageSize: 500,
        );
        allCandidates.addAll(candidates);
      } catch (e) {
        // Skip levels that fail
        continue;
      }
    }

    if (allCandidates.isEmpty) {
      throw Exception('No Digimon found for selected levels');
    }

    // Remove duplicates by ID
    final uniqueById = <int, Map<String, dynamic>>{};
    for (final c in allCandidates) {
      uniqueById[c['id']] = c;
    }
    final uniqueCandidates = uniqueById.values.toList();

    // Shuffle and pick candidates
    uniqueCandidates.shuffle(_random);
    final idsToFetch = uniqueCandidates.take(count + 10).toList();

    // Fetch full detail for each candidate in parallel batches
    const batchSize = 6;
    List<Digimon> digimonList = [];

    for (
      int i = 0;
      i < idsToFetch.length && digimonList.length < count;
      i += batchSize
    ) {
      final batch = idsToFetch.skip(i).take(batchSize).toList();

      final results = await Future.wait(
        batch.map((c) => getDigimonById(c['id'])),
        eagerError: false,
      );

      for (final digimon in results) {
        if (digimon != null && digimonList.length < count) {
          digimonList.add(digimon);
        }
      }

      if (digimonList.length >= count) break;
    }

    if (digimonList.isEmpty) {
      throw Exception('Failed to fetch any Digimon');
    }

    return digimonList;
  }

  /// Get multiple random Digimon (no level filter).
  static Future<List<Digimon>> getMultipleRandomDigimon(int count) async {
    List<Digimon> digimonList = [];
    Set<int> usedIds = {};

    while (digimonList.length < count) {
      int randomId = _random.nextInt(maxDigimonId) + 1;

      if (!usedIds.contains(randomId)) {
        usedIds.add(randomId);
        try {
          final digimon = await getDigimonById(randomId);
          if (digimon != null) {
            digimonList.add(digimon);
          }
        } catch (e) {
          continue;
        }
      }
    }

    return digimonList;
  }

  /// Search for Digimon names (for autocomplete).
  static Future<List<String>> searchDigimonNames(String query) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/digimon?name=${Uri.encodeComponent(query)}&pageSize=10',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>? ?? [];
        return content
            .map((e) => (e as Map<String, dynamic>)['name'] as String)
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
