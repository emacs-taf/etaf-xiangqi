;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-model.el --- Decode public xiangqi observations for presentation

;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'etaf-gamekit)

(defconst etaf-xiangqi--glyphs
  '((?R . "俥") (?H . "傌") (?E . "相") (?A . "仕") (?G . "帥") (?C . "炮") (?S . "兵")
    (?r . "車") (?h . "馬") (?e . "象") (?a . "士") (?g . "將") (?c . "砲") (?s . "卒"))
  "Display glyphs for the OpenSpiel xiangqi piece letters.")

(defun etaf-xiangqi--glyph (char)
  "Return the display glyph for piece CHAR, or nil."
  (cdr (assq char etaf-xiangqi--glyphs)))

(defun etaf-xiangqi--side (char)
  "Return the side of piece CHAR: `red' or `black'."
  (when char (if (eq (downcase char) char) 'black 'red)))

(defun etaf-xiangqi--name (char)
  "Return an accessible name for piece CHAR."
  (when char
    (concat (pcase (etaf-xiangqi--side char) ('red "红") ('black "黑"))
            (or (etaf-xiangqi--glyph char) (char-to-string char)))))

(defun etaf-xiangqi--coord (row column)
  "Return the coordinate cons for ROW and COLUMN."
  (cons row column))

(defun etaf-xiangqi--parse-move (label)
  "Parse a public move LABEL such as S(6,0)-(5,0) into a move plist."
  (when (and (stringp label)
             (string-match "\\`[A-Za-z](\\([0-9]+\\),\\([0-9]+\\))-(\\([0-9]+\\),\\([0-9]+\\))" label))
    (list :from (etaf-xiangqi--coord (string-to-number (match-string 1 label))
                                     (string-to-number (match-string 2 label)))
          :to (etaf-xiangqi--coord (string-to-number (match-string 3 label))
                                   (string-to-number (match-string 4 label))))))

(defun etaf-xiangqi--table (view)
  "Project the public OpenSpiel xiangqi VIEW without re-implementing rules."
  (when-let* ((text (plist-get view :observation))
              (rows (and (stringp text) (split-string text "\n")))
              ((= (length rows) 10))
              ((cl-every (lambda (row) (= (length row) 9)) rows)))
    (list :rows rows
          :moves (delq nil
                       (mapcar (lambda (action)
                                 (when-let* ((move (etaf-xiangqi--parse-move (plist-get action :label))))
                                   (append move (list :id (plist-get action :id)
                                                      :label (plist-get action :label)))))
                               (plist-get view :legal_actions)))
          :side (if (= (or (plist-get view :current_player) 0) 0) 'red 'black)
          :player (plist-get view :player)
          :count (or (plist-get view :action_count) 0)
          :can-undo (eq t (plist-get view :can_undo))
          :can-redo (eq t (plist-get view :can_redo))
          :terminal (eq t (plist-get view :terminal)))))

(defun etaf-xiangqi--cell (table row column)
  "Return the piece char at ROW/COLUMN in TABLE, or nil for an empty point."
  (when-let* ((rows (plist-get table :rows)))
    (let ((line (nth row rows)))
      (when (and line (< column (length line)) (not (= (aref line column) ?.)))
        (aref line column)))))

(defun etaf-xiangqi--froms (table)
  "Return every source coordinate that has a native legal move in TABLE."
  (delete-dups (mapcar (lambda (move) (plist-get move :from)) (plist-get table :moves))))

(defun etaf-xiangqi--targets (table coord)
  "Return every legal target coordinate from COORD in TABLE."
  (delq nil (mapcar (lambda (move) (when (equal coord (plist-get move :from))
                                     (plist-get move :to)))
                    (plist-get table :moves))))

(defun etaf-xiangqi--move (table from to)
  "Return the native move in TABLE going from FROM to TO, or nil."
  (cl-find-if (lambda (move) (and (equal from (plist-get move :from))
                                  (equal to (plist-get move :to))))
              (plist-get table :moves)))

(defun etaf-xiangqi--row-label (row)
  "Return the Chinese file label for ROW, red at the bottom."
  (format "%s%d" (if (< row 5) "黑" "红") (- 10 row)))

(defun etaf-xiangqi--send (session selected operation &optional arguments)
  "Send OPERATION and clear caller-owned SELECTED when the instance is ready."
  (when (eq (etaf-gamekit-status session) 'ready)
    (etaf-gamekit-action session operation arguments)
    (setf (etaf-value selected) nil)))

(defun etaf-xiangqi--press (session selected table coord)
  "Choose the piece at COORD or submit the native move from the current selection."
  (let ((move (etaf-xiangqi--move table (etaf-value selected) coord)))
    (cond
     (move (etaf-xiangqi--send session selected "act" (list :action (plist-get move :id))))
     ((equal (etaf-value selected) coord) (setf (etaf-value selected) nil))
     ((cl-find coord (etaf-xiangqi--froms table) :test #'equal) (setf (etaf-value selected) coord))
     (t (setf (etaf-value selected) nil)))))

(defun etaf-xiangqi--snapshot (session selected operation)
  "Choose an explicit snapshot file for OPERATION."
  (let ((file (etaf-call-with-input
               (lambda () (read-file-name (concat (capitalize operation) " match: ")
                                          nil nil (equal operation "load") "xiangqi.json")))))
    (when file (etaf-xiangqi--send session selected operation (list :path (expand-file-name file))))))

(provide 'etaf-xiangqi-model)
;;; etaf-xiangqi-model.el ends here
