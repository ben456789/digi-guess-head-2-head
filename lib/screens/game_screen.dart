import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vibration/vibration.dart';
import '../l10n/app_localizations.dart';
import '../providers/game_provider.dart';
import '../models/game_state.dart';
import '../models/digimon.dart';
import 'digimon_selection_screen.dart';
import 'game_over_screen.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/settings_modal.dart';
import '../services/settings_service.dart';

class GameScreen extends StatefulWidget {
  final List<int> selectedLevels;

  const GameScreen({super.key, required this.selectedLevels});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final _questionController = TextEditingController();
  final FocusNode _questionFocusNode = FocusNode();
  late AnimationController _shakeController;
  late AnimationController _timerController;
  late Animation<double> _shakeAnimation;
  bool _userInitiatedLeave = false;
  bool _hadGameState = false;
  bool _showFirstPlayerModal = false;
  String? _firstPlayerName;
  final ScrollController _chatScrollController = ScrollController();
  bool _userScrolledUp = false;
  // Removed local _eliminatedDigimonIds. Always use backend value.
  bool _hideEliminatedDigimon = false; // Toggle to hide eliminated Digimon
  bool _chatModalOpen = false; // Track if chat modal is open
  bool _answerButtonsEnabled = false;

  // Track if selected character is hidden
  bool _hideSelectedCharacter = false;

  // Track previous turn message for vibration
  String? _previousTurnMessage;

  // Removed _sendingAnswer: no longer tracking answer sending state

  // Helper to get Digimon name in current locale
  String _getLocalizedDigimonName(Digimon digimon, BuildContext context) {
    final locale = Localizations.localeOf(context);
    return digimon.getLocalizedName(locale.languageCode);
  }

