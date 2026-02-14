class EvolutionMember {
  final String name;
  final String imageUrl;
  final int id;
  final Map<String, String>? localizedNames;

  EvolutionMember({
    required this.name,
    required this.imageUrl,
    required this.id,
    this.localizedNames,
  });

  factory EvolutionMember.fromJson(Map<String, dynamic> json) {
    Map<String, String>? localizedNames;
    if (json['localizedNames'] != null && json['localizedNames'] is Map) {
      localizedNames = Map<String, String>.from(json['localizedNames']);
    }

    return EvolutionMember(
      name: json['name'],
      imageUrl: json['imageUrl'],
      id: json['id'],
      localizedNames: localizedNames,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'imageUrl': imageUrl,
      'id': id,
      if (localizedNames != null) 'localizedNames': localizedNames,
    };
  }
}

class Digimon {
  final int id;
  final String name;
  final String imageUrl;
  final List<String> types; // Digimon types (e.g. "Reptile", "Dragon")
  final List<String> attributes; // e.g. "Vaccine", "Virus", "Data"
  final List<String> levels; // e.g. "Child", "Adult", "Perfect", "Ultimate"
  final List<String> fields; // e.g. "Nature Spirits", "Deep Savers"
  final List<Map<String, String>> skills; // name + description
  final String? description;
  final String? releaseDate;
  final List<EvolutionMember>? priorEvolutions;
  final List<EvolutionMember>? nextEvolutions;
  final Map<String, String>? localizedNames;

  Digimon({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.types = const [],
    this.attributes = const [],
    this.levels = const [],
    this.fields = const [],
    this.skills = const [],
    this.description,
    this.releaseDate,
    this.priorEvolutions,
    this.nextEvolutions,
    this.localizedNames,
  });

  Digimon copyWith({
    int? id,
    String? name,
    String? imageUrl,
    List<String>? types,
    List<String>? attributes,
    List<String>? levels,
    List<String>? fields,
    List<Map<String, String>>? skills,
    String? description,
    String? releaseDate,
    List<EvolutionMember>? priorEvolutions,
    List<EvolutionMember>? nextEvolutions,
    Map<String, String>? localizedNames,
  }) {
    return Digimon(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      types: types ?? this.types,
      attributes: attributes ?? this.attributes,
      levels: levels ?? this.levels,
      fields: fields ?? this.fields,
      skills: skills ?? this.skills,
      description: description ?? this.description,
      releaseDate: releaseDate ?? this.releaseDate,
      priorEvolutions: priorEvolutions ?? this.priorEvolutions,
      nextEvolutions: nextEvolutions ?? this.nextEvolutions,
      localizedNames: localizedNames ?? this.localizedNames,
    );
  }

  /// Parse a single Digimon from the **full detail** endpoint
  /// (`/api/v1/digimon/{id}`).
  factory Digimon.fromApiJson(Map<String, dynamic> json) {
    // Image – take the first entry from the images list
    String imageUrl = '';
    if (json['images'] != null &&
        json['images'] is List &&
        (json['images'] as List).isNotEmpty) {
      imageUrl = json['images'][0]['href'] ?? '';
    }

    // Types
    List<String> types = [];
    if (json['types'] != null && json['types'] is List) {
      for (var t in json['types']) {
        if (t is Map && t.containsKey('type')) {
          types.add(t['type']);
        }
      }
    }

    // Attributes
    List<String> attributes = [];
    if (json['attributes'] != null && json['attributes'] is List) {
      for (var a in json['attributes']) {
        if (a is Map && a.containsKey('attribute')) {
          attributes.add(a['attribute']);
        }
      }
    }

    // Levels
    List<String> levels = [];
    if (json['levels'] != null && json['levels'] is List) {
      for (var l in json['levels']) {
        if (l is Map && l.containsKey('level')) {
          levels.add(l['level']);
        }
      }
    }

    // Fields
    List<String> fields = [];
    if (json['fields'] != null && json['fields'] is List) {
      for (var f in json['fields']) {
        if (f is Map && f.containsKey('field')) {
          fields.add(f['field']);
        }
      }
    }

    // Skills
    List<Map<String, String>> skills = [];
    if (json['skills'] != null && json['skills'] is List) {
      for (var s in json['skills']) {
        if (s is Map) {
          skills.add({
            'name': s['skill']?.toString() ?? '',
            'description': s['description']?.toString() ?? '',
          });
        }
      }
    }

    // Description – prefer English
    String? description;
    if (json['descriptions'] != null && json['descriptions'] is List) {
      for (var d in json['descriptions']) {
        if (d is Map && d['language'] == 'en_us') {
          description = d['description'];
          break;
        }
      }
      // Fallback to first available description
      if (description == null && (json['descriptions'] as List).isNotEmpty) {
        description = (json['descriptions'] as List).first['description'];
      }
    }

    // Prior evolutions
    List<EvolutionMember>? priorEvolutions;
    if (json['priorEvolutions'] != null && json['priorEvolutions'] is List) {
      priorEvolutions = (json['priorEvolutions'] as List).map((e) {
        return EvolutionMember(
          id: e['id'] ?? 0,
          name: e['digimon'] ?? '',
          imageUrl: e['image'] ?? '',
        );
      }).toList();
    }

    // Next evolutions
    List<EvolutionMember>? nextEvolutions;
    if (json['nextEvolutions'] != null && json['nextEvolutions'] is List) {
      nextEvolutions = (json['nextEvolutions'] as List).map((e) {
        return EvolutionMember(
          id: e['id'] ?? 0,
          name: e['digimon'] ?? '',
          imageUrl: e['image'] ?? '',
        );
      }).toList();
    }

    return Digimon(
      id: json['id'],
      name: json['name'],
      imageUrl: imageUrl,
      types: types,
      attributes: attributes,
      levels: levels,
      fields: fields,
      skills: skills,
      description: description,
      releaseDate: json['releaseDate']?.toString(),
      priorEvolutions: priorEvolutions,
      nextEvolutions: nextEvolutions,
    );
  }

