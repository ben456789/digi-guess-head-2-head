# character Head 2 Head 🎯

A multiplayer "Guess Who" style game with character! Players take turns asking yes/no questions to guess their opponent's chosen character.

## Features

- **Multiplayer Gameplay**: Real-time communication between two devices
- **character Generation Selection**: Choose which character generations to include
- **QR Code Game Joining**: Easy game joining via QR code or manual code entry
- **Grid-Based character Display**: Visual grid of all available character
- **Yes/No Question System**: Ask strategic questions to eliminate character
- **character Elimination**: Toggle off character as you narrow down possibilities

## How to Play

1. **Create Game**: Player 1 creates a game and selects character generations
2. **Join Game**: Player 2 joins via QR code scan or manual code entry
3. **character Selection**: 36 character from selected generations are displayed
4. **Choose character**: Each player secretly selects their character
5. **Ask Questions**: Take turns asking yes/no questions about opponent's character
6. **Eliminate character**: Use answers to eliminate character from the grid
7. **Final Guess**: Make your final guess when you think you know their character
8. **Win Condition**: First player to correctly guess wins!## Game Screens

- **Setup Screen**: Enter player names and view game rules
- **Game Screen**: View character images and make guesses
- **Result Screen**: See if your guess was correct and learn about the character
- **Game Over**: Final scores and play again option

## Technical Features

- Built with Flutter for cross-platform compatibility
- Uses Provider for state management
- Integrates with digiAPI (https://digiapi.co/) for character data
- Cached network images for better performance
- Smooth animations and transitions
- Responsive design for different screen sizes

## Getting Started

### Prerequisites

- Flutter SDK (3.10.7 or higher)
- Android Studio / Xcode for device testing
- Internet connection (required for character API)

### Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd digi_guess_head_2_head
```

2. Install dependencies:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

### For Android:

- Connect an Android device or start an emulator
- Run `flutter run` to install and launch the app

### For iOS:

- Open the project in Xcode (requires macOS)
- Connect an iOS device or use the iOS Simulator
- Run `flutter run` to install and launch the app

## Dependencies

- **flutter**: The core Flutter framework
- **http**: For making API requests to digiAPI
- **provider**: State management solution
- **cached_network_image**: Efficient image loading and caching
- **flutter_animate**: Smooth animations and transitions
- **cupertino_icons**: iOS-style icons

## API Used

This game uses the [digiAPI](https://digiapi.co/) - a free RESTful API providing comprehensive character data including:

- character names and IDs
- High-quality official artwork
- Type information
- Physical characteristics

## Game Flow

```
Setup Screen → Game Screen → Result Screen → Game Screen → ... → Game Over Screen
     ↑                                                              ↓
     ←←←←←←←←←←←←←←← Play Again Button ←←←←←←←←←←←←←←←←←←←←←←←
```

## Screenshots

The app features a modern, colorful design with:

- Gradient backgrounds
- Card-based layouts
- Smooth animations
- Responsive character image display
- Real-time timer with color coding
- Clear score tracking

## Contributing

Feel free to contribute to this project by:

- Adding new game modes
- Improving the UI/UX
- Adding sound effects
- Implementing difficulty levels
- Adding more character generations

## License

This project is open source and available under the MIT License.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

flutter clean
flutter pub get
flutter run
flutter run -d web-server

#e6c229 - 0xFFe6c229
#f17105 - 0xFFf17105
#d11149 - 0xFFd11149
#6610f2 - 0xFF6610f2
#1a8fe3 - 0xFF1a8fe3
