class MultiplayerGameDefinition {
  const MultiplayerGameDefinition({
    required this.key,
    required this.short,
    required this.title,
    required this.subtitle,
    required this.modeSummary,
    required this.actionLabel,
    required this.requiresAction,
    required this.instructions,
    required this.minStake,
    required this.imagePath,
    required this.cardTag,
  });

  final String key;
  final String short;
  final String title;
  final String subtitle;
  final String modeSummary;
  final String actionLabel;
  final bool requiresAction;
  final List<String> instructions;
  final double minStake;
  final String imagePath;
  final String cardTag;
}

const List<MultiplayerGameDefinition> multiplayerGameCatalog = [
  MultiplayerGameDefinition(
    key: 'RPS_CLASH',
    short: 'RPS',
    title: 'Rock Paper Scissors',
    subtitle: 'Shape wins.',
    modeSummary: 'Lock a move. Winning shape splits the pool.',
    actionLabel: 'SUBMIT MOVE',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/screen_15.png',
    cardTag: 'ROOM',
    instructions: [
      'Each player chooses rock, paper, or scissors before the timer ends.',
      'If one shape beats another, everyone on the winning shape shares 85% of the pot.',
      'If the table ties, the round settles evenly across the room.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'DICE_DUEL',
    short: 'DICE',
    title: 'Dice Duel',
    subtitle: 'Highest roll.',
    modeSummary: 'Ready up. Highest roll wins.',
    actionLabel: '',
    requiresAction: false,
    minStake: 1,
    imagePath: 'assets/images/neon_rise_bg.png',
    cardTag: 'ROOM',
    instructions: [
      'Once the host starts, every ready player locks the same entry amount into the pot.',
      'The server rolls one die for each player.',
      'Highest roll wins the room. Matching top rolls split the winner pool.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'TARGET_STRIKE',
    short: 'TARGET',
    title: 'Target Strike',
    subtitle: 'Closest number.',
    modeSummary: 'Pick a number. Closest wins.',
    actionLabel: 'SUBMIT NUMBER',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/digit_dash_bg.png',
    cardTag: 'ROOM',
    instructions: [
      'Every player submits one number from 0 to 99.',
      'The server reveals a hidden target after everyone locks in.',
      'Closest number wins the room. Tied closest players split the winner pool.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'HIGH_CARD',
    short: 'CARD',
    title: 'High Card',
    subtitle: 'Highest card.',
    modeSummary: 'Ready up. Highest card wins.',
    actionLabel: '',
    requiresAction: false,
    minStake: 1,
    imagePath: 'assets/images/screen_14.png',
    cardTag: 'ROOM',
    instructions: [
      'Ready up and start the room. No move input is needed.',
      'The server draws one card rank for each player.',
      'Highest card wins. Matching top ranks split the winner pool.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'PARITY_CLASH',
    short: 'PARITY',
    title: 'Parity Clash',
    subtitle: 'Odd or even.',
    modeSummary: 'Pick a digit. Sum parity wins.',
    actionLabel: 'SUBMIT DIGIT',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/dual_dimension_flip_bg.png',
    cardTag: 'ROOM',
    instructions: [
      'Each player submits a single digit from 0 to 9.',
      'All digits are added together after lock-in.',
      'Players whose chosen digit parity matches the final sum parity share the winner pool.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'COIN_TOSS',
    short: 'COIN',
    title: 'Coin Toss Clash',
    subtitle: 'Heads or tails.',
    modeSummary: 'Pick a side. Match to win.',
    actionLabel: 'LOCK SIDE',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/screen_12.png',
    cardTag: 'ROOM',
    instructions: [
      'Choose heads or tails before the round resolves.',
      'The server flips one coin for the whole room.',
      'Everyone on the winning side shares the distributable winner pool.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'TREASURE_BOX',
    short: 'BOX',
    title: 'Treasure Box Hunt',
    subtitle: 'Pick a box.',
    modeSummary: 'Exact hit wins. Closest fallback.',
    actionLabel: 'LOCK BOX',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/screen_13.png',
    cardTag: 'ROOM',
    instructions: [
      'Each player picks one treasure box numbered 1 to 6.',
      'The server reveals the winning treasure box after everyone locks in.',
      'Exact matches win first. If nobody hits exactly, the closest box wins.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'SECRET_BID',
    short: 'BID',
    title: 'Secret Bid',
    subtitle: 'Unique bid.',
    modeSummary: 'Highest unique bid wins.',
    actionLabel: 'LOCK BID',
    requiresAction: true,
    minStake: 2,
    imagePath: 'assets/images/neon_perimeter_bg.png',
    cardTag: 'ROOM',
    instructions: [
      'Each player secretly submits a bid from 1 to 100.',
      'The server compares every bid after lock-in.',
      'The highest unique bid wins. If no bid is unique, the room splits the pot evenly.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'SPIN_BOTTLE',
    short: 'BOTTLE',
    title: 'Spin the Bottle',
    subtitle: 'Left or right.',
    modeSummary: 'Pick a side. Match to win.',
    actionLabel: 'LOCK SIDE',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/screen_12.png',
    cardTag: 'ROOM',
    instructions: [
      'Each player picks LEFT or RIGHT before the spin resolves.',
      'If the bottle stops on LEFT or RIGHT, matching players split 85% of the room pot.',
      'If the bottle stops in the middle, the round has no winners and the house keeps the pot.',
    ],
  ),
  MultiplayerGameDefinition(
    key: 'LOOT_BOX_POOL',
    short: 'LOOT',
    title: 'Loot Box Pool',
    subtitle: 'Pick a box.',
    modeSummary: 'Exact hit wins. Closest fallback.',
    actionLabel: 'LOCK BOX',
    requiresAction: true,
    minStake: 1,
    imagePath: 'assets/images/screen_13.png',
    cardTag: 'ROOM',
    instructions: [
      'Each player chooses one loot box numbered 1 to 20.',
      'The server reveals 5 winning boxes after everyone locks in.',
      'Exact hits win first. If nobody hits exactly, the closest chosen box wins the room.',
    ],
  ),
];

MultiplayerGameDefinition? multiplayerGameForKey(String? key) {
  if (key == null || key.trim().isEmpty) {
    return null;
  }
  final normalized = key.trim().toUpperCase();
  for (final game in multiplayerGameCatalog) {
    if (game.key == normalized) {
      return game;
    }
  }
  return null;
}
