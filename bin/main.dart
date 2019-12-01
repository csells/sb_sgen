import 'dart:convert';
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
import 'options.dart';

main(List<String> args) async => await SiteGenerator(Options.fromArgs(args)).generateSite();

class FileInfo {
  final File file; // generated file
  final String title; // first '# title' or first '<h1>title</h1>'
  final String blurb; // the first few lines of content in plain text
  final Uri image; // primary image (aka first image)
  final DateTime date; // metadata or file date (UTC)
  final Uri permalink; // metadata or base filename no extension
  final Uri disqus; // metadata or Permalink
  final List<String> tags; // metadata or nothing
  final bool feed; // whether to feed the file or not (non-draft, non-page HTML file)

  FileInfo({
    @required this.file,
    this.title,
    this.blurb,
    this.image,
    this.date,
    this.permalink,
    this.disqus,
    this.tags,
    bool feed,
  }) : this.feed = feed == null ? false : feed;
}

class SiteGenerator {
  final Options options;
  SiteGenerator(this.options);

  void generateSite() async {
    // generate the site, getting the files that need to be part of the feed
    var feedFiles = List<FileInfo>();
    var files = await options.sourceDir.list(recursive: true).ofType<File>().toList();
    for (var file in files) {
      var info = await _generateFile(file);
      if (info.feed) {
        assert(info.file.isHtml); // should only be feeding HTML files
        feedFiles.add(info);
      }
    }
    feedFiles.sort((lhs, rhs) => rhs.date.compareTo(lhs.date));

    // atom feed categories
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

    // generate the first page of the feed
    // TODO: generate the rest of the feed pages, too
    var atom = AtomFeed(
      id: Uri.parse(_baseUrl),
      title: 'Marquee de Sells',
      subtitle: 'Chris\'s insight outlet',
      updated: feedFiles.first.date,
      // TODO: non-Blot source
      // icon: Uri.parse('http://blotcdn.com/blog_12688eba996c4a98b1ec3a945e78e4f1/_avatars/2daebd98-55ac-4462-b80d-a1bb7156ce67.jpg'),
      // logo: Uri.parse('http://blotcdn.com/blog_12688eba996c4a98b1ec3a945e78e4f1/_avatars/2daebd98-55ac-4462-b80d-a1bb7156ce67.jpg'),
      authors: [
        AtomPerson(name: 'Chris Sells', uri: Uri.parse(_baseUrl), email: 'csells@sellsbrothers.com'),
      ],
      categories: categories,
      links: [
        AtomLink(rel: 'self', href: Uri.parse('$_baseUrl/atom.feed')),
        // TODO: pagination links
      ],
      rights: 'Copyright © 1995 - ${DateTime.now().year}',
      items: feedFiles
          .where((i) => i.feed)
          .take(options.pageSize)
          .map(
            (m) => AtomItem(
              id: m.permalink,
              title: m.title,
              categories: m.tags == null ? null : m.tags.map((t) => categories.firstWhere((c) => c.term == t)).toList(),
              published: m.date,
              updated: m.date,
              summary: AtomContent(text: m.blurb),
              content: AtomContent(type: 'html', text: m.file.readAsStringSync()),
              links: itemLinks(m),
            ),
          )
          .toList(),
    );

    // write the atom feed
    var atomfile = File(pathutil.join(options.targetDir.path, 'feed.atom'));
    await Directory(pathutil.dirname(atomfile.path)).create(recursive: true);
    await atomfile.writeAsString(atom.toXml().toXmlString(pretty: true));
  }

  // TODO: remove (local debugging)
  static final _baseUrl = 'http://localhost:8080/';
  //static final _baseUrl = 'https://sellsbrothers.com/';

  static final _imgRE = RegExp(r'<img(\s|[^>])*src=[' '"](?<src>[^' '"]*)[' '"]', multiLine: true);
  static final _h1RE = RegExp(r'<h1>(?<title>[^<]*)<\/h1>');
  static final _stripTagsRE = RegExp(r'<[^>]+>', multiLine: true);
  static final _collapseWhitespaceRE = RegExp(r'\s\s+');

  static String permaFromTitle(String title) => title.toLowerCase().replaceAll(' ', '-');

  List<AtomLink> itemLinks(FileInfo m) => m.image == null
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

