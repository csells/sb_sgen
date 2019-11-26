import 'dart:io';
import 'package:jiffy/jiffy.dart';
import 'package:path/path.dart' as pathutil;
import 'package:yaml/yaml.dart' as yaml;
import 'package:meta/meta.dart';

main(List<String> args) async {
  var dir = '/Users/csells/Code/sb-blot';
  var files = await Directory(dir).list(recursive: true).ofType<File>().where((f) => f.isMarkdown || f.isHtml).toList();
  for (var meta in (await Metadata.fromFiles(files)).where((m) => !m.isDraft)) {
    print('filename= ${meta.filename}');
    print('  title= ${meta.title}');
    print('  blurb= ${meta.blurb}');
    print('  image= ${meta.image}');
    print('  date= ${meta.date.toLocal()}');
    print('  permalink= ${meta.permalink}');
    print('  discus= ${meta.disqus}');
    print('  tags= ${meta.tags}');
    print('  isPage= ${meta.isPage}');
  }
}

class Metadata {
  final String filename;
  final String title;
  final String blurb;
  final Uri image;
  final DateTime date;
  final String permalink;
  final String disqus;
  final List<String> tags;
  final bool isPage;
  final bool isDraft;

  Metadata({
    @required this.filename,
    @required this.title,
    @required this.blurb,
    @required this.image,
    @required this.date,
    @required this.permalink,
    @required this.disqus,
    @required this.tags,
    @required this.isPage,
    @required this.isDraft,
  });

  static Future<List<Metadata>> fromFiles(Iterable<File> files) async {
    var metadata = List<Metadata>();
    for (var file in files) {
      metadata.add(await Metadata.ctor(file));
    }
    return metadata;
  }

  static Future<Metadata> ctor(File file) async {
    final meta = await _getMetadataFromFile(file);

    final filename = file.path;
    final title = 'TODO'; // TODO
    final blurb = 'TODO'; // TODO
    final image = Uri.parse('https://todo.com/todo.png'); // TODO
    final date = meta.containsKey('Date') ? Jiffy(meta['Date'], 'MM/dd/yyy').utc() : (await file.stat()).changed.toUtc();
    final permalink = meta.containsKey('Permalink') ? meta['Permalink'] : pathutil.basenameWithoutExtension(file.path);
    final disqus = meta.containsKey('Disqus') ? meta['Permalink'] : permalink;
    final tags = meta.containsKey('Tags') ? meta['Tags'].split(',') : List<String>();
    final isPage = meta.containsKey('Page') ? meta['Page'] == 'yes' : false;
    final isDraft = pathutil.basenameWithoutExtension(file.path).toLowerCase().contains('[draft]');
    return Metadata(filename: filename, title: title, blurb: blurb, image: image, date: date, permalink: permalink, disqus: disqus, tags: tags, isPage: isPage, isDraft: isDraft);
  }

  // Title: first '# title' or first '<h1>title</h1>' (TODO)
  // Blurb: the first few lines of content in plain text (TODO)
  // Date: metadata or file date (UTC)
  // Permalink: metadata or base filename no extension
  // Disqus: metadata or Permalink
  // Tags: metadata or nothing
  static Future<Map<String, String>> _getMetadataFromFile(File file) async {
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

      <img ... />
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