  // Helper to get localized name for an evolution member
  String _getLocalizedEvolutionName(
    EvolutionMember evolution,
    BuildContext context,
  ) {
    final locale = Localizations.localeOf(context);
    final languageCode = locale.languageCode;

    // Prefer localized names stored on the evolution member itself
    final localizedNames = evolution.localizedNames;
    if (localizedNames != null && localizedNames.containsKey(languageCode)) {
      return localizedNames[languageCode]!;
    }
    if (localizedNames != null && localizedNames.containsKey('en')) {
      return localizedNames['en']!;
    }

    // Fallback: try to find a matching Digimon in the current game list
    final gameProvider = context.read<GameProvider>();
    final gameState = gameProvider.gameState;
    if (gameState != null) {
      try {
        final digimon = gameState.availableDigimon.firstWhere(
          (p) => p.id == evolution.id,
        );
        return _getLocalizedDigimonName(digimon, context);
      } catch (_) {
        // Ignore and fall through to final fallback
      }
    }

    // Final fallback to capitalized English name
    final name = evolution.name;
    if (name.isEmpty) return name;
    return name[0].toUpperCase() + name.substring(1);
  }

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _timerController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    // Listen to scroll position to detect manual scrolling
    _chatScrollController.addListener(_onChatScroll);
  }

  void _onChatScroll() {
    if (_chatScrollController.hasClients) {
      // If user is not at the bottom, mark that they scrolled up
      final isAtBottom =
          _chatScrollController.position.pixels >=
          _chatScrollController.position.maxScrollExtent - 50; // 50px buffer
      _userScrolledUp = !isAtBottom;
    }
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients && !_userScrolledUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
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
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              _userInitiatedLeave = true;
              await gameProvider.leaveGame();
              if (!mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
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

  @override
  void dispose() {
    _questionController.dispose();
    _questionFocusNode.dispose();
    _shakeController.dispose();
    _timerController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _submitQuestion(GameProvider gameProvider, GameState gameState) {
    if (_questionController.text.trim().isEmpty) {
      _shakeController.forward().then((_) => _shakeController.reset());
      return;
    }

    final question = _questionController.text.trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'ðŸ“¤ Sending question...\nPhase: ${gameState.currentPhase}\nCurrentPlayer: ${gameState.currentPlayerId}',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );

    gameProvider
        .submitQuestion(question)
        .then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('âœ… Question sent!'),
                duration: Duration(seconds: 1),
                backgroundColor: Color(0xFF1a8fe3),
              ),
            );
          }
        })
        .catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('âŒ Error: $error'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        });

    _questionController.clear();
  }

  void _submitAnswer(GameProvider gameProvider, bool isYes) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ðŸ“¤ Sending answer: ${isYes ? "YES" : "NO"}'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blue,
      ),
    );

    gameProvider
        .submitAnswer(isYes)
        .then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('âœ… Answer sent!'),
                duration: Duration(seconds: 1),
                backgroundColor: Color(0xFF1a8fe3),
              ),
            );
          }
        })
        .catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('âŒ Error: $error'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
  }

  void _submitDontKnowAnswer(GameProvider gameProvider) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ðŸ“¤ Sending answer: I don\'t know'),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.blue,
      ),
    );
    // Send "I don't know" as an answer (null value)
    // Turn will switch back to questioner so they can ask another question
    gameProvider
        .submitAnswer(null)
        .then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('âœ… Answer sent!'),
                duration: Duration(seconds: 1),
                backgroundColor: Color(0xFF1a8fe3),
              ),
            );
          }
        })
        .catchError((error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('âŒ Error: $error'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();
    final gameState = gameProvider.gameState;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _onWillPop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1a8fe3),
        body: Consumer<GameProvider>(
          builder: (context, gameProvider, child) {
            final gameState = gameProvider.gameState;
            // Always get eliminatedDigimonIds from backend (current player)
            List<int> eliminatedDigimonIds = [];
            if (gameState != null) {
              final currentPlayer =
                  (gameState.playerOne.id == gameProvider.playerId)
                  ? gameState.playerOne
                  : gameState.playerTwo;
              eliminatedDigimonIds = currentPlayer?.eliminatedDigimonIds ?? [];
            }
            // Reset modal flag when entering character selection phase
            if (gameState != null &&
                gameState.currentPhase == GamePhase.digimonSelection &&
                _showFirstPlayerModal) {
              _showFirstPlayerModal = false;
            }

            // Show modal when game starts or rematch occurs and first player is selected
            if (gameState != null &&
                gameState.currentPhase == GamePhase.inGame &&
                !_showFirstPlayerModal) {
              _showFirstPlayerModal = true;
              final firstPlayer = gameState.players[gameState.currentPlayerId];
              _firstPlayerName = firstPlayer?.name ?? "Unknown";
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                final dialogContext = context;
                if (!mounted) return;
                showGeneralDialog(
                  context: dialogContext,
                  barrierDismissible: false,
                  barrierColor: Colors.black54,
                  transitionDuration: const Duration(milliseconds: 200),
                  pageBuilder: (context, animation, secondaryAnimation) {
                    return Center(
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _firstPlayerName == gameProvider.playerName
                                    ? Icons.looks_one
                                    : Icons.looks_two,
                                size: 48,
                                color: Colors.orange,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _firstPlayerName == gameProvider.playerName
                                    ? AppLocalizations.of(context)!.youGoFirst
                                    : AppLocalizations.of(
                                        context,
                                      )!.playerGoesFirst(_firstPlayerName!),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
                await Future.delayed(const Duration(seconds: 3));
                if (!mounted) return;
                Navigator.of(dialogContext, rootNavigator: true).pop();
              });
            }

            // Check if game was deleted while we had it
            if (gameState == null &&
                _hadGameState &&
                !_userInitiatedLeave &&
                mounted) {
              // Game was deleted by opponent
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!.opponentLeft),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  Future.delayed(const Duration(seconds: 2), () {
                    if (!mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  });
                }
              });
              _hadGameState = false; // Reset to avoid showing multiple times
            }

            if (gameState != null) {
              _hadGameState = true;
            }

            if (gameState == null) {
              // Null state: return to homepage
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              });
              return const SizedBox.shrink();
            }

            // If the current user has not yet chosen a Digimon, force
            // the character selection screen.
            // This makes the flow robust even if the backend phase or
            // player list lags behind or is already set to inGame.
            final currentUser = gameProvider.currentUser;
            if (currentUser != null &&
                currentUser.chosenDigimon == null &&
                gameState.currentPhase != GamePhase.gameOver) {
              return DigimonSelectionScreen(gameState: gameState);
            }

            if (gameState.currentPhase == GamePhase.gameOver) {
              // Close chat modal if it's still open
              if (_chatModalOpen && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_chatModalOpen && mounted) {
                    _chatModalOpen = false;
                    Navigator.of(context).pop();
                  }
                });
              }
              return GameOverScreen(gameState: gameState);
            }

            if (gameState.currentPhase == GamePhase.digimonSelection ||
                (gameState.currentPhase == GamePhase.waitingForPlayers &&
                    gameState.players.length == 2)) {
              return DigimonSelectionScreen(gameState: gameState);
            }

            if (gameState.currentPhase == GamePhase.roundResult) {
              return _buildResultScreen(gameState);
            }

            return _buildGuessingScreen(gameState, gameProvider);
          },
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final gameProvider = context.read<GameProvider>();
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.leaveGame),
        content: Text(AppLocalizations.of(context)!.leaveGameConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppLocalizations.of(context)!.leave,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (shouldLeave == true) {
      _userInitiatedLeave = true;
      await gameProvider.leaveGame();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }

    // Prevent default pop; we handle navigation ourselves when leaving.
    return false;
  }

  Widget _buildGuessingScreen(GameState gameState, GameProvider gameProvider) {
    final isMyTurn =
        gameState.currentPlayerId == context.read<GameProvider>().playerId;

    // Determine if device is a tablet
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;
    return Scaffold(
      backgroundColor: const Color(0xFF1a8fe3),
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.guessTheCharacter),
        backgroundColor: const Color(0xFF1a8fe3),
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
              _showLeaveConfirmation(context, gameProvider);
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF1a8fe3),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Top cards: selected Digimon + quick chat entry
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 171,
                        child: _buildSelectedDigimonDisplay(gameState),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 171,
                        child: GestureDetector(
                          onTap: () =>
                              _showChatModal(context, gameState, gameProvider),
                          child: Card(
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.max,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(
                                            Icons.chat,
                                            color: Colors.black,
                                            size: 28,
                                          ),
                                          if (gameProvider.unreadMessageCount >
                                              0)
                                            Positioned(
                                              right: -8,
                                              top: -12,
                                              child: Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 16,
                                                      minHeight: 16,
                                                    ),
                                                child: Text(
                                                  '${gameProvider.unreadMessageCount}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        width: 1,
                                        height: 24,
                                        color: Colors.black26,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        AppLocalizations.of(context)!.chat,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Builder(
                                    builder: (context) {
                                      // Determine which message to show
                                      String message;
                                      Color color;
                                      // Find the most recent unanswered question
                                      final gameProvider = context
                                          .read<GameProvider>();
                                      final gameState = gameProvider.gameState;
                                      final isMyTurn =
                                          gameState?.currentPlayerId ==
                                          gameProvider.playerId;
                                      // Find last question and answer status
                                      GameMessage? lastQuestion;
                                      bool hasAnswerAfterLastQuestion = false;
                                      final messages =
                                          gameState?.questionsAndAnswers;
                                      for (
                                        int i = messages!.length - 1;
                                        i >= 0;
                                        i--
                                      ) {
                                        if (messages[i].type ==
                                            QuestionType.question) {
                                          lastQuestion = messages[i];
                                          hasAnswerAfterLastQuestion =
                                              i < messages.length - 1 &&
                                              messages
                                                  .sublist(i + 1)
                                                  .any(
                                                    (m) =>
                                                        m.type ==
                                                        QuestionType.answer,
                                                  );
                                          break;
                                        }
                                      }
                                      final hasPendingQuestion =
                                          lastQuestion != null &&
                                          !hasAnswerAfterLastQuestion;
                                      final lastQuestionIsFromMe =
                                          lastQuestion?.senderId ==
                                          gameProvider.playerId;
                                      if (isMyTurn) {
                                        if (hasPendingQuestion &&
                                            !lastQuestionIsFromMe) {
                                          message = AppLocalizations.of(
                                            context,
                                          )!.yourTurnToAnswer;
                                          color = const Color(0xFF43C463);
                                        } else {
                                          message = AppLocalizations.of(
                                            context,
                                          )!.yourTurnToAsk;
                                          color = const Color(0xFF7ED957);
                                        }
                                      } else {
                                        if (hasPendingQuestion &&
                                            lastQuestionIsFromMe) {
                                          message = AppLocalizations.of(
                                            context,
                                          )!.waitingForAnswer;
                                          color = const Color(0xFFFFA726);
                                        } else {
                                          message = AppLocalizations.of(
                                            context,
                                          )!.waitingForQuestion;
                                          color = const Color(0xFFFB8C00);
                                        }
                                      }

                                      // Vibrate when message changes
                                      if (_previousTurnMessage != null &&
                                          _previousTurnMessage != message) {
                                        // Only vibrate when it becomes your turn (opponent did something)
                                        if (message ==
                                                AppLocalizations.of(
                                                  context,
                                                )!.yourTurnToAnswer ||
                                            message ==
                                                AppLocalizations.of(
                                                  context,
                                                )!.waitingForQuestion) {
                                          SettingsService.isVibrationEnabled()
                                              .then((enabled) {
                                                if (enabled) {
                                                  Vibration.vibrate(
                                                    duration: 200,
                                                  );
                                                }
                                              });
                                        }
                                      }

                                      // Schedule state update after build
                                      if (_previousTurnMessage != message) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (mounted &&
                                                  _previousTurnMessage !=
                                                      message) {
                                                setState(() {
                                                  _previousTurnMessage =
                                                      message;
                                                });
                                              }
                                            });
                                      }

                                      return Text(
                                        message,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: 12.0,
                    left: 4.0,
                    right: 4.0,
                  ),
                ),
                const SizedBox(height: 16),
                // Hide Eliminated toggle row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 1,
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.hideEliminated,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                            Checkbox(
                              value: _hideEliminatedDigimon,
                              onChanged: (value) {
                                if (!mounted) return;
                                setState(() {
                                  _hideEliminatedDigimon = value ?? false;
                                });
                              },
                              fillColor: WidgetStateProperty.all(Colors.white),
                              checkColor: Colors.black,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Consumer<GameProvider>(
                          builder: (context, gameProvider, child) {
                            final gameState = gameProvider.gameState;
                            if (gameState == null)
                              return const SizedBox.shrink();

                            // Get opponent's eliminated Digimon count
                            final opponentPlayer =
                                (gameState.playerOne.id ==
                                    gameProvider.playerId)
                                ? gameState.playerTwo
                                : gameState.playerOne;
                            final opponentEliminatedIds =
                                opponentPlayer?.eliminatedDigimonIds ?? [];
                            final opponentRemainingCount =
                                gameState.availableDigimon.length -
                                opponentEliminatedIds.length;

                            final opponentName =
                                opponentPlayer?.name ?? 'Opponent';
                            return Text(
                              AppLocalizations.of(context)!.charactersRemaining(
                                opponentName,
                                opponentRemainingCount,
                              ),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Grid of available digimon
                Consumer<GameProvider>(
                  builder: (context, gameProvider, child) {
                    final gameState = gameProvider.gameState;
                    List<int> eliminatedDigimonIds = [];
                    if (gameState != null) {
                      final currentPlayer =
                          (gameState.playerOne.id == gameProvider.playerId)
                          ? gameState.playerOne
                          : gameState.playerTwo;
                      eliminatedDigimonIds =
                          currentPlayer?.eliminatedDigimonIds ?? [];
                    }
                    return Expanded(
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isTablet ? 4 : 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.75,
                        ),
                        padding: EdgeInsets.zero,
                        itemCount: _hideEliminatedDigimon
                            ? gameState?.availableDigimon
                                  .where(
                                    (p) => !eliminatedDigimonIds.contains(p.id),
                                  )
                                  .length
                            : gameState?.availableDigimon.length,
                        itemBuilder: (context, index) {
                          List<Digimon> sortedList;
                          if (_hideEliminatedDigimon) {
                            sortedList =
                                gameState?.availableDigimon
                                    .where(
                                      (p) =>
                                          !eliminatedDigimonIds.contains(p.id),
                                    )
                                    .toList() ??
                                [];
                          } else {
                            // Sort: non-eliminated first, then eliminated in reverse order
                            // (first eliminated appears last in grid)
                            final nonEliminated =
                                gameState?.availableDigimon
                                    .where(
                                      (p) =>
                                          !eliminatedDigimonIds.contains(p.id),
                                    )
                                    .toList() ??
                                [];
                            final eliminated =
                                gameState?.availableDigimon
                                    .where(
                                      (p) =>
                                          eliminatedDigimonIds.contains(p.id),
                                    )
                                    .toList() ??
                                [];
                            // Sort eliminated by their elimination order, then reverse
                            eliminated.sort((a, b) {
                              final indexA = eliminatedDigimonIds.indexOf(a.id);
                              final indexB = eliminatedDigimonIds.indexOf(b.id);
                              return indexA.compareTo(indexB);
                            });
                            sortedList = [
                              ...nonEliminated,
                              ...eliminated.reversed,
                            ];
                          }
                          final poke = sortedList[index];
                          final isEliminated = eliminatedDigimonIds.contains(
                            poke.id,
                          );
                          return _buildDigimonGridItem(
                            poke,
                            isEliminated,
                            eliminatedDigimonIds,
                          );
                        },
                      ),
                    );
                  },
                ),

                // Banner Ad
                const SizedBox(height: 8),
                const BannerAdWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDigimonGridItem(
    Digimon digimon,
    bool isEliminated,
    List<int> eliminatedDigimonIds,
  ) {
    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isEliminated
            ? const BorderSide(color: Colors.red, width: 2)
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          Opacity(
            opacity: isEliminated ? 0.4 : 1.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: CachedNetworkImage(
                      imageUrl: digimon.imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(
                    _getLocalizedDigimonName(digimon, context),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    right: 4,
                    top: 2,
                    bottom: 8,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
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
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          // Elimination toggle icon (top-left)
          Positioned(
            top: 5,
            left: 5,
            child: GestureDetector(
              onTap: () async {
                if (!mounted) return;
                final gameProvider = context.read<GameProvider>();
                List<int> newEliminated = List<int>.from(eliminatedDigimonIds);
                if (eliminatedDigimonIds.contains(digimon.id)) {
                  newEliminated.remove(digimon.id);
                } else {
                  newEliminated.add(digimon.id);
                }
                await gameProvider.updateEliminatedDigimonIds(newEliminated);
              },
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isEliminated ? Colors.red : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: isEliminated
                    ? const Icon(Icons.close, color: Colors.white, size: 16)
                    : null,
              ),
            ),
          ),
          // Info icon (top-right)
          Positioned(
            top: 5,
            right: 5,
            child: GestureDetector(
              onTap: () => _showDigimonInfo(digimon),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatModal(
    BuildContext context,
    GameState gameState,
    GameProvider gameProvider,
  ) {
    // Clear unread message count when modal opens
    gameProvider.clearUnreadMessages();
    gameProvider.setChatOpen(true);
    _userScrolledUp = false; // Reset scroll state when modal opens
    _chatModalOpen = true; // Track that modal is open
    // Scroll to bottom and focus input when modal opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _questionFocusNode.requestFocus();
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer<GameProvider>(
        builder: (context, gameProvider, child) {
          final currentGameState = gameProvider.gameState;
          if (currentGameState == null) {
            return Container();
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: () {
                            _chatModalOpen = false;
                            gameProvider.setChatOpen(false);
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Chat Messages
                  Expanded(
                    child: currentGameState.questionsAndAnswers.isEmpty
                        ? Center(
                            child: Text(
                              AppLocalizations.of(context)!.noMessagesYet,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          )
                        : Builder(
                            builder: (context) {
                              final sortedMessages =
                                  List<GameMessage>.from(
                                    currentGameState.questionsAndAnswers,
                                  )..sort(
                                    (a, b) =>
                                        a.timestamp.compareTo(b.timestamp),
                                  );
                              return ListView.builder(
                                controller: _chatScrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                itemCount: sortedMessages.length,
                                itemBuilder: (context, index) {
                                  final message = sortedMessages[index];
                                  final isMyMessage =
                                      message.senderId == gameProvider.playerId;
                                  // Scroll to bottom after building the last item
                                  if (index == sortedMessages.length - 1) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => _scrollToBottom(),
                                        );
                                  }
                                  return _buildChatMessage(
                                    message,
                                    isMyMessage,
                                  );
                                },
                              );
                            },
                          ),
                  ),

                  // Input Area
                  Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: _buildChatInput(gameProvider, currentGameState),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      // Set flag to false when modal is dismissed (by any means)
      _chatModalOpen = false;
      if (!mounted) return;
      context.read<GameProvider>().setChatOpen(false);
    });
  }

  Widget _buildChatInput(GameProvider gameProvider, GameState gameState) {
    final isMyTurn = gameState.currentPlayerId == gameProvider.playerId;

    // Find the most recent unanswered question
    GameMessage? lastQuestion;
    bool hasAnswerAfterLastQuestion = false;

    final messages = gameState.questionsAndAnswers;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].type == QuestionType.question) {
        lastQuestion = messages[i];
        // Check if there's an answer after this question
        hasAnswerAfterLastQuestion =
            i < messages.length - 1 &&
            messages.sublist(i + 1).any((m) => m.type == QuestionType.answer);
        break;
      }
    }

    final hasPendingQuestion =
        lastQuestion != null && !hasAnswerAfterLastQuestion;
    final lastQuestionIsFromMe =
        lastQuestion?.senderId == gameProvider.playerId;

    // Determine what input to show
    if (!isMyTurn) {
      // Not my turn - show waiting state
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12, width: 1.5)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildWaitingMessage(
                hasPendingQuestion && lastQuestionIsFromMe
                    ? AppLocalizations.of(context)!.waitingForAnswerEllipsis
                    : AppLocalizations.of(context)!.waitingForQuestionEllipsis,
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  AppLocalizations.of(context)!.eliminateReminder,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (hasPendingQuestion && !lastQuestionIsFromMe) {
      // Reset and delay enable every time a new pending question is detected
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_answerButtonsEnabled) {
          setState(() {
            _answerButtonsEnabled = false;
          });
        }
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _answerButtonsEnabled = true;
            });
          }
        });
      });
      // My turn and there's a question from opponent - show answer buttons
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12, width: 1.5)),
        ),
        child: _buildAnswerButtons(gameProvider),
      );
    } else {
      // My turn and no pending question - show question input
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.black12, width: 1.5)),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black),
          child: _buildQuestionInput(gameProvider, gameState),
        ),
      );
    }
  }

  Widget _buildWaitingMessage(String message) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1a8fe3)),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.black54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatMessage(GameMessage message, bool isMyMessage) {
    Color? bgColor;
    Color textColor = Colors.black;
    if (message.type == QuestionType.answer) {
      if (message.answerValue == null) {
        // "I don't know" answer - dark gray
        bgColor = Colors.grey[800];
        textColor = Colors.white;
      } else {
        // Yes/No answers - green/red
        bgColor = message.answerValue! ? Colors.green : Colors.red;
        textColor = Colors.white;
      }
    } else {
      bgColor = isMyMessage ? const Color(0xFF1a8fe3) : Colors.grey[200];
      textColor = isMyMessage ? Colors.white : Colors.black;
    }
    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: isMyMessage
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == QuestionType.question)
              Text(
                message.content,
                style: TextStyle(color: textColor, fontSize: 14),
              )
            else if (message.type == QuestionType.answer)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (message.answerValue ?? false)
                        ? Icons.check_circle
                        : (message.answerValue == false)
                        ? Icons.cancel
                        : Icons.help_outline,
                    color: (message.answerValue == null)
                        ? Colors.grey
                        : Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    (message.answerValue == null)
                        ? AppLocalizations.of(context)!.dontKnow
                        : (message.answerValue ?? false)
                        ? AppLocalizations.of(context)!.yes
                        : AppLocalizations.of(context)!.no,
                    style: TextStyle(
                      color: (message.answerValue == null)
                          ? Colors.grey[300]
                          : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showAnswerButtonsWithDelay() {
    setState(() {
      _answerButtonsEnabled = false;
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _answerButtonsEnabled = true;
        });
      }
    });
  }

  Widget _buildQuestionInput(GameProvider gameProvider, GameState gameState) {
    void _onSubmit() {
      gameProvider.clearTyping();
      _submitQuestion(gameProvider, gameState);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            AppLocalizations.of(context)!.eliminateReminder,
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        if (gameProvider.isOpponentTyping)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: const [
                SizedBox(width: 4),
                Icon(Icons.more_horiz, color: Colors.blueAccent, size: 20),
                SizedBox(width: 6),
                Text(
                  'Opponent is typing...',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 13),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_shakeAnimation.value, 0),
              child: TextField(
                controller: _questionController,
                focusNode: _questionFocusNode,
                style: const TextStyle(color: Colors.black),
                maxLines: 1,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.askQuestion,
                  hintStyle: const TextStyle(color: Colors.black45),
                  filled: true,
                  fillColor: Color(0xFFF3F4F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black26),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black26),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF1a8fe3),
                      width: 2,
                    ),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF1a8fe3)),
                    onPressed: _onSubmit,
                  ),
                ),
                onSubmitted: (_) => _onSubmit(),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF1a8fe3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)!.sendQuestion,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _showGuessPicker(gameProvider, gameState),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Color(0xFF000000),
                  side: const BorderSide(color: Color(0xFF000000), width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)!.guessCharacter,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showGuessPicker(GameProvider gameProvider, GameState gameState) {
    final rootContext = context;
    // Always get eliminatedDigimonIds from backend (current player)
    List<int> eliminatedDigimonIds = [];
    final gameProvider = context.read<GameProvider>();
    final currentPlayer = (gameState.playerOne.id == gameProvider.playerId)
        ? gameState.playerOne
        : gameState.playerTwo;
    eliminatedDigimonIds = currentPlayer?.eliminatedDigimonIds ?? [];
    final remainingDigimon = gameState.availableDigimon
        .where((p) => !eliminatedDigimonIds.contains(p.id))
        .toList();

    if (remainingDigimon.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.noAvailableCharacter),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: rootContext,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(rootContext).size.height * 0.6,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a8fe3), Color(0xFF1976d2)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(context)!.makeAGuess,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: remainingDigimon.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white12, height: 1),
                  itemBuilder: (context, index) {
                    final poke = remainingDigimon[index];
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: CachedNetworkImage(
                            imageUrl: poke.imageUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      title: Text(
                        _getLocalizedDigimonName(poke, rootContext),
                        style: const TextStyle(color: Colors.white),
                      ),
                      onTap: () async {
                        if (!mounted) return;
                        final localizedName = _getLocalizedDigimonName(
                          poke,
                          rootContext,
                        );
                        final confirm = await showDialog<bool>(
                          context: rootContext,
                          builder: (context) => AlertDialog(
                            content: Text(
                              AppLocalizations.of(
                                context,
                              )!.confirmGuess(localizedName),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(
                                  AppLocalizations.of(context)!.cancel,
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(
                                  AppLocalizations.of(context)!.guess,
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        Navigator.pop(sheetContext);
                        try {
                          final localizedName = _getLocalizedDigimonName(
                            poke,
                            rootContext,
                          );
                          final localizedQuestion = AppLocalizations.of(
                            rootContext,
                          )!.guessQuestion(localizedName);
                          final localizedNo = AppLocalizations.of(
                            rootContext,
                          )!.no;

                          final isCorrect = await gameProvider.submitGuess(
                            poke,
                            localizedQuestion,
                            localizedNo,
                          );
                          if (!mounted) return;
                          if (isCorrect) {
                            // Close the chat modal if it's open
                            if (_chatModalOpen && rootContext.mounted) {
                              _chatModalOpen = false;
                              Navigator.pop(rootContext);
                            }
                          } else {
                            if (rootContext.mounted) {
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Guessing ${poke.capitalizedName}...',
                                  ),
                                  duration: const Duration(seconds: 1),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          if (rootContext.mounted) {
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnswerButtons(GameProvider gameProvider) {
    return StatefulBuilder(
      builder: (context, modalSetState) {
        // Use a persistent local variable
        // Declare it outside the builder so it persists
        // But since StatefulBuilder doesn't provide a persistent state, use a ValueNotifier
        final ValueNotifier<bool> enabledNotifier = ValueNotifier(false);

        // Trigger the delay only once
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!enabledNotifier.value) {
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) {
                enabledNotifier.value = true;
              }
            });
          }
        });

        return ValueListenableBuilder<bool>(
          valueListenable: enabledNotifier,
          builder: (context, localEnabled, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: localEnabled
                            ? () => _submitAnswer(gameProvider, true)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF53E848),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.yes.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // --- Don't Know Button ---
                    SizedBox(
                      width: 48,
                      child: ElevatedButton(
                        onPressed: localEnabled
                            ? () => _submitDontKnowAnswer(gameProvider)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          minimumSize: const Size(48, 48),
                        ),
                        child: const Text(
                          '?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: localEnabled
                            ? () => _submitAnswer(gameProvider, false)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.no.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSelectedDigimonDisplay(GameState gameState) {
    // Get current user's player data
    final gameProvider = context.read<GameProvider>();
    final currentUserId = gameProvider.playerId;
    final isPlayerOne = currentUserId == gameState.playerOne.id;
    final currentPlayer = isPlayerOne
        ? gameState.playerOne
        : gameState.playerTwo;

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(
              AppLocalizations.of(context)!.yourCharacter,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            _buildSelectedDigimonCard(currentPlayer?.chosenDigimon),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDigimonCard(Digimon? digimon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (digimon != null)
          Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 12),
                child: SizedBox(
                  height: 80,
                  width: 80,
                  child: _hideSelectedCharacter
                      ? const Center(
                          child: Text(
                            '?',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.black26,
                            ),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: digimon.imageUrl,
                          fit: BoxFit.contain,
                        ),
                ),
              ),

              // Info icon (top right)
              if (!_hideSelectedCharacter)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showDigimonInfo(digimon),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),

              // Eye icon (top left) â€” NOW FULLY TAPPABLE
              Positioned(
                top: 0,
                left: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _hideSelectedCharacter = !_hideSelectedCharacter;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _hideSelectedCharacter
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 18,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          const SizedBox(
            height: 68,
            width: 68,
            child: Center(
              child: Icon(Icons.help_outline, color: Colors.black26),
            ),
          ),

        const SizedBox(height: 4),

        Text(
          _hideSelectedCharacter
              ? ''
              : (digimon != null
                    ? _getLocalizedDigimonName(digimon, context)
                    : '?'),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Color _getAttributeColor(String attribute) {
    switch (attribute.toLowerCase()) {
      case 'vaccine':
        return const Color(0xFF4CAF50);
      case 'virus':
        return const Color(0xFFF44336);
      case 'data':
        return const Color(0xFF2196F3);
      case 'free':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF808080);
    }
  }

  void _showDigimonInfo(Digimon digimon) {
    final scrollController = ScrollController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Stack(
            children: [
              Scrollbar(
                controller: scrollController,
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Row(
                          children: [
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '#${digimon.id}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _getLocalizedDigimonName(
                                            digimon,
                                            context,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (digimon.levels.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      digimon.levelsString,
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Digimon Image
                        Center(
                          child: CachedNetworkImage(
                            imageUrl: digimon.imageUrl,
                            height: 140,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Description
                        if (digimon.description != null &&
                            digimon.description!.isNotEmpty) ...[
                          const Text(
                            'Description',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            digimon.description!,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Prior Evolutions
                        if (digimon.priorEvolutions != null &&
                            digimon.priorEvolutions!.isNotEmpty) ...[
                          const Text(
                            'Prior Evolutions',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: digimon.priorEvolutions!.map((evo) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CachedNetworkImage(
                                          imageUrl: evo.imageUrl,
                                          height: 45,
                                          width: 45,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 60,
                                          child: Text(
                                            evo.name,
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Next Evolutions
                        if (digimon.nextEvolutions != null &&
                            digimon.nextEvolutions!.isNotEmpty) ...[
                          const Text(
                            'Next Evolutions',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: digimon.nextEvolutions!.take(8).map((
                                  evo,
                                ) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CachedNetworkImage(
                                          imageUrl: evo.imageUrl,
                                          height: 45,
                                          width: 45,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 60,
                                          child: Text(
                                            evo.name,
                                            style: const TextStyle(
                                              fontSize: 9,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Types
                        if (digimon.types.isNotEmpty) ...[
                          Text(
                            AppLocalizations.of(context)!.type,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: digimon.types.map((type) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  type,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Attributes
                        if (digimon.attributes.isNotEmpty) ...[
                          const Text(
                            'Attributes',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: digimon.attributes.map((attr) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getAttributeColor(attr),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  attr,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Fields
                        if (digimon.fields.isNotEmpty) ...[
                          const Text(
                            'Fields',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: digimon.fields.map((field) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Text(
                                  field,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // Skills (show first 6)
                        if (digimon.skills.isNotEmpty) ...[
                          const Text(
                            'Skills',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: digimon.skills.take(6).map((skill) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Text(
                                  skill['name'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultScreen(GameState gameState) {
    final isCorrect = gameState.lastGuessResult == GuessResult.correct;
    final isTimeout = gameState.lastGuessResult == GuessResult.timeout;
    final digimon = gameState.currentPlayer?.currentDigimon;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.roundResult),
        backgroundColor: const Color(0xFF363636),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              final gameProvider = context.read<GameProvider>();
              _showLeaveConfirmation(context, gameProvider);
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF363636),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  size: 100,
                  color: isCorrect ? Color(0xFF1a8fe3) : Colors.red,
                ),
                const SizedBox(height: 20),

                Text(
                  isCorrect
                      ? AppLocalizations.of(context)!.correct
                      : isTimeout
                      ? AppLocalizations.of(context)!.timesUp
                      : AppLocalizations.of(context)!.incorrect,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? Color(0xFF1a8fe3) : Colors.red,
                  ),
                ),
                const SizedBox(height: 20),

                if (digimon != null) ...[
                  Card(
                    color: const Color(0xFF464646),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          CachedNetworkImage(
                            imageUrl: digimon.imageUrl,
                            height: 150,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getLocalizedDigimonName(digimon, context),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Type: ${digimon.typesString}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                if (gameState.currentGuess != null) ...[
                  Text(
                    'Your guess: "${gameState.currentGuess}"',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                ],

                Text(
                  AppLocalizations.of(context)!.nextRoundStarting,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 10),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
