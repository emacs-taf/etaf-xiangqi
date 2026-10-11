# Chu He · 中国象棋

Chinese chess (xiangqi) with a native ETAF board and the OpenSpiel rule
engine. Two players alternate hot-seat in one window: pick a stone, click a
highlighted point, and the bridge hands the turn to the other side. Legality,
check and history live in OpenSpiel; the application owns the board, both
palettes, selection and the move list.

This is an independent application. Its presentation, themes, tests and
launcher live here. GameKit supplies only the shared game instance and backend
connection.

## Install and play

Requires Emacs 29.1+, GameKit, ETAF and etaf-ui on `load-path`, and GameKit's
OpenSpiel runtime installed. Add this repository root to `load-path`:

```elisp
(require 'etaf-xiangqi)
(etaf-xiangqi-open)
```

Red moves first. Click a stone, then a highlighted point; or press one of the
legal moves listed beside the board. `U`/`Y` undo and redo, `N` starts a new
match, `T` switches between the paper and night palettes, `F1` opens the help
dialog and `Q` closes the match. Both palettes are supported; the theme switch
never resets the match.

The [manual](docs/manual.md) describes the board, window adaptation and
recovery. The [entry Commentary](etaf-xiangqi.el) owns the public API.
`make check` runs compilation, API and real-backend behavior checks.
