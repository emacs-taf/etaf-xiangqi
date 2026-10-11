;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-theme.el --- Chu He board palettes

;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf)
(defconst etaf-xiangqi--light-theme
  '(:ui-bg "#F6F1E6" :ui-fg "#2B2A26" :ui-muted-fg "#7C776B"
    :ui-panel-bg "#FFFDF8" :ui-panel-fg "#2B2A26" :ui-panel-border "#E0D8C8"
    :ui-border "#E0D8C8" :ui-accent "#9C2E2A" :ui-accent-fg "#FFFFFF"
    :ui-button-primary-bg "#9C2E2A" :ui-button-primary-fg "#FFFFFF"
    :ui-button-secondary-bg "#ECE3D2" :ui-button-secondary-fg "#6A4A2A"
    :ui-button-ghost-fg "#6B6355" :ui-disabled-bg "#EFE9DC" :ui-disabled-fg "#ABA294"
    :ui-disabled-border "#E0D8C8" :ui-divider-bg "#E0D8C8"
    :ui-info-bg "#E7EEF5" :ui-info-fg "#3C6382" :ui-info-border "#CFDDE9"
    :ui-success-bg "#E6F0E5" :ui-success-fg "#3F7A4A" :ui-success-border "#CDDFCC"
    :ui-warning-bg "#F7EFD8" :ui-warning-fg "#8B6E2E" :ui-warning-border "#E7D9B4"
    :ui-danger-bg "#F9E7E4" :ui-danger-fg "#A63B34" :ui-danger-border "#EACBC6"
    :ui-progress-track "#E8E1D4"
    :xiangqi-board-bg "#EFE3C8" :xiangqi-board-alt-bg "#E9DBBC"
    :xiangqi-river-bg "#E0CEA8" :xiangqi-palace-bg "#E8D6B2"
    :xiangqi-red "#B2352C" :xiangqi-black "#2A2F36"
    :xiangqi-red-bg "#F1CFC9" :xiangqi-black-bg "#D3D9DF"
    :xiangqi-selected-bg "#F3D488" :xiangqi-target-bg "#BFDCC4"
    :xiangqi-last-bg "#E3C79F")
  "Paper and cinnabar palette for the Chu He board; it does not alter Emacs.")

(defconst etaf-xiangqi--dark-theme
  '(:ui-bg "#1B1F27" :ui-fg "#E7E3DA" :ui-muted-fg "#918B80"
    :ui-panel-bg "#242A34" :ui-panel-fg "#E7E3DA" :ui-panel-border "#333B47"
    :ui-border "#333B47" :ui-accent "#E4695E" :ui-accent-fg "#2A1110"
    :ui-button-primary-bg "#E4695E" :ui-button-primary-fg "#2A1110"
    :ui-button-secondary-bg "#333B47" :ui-button-secondary-fg "#E9B7A9"
    :ui-button-ghost-fg "#B9B2A6" :ui-disabled-bg "#242A34" :ui-disabled-fg "#6B7280"
    :ui-disabled-border "#333B47" :ui-divider-bg "#333B47"
    :ui-info-bg "#28323D" :ui-info-fg "#A8C6DF" :ui-info-border "#3A4B5C"
    :ui-success-bg "#263A2F" :ui-success-fg "#9ED3A8" :ui-success-border "#3C5A45"
    :ui-warning-bg "#3E352C" :ui-warning-fg "#E0CA96" :ui-warning-border "#5C503E"
    :ui-danger-bg "#402A2E" :ui-danger-fg "#F0A0A0" :ui-danger-border "#69414A"
    :ui-progress-track "#333B47"
    :xiangqi-board-bg "#2A313C" :xiangqi-board-alt-bg "#262D37"
    :xiangqi-river-bg "#1F262F" :xiangqi-palace-bg "#2F2A38"
    :xiangqi-red "#E4695E" :xiangqi-black "#C9D4DF"
    :xiangqi-red-bg "#473034" :xiangqi-black-bg "#37414D"
    :xiangqi-selected-bg "#5A4620" :xiangqi-target-bg "#2F5D46"
    :xiangqi-last-bg "#3A4150")
  "Night-aubergine palette with clear red and black stone contrasts.")

(defun etaf-xiangqi--color (token)
  "Read reactive TOKEN from this instance's scoped theme."
  (etaf-theme-token token (plist-get etaf-xiangqi--light-theme token)))
(provide 'etaf-xiangqi-theme)
;;; etaf-xiangqi-theme.el ends here
