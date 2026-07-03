In EWW, page content is rendered as formatted Emacs text, not a raw
HTML dump. When visual-line-mode is on, line wrapping is driven by the
window width at render time, and EWW's output interacts with that in
ways that look "random":

1. EWW pre-wraps some blocks itself. EWW converts HTML to a buffer
   using shr (Simple HTML Renderer). For many elements (<pre>, table
   cells, and sometimes <p> with shr-width set), shr hard-wraps text
   to a fixed width at render time, inserting real
   newlines. visual-line-mode then wraps those already-broken lines
   again against the current window width. So you get a mix of shr's
   logical line breaks (fixed at render width) and visual-line-mode's
   wrapping (current window width). If the window was a different
   width when the page rendered than it is now, breaks land at odd
   spots.
2. Render width vs. display width mismatch. shr uses shr-width (often
   window-width or fill-column) at the time of rendering. Resize the
   window or split it after loading, and the shr-broken lines no
   longer match the window. visual-line-mode fills around them,
   producing short/ragged lines that look arbitrary.
3. Inline elements and whitespace collapse. shr collapses whitespace
   per HTML rules but keeps soft newlines around block boundaries,
   images, and links. Those become break opportunities that
   visual-line-mode fills to, again at unpredictable columns.
4. Non-breaking spaces and CJK/emoji width miscalculations. nbsp and
   wide characters can throw off the column math, causing a line to
   wrap early or a paragraph to break mid-thought.

Practical fixes:

- Re-render at the current width: M-x eww-reload (or g) after sizing
  the window. That regenerates shr's breaks for the current
  window-width.
- Set a stable render width independent of the window:
(setq shr-width 80)          ; or your preferred fill column
- shr will then wrap to 80 regardless of window size, and
  visual-line-mode just respects those lines.
- If you don't want shr's own wrapping at all, force only visual
  wrapping:
(setq shr-width -1)         ; don't pre-wrap; let visual-line-mode do it
- Then resizing the window reflows cleanly because there are no
  embedded hard breaks to fight. This is usually the cleanest answer
  for "reading in EWW."

The "random" breaks you see are essentially shr's render-time wrapping
(frozen at an old window width) clashing with visual-line-mode's live
wrapping. shr-width -1 + visual-line-mode removes the conflict.
