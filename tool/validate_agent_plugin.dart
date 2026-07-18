// Validates the agent-plugin distribution tree of this repository.
//
// Run from the repository root:
//
//   dart tool/validate_agent_plugin.dart
//
// Checks (all static, no network, no AI):
//   - plugin manifests (.claude-plugin/plugin.json, .codex-plugin/plugin.json)
//     are valid JSON with required fields and versions equal to pubspec.yaml;
//   - both repo marketplaces list the plugin with an existing, repo-relative
//     source path (no absolute paths, no path traversal);
//   - every skill directory has a SKILL.md whose frontmatter is exactly
//     `name` (kebab-case, matching the directory) and `description`
//     (non-empty, <= 1024 chars), and stays under 500 lines;
//   - files referenced as `references/...` from a SKILL.md exist;
//   - no absolute paths or secret-looking strings in the plugin tree;
//   - .claude/skills and .agents/skills are byte-identical mirrors;
//   - every eval case has prompt.md and at least one grader;
//   - .pubignore excludes the whole agent tooling tree from the pub archive.

import 'dart:convert';
import 'dart:io';

const _pluginName = 'webview-flutter-windows';
const _pluginRoot = 'agent_plugins/webview-flutter-windows';

final List<String> _errors = <String>[];

void _fail(String message) => _errors.add(message);

/// Entry point; exits non-zero when any check fails.
void main() {
  final pubspecVersion = _readPubspecVersion();

  _checkClaudeManifest(pubspecVersion);
  _checkCodexManifest(pubspecVersion);
  _checkClaudeMarketplace(pubspecVersion);
  _checkCodexMarketplace();
  _checkSkills();
  _checkEvals();
  _checkMirrors();
  _checkPubignore();
  _checkForbiddenContent();

  if (_errors.isEmpty) {
    stdout.writeln(
      'agent plugin validation: OK '
      '(version $pubspecVersion, plugin $_pluginName)',
    );
    return;
  }
  stderr.writeln('agent plugin validation: ${_errors.length} error(s)');
  for (final error in _errors) {
    stderr.writeln('  - $error');
  }
  exitCode = 1;
}

String _readPubspecVersion() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  for (final line in lines) {
    final match = RegExp(r'^version:\s*(\S+)\s*$').firstMatch(line);
    if (match != null) {
      return match.group(1)!;
    }
  }
  _fail('pubspec.yaml: no version line found');
  return '';
}

Map<String, Object?>? _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _fail('$path: missing');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      _fail('$path: top level is not a JSON object');
      return null;
    }
    return decoded;
  } on FormatException catch (e) {
    _fail('$path: invalid JSON (${e.message})');
    return null;
  }
}

final _kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

void _requireField(
  Map<String, Object?> json,
  String path,
  String field, {
  String? equals,
}) {
  final value = json[field];
  if (value == null || (value is String && value.isEmpty)) {
    _fail('$path: missing required field "$field"');
    return;
  }
  if (equals != null && value != equals) {
    _fail('$path: "$field" is "$value", expected "$equals"');
  }
}

void _checkClaudeManifest(String version) {
  final path = '$_pluginRoot/.claude-plugin/plugin.json';
  final json = _readJson(path);
  if (json == null) return;
  _requireField(json, path, 'name', equals: _pluginName);
  _requireField(json, path, 'version', equals: version);
  _requireField(json, path, 'description');
  if (json['skills'] != './skills/') {
    _fail('$path: "skills" must be "./skills/"');
  }
}

void _checkCodexManifest(String version) {
  final path = '$_pluginRoot/.codex-plugin/plugin.json';
  final json = _readJson(path);
  if (json == null) return;
  // Codex requires name, version, and description.
  _requireField(json, path, 'name', equals: _pluginName);
  _requireField(json, path, 'version', equals: version);
  _requireField(json, path, 'description');
  if (json['skills'] != './skills/') {
    _fail('$path: "skills" must be "./skills/"');
  }
}

void _checkSource(String path, String source) {
  if (source.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(source)) {
    _fail('$path: source "$source" is an absolute path');
    return;
  }
  if (source.split('/').contains('..')) {
    _fail('$path: source "$source" contains path traversal');
    return;
  }
  final normalized = source.startsWith('./') ? source.substring(2) : source;
  if (normalized != _pluginRoot) {
    _fail('$path: source "$source" does not point at $_pluginRoot');
  }
  if (!Directory(normalized).existsSync()) {
    _fail('$path: source directory "$normalized" does not exist');
  }
}