  Future<FileInfo> _generateFile(File sourcefile) async {
    // calculate target file name
    final relativeSourcepath = pathutil.relative(sourcefile.path, from: options.sourceDir.path);
    var relativeTargetpath = relativeSourcepath;
    var targetfile = File(pathutil.absolute(options.targetDir.path, relativeTargetpath));

    // just copy the first if it's not a content file
    if (!sourcefile.isHtml && !sourcefile.isMarkdown) {
      await copyIfNewer(sourcefile: sourcefile, targetfile: targetfile);
      return FileInfo(file: targetfile);
    }

    // if it's a draft content file, don't do anything with it
    final isDraft = pathutil.basenameWithoutExtension(sourcefile.path).toLowerCase().contains('[draft]');
    if (isDraft) return FileInfo(file: sourcefile);

    // read content from source
    final lines = await sourcefile.readAsLines();
    final metadataLines = List<String>();
    var bodyStartLine = 0;

    // TODO: remove (local debugging)
    for (var i = 0; i != lines.length; ++i) {
      lines[i] = lines[i].replaceAll(RegExp(r'https?:\/\/w*\.?sellsbrothers.com\/'), 'http://127.0.0.1:8080/');
    }

    if (sourcefile.isHtml) {
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
    } else {
      assert(sourcefile.isMarkdown);
      /* Markdown metadata example
      Date: 11/12/2017

      <img ... />
      # WebAssembly *explodes* client-side programming
      ...
      */
      final metalines = lines.map((l) => l.trim()).takeWhile((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('<'));
      metadataLines.addAll(metalines);
      bodyStartLine = metalines.length + 1;

      // change target file from .md to .html extension
      relativeTargetpath = pathutil.withoutExtension(relativeSourcepath) + '.html';
      targetfile = File(pathutil.absolute(options.targetDir.path, relativeTargetpath));
    }

    // grab "name: value" pairs
    final meta = Map<String, String>();
    if (metadataLines.isNotEmpty) {
      final map = yaml.loadYaml(metadataLines.join('\n')) as yaml.YamlMap;
      for (var key in map.keys) meta[key] = map[key].toString();
    }

    // get content in HTML
    var body = lines.skip(bodyStartLine).join('\n');
    var html = sourcefile.isMarkdown ? markdownToHtml(body) : body;

    // create target file if it's newer
    await writeAsStringIfNewer(sourcefile: sourcefile, targetfile: targetfile, html: html);

    // grab title
    var title = _h1RE.firstMatch(html)?.namedGroup('title')?.trim();
    if (title == null) title = lines.skip(bodyStartLine).take(1).first;
    assert(title != null && title.isNotEmpty);
    meta['Title'] = title;

    // grab image
    var image = _imgRE.firstMatch(body)?.namedGroup('src');
    if (image != null) meta['Image'] = image;
    assert(meta['Image'] != null || !body.contains('<img'));

    // grab the blurb
    final someContent = body.substring(0, min(body.length, options.blurbLength * 2));
    final someHtml = sourcefile.isHtml ? someContent : markdownToHtml(someContent);
    meta['Blurb'] = someHtml.replaceAll(_stripTagsRE, ' ').trimLeft().stripLeading(title).trimLeft().replaceAll(_collapseWhitespaceRE, ' ').replaceAll(' .', '.').replaceAll(' ,', ',').replaceAll(' !', '!').replaceAll(' ?', '?').replaceAll(' ;', ';').truncateWithEllipsis(options.blurbLength);

    final permalink = Uri.parse(_baseUrl + (meta.containsKey('Permalink') ? meta['Permalink'] : permaFromTitle(meta['Title'])));
    final isPage = meta.containsKey('Page') ? meta['Page'] == 'yes' : false;

    return FileInfo(
      file: targetfile,
      title: meta['Title'],
      blurb: meta['Blurb'],
      image: meta.containsKey('Image') ? Uri.parse(meta['Image']) : null,
      date: meta.containsKey('Date') ? Jiffy(meta['Date'], 'MM/dd/yyy').utc() : (await sourcefile.stat()).changed.toUtc(),
      permalink: permalink,
      disqus: meta.containsKey('Disqus') ? Uri.parse(meta['Disqus']) : permalink,
      tags: meta.containsKey('Tags') ? meta['Tags'].split(',') : null,
      feed: !isPage, // pages are just copied to the target folder w/o putting them into the feed
    );
  }

  // only copy if the target file doesn't exist or the source file is newer
  void copyIfNewer({File sourcefile, File targetfile}) async {
    var sourcestat = await sourcefile.stat();
    var targetstat = await targetfile.stat();

    stdout.write('${sourcefile.path} => ${targetfile.path}...');
    if ((targetstat.type == FileSystemEntityType.notFound || sourcestat.modified.isAfter(targetstat.modified)) && !sourcefile.path.contains('/.git/')) {
      // TODO: remove (local debugging)
      if (targetfile.isHtml) {
        assert(sourcefile.isHtml); // shouldn't be copying md files...
        var html = (await sourcefile.readAsString()).replaceAll(RegExp(r'https?:\/\/w*\.?sellsbrothers.com\/'), 'http://127.0.0.1:8080/');
        await writeAsStringIfNewer(sourcefile: sourcefile, targetfile: targetfile, html: html);
        return;
      }

      await Directory(pathutil.dirname(targetfile.path)).create(recursive: true);
      await sourcefile.copy(targetfile.path);
      print('copied');
    } else {
      print('skipped');
    }
  }

  // only write the contents if the target file doesn't exist or the source file is newer
  void writeAsStringIfNewer({File sourcefile, File targetfile, String html}) async {
    var sourcestat = await sourcefile.stat();
    var targetstat = await targetfile.stat();

    stdout.write('${sourcefile.path} => ${targetfile.path}...');
    if ((targetstat.type == FileSystemEntityType.notFound || sourcestat.modified.isAfter(targetstat.modified)) && !sourcefile.path.contains('/.git/')) {
      await Directory(pathutil.dirname(targetfile.path)).create(recursive: true);
      await targetfile.writeAsString(html);
      print('written');
    } else {
      print('skipped');
    }
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
