import 'dart:io';
import 'package:path/path.dart' as pathutil;

extension on String {
  int compareNoCase(String other) => this.toLowerCase().compareTo(other.toLowerCase());
}

main(List<String> args) async {
  var dir = '/Users/csells/Code/sb-blot';
  var files = await Directory(dir).list(recursive: true).where((fse) => isMarkdownFile(fse) || isHtmlFile(fse)).toList();
  for (var file in files) {
    print(file);
  }
}

bool isMarkdownFile(FileSystemEntity fse) => fse is File && pathutil.extension(fse.path).compareNoCase('.md') == 0;
bool isHtmlFile(FileSystemEntity fse) => fse is File && pathutil.extension(fse.path).compareNoCase('.html') == 0;

// TODO: pull out metadata for each file
// Title: first '# title' or first '<h1>title</h1>'
// Date: metadata or file date
// Permalink: metadata or ???
// Disqus: metadata or ???
// Tags: metadata or nothing

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

/* Markdown metadata example
Date: 11/12/2017

# WebAssembly *explodes* client-side programming
...
*/