void _checkClaudeMarketplace(String version) {
  const path = '.claude-plugin/marketplace.json';
  final json = _readJson(path);
  if (json == null) return;
  final name = json['name'];
  if (name is! String || !_kebab.hasMatch(name)) {
    _fail('$path: marketplace "name" must be kebab-case');
  }
  final owner = json['owner'];
  if (owner is! Map || owner['name'] is! String) {
    _fail('$path: "owner.name" is required');
  }
  final plugins = json['plugins'];
  if (plugins is! List || plugins.isEmpty) {
    _fail('$path: "plugins" must be a non-empty list');
    return;
  }
  final names = <String>{};
  for (final entry in plugins.whereType<Map<String, Object?>>()) {
    final entryName = entry['name'];
    if (entryName is! String || !_kebab.hasMatch(entryName)) {
      _fail('$path: plugin name "$entryName" must be kebab-case');
      continue;
    }
    if (!names.add(entryName)) {
      _fail('$path: duplicate plugin name "$entryName"');
    }
  }
  final entry = plugins
      .whereType<Map<String, Object?>>()
      .where((p) => p['name'] == _pluginName)
      .toList();
  if (entry.length != 1) {
    _fail('$path: expected exactly one "$_pluginName" entry');
    return;
  }
  final source = entry.single['source'];
  if (source is String) {
    _checkSource(path, source);
  } else {
    _fail('$path: "$_pluginName" source must be a relative path string');
  }
  final entryVersion = entry.single['version'];
  if (entryVersion != null && entryVersion != version) {
    _fail('$path: entry version "$entryVersion" != pubspec "$version"');
  }
}

void _checkCodexMarketplace() {
  const path = '.agents/plugins/marketplace.json';
  final json = _readJson(path);
  if (json == null) return;
  final name = json['name'];
  if (name is! String || !_kebab.hasMatch(name)) {
    _fail('$path: marketplace "name" must be kebab-case');
  }
  final plugins = json['plugins'];
  if (plugins is! List || plugins.isEmpty) {
    _fail('$path: "plugins" must be a non-empty list');
    return;
  }
  final entry = plugins
      .whereType<Map<String, Object?>>()
      .where((p) => p['name'] == _pluginName)
      .toList();
  if (entry.length != 1) {
    _fail('$path: expected exactly one "$_pluginName" entry');
    return;
  }
  final source = entry.single['source'];
  if (source is! Map ||
      source['source'] != 'local' ||
      source['path'] is! String) {
    _fail('$path: source must be {"source": "local", "path": ...}');
    return;
  }
  _checkSource(path, source['path'] as String);
}

void _checkSkills() {
  final skillsDir = Directory('$_pluginRoot/skills');
  if (!skillsDir.existsSync()) {
    _fail('${skillsDir.path}: missing');
    return;
  }
  final skillDirs = skillsDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (skillDirs.isEmpty) {
    _fail('${skillsDir.path}: no skills found');
  }
  for (final dir in skillDirs) {
    final dirName = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    _checkSkill(dir, dirName);
  }
}

void _checkSkill(Directory dir, String dirName) {
  final skillFile = File('${dir.path}/SKILL.md');
  if (!skillFile.existsSync()) {
    _fail('${dir.path}: missing SKILL.md');
    return;
  }
  final lines = skillFile.readAsLinesSync();
  if (lines.length > 500) {
    _fail('${skillFile.path}: ${lines.length} lines (limit 500)');
  }
  if (lines.isEmpty || lines.first.trim() != '---') {
    _fail('${skillFile.path}: missing frontmatter opening "---"');
    return;
  }
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end < 0) {
    _fail('${skillFile.path}: missing frontmatter closing "---"');
    return;
  }
  final fields = <String, String>{};
  String? currentKey;
  for (final raw in lines.sublist(1, end)) {
    if (raw.trim().isEmpty) continue;
    final keyMatch = RegExp(
      r'^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$',
    ).firstMatch(raw);
    if (keyMatch != null) {
      currentKey = keyMatch.group(1)!;
      fields[currentKey] = keyMatch.group(2)!.trim();
    } else if (currentKey != null && raw.startsWith('  ')) {
      // Folded continuation line of the previous value.
      fields[currentKey] = '${fields[currentKey]} ${raw.trim()}'.trim();
    } else {
      _fail('${skillFile.path}: unparseable frontmatter line "$raw"');
    }
  }
  final unexpected = fields.keys.toSet()..removeAll({'name', 'description'});
  if (unexpected.isNotEmpty) {
    _fail(
      '${skillFile.path}: unexpected frontmatter keys $unexpected '
      '(allowed: name, description)',
    );
  }
  final name = fields['name'] ?? '';
  if (name != dirName) {
    _fail(
      '${skillFile.path}: frontmatter name "$name" != directory '
      '"$dirName"',
    );
  }
  if (!_kebab.hasMatch(name) || name.length > 64) {
    _fail('${skillFile.path}: name must be kebab-case, <= 64 chars');
  }
  final description = fields['description'] ?? '';
  if (description.isEmpty || description.length > 1024) {
    _fail(
      '${skillFile.path}: description must be 1..1024 chars '
      '(is ${description.length})',
    );
  }
  if (end + 1 >= lines.length ||
      lines.sublist(end + 1).every((l) => l.trim().isEmpty)) {
    _fail('${skillFile.path}: empty body');
  }

  // Every references/<file> mention must exist inside the skill directory.
  final body = lines.sublist(end + 1).join('\n');
  for (final match in RegExp(r'references/[A-Za-z0-9._\-]+').allMatches(body)) {
    final ref = match.group(0)!;
    if (!File('${dir.path}/$ref').existsSync()) {
      _fail('${skillFile.path}: referenced file "$ref" does not exist');
    }
  }
}

