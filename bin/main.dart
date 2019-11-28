import 'dart:io';
import 'package:jiffy/jiffy.dart';
import 'package:path/path.dart' as pathutil;
import 'package:yaml/yaml.dart' as yaml;
import 'package:meta/meta.dart';
import 'package:markdown/markdown.dart';

main(List<String> args) async {
  var dir = '/Users/csells/Code/sb-blot';
  var files = await Directory(dir).list(recursive: true).ofType<File>().where((f) => f.isMarkdown || f.isHtml).take(10).toList();
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
  final int bodyStartLine;

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
    @required this.bodyStartLine,
  });

  static Future<List<Metadata>> fromFiles(Iterable<File> files) async {
    var metadata = List<Metadata>();
    for (var file in files) {
      metadata.add(await Metadata.fromFile(file));
    }
    return metadata;
  }

  static Future<Metadata> fromFile(File file) async {
    final meta = await _getMetadataFromFile(file);
    final permalink = meta.containsKey('Permalink') ? meta['Permalink'] : pathutil.basenameWithoutExtension(file.path);

    return Metadata(
      filename: file.path,
      title: meta['Title'],
      blurb: meta['Blurb'],
      image: meta.containsKey('Image') ? Uri.parse(meta['Image']) : null,
      date: meta.containsKey('Date') ? Jiffy(meta['Date'], 'MM/dd/yyy').utc() : (await file.stat()).changed.toUtc(),
      permalink: permalink,
      disqus: meta.containsKey('Disqus') ? meta['Permalink'] : permalink,
      tags: meta.containsKey('Tags') ? meta['Tags'].split(',') : null,
      isPage: meta.containsKey('Page') ? meta['Page'] == 'yes' : false,
      isDraft: pathutil.basenameWithoutExtension(file.path).toLowerCase().contains('[draft]'),
      bodyStartLine: int.parse(meta['BodyStartLine']),
    );
  }

  static final _htmlImgRE = RegExp(r'<img(\s|[^>])*src=[' '"](?<src>[^' '"]*)[' '"]', multiLine: true);
  static final _htmlH1RE = RegExp(r'<h1>(?<title>[^<]*)<\/h1>');
  static final _mdH1RE = RegExp(r'^#(?<title>.*$)');
  static final _htmlStripTagsRE = RegExp(r'<[^>]+>', multiLine: true);
  static final _collapseWhitespaceRE = RegExp(r'\s\s+');

  // Title: first '# title' or first '<h1>title</h1>'
  // Blurb: the first few lines of content in plain text
  // Image: primary image (aka first image)
  // Date: metadata or file date (UTC)
  // Permalink: metadata or base filename no extension
  // Disqus: metadata or Permalink
  // Tags: metadata or nothing
  // BodyStartLine: metadata
  static Future<Map<String, String>> _getMetadataFromFile(File file) async {
    final lines = await file.readAsLines();
    final metadataLines = List<String>();
    var bodyStartLine = 0;

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
        final metalines = lines.skip(1).takeWhile((l) => l.trim() != '-->');
        metadataLines.addAll(metalines);
        bodyStartLine = metalines.length + 2; // skip the trailing '-->'
      }
    } else if (file.isMarkdown) {
      /* Markdown metadata example
      Date: 11/12/2017

      <img ... />
      # WebAssembly *explodes* client-side programming
      ...
      */
      final metalines = lines.map((l) => l.trim()).takeWhile((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('<'));
      metadataLines.addAll(metalines);
      bodyStartLine = metalines.length + 1;
    } else {
      assert(false, 'must have HTML or Markdown file: ${file.path}');
    }

    // grab "name: value" pairs
    final meta = Map<String, String>();
    if (metadataLines.isNotEmpty) {
      final map = yaml.loadYaml(metadataLines.join('\n')) as yaml.YamlMap;
      for (var key in map.keys) meta[key] = map[key].toString();
    }

    // the rest is the body of the content
    meta['BodyStartLine'] = bodyStartLine.toString();
    var body = lines.skip(bodyStartLine).join('\n');

    // grab title
    final titleRE = file.isHtml ? _htmlH1RE : file.isMarkdown ? _mdH1RE : null;
    assert(titleRE != null, 'must have HTML or Markdown file: ${file.path}');
    var title = titleRE.firstMatch(body)?.namedGroup('title')?.trim();
    if (title == null) title = lines.skip(bodyStartLine).take(1).first;
    assert(title != null && title.isNotEmpty);
    meta['Title'] = title;

    // grab image from the body of the content
    var image = _htmlImgRE.firstMatch(body)?.namedGroup('src');
    if (image != null) meta['Image'] = image;
    assert(meta['Image'] != null || !body.contains('<img'));

    // grab the blurb
    final someHtml = file.isHtml ? body.substring(0, 1024) : markdownToHtml(body.substring(0, 1024));
    meta['Blurb'] = someHtml.replaceAll(_htmlStripTagsRE, ' ').trimLeft().stripLeading(title).trimLeft().replaceAll(_collapseWhitespaceRE, ' ').replaceAll(' .', '.').replaceAll(' ,', ',').replaceAll(' !', '!').replaceAll(' ?', '?').replaceAll(' ;', ';').truncateWithEllipsis(256);

    return meta;
  }
}

extension MyStream<T> on Stream<T> {
  Stream<T> ofType<T>() => this.where((fse) => fse is T).map((fse) => fse as T);
}

extension on String {
  int compareNoCase(String other) => this.toLowerCase().compareTo(other.toLowerCase());
  String stripLeading(String leading) => this.startsWith(leading) ? this.substring(leading.length) : this;
  String truncateWithEllipsis(int cutoff) => this.length > cutoff ? '${this.substring(0, cutoff)}...' : this;
}

extension on File {
  bool hasExtension(String ext) => pathutil.extension(this.path).compareNoCase(ext) == 0;
  bool get isMarkdown => this.hasExtension('.md');
  bool get isHtml => this.hasExtension('.html');
}
