A CLI for generating static content from github.com/csells/sb-blot to github.com/csells/sb6.

## Usage
```bash
$ git clone https://github.com/csells/sb-blot
$ git clone https://github.com/csells/sb6
$ dart sb_sgen/bin/main.dart --source-dir sb-blot --target-dir sb6 --base-url https://csells.github.io/sb6/
$ cd sb6
$ git add *
$ git commit -m 'something useful'
$ git push
```