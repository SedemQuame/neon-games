import 'dart:io';

void main() {
  final dir = Directory('lib/screens/game_screens');
  int count = 0;
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    String content = file.readAsStringSync();
    
    final targetStr = '''
    if (mounted) {
      context.read<SessionManager>().gameService.leaveGame();
    }
''';

    if (content.contains(targetStr)) {
      content = content.replaceAll(targetStr, '');
      file.writeAsStringSync(content);
      count++;
      print('Fixed \${file.path}');
    }
  }
  print('Fixed dispose in \$count files.');
}
