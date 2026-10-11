# Chu He · 中国象棋

Chu He is a standalone GameKit application. It presents the OpenSpiel xiangqi
rule set on a native ETAF board with both palettes and a hot-seat turn. The
application owns its presentation, colors, launcher and tests; it uses only
public GameKit, ETAF and catalog APIs.

Install GameKit, ETAF, etaf-ui and GameKit's OpenSpiel runtime, then add the
application directory to `load-path`:

```elisp
(add-to-list 'load-path "/path/to/etaf-games/etaf-xiangqi")
(require 'etaf-xiangqi)
(etaf-xiangqi-open)
```

`etaf-xiangqi-game` is a game definition. `etaf-xiangqi-open` starts an
independent OpenSpiel match, displays its buffer and fits the view to its
window. `etaf-xiangqi-open` accepts an optional integer seed for a reproducible
opening. The application's [entry Commentary](../etaf-xiangqi.el) describes its
public API.

Red (bottom) moves first; the two sides alternate hot-seat in one window. After
every accepted move the bridge view switches to the side to move, and the legal
move list follows. OpenSpiel owns legality, check, repetition and history; the
application never re-implements a move.

| Input | Action |
| --- | --- |
| Click a stone / Enter | Select it and highlight its legal targets |
| Click a highlighted point | Submit that native move |
| 走法 → select a move | Open the legal moves dialog and submit that move directly |
| U / Y | Undo or redo a move; the turn follows the restored position |
| N / New match | Start a fresh match with a random seed |
| C-s / C-o | Save or load an explicit local snapshot |
| T / Light–Dark | Switch between the paper and night palettes |
| F1 / Help | Open the rules dialog |
| Q | Close the match |

`etaf-xiangqi-appearance` selects the initial palette: `auto` (the default)
follows the frame's background mode, or set `light`/`dark` before calling
`etaf-xiangqi-open`. Switching the palette at runtime repaints the board and
never resets the match.

The board is the primary surface, with compact controls above it. Legal moves
are marked by dots (empty intersections) or rings (captures); **走法** opens
an optional list instead of taking permanent space beside the board. A solid
jade ring identifies the selected stone; a dotted ring identifies keyboard
focus. Arrow keys move focus, Enter selects or moves, and Escape first closes
an open dialog, then clears selection on the next press.

Graphical Emacs with SVG support renders an intersection lattice, river and
palaces with circular ivory stones. Each intersection is a native ETAF tile,
not a screenshot with a separate hit-testing overlay. The image Host divides
its artwork into ordinary text rows, preserving line height and keyboard input.
Terminals use named text cells with the same native rules and activation paths.

Cell dimensions are chosen once from the opening frame's metrics: three text
rows, and the nearest character width to a square. A typical 7 × 16 pixel font
uses 49 × 48 pixel cells, making the board 441 × 480 pixels. Resizing does not
stretch or replace the stones. Short windows remove vertical gaps and padding;
at those metrics the complete compact table needs 67 columns × 34 rows.
Below that minimum the board stays anchored at the left and may be clipped or
scrolled. Closing makes no implicit save.

For GUI acceptance, load ETAF's `scripts/emacs-gui-verifier.el` and this
application's `scripts/etaf-xiangqi-gui-scenarios.el` in a dedicated graphical
Emacs, then run `etaf-xiangqi-gui-run` with a fresh evidence directory. It covers
both themes, fixed metrics across viewport sizes, native keys, dialogs and
history. Inspect the saved screenshots; functional assertions alone do not
certify appearance. `benchmarks/performance-scenarios.el` registers selection,
theme and resize workloads for the enclosing workspace's performance driver.
