;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi.el --- Chinese chess (Xiangqi), a standalone GameKit application

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf-gamekit "0.1.0") (etaf-ui "0.1.0"))
;;; Commentary:
;; Chu He presents OpenSpiel's xiangqi rules on a native ETAF board with both
;; palettes and a hot-seat turn. Piece glyphs, selection and move hints are
;; presentation only; legality, check and history stay in OpenSpiel.
;;
;; Variable: etaf-xiangqi-game
;; Inert game definition usable with etaf-gamekit-start. Each instance owns an
;; independent match with red moving first. Override :seed in GameKit options
;; for a reproducible opening.
;;
;; Variable: etaf-xiangqi-appearance
;; Initial appearance for new instances: auto (default), light or dark. Auto
;; follows the opening frame's background mode. Each instance can switch
;; independently with the theme button or T without resetting the match.
;;
;; Function: etaf-xiangqi-open (&optional seed)
;;;###autoload (autoload 'etaf-xiangqi-open "etaf-xiangqi" nil t)
;; Open and display an independent match; return its GameKit instance. SEED is
;; an optional integer. Both sides are played hot-seat in one buffer: after a
;; move the bridge view switches to the side to move. Requires the OpenSpiel
;; runtime installed by GameKit. No snapshot is loaded implicitly.
;;
;; Function: etaf-xiangqi-close (&optional instance)
;;;###autoload (autoload 'etaf-xiangqi-close "etaf-xiangqi" nil t)
;; Close INSTANCE and its buffer. Omitted uses the current Xiangqi buffer.
;; No automatic save is performed; use the application's Save command first.
;;
;;; Code:
(require 'etaf-gamekit)
(require 'etaf-ui)
(defgroup etaf-xiangqi nil "Chu He xiangqi." :group 'games)
(defcustom etaf-xiangqi-appearance 'auto
  "Initial appearance of new Xiangqi instances."
  :type '(choice (const auto) (const light) (const dark)) :group 'etaf-xiangqi)
(defconst etaf-xiangqi--directory
  (file-name-directory (or load-file-name buffer-file-name)))
(let ((load-path (cons (expand-file-name "lisp" etaf-xiangqi--directory) load-path)))
  (require 'etaf-xiangqi-theme)
  (require 'etaf-xiangqi-model)
  (require 'etaf-xiangqi-views)
  (require 'etaf-xiangqi-app))
(provide 'etaf-xiangqi)
;;; etaf-xiangqi.el ends here
