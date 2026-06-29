# pastes

Personal pastebin backed by this repository, GitHub raw file hosting, and a
small GitHub Pages viewer.

Text pastes and image pastes are committed to `main`.  GitHub Pages is served
from `gh-pages` and contains only the static viewer app at:

```text
https://trevs.site/pastes/
```

Normal paste publishing only pushes a raw file to `main`; it does not need a
Pages rebuild or CI run.

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

- Text payloads are written under `r/`, for example `r/a16ac49e.el`.
- Image payloads are written under `i/`, for example `i/1d85128b.png`.

Public URLs are viewer routes:

```text
https://trevs.site/pastes/#/t/a16ac49e.el
https://trevs.site/pastes/#/i/1d85128b.png
```

The viewer on `gh-pages` fetches the corresponding raw file from `main`.

## Cleanup

Deletion and history flattening are best-effort public cleanup only.  Once
content has been pushed to GitHub or GitHub Pages, treat it as exposed.

Old direct HTML paste URLs are no longer generated, but deletion still accepts
them when possible so stale URLs can be cleaned up from the live snapshot.
