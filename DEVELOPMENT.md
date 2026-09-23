# Development

Notes for working on neotoolkit itself. Consumers of the library need only
[README.md](README.md).

## Tests

```sh
make test
make test BUSTED_ARGS="--filter=crop_for_ui -o gtest"
```

Specs run under busted with `nlua`, so they execute inside Neovim and can use
the `vim` API. busted and nlua install into a gitignored project-local luarocks
tree (`.luarocks`) on first run. `tests/init.lua` prepends the repo to
`runtimepath` and `package.path` and restores what `-u NONE` omits.

## Documentation

`doc/neotoolkit.txt` is generated from `README.md` with panvimdoc. Edit the
README, never the help file.

```sh
scripts/gendoc.sh           # rewrite doc/neotoolkit.txt and doc/tags
scripts/gendoc.sh --check   # exit 1 when the help file is out of date
```

Needs pandoc; panvimdoc is fetched and cached at a pinned commit on first run.

Section help tags come from a hidden comment on the heading:
`## neotoolkit.ui <!-- tag: ui -->` yields `*neotoolkit-ui*`. Without one, the
tag is derived from the heading text, which for a module heading gives
`*neotoolkit-neotoolkit.ui*`.

Markdown with no place in a help file goes between
`<!-- panvimdoc-ignore-start -->` and `<!-- panvimdoc-ignore-end -->`;
help-file-only text goes in a `<!-- vimdoc-only … -->` comment.

### Table widths

Help-file table columns are sized from the dash counts in each separator row,
scaled to 72 columns — a `| --- |` separator therefore gives pandoc nothing to
scale by. A column is never narrower than its widest unbreakable atom, and a
`code span` is one atom, so a cell holding a single long signature widens the
whole table past 78 columns. Split such a cell into two spans, or move the
signature into the prose below the table.

After editing a table, check the result:

```sh
scripts/gendoc.sh && awk 'length($0) > 79' doc/neotoolkit.txt
```
