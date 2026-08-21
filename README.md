# pastes

Personal pastebin backed by this repository, GitHub raw file hosting, and a
small GitHub Pages viewer.

Text and image pastes are committed to `main`. The viewer source lives on
`gh-pages` and is deployed with generated fallback pages at:

```text
https://trevs.site/pastes/
```

JavaScript browsers are redirected from each fallback page to the existing
viewer. Non-JavaScript browsers are redirected to the raw GitHub payload.

## Emacs package

The Emacs frontend package lives in `elisp/` and can be installed directly from
this repo:

```elisp
(use-package pastes
  :vc (:url "git@github.com:trevarj/pastes.git"
       :branch "main"
       :lisp-dir "elisp"
       :main-file "pastes.el"
       :rev :newest)
  :commands (pastes-setup
             pastes-region
             pastes-buffer
             pastes-file
             pastes-clipboard-image
             pastes-delete-url))
```

Run `M-x pastes-setup` once to verify or clone the local checkout used for
publishing.  The default checkout is `~/Workspace/pastes`.

## Commands

- `pastes-region`: preview and publish the active region.
- `pastes-buffer`: preview and publish the current buffer.
- `pastes-file`: preview and publish a text or image file.
- `pastes-clipboard-image`: preview and publish a PNG image from the clipboard.
- `pastes-delete-url`: remove a paste from the current live snapshot.

Preview buffers use `pastes-preview-mode`, so they can be closed with `q`.

Clipboard image publishing tries `wl-paste`, `xclip`, and `pngpaste`, in that
order.

## Storage and URLs

The `main` branch stores the package and raw paste payloads:

- Text payloads are written under `r/`, for example `r/shell-byte-patch.el`.
- Image payloads are written under `i/`, for example `i/shell-byte-patch.png`.
- Paste creation timestamps are recorded in `.pastes-manifest`.
- New paste names use human-friendly three-word slugs, for example
  `shell-byte-patch`.

Public URLs enter through generated fallback pages:

```text
https://trevs.site/pastes/t/shell-byte-patch.el.html
https://trevs.site/pastes/i/shell-byte-patch.png.html
```

The Pages deployment workflow combines the viewer from `gh-pages` with
fallback pages generated from current `main` payloads, then deploys the result
through GitHub Actions.

## Cleanup

Deletion and history flattening are best-effort public cleanup only.  Once
content has been pushed to GitHub or GitHub Pages, treat it as exposed.

The monthly cleanup workflow removes text and image paste payloads whose
manifest timestamps are at least 30 days old.

Deletion still accepts old hash routes and legacy HTML URLs when possible so
stale URLs can be cleaned up from the live snapshot.
