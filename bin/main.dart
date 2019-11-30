import 'dart:io';
import 'dart:math';
import 'package:jiffy/jiffy.dart';
import 'package:path/path.dart' as pathutil;
import 'package:strings/strings.dart';
import 'package:webfeed/webfeed.dart';
import 'package:yaml/yaml.dart' as yaml;
import 'package:meta/meta.dart';
import 'package:markdown/markdown.dart';
import 'package:dartx/dartx.dart';
import 'arg_parser.dart';

main(List<String> args) async {
  final opts = ArgParser(args);
  var files = await opts.sourceDir.list(recursive: true).ofType<File>().where((f) => f.isMarkdown || f.isHtml).toList();
  var meta = (await Metadata.fromFiles(files, blurbLength: opts.blurbLength)).where((m) => !m.isDraft && !m.isPage).sortedByDescending((m) => m.date);
  var categories = [
    AtomCategory(term: 'interview', label: 'Interviewing'),
    AtomCategory(term: 'win8', label: 'Windows 8'),
    AtomCategory(term: 'spout', label: 'The Spout'),
    AtomCategory(term: 'oslofeaturedcontent', label: 'Oslo'),
    AtomCategory(term: 'osloeditorial', label: 'Oslo'),
    AtomCategory(term: '.net', label: '.NET'),
    AtomCategory(term: 'book', label: 'Books'),
    ...[
      'fun',
      'colophon',
      'books',
      'tools',
      'conference',
      'writing',
      'money',
      'data',
      'telerik',
      'oslo',
    ].map((s) => AtomCategory(term: s, label: capitalize(s)))
  ].sortedBy((m) => m.label);

  var feed = AtomFeed(
    id: Uri.parse('https://sellsbrothers.com'),
    title: 'Marquee de Sells',
    subtitle: 'Chris\'s insight outlet',
    updated: meta.first.date,
    icon: Uri.parse('http://blotcdn.com/blog_12688eba996c4a98b1ec3a945e78e4f1/_avatars/2daebd98-55ac-4462-b80d-a1bb7156ce67.jpg'), // TODO: non-Blot source
    logo: Uri.parse('http://blotcdn.com/blog_12688eba996c4a98b1ec3a945e78e4f1/_avatars/2daebd98-55ac-4462-b80d-a1bb7156ce67.jpg'), // TODO: non-Blot source
    authors: [
      AtomPerson(name: 'Chris Sells', uri: Uri.parse('https://sellsbrothers.com'), email: 'csells@sellsbrothers.com'),
    ],
    categories: categories,
    links: [
      AtomLink(rel: 'alternate', href: Uri.parse('https://sellsbrothers.com/feed.rss'), type: 'application/rss+xml'),
      AtomLink(rel: 'alternate', href: Uri.parse('https://sellsbrothers.com/feed.atom'), type: 'application/atom+xml'),
      // TODO: pagination links
    ],
    rights: 'Copyright © 1995 - ${DateTime.now().year}',
    items: meta
        .take(opts.pageSize)
        .map(
          (m) => AtomItem(
            id: m.permalink,
            title: m.title,
            categories: m.tags == null ? null : m.tags.map((t) => categories.firstWhere((c) => c.term == t)).toList(),
            published: m.date,
            updated: m.date,
            summary: AtomContent(text: m.blurb),
            content: AtomContent(text: m.file.isHtml ? m.file.readAsStringSync() : markdownToHtml(m.file.readAsStringSync())),
            links: itemLinks(m),
          ),
        )
        .toList(),
  );

  print(feed.toXml().toXmlString(pretty: true));
}

List<AtomLink> itemLinks(Metadata m) => m.image == null
    ? null
    : [
        AtomLink(rel: 'enclosure', type: mimetypeOf(m.image), href: m.image)
      ];

String mimetypeOf(Uri image) {
  var ext = pathutil.extension(image.pathSegments.last).toLowerCase();
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpg';
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    default:
      throw Exception('unknown image extesion: $ext');
  }
}

class Metadata {
  final File file;
  final String title;
  final String blurb;
  final Uri image;
  final DateTime date;
  final Uri permalink;
  final Uri disqus;
  final List<String> tags;
  final bool isPage;
  final bool isDraft;
  final int bodyStartLine;

  Metadata({
    @required this.file,
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

  static Future<List<Metadata>> fromFiles(Iterable<File> files, {int blurbLength}) async {
    var metadata = List<Metadata>();
    for (var file in files) metadata.add(await Metadata.fromFile(file, blurbLength: blurbLength));
    return metadata;
  }

  static final _baseUrl = 'https://sellsbrothers.com/';
  static String permaFromTitle(String title) => title.toLowerCase().replaceAll(' ', '-');

  static Future<Metadata> fromFile(File file, {int blurbLength}) async {
    final meta = await _getMetadataFromFile(file, blurbLength: blurbLength);
    final permalink = Uri.parse(_baseUrl + (meta.containsKey('Permalink') ? meta['Permalink'] : permaFromTitle(meta['Title'])));

    return Metadata(
      file: file,
      title: meta['Title'],
      blurb: meta['Blurb'],
      image: meta.containsKey('Image') ? Uri.parse(meta['Image']) : null,
      date: meta.containsKey('Date') ? Jiffy(meta['Date'], 'MM/dd/yyy').utc() : (await file.stat()).changed.toUtc(),
      permalink: permalink,
      disqus: meta.containsKey('Disqus') ? Uri.parse(meta['Disqus']) : permalink,
      tags: meta.containsKey('Tags') ? meta['Tags'].split(',') : null,
      isPage: meta.containsKey('Page') ? meta['Page'] == 'yes' : false,
      isDraft: pathutil.basenameWithoutExtension(file.path).toLowerCase().contains('[draft]'),
      bodyStartLine: int.parse(meta['BodyStartLine']),
    );
  }

  static final _htmlImgRE = RegExp(r'<img(\s|[^>])*src=[' '"](?<src>[^' '"]*)[' '"]', multiLine: true);
  static final _htmlH1RE = RegExp(r'<h1>(?<title>[^<]*)<\/h1>');
  static final _mdH1RE = RegExp(r'^#(?<title>.*$)', multiLine: true);
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
  static Future<Map<String, String>> _getMetadataFromFile(File file, {int blurbLength}) async {
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
    final someContent = body.substring(0, min(body.length, blurbLength * 2));
    final someHtml = file.isHtml ? someContent : markdownToHtml(someContent);
    meta['Blurb'] = someHtml.replaceAll(_htmlStripTagsRE, ' ').trimLeft().stripLeading(title).trimLeft().replaceAll(_collapseWhitespaceRE, ' ').replaceAll(' .', '.').replaceAll(' ,', ',').replaceAll(' !', '!').replaceAll(' ?', '?').replaceAll(' ;', ';').truncateWithEllipsis(blurbLength);

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