  /// Parse a Digimon from the **list** endpoint
  /// (`/api/v1/digimon?pageSize=…`).
  factory Digimon.fromListJson(Map<String, dynamic> json) {
    return Digimon(
      id: json['id'],
      name: json['name'],
      imageUrl: json['image'] ?? '',
    );
  }

  /// Parse from stored/serialised JSON (our own `toJson()` format).
  factory Digimon.fromJson(Map<String, dynamic> json) {
    // Types
    List<String> types = [];
    if (json['types'] != null && json['types'] is List) {
      types = List<String>.from(json['types']);
    }

    // Attributes
    List<String> attributes = [];
    if (json['attributes'] != null && json['attributes'] is List) {
      attributes = List<String>.from(json['attributes']);
    }

    // Levels
    List<String> levels = [];
    if (json['levels'] != null && json['levels'] is List) {
      levels = List<String>.from(json['levels']);
    }

    // Fields
    List<String> fields = [];
    if (json['fields'] != null && json['fields'] is List) {
      fields = List<String>.from(json['fields']);
    }

    // Skills
    List<Map<String, String>> skills = [];
    if (json['skills'] != null && json['skills'] is List) {
      for (var s in json['skills']) {
        if (s is Map) {
          skills.add(
            Map<String, String>.from(
              s.map((k, v) => MapEntry(k.toString(), v.toString())),
            ),
          );
        }
      }
    }

    // Prior evolutions
    List<EvolutionMember>? priorEvolutions;
    if (json['priorEvolutions'] != null && json['priorEvolutions'] is List) {
      priorEvolutions = (json['priorEvolutions'] as List).map((e) {
        final data = Map<String, dynamic>.from(
          (e as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
        return EvolutionMember.fromJson(data);
      }).toList();
    }

    // Next evolutions
    List<EvolutionMember>? nextEvolutions;
    if (json['nextEvolutions'] != null && json['nextEvolutions'] is List) {
      nextEvolutions = (json['nextEvolutions'] as List).map((e) {
        final data = Map<String, dynamic>.from(
          (e as Map).map((k, v) => MapEntry(k.toString(), v)),
        );
        return EvolutionMember.fromJson(data);
      }).toList();
    }

    // Localized names
    Map<String, String>? localizedNames;
    if (json['localizedNames'] != null && json['localizedNames'] is Map) {
      localizedNames = Map<String, String>.from(json['localizedNames']);
    }

    return Digimon(
      id: json['id'],
      name: json['name'],
      imageUrl: json['imageUrl'] ?? '',
      types: types,
      attributes: attributes,
      levels: levels,
      fields: fields,
      skills: skills,
      description: json['description'],
      releaseDate: json['releaseDate'],
      priorEvolutions: priorEvolutions,
      nextEvolutions: nextEvolutions,
      localizedNames: localizedNames,
    );
  }

  String get capitalizedName {
    if (name.isEmpty) return name;
    return name[0].toUpperCase() + name.substring(1);
  }

  String getLocalizedName(String languageCode) {
    if (localizedNames != null && localizedNames!.containsKey(languageCode)) {
      return localizedNames![languageCode]!;
    }
    if (localizedNames != null && localizedNames!.containsKey('en')) {
      return localizedNames!['en']!;
    }
    return capitalizedName;
  }

  String get typesString {
    return types
        .map((type) => type[0].toUpperCase() + type.substring(1))
        .join(', ');
  }

  String get attributesString {
    return attributes.join(', ');
  }

  String get levelsString {
    return levels.join(', ');
  }

  String get fieldsString {
    return fields.join(', ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'types': types,
      'attributes': attributes,
      'levels': levels,
      'fields': fields,
      'skills': skills,
      'description': description,
      'releaseDate': releaseDate,
      if (priorEvolutions != null)
        'priorEvolutions': priorEvolutions!.map((e) => e.toJson()).toList(),
      if (nextEvolutions != null)
        'nextEvolutions': nextEvolutions!.map((e) => e.toJson()).toList(),
      if (localizedNames != null) 'localizedNames': localizedNames,
    };
  }
}
