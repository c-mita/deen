# deen

A command line tool to lookup English definitions of German words. A "de-en" dictionary.

The primary purpose is to provide me with a quick command-line dictionary with which I can use
tab-completion to look up German words. My German skills are still very much a "Work in Progress".

deen is meant to load very quickly. To that end, the dictionary is preprocessed into a prefix-trie
and embedded into the binary itself. A release build is ~46 MB as of writing.

## Wiktionary definitions

Word definitions originate from my favourite "German to English" website - en.wiktionary.org.

The actual data comes from https://kaikki.org/dictionary/rawdata.html.

The https://github.com/tatuylonen/wiktextract project describes the JSONL file used by this project.

## Zig version

The code was written for, and compiles with, zig version 0.15.2.