void _checkEvals() {
  final evalsDir = Directory('$_pluginRoot/evals');
  if (!evalsDir.existsSync()) {
    _fail('${evalsDir.path}: missing');
    return;
  }
  for (final dir in evalsDir.listSync().whereType<Directory>()) {
    if (!File('${dir.path}/prompt.md').existsSync()) {
      _fail('${dir.path}: missing prompt.md');
    }
    final graders = Directory('${dir.path}/graders');
    if (!graders.existsSync() ||
        graders
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))
            .isEmpty) {
      _fail('${dir.path}: missing graders/*.md');
    }
  }
}

void _checkMirrors() {
  const a = '.claude/skills';
  const b = '.agents/skills';
  final filesA = _relativeFiles(a);
  final filesB = _relativeFiles(b);
  for (final rel in {...filesA.keys, ...filesB.keys}) {
    final inA = filesA[rel];
    final inB = filesB[rel];
    if (inA == null) {
      _fail('$a/$rel: missing (exists in $b)');
    } else if (inB == null) {
      _fail('$b/$rel: missing (exists in $a)');
    } else if (!_sameBytes(inA, inB)) {
      _fail('$a/$rel and $b/$rel differ (mirrors must be byte-identical)');
    }
  }
}

Map<String, File> _relativeFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) {
    _fail('$root: missing');
    return <String, File>{};
  }
  final result = <String, File>{};
  for (final entity in dir.listSync(recursive: true).whereType<File>()) {
    result[entity.path.substring(root.length + 1)] = entity;
  }
  return result;
}

bool _sameBytes(File a, File b) {
  final bytesA = a.readAsBytesSync();
  final bytesB = b.readAsBytesSync();
  if (bytesA.length != bytesB.length) return false;
  for (var i = 0; i < bytesA.length; i++) {
    if (bytesA[i] != bytesB[i]) return false;
  }
  return true;
}

void _checkPubignore() {
  const path = '.pubignore';
  final file = File(path);
  if (!file.existsSync()) {
    _fail('$path: missing');
    return;
  }
  final entries = file.readAsLinesSync().map((l) => l.trim()).toSet();
  const required = <String>{
    'agent_plugins/',
    '.claude/',
    '.agents/',
    '.claude-plugin/',
    'AGENTS.md',
    'CLAUDE.md',
    'tool/',
    'docs/',
  };
  for (final entry in required) {
    if (!entries.contains(entry)) {
      _fail(
        '$path: missing "$entry" (agent tooling must not ship in the '
        'pub archive)',
      );
    }
  }
}

void _checkForbiddenContent() {
  final secret = RegExp(
    r'(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|'
    r'gho_[A-Za-z0-9]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|'
    r'-----BEGIN [A-Z ]*PRIVATE KEY-----)',
  );
  final absolutePath = RegExp(
    r'(/Users/[A-Za-z0-9_.-]+/|/home/[A-Za-z0-9_.-]+/|C:\\Users\\)',
  );
  final roots = <String>[_pluginRoot, '.claude', '.agents', '.claude-plugin'];
  final files = <File>[
    for (final root in roots)
      if (Directory(root).existsSync())
        ...Directory(root).listSync(recursive: true).whereType<File>(),
    File('AGENTS.md'),
    File('CLAUDE.md'),
  ];
  for (final file in files) {
    if (!file.existsSync()) continue;
    final content = file.readAsStringSync();
    if (secret.hasMatch(content)) {
      _fail('${file.path}: contains a secret-looking string');
    }
    if (absolutePath.hasMatch(content)) {
      _fail('${file.path}: contains a machine-specific absolute path');
    }
  }
}
