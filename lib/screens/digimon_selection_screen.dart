import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../providers/game_provider.dart';
import '../models/game_state.dart';
import '../models/digimon.dart';
import '../services/digimon_service.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/settings_modal.dart';

class DigimonSelectionScreen extends StatefulWidget {
  final GameState gameState;

  const DigimonSelectionScreen({super.key, required this.gameState});

  @override
  State<DigimonSelectionScreen> createState() => _DigimonSelectionScreenState();
}

class _DigimonSelectionScreenState extends State<DigimonSelectionScreen> {
  int? _locallySelectedDigimonId;
  bool _snackbarCallbackPending = false;
  bool _isSnackbarShowing = false;

  void _updateOpponentReadySnackbar(
    BuildContext context,
    bool hasOpponentChosen,
    bool hasCurrentChosen,
  ) {
    // Prevent stacking multiple post-frame callbacks on rapid rebuilds
    if (_snackbarCallbackPending) return;
    _snackbarCallbackPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snackbarCallbackPending = false;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (hasOpponentChosen && !hasCurrentChosen) {
        // Only show if not already showing – avoids clear+show cascade
        if (!_isSnackbarShowing) {
          if (ModalRoute.of(context)?.isCurrent ?? true) {
            _isSnackbarShowing = true;
            messenger.clearSnackBars();
            messenger.showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.opponentReady),
                duration: const Duration(days: 365),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green[700],
                action: SnackBarAction(
                  label: AppLocalizations.of(context)!.dismiss,
                  textColor: Colors.white,
                  onPressed: () {
                    _isSnackbarShowing = false;
                    messenger.clearSnackBars();
                  },
                ),
              ),
            );
          }
        }
      } else {
        if (_isSnackbarShowing) {
          _isSnackbarShowing = false;
          messenger.clearSnackBars();
        }
      }
    });
  }

  @override
  void dispose() {
    // Clear any lingering snackbar when leaving the screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isSnackbarShowing) {
        try {
          ScaffoldMessenger.of(context).clearSnackBars();
        } catch (_) {}
      }
    });
    super.dispose();
  }

  void _showLeaveConfirmation(BuildContext context, GameProvider gameProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.leaveGame),
        content: Text(AppLocalizations.of(context)!.leaveGameConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              gameProvider.leaveGame().then((_) {
                // Navigate back to home screen
                if (!mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              });
            },
            child: Text(
              AppLocalizations.of(context)!.leave,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showDigimonConfirmation(
    BuildContext context,
    Digimon digimon,
    GameProvider gameProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          _getLocalizedDigimonName(digimon, context),
          style: const TextStyle(color: Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: digimon.imageUrl,
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              setState(() {
                _locallySelectedDigimonId = digimon.id;
              });
              gameProvider.chooseDigimon(digimon);
              Navigator.pop(context);
            },
            child: Text(
              AppLocalizations.of(context)!.confirm,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF6B6B), Color(0xFFFA5252), Color(0xFFC92A2A)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.selectCharacter),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, size: 20),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const SettingsModal(),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () {
                final gameProvider = context.read<GameProvider>();
                _showLeaveConfirmation(context, gameProvider);
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Consumer<GameProvider>(
              builder: (context, gameProvider, child) {
                // Always use the latest game state from the provider,
                // falling back to the widget's initial snapshot only if
                // needed. This ensures opponent selection changes and
                // phase updates are reflected.
                final liveState = gameProvider.gameState ?? widget.gameState;

                debugPrint(
                  '[DigimonSelectionScreen] phase: \\${liveState.currentPhase}, playerOne.chosen: \\${liveState.playerOne.chosenDigimon?.id}, playerTwo.chosen: \\${liveState.playerTwo?.chosenDigimon?.id}',
                );

                final isPlayerOne =
                    gameProvider.playerId == liveState.playerOne.id;
                final currentPlayer = isPlayerOne
                    ? liveState.playerOne
                    : liveState.playerTwo;
                final opponentPlayer = isPlayerOne
                    ? liveState.playerTwo
                    : liveState.playerOne;

                // --- Persistent Snackbar Logic ---
                final hasOpponentChosen = opponentPlayer?.chosenDigimon != null;
                final hasCurrentChosen = currentPlayer?.chosenDigimon != null;
                _updateOpponentReadySnackbar(
                  context,
                  hasOpponentChosen,
                  hasCurrentChosen,
                );
                // --- End Persistent Snackbar Logic ---

                // Compose levels text
                final selectedLevels = liveState.selectedLevels;
                final sortedLevels = (selectedLevels.toList()..sort());
                return Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.playingAgainst(
                        isPlayerOne
                            ? (liveState.playerTwo?.name ?? "Opponent")
                            : liveState.playerOne.name,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.generationsInGame,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: sortedLevels.map((levelIdx) {
                              final levelName =
                                  DigimonService.levelMap[levelIdx] ??
                                  'Unknown';
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  levelName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),

                    Expanded(
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 4 : 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: liveState.availableDigimon.length,
                        itemBuilder: (context, index) {
                          final digimon = liveState.availableDigimon[index];
                          final isSelected =
                              currentPlayer?.chosenDigimon?.id == digimon.id ||
                              _locallySelectedDigimonId == digimon.id;
                          return _buildDigimonTile(
                            digimon,
                            gameProvider,
                            isSelected,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        bottomNavigationBar: Container(
          color: Colors.transparent,
          child: const SafeArea(child: BannerAdWidget()),
        ),
      ),
    );
  }

  String _getLocalizedDigimonName(Digimon digimon, BuildContext context) {
    final locale = Localizations.localeOf(context);
    return digimon.getLocalizedName(locale.languageCode);
  }

  Widget _buildDigimonTile(
    Digimon digimon,
    GameProvider gameProvider,
    bool isSelected,
  ) {
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          _showDigimonConfirmation(context, digimon, gameProvider);
        }
      },
      child: Card(
        color: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    flex: 2,
                    child: CachedNetworkImage(
                      imageUrl: digimon.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error_outline),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getLocalizedDigimonName(digimon, context),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    children: digimon.types.map((type) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getAttributeColor(
                            digimon.attributes.isNotEmpty
                                ? digimon.attributes.first
                                : '',
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          type,
                          style: const TextStyle(
                            fontSize: 7,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Color based on Digimon attribute (Vaccine, Virus, Data, Free, etc.)
  Color _getAttributeColor(String attribute) {
    switch (attribute.toLowerCase()) {
      case 'vaccine':
        return const Color(0xFF4CAF50); // Green
      case 'virus':
        return const Color(0xFFF44336); // Red
      case 'data':
        return const Color(0xFF2196F3); // Blue
      case 'free':
        return const Color(0xFFFF9800); // Orange
      case 'no data':
        return const Color(0xFF9E9E9E); // Grey
      default:
        return const Color(0xFF808080);
    }
  }
}
