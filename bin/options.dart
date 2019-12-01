import 'dart:io';
import 'package:args/args.dart' as args;

class Options {
  Directory get sourceDir => Directory(_parsed['source-dir']);
  Directory get targetDir => Directory(_parsed['target-dir']);
  int get blurbLength => int.parse(_parsed['blurb-length']);
  int get pageSize => int.parse(_parsed['page-size']);

  Options.fromArgs(List<String> args) {
    _parser.addOption('source-dir', abbr: 's', help: 'source directory for authored content (required)', valueHelp: 'dir');
    _parser.addOption('target-dir', abbr: 't', help: 'target directory for generated content (required)', valueHelp: 'dir');
    _parser.addOption('page-size', abbr: 'p', defaultsTo: '15', help: 'number of items in each page of generated feed', valueHelp: 'size');
    _parser.addOption('blurb-length', abbr: 'b', defaultsTo: "512", help: 'maximum plain text blurb length', valueHelp: 'length');
    _parser.addFlag('help', abbr: 'h', negatable: false, help: 'print usage');
    _parseWithExit(args);
  }

  args.ArgParser _parser = args.ArgParser();
  args.ArgResults _parsed;

  static final _requiredArgs = [
    'source-dir',
    'target-dir'
  ];

  void _parseWithExit(List<String> args) {
    try {
      _parsed = _parser.parse(args);
      if (_parsed['help']) _printUsageAndExit();
      for (var a in _requiredArgs) if (!_parsed.wasParsed(a)) _printUsageAndExit(e: Exception('missing required arg: $a'));
    } catch (e) {
      _printUsageAndExit(e: e);
    }
  }

  void _printUsageAndExit({Exception e}) {
    final options = _parser.options.keys.fold('', (s, k) => '$s [--$k]');
    final usage = 'usage: dart main.dart${options}\n${_parser.usage}';

    if (e != null) {
      stderr.write(e.toString().replaceFirst('Exception', 'Error'));
      stderr.write('\n');
      stderr.write(usage);
      stderr.write('\n');
      exit(1);
    } else {
      print(usage);
      exit(0);
    }
  }
}
