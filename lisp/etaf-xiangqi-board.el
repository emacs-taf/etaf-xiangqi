;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-board.el --- Vector artwork for native interactive intersections
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-ui)
(require 'etaf-xiangqi-model)

(defun etaf-xiangqi--board-metrics ()
  "Choose fixed cell metrics once for the opening display, never on resize."
  (if (and (display-graphic-p) (image-type-available-p 'svg))
      (let* ((height (* 3 (frame-char-height)))
             (columns (max 3 (round (/ (float height) (frame-char-width))))))
        (list :columns columns :lines 3
              :width (* columns (frame-char-width)) :height height :graphic t))
    '(:columns 4 :lines 1 :width 40 :height 40 :graphic nil)))

(defun etaf-xiangqi--board-lines (palette width height)
  "Draw the full intersection lattice in PALETTE with WIDTH/HEIGHT pitch."
  (let ((paper (plist-get palette :xq-paper))
        (line (plist-get palette :xq-line))
        (edge (plist-get palette :xq-edge))
        (river (plist-get palette :xq-river))
        (x0 (/ width 2.0)) (y0 (/ height 2.0)) parts)
    (push (format "<rect width='%d' height='%d' fill='%s'/>" (* 9 width) (* 10 height) paper) parts)
    (push (format "<rect x='5' y='5' width='%d' height='%d' rx='9' fill='none' stroke='%s' stroke-width='1.2'/>"
                  (- (* 9 width) 10) (- (* 10 height) 10) edge) parts)
    (push (format "<g fill='none' stroke='%s' stroke-width='.85'>" line) parts)
    (dotimes (r 10)
      (push (format "<path d='M%.2f %.2f H%.2f'/>" x0 (+ y0 (* r height)) (+ x0 (* 8 width))) parts))
    (dotimes (c 9)
      (let ((x (+ x0 (* c width))))
        (push (if (memq c '(0 8))
                  (format "<path d='M%.2f %.2f V%.2f'/>" x y0 (+ y0 (* 9 height)))
                (format "<path d='M%.2f %.2f V%.2f M%.2f %.2f V%.2f'/>"
                        x y0 (+ y0 (* 4 height)) x (+ y0 (* 5 height)) (+ y0 (* 9 height)))) parts)))
    (dolist (r '(0 7))
      (push (format "<path d='M%.2f %.2f L%.2f %.2f M%.2f %.2f L%.2f %.2f'/>"
                    (+ x0 (* 3 width)) (+ y0 (* r height)) (+ x0 (* 5 width)) (+ y0 (* (+ r 2) height))
                    (+ x0 (* 5 width)) (+ y0 (* r height)) (+ x0 (* 3 width)) (+ y0 (* (+ r 2) height))) parts))
    ;; Traditional cannon and soldier placement marks; these are board artwork.
    (dolist (site '((2 1) (2 7) (7 1) (7 7) (3 0) (3 2) (3 4) (3 6) (3 8)
                   (6 0) (6 2) (6 4) (6 6) (6 8)))
      (let ((x (+ x0 (* (cadr site) width))) (y (+ y0 (* (car site) height))))
        (dolist (dx '(-1 1))
          (unless (or (and (= (cadr site) 0) (= dx -1)) (and (= (cadr site) 8) (= dx 1)))
            (dolist (dy '(-1 1))
              (push (format "<path d='M%.2f %.2f v%.2f h%.2f'/>"
                            (+ x (* dx 7)) (+ y (* dy 3)) (* dy 4.0) (* dx -4.0)) parts))))))
    (push "</g>" parts)
    (dolist (entry '((2.3 . "楚 河") (6.7 . "汉 界")))
      (push (format "<text x='%.2f' y='%.2f' text-anchor='middle' font-family='Songti SC,STSong,serif' font-size='%.2f' fill='%s'>%s</text>"
                    (* (car entry) width) (+ (* 5 height) (* height 0.15)) (* height 0.39) river (cdr entry)) parts))
    (apply #'concat (nreverse parts))))

(defun etaf-xiangqi--cell-art (cache palette metrics row column piece selected target focused)
  "Return cached vector artwork for one interactive intersection.
CACHE is instance-owned and bounded. PALETTE and METRICS are presentation
values; PIECE, SELECTED, TARGET and FOCUSED never alter the native match."
  (let* ((width (plist-get metrics :width)) (height (plist-get metrics :height))
         (key (list palette width height row column piece selected target focused)))
    (or (gethash key cache)
        (let* ((base-key (list 'lattice palette width height))
               (base (or (gethash base-key cache)
                         (puthash base-key (etaf-xiangqi--board-lines palette width height) cache)))
               (x (* (+ column 0.5) width)) (y (* (+ row 0.5) height))
               (radius (* (min width height) 0.385))
               (ink (plist-get palette (if (eq (etaf-xiangqi--side piece) 'red) :xq-red :xq-black)))
               (accent (plist-get palette :xq-accent))
               (body base))
          (when (or focused selected)
            (setq body (concat body
                               (format "<circle cx='%.2f' cy='%.2f' r='%.2f' fill='none' stroke='%s' stroke-width='%s' %s/>"
                                       x y (+ radius 3) accent (if selected "2.3" "1.2")
                                       (if selected "" "stroke-dasharray='3 3'")))))
          (when piece
            (setq body
                  (concat body
                          (format "<circle cx='%.2f' cy='%.2f' r='%.2f' fill='%s' opacity='.20'/>"
                                  x (+ y 1.7) (+ radius 0.8) (plist-get palette :xq-shadow))
                          (format "<circle cx='%.2f' cy='%.2f' r='%.2f' fill='%s' stroke='%s' stroke-width='1.1'/>"
                                  x y radius (plist-get palette :xq-piece) (plist-get palette :xq-edge))
                          (format "<circle cx='%.2f' cy='%.2f' r='%.2f' fill='none' stroke='%s' stroke-width='.85' opacity='.72'/>"
                                  x y (- radius 3.1) ink)
                          (format "<text x='%.2f' y='%.2f' text-anchor='middle' font-family='Songti SC,STSong,Noto Serif CJK SC,serif' font-weight='600' font-size='%.2f' fill='%s'>%s</text>"
                                  x (+ y (* radius 0.41)) (* radius 1.24) ink (etaf-xiangqi--glyph piece)))))
          (when target
            (setq body (concat body
                               (if piece
                                   (format "<circle cx='%.2f' cy='%.2f' r='%.2f' fill='none' stroke='%s' stroke-width='2.4'/>" x y (+ radius 1) accent)
                                 (format "<circle cx='%.2f' cy='%.2f' r='4' fill='%s'/><circle cx='%.2f' cy='%.2f' r='7.5' fill='none' stroke='%s' stroke-width='.8' opacity='.65'/>" x y accent x y accent)))))
          (let ((image (list 'image :type 'svg :data
                             (format "<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='%d %d %d %d'>%s</svg>"
                                     width height (* column width) (* row height) width height body))))
            (when (> (hash-table-count cache) 512) (clrhash cache))
            (puthash key image cache))))))

(etaf-define-component etaf-xiangqi--board (&key session table selected palette metrics)
  :bindings ((cache (make-hash-table :test #'equal)) (cursor (etaf-ref nil)))
  :view
  (etaf-tile-grid :ref 'xiangqi-board :rows 10 :columns 9
    :cell-width (plist-get metrics :columns) :cell-height (plist-get metrics :lines)
    :region '(:id xiangqi-board :label "棋盘" :key "b" :enter xiangqi-cell-6-4)
    :cell-ref (lambda (r c) (intern (format "xiangqi-cell-%d-%d" r c)))
    :cell-image
    (when (plist-get metrics :graphic)
      (lambda (r c)
        (let* ((position (etaf-xiangqi--coord r c)) (state (etaf-value table))
               (chosen (etaf-value selected)))
          (etaf-xiangqi--cell-art
           cache (etaf-value palette) metrics r c (etaf-xiangqi--cell state r c)
           (equal position chosen) (and (etaf-xiangqi--move state chosen position) t)
           (equal position (etaf-value cursor))))))
    :cell-text (lambda (r c) (or (etaf-xiangqi--glyph (etaf-xiangqi--cell (etaf-value table) r c)) "·"))
    :cell-background (lambda (_r _c) (plist-get (etaf-value palette) :xq-paper))
    :cell-color (lambda (r c) (plist-get (etaf-value palette)
                                       (if (eq (etaf-xiangqi--side (etaf-xiangqi--cell (etaf-value table) r c)) 'red)
                                           :xq-red :xq-black)))
    :cell-label (lambda (r c)
                  (format "%s · 第%d行第%d路%s" (or (etaf-xiangqi--name (etaf-xiangqi--cell (etaf-value table) r c)) "空位")
                          (1+ r) (1+ c)
                          (if (etaf-xiangqi--move (etaf-value table) (etaf-value selected) (cons r c)) " · 可走" "")))
    :on-cell-focus (lambda (r c) (setf (etaf-value cursor) (cons r c)))
    :on-cell-press (lambda (r c) (etaf-xiangqi--press session selected (etaf-value table) (cons r c)))))

(provide 'etaf-xiangqi-board)
;;; etaf-xiangqi-board.el ends here
