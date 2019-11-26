import 'dart:io';
import 'package:jiffy/jiffy.dart';
import 'package:path/path.dart' as pathutil;
import 'package:yaml/yaml.dart' as yaml;
import 'package:meta/meta.dart';

main(List<String> args) async {
  var dir = '/Users/csells/Code/sb-blot';
  var files = await Directory(dir).list(recursive: true).ofType<File>().where((f) => f.isMarkdown || f.isHtml).toList();
  for (var file in files) {
    var meta = await Metadata.ctor(file);
    print(file);
    print('  date= ${meta.date.toLocal()}');
    print('  permalink= ${meta.permalink}');
    print('  discus= ${meta.disqus}');
    print('  tags= ${meta.tags}');
    print('  isPage= ${meta.isPage}');
    print('  isDraft= ${meta.isDraft}');
  }
}

class Metadata {
  final DateTime date;
  final String permalink;
  final String disqus;
  final List<String> tags;
  final bool isPage;
  final bool isDraft;

  Metadata({
    @required this.date,
    @required this.permalink,
    @required this.disqus,
    @required this.tags,
    @required this.isPage,
    @required this.isDraft,
  });

  static Future<Metadata> ctor(File file) async {
    final meta = await getMetadataFromFile(file);

    final date = meta.containsKey('Date') ? Jiffy(meta['Date'], 'MM/dd/yyy').utc() : (await file.stat()).changed.toUtc();
    final permalink = meta.containsKey('Permalink') ? meta['Permalink'] : pathutil.basenameWithoutExtension(file.path);
    final disqus = meta.containsKey('Disqus') ? meta['Permalink'] : permalink;
    final tags = meta.containsKey('Tags') ? meta['Tags'].split(',') : List<String>();
    final isPage = meta.containsKey('Page') ? meta['Page'] == 'yes' : false;
    final isDraft = pathutil.basenameWithoutExtension(file.path).toLowerCase().contains('[draft]');
    return Metadata(date: date, permalink: permalink, disqus: disqus, tags: tags, isPage: isPage, isDraft: isDraft);
  }

// Title: first '# title' or first '<h1>title</h1>'
// Blurb: the first few lines of content in plain text
// Date: metadata or file date
// Permalink: metadata or ???
// Disqus: metadata or ???
// Tags: metadata or nothing
  static Future<Map<String, String>> getMetadataFromFile(File file) async {
    var lines = await file.readAsLines();
    var metadataLines = List<String>();

    if (file.isHtml) {
      /* HTML metadata example
    <!--
    Date: 8/30/2006 3:09:32 PM  -08:00
    Permalink: 2039
    Disqus: 2039
    Tags: fun
    -->
    <h1>USB MP3 Player + SD Card = Gadget-o-licious</h1>
    ...
    */
      if (lines[0].trim() == '<!--') {
        metadataLines.addAll(lines.skip(1).takeWhile((l) => l.trim() != '-->'));
      }
    } else if (file.isMarkdown) {
      /* Markdown metadata example
    Date: 11/12/2017

    # WebAssembly *explodes* client-side programming
    ...
    */
      metadataLines.addAll(lines.map((l) => l.trim()).takeWhile((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('<')));
    } else {
      assert(false, 'must have HTML or Markdown file: ${file.path}');
    }

    var metadata = Map<String, String>();
    if (metadataLines.isNotEmpty) {
      var map = yaml.loadYaml(metadataLines.join('\n')) as yaml.YamlMap;
      for (var key in map.keys) {
        metadata[key] = map[key].toString();
      }
    }
    return metadata;
  }
}

extension MyStream<T> on Stream<T> {
  Stream<T> ofType<T>() => this.where((fse) => fse is T).map((fse) => fse as T);
}

extension on String {
  int compareNoCase(String other) => this.toLowerCase().compareTo(other.toLowerCase());
}

extension on File {
  bool hasExtension(String ext) => pathutil.extension(this.path).compareNoCase(ext) == 0;
  bool get isMarkdown => this.hasExtension('.md');
  bool get isHtml => this.hasExtension('.html');
}
