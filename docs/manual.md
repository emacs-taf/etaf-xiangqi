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
| Click a legal move button | Submit that move directly |
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

The board is a fixed 9 × 10 grid of two-column stones. Resizing reflows the
side panel without stretching the board. Wide windows keep the move panel
beside the board; narrow windows move it into the **棋谱** dialog. The minimum
canvas is 76 character columns by 26 rows; smaller windows clip or scroll that
canvas with soft wrapping disabled. Closing makes no implicit save.

For GUI acceptance, load ETAF's `scripts/emacs-gui-verifier.el` with a dedicated
graphical Emacs and observe `xiangqi-board` and `xiangqi-theme` through the
public host refs. Inspect screenshots for both palettes; functional assertions
alone do not certify appearance.
