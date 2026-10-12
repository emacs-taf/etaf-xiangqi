;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-board.el --- Vector artwork for native interactive intersections
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'cl-lib)
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

(defun etaf-xiangqi--board-parts (palette width height)
  "Return the board artwork in PALETTE with WIDTH/HEIGHT pitch as parts.
The result is (FRAME . ITEMS): FRAME is markup every intersection draws and
each item is (LEFT TOP RIGHT BOTTOM GROUP MARKUP) with its scene bounds.
GROUP is non-nil for lattice strokes that share the line style."
  (let* ((paper (plist-get palette :xq-paper))
         (edge (plist-get palette :xq-edge))
         (river (plist-get palette :xq-river))
         (x0 (/ width 2.0)) (y0 (/ height 2.0)) (items nil))
    (cl-flet ((stroke (x1 y1 x2 y2)
                (push (list (min x1 x2) (min y1 y2) (max x1 x2) (max y1 y2) t
                            (etaf-ui-svg-line x1 y1 x2 y2))
                      items)))
      (dotimes (r 10)
        (stroke x0 (+ y0 (* r height)) (+ x0 (* 8 width)) (+ y0 (* r height))))
      (dotimes (c 9)
        (let ((x (+ x0 (* c width))))
          (if (memq c '(0 8))
              (stroke x y0 x (+ y0 (* 9 height)))
            (stroke x y0 x (+ y0 (* 4 height)))
            (stroke x (+ y0 (* 5 height)) x (+ y0 (* 9 height))))))
      (dolist (r '(0 7))
        (stroke (+ x0 (* 3 width)) (+ y0 (* r height))
                (+ x0 (* 5 width)) (+ y0 (* (+ r 2) height)))
        (stroke (+ x0 (* 5 width)) (+ y0 (* r height))
                (+ x0 (* 3 width)) (+ y0 (* (+ r 2) height))))
      ;; Traditional cannon and soldier placement marks; these are board artwork.
      (dolist (site '((2 1) (2 7) (7 1) (7 7) (3 0) (3 2) (3 4) (3 6) (3 8)
                      (6 0) (6 2) (6 4) (6 6) (6 8)))
        (let ((x (+ x0 (* (cadr site) width))) (y (+ y0 (* (car site) height))))
          (dolist (dx '(-1 1))
            (unless (or (and (= (cadr site) 0) (= dx -1)) (and (= (cadr site) 8) (= dx 1)))
              (dolist (dy '(-1 1))
                (let ((px (+ x (* dx 7))) (py (+ y (* dy 3))))
                  (stroke px py px (+ py (* dy 4)))
                  (stroke px (+ py (* dy 4)) (+ px (* dx -4)) (+ py (* dy 4))))))))))
    (dolist (entry '((2.3 . "楚 河") (6.7 . "汉 界")))
      (let ((x (* (car entry) width)) (y (+ (* 5 height) (* height 0.15)))
            (size (* height 0.39)))
        (push (list (- x (* 2 size)) (- y size) (+ x (* 2 size)) (+ y (* 0.5 size)) nil
                    (etaf-ui-svg-text x y (cdr entry)
                                      :font-family "Songti SC,STSong,serif"
                                      :font-size size :text-anchor "middle" :fill river))
              items)))
    (cons (concat (etaf-ui-svg-rect 0 0 (* 9 width) (* 10 height) :fill paper)
                  (etaf-ui-svg-rect 5 5 (- (* 9 width) 10) (- (* 10 height) 10)
                                    :rx 9 :fill "none" :stroke edge :stroke-width 1.2))
          (nreverse items))))

(defun etaf-xiangqi--board-window (parts palette left top width height)
  "Return board markup from PARTS in PALETTE visible in one window.
LEFT, TOP, WIDTH and HEIGHT bound the window in scene coordinates.  Parts
outside it draw no pixels there, so omitting them keeps the picture and
saves decoding the complete board for every intersection."
  (let ((right (+ left width)) (bottom (+ top height)) (margin 2)
        lattice text)
    (dolist (item (cdr parts))
      (when (and (<= (- (nth 0 item) margin) right) (>= (+ (nth 2 item) margin) left)
                 (<= (- (nth 1 item) margin) bottom) (>= (+ (nth 3 item) margin) top))
        (if (nth 4 item)
            (push (nth 5 item) lattice)
          (push (nth 5 item) text))))
    (concat (car parts)
            (and lattice
                 (etaf-ui-svg-group (apply #'concat (nreverse lattice))
                                    :fill "none" :stroke (plist-get palette :xq-line)
                                    :stroke-width .85))
            (apply #'concat (nreverse text)))))

(defun etaf-xiangqi--cache-get (cache key)
  "Return KEY's artwork from CACHE, keeping recently used entries.
CACHE is (RECENT . OLDER); a hit in OLDER moves into RECENT."
  (or (gethash key (car cache))
      (let ((value (gethash key (cdr cache))))
        (when value (etaf-xiangqi--cache-put cache key value)))))

(defun etaf-xiangqi--cache-put (cache key value)
  "Store VALUE under KEY in CACHE and return VALUE.
When RECENT is full it becomes OLDER, so the cache stays bounded without
discarding the artwork that is still being shown."
  (when (>= (hash-table-count (car cache)) 256)
    (setcdr cache (car cache))
    (setcar cache (make-hash-table :test #'equal)))
  (puthash key value (car cache)))

(defun etaf-xiangqi--cell-art (cache palette metrics row column piece selected target focused)
  "Return cached vector artwork for one interactive intersection.
CACHE is instance-owned and bounded. PALETTE and METRICS are presentation
values; PIECE, SELECTED, TARGET and FOCUSED never alter the native match."
  (let* ((width (plist-get metrics :width)) (height (plist-get metrics :height))
         (key (list palette width height row column piece selected target focused)))
    (or (etaf-xiangqi--cache-get cache key)
        (let* ((base-key (list 'board palette width height))
               (parts (or (etaf-xiangqi--cache-get cache base-key)
                          (etaf-xiangqi--cache-put
                           cache base-key
                           (etaf-xiangqi--board-parts palette width height))))
               (x (* (+ column 0.5) width)) (y (* (+ row 0.5) height))
               (radius (* (min width height) 0.385))
               (ink (plist-get palette (if (eq (etaf-xiangqi--side piece) 'red) :xq-red :xq-black)))
               (accent (plist-get palette :xq-accent))
               (body (etaf-xiangqi--board-window parts palette (* column width)
                                                 (* row height) width height)))
          (when (or focused selected)
            (setq body (concat body
                               (etaf-ui-svg-circle x y (+ radius 3)
                                                   :fill "none" :stroke accent
                                                   :stroke-width (if selected 2.3 1.2)
                                                   :stroke-dasharray (unless selected "3 3")))))
          (when piece
            (setq body
                  (concat body
                          (etaf-ui-svg-circle x (+ y 1.7) (+ radius 0.8)
                                              :fill (plist-get palette :xq-shadow)
                                              :opacity .20)
                          (etaf-ui-svg-circle x y radius
                                              :fill (plist-get palette :xq-piece)
                                              :stroke (plist-get palette :xq-edge)
                                              :stroke-width 1.1)
                          (etaf-ui-svg-circle x y (- radius 3.1)
                                              :fill "none" :stroke ink
                                              :stroke-width .85 :opacity .72)
                          (etaf-ui-svg-text
                           x (+ y (* radius 0.41)) (etaf-xiangqi--glyph piece)
                           :font-family "Songti SC,STSong,Noto Serif CJK SC,serif"
                           :font-weight 600 :font-size (* radius 1.24)
                           :text-anchor "middle" :fill ink))))
          (when target
            (setq body (concat body
                               (if piece
                                   (etaf-ui-svg-circle x y (+ radius 1)
                                                       :fill "none" :stroke accent
                                                       :stroke-width 2.4)
                                 (concat
                                  (etaf-ui-svg-circle x y 4 :fill accent)
                                  (etaf-ui-svg-circle x y 7.5 :fill "none"
                                                      :stroke accent :stroke-width .8
                                                      :opacity .65))))))
          (let ((image (etaf-ui-svg-image
                        body width height
                        (list (* column width) (* row height) width height))))
            (etaf-xiangqi--cache-put cache key image))))))

(etaf-define-component etaf-xiangqi--board (&key session table selected palette metrics)
  :bindings ((cache (cons (make-hash-table :test #'equal) (make-hash-table :test #'equal))) (cursor (etaf-ref nil)))
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
