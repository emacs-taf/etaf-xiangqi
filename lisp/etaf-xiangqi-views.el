;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-views.el --- Chu He's native xiangqi board

;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-ui)
(require 'etaf-xiangqi-theme)
(require 'etaf-xiangqi-model)
(declare-function etaf-xiangqi-close "etaf-xiangqi" (&optional instance))
(defvar etaf-xiangqi-appearance)

(defun etaf-xiangqi--palace-p (row column)
  "Whether ROW/COLUMN is inside either 3x3 palace."
  (and (<= 3 column 5) (or (<= 0 row 2) (<= 7 row 9))))

(defun etaf-xiangqi--move-text (table move)
  "Describe MOVE in TABLE with its piece glyph and board coordinates."
  (let* ((from (plist-get move :from)) (to (plist-get move :to))
         (piece (etaf-xiangqi--cell table (car from) (cdr from))))
    (format "%s %d,%d → %d,%d" (or (etaf-xiangqi--glyph piece) "•")
            (car from) (cdr from) (car to) (cdr to))))

(etaf-define-component etaf-xiangqi--theme-switch (&key appearance)
  :view
  (etaf-button :label (if (eq (etaf-value appearance) 'dark) "浅色" "暗色")
    :ref 'xiangqi-theme :variant 'ghost :help-echo "切换亮暗主题 · T"
    :on-press (lambda () (setf (etaf-value appearance)
                              (if (eq (etaf-value appearance) 'dark) 'light 'dark)))))

(etaf-define-component etaf-xiangqi--board (&key session table selected)
  :view
  (etaf-tile-grid :rows 10 :columns 9 :cell-width 4 :ref 'xiangqi-board
    :cell-ref (lambda (r c) (intern (format "xiangqi-cell-%d-%d" r c)))
    :cell-text (lambda (r c) (or (etaf-xiangqi--glyph (etaf-xiangqi--cell (etaf-value table) r c)) " "))
    :cell-color (lambda (r c)
                  (pcase (etaf-xiangqi--side (etaf-xiangqi--cell (etaf-value table) r c))
                    ('red (etaf-xiangqi--color :xiangqi-red))
                    ('black (etaf-xiangqi--color :xiangqi-black))
                    (_ (etaf-xiangqi--color :ui-muted-fg))))
    :cell-background
    (lambda (r c)
      (let* ((coord (etaf-xiangqi--coord r c))
             (target-p (member coord (etaf-xiangqi--targets (etaf-value table) (etaf-value selected)))))
        (cond
         ((equal coord (etaf-value selected)) (etaf-xiangqi--color :xiangqi-selected-bg))
         (target-p (etaf-xiangqi--color :xiangqi-target-bg))
         ((and (>= r 4) (<= r 5)) (etaf-xiangqi--color :xiangqi-river-bg))
         ((etaf-xiangqi--palace-p r c) (etaf-xiangqi--color :xiangqi-palace-bg))
         ((cl-evenp (+ r c)) (etaf-xiangqi--color :xiangqi-board-bg))
         (t (etaf-xiangqi--color :xiangqi-board-alt-bg)))))
    :cell-label
    (lambda (r c)
      (let* ((coord (etaf-xiangqi--coord r c))
             (piece (etaf-xiangqi--cell (etaf-value table) r c))
             (target-p (member coord (etaf-xiangqi--targets (etaf-value table) (etaf-value selected)))))
        (format "%s · %s%d%s" (if piece (etaf-xiangqi--name piece) "空")
                (if (< r 5) "黑" "红") (- 10 r) (if target-p " · 可走" ""))))
    :on-cell-press
    (lambda (r c) (etaf-xiangqi--press session selected (etaf-value table) (etaf-xiangqi--coord r c)))))

(etaf-define-component etaf-xiangqi--moves (&key session table selected)
  :bindings ((moves (etaf-computed
                     (lambda ()
                       (let ((all (plist-get (etaf-value table) :moves)))
                         (if-let* ((coord (etaf-value selected)))
                             (cl-remove-if-not (lambda (move) (equal coord (plist-get move :from))) all)
                           all))) :test #'equal)))
  :view
  (etaf-panel :ref 'xiangqi-moves :title "棋谱 / LEGAL MOVES" :width '(ch 34)
              :item-gap '(lh 1) :role 'region :aria-label "合法走法"
    (etaf-label :text (pcase (plist-get (etaf-value table) :side)
                        ('red "红方行棋" ) ('black "黑方行棋") (_ "等待开局"))
      :variant 'strong :color (pcase (plist-get (etaf-value table) :side)
                                ('red (etaf-xiangqi--color :xiangqi-red))
                                (_ (etaf-xiangqi--color :xiangqi-black))))
    (etaf-label :if (etaf-value selected)
      :text (format "已选 %s %d,%d" (etaf-xiangqi--name (etaf-xiangqi--cell (etaf-value table)
                                                                             (car (etaf-value selected))
                                                                             (cdr (etaf-value selected))))
                    (car (etaf-value selected)) (cdr (etaf-value selected)))
      :variant 'muted)
    (etaf-label :if (not (etaf-value selected)) :text "点选棋子查看它的合法走法。" :variant 'muted :wrap-mode 'word)
    (etaf-label :if (null (etaf-value moves)) :text "没有可用的走法，可撤销或开始新局。" :variant 'muted :wrap-mode 'word)
    (column :item-gap '(lh 0)
      (etaf-button :for (move (cl-subseq (etaf-value moves) 0 (min 8 (length (etaf-value moves))))) :key (plist-get move :id)
        :ref (intern (format "xiangqi-move-%d" (plist-get move :id)))
        :label (etaf-xiangqi--move-text (etaf-value table) move) :variant 'secondary
        :disabled (not (eq (etaf-gamekit-status session) 'ready))
        :on-press (lambda () (etaf-xiangqi--send session selected "act" (list :action (plist-get move :id))))))
    (etaf-divider)
    (etaf-label :text (format "步数 %d" (or (plist-get (etaf-value table) :count) 0)) :variant 'muted)
    (etaf-label :if (plist-get (etaf-value table) :terminal) :text "对局结束 · 可撤销回看" :variant 'strong)))

(etaf-define-component etaf-xiangqi--app (&key session)
  :bindings ((appearance (etaf-ref (if (eq etaf-xiangqi-appearance 'auto)
                                      (if (eq (frame-parameter nil 'background-mode) 'dark) 'dark 'light)
                                    etaf-xiangqi-appearance)))
             (theme (etaf-computed (lambda () (if (eq (etaf-value appearance) 'dark)
                                                 etaf-xiangqi--dark-theme etaf-xiangqi--light-theme))
                                   :test #'equal))
             (observation (etaf-computed (lambda () (etaf-gamekit-view session)) :test #'equal))
             (table (etaf-computed (lambda () (etaf-xiangqi--table (etaf-value observation))) :test #'equal))
             (selected (etaf-ref nil)) (help (etaf-ref nil)) (moves-open (etaf-ref nil))
             (viewport (etaf-computed
                        (lambda () (let ((size (etaf-viewport)))
                                     (cons (or (car size) 1024) (or (cdr size) 50)))) :test #'equal))
             (wide (etaf-computed (lambda () (>= (car (etaf-value viewport)) (* 86 (frame-char-width))))))
             (compact (etaf-computed (lambda () (< (cdr (etaf-value viewport)) 28)))))
  :setup (progn
           (etaf-theme-provide theme)
           (etaf-watch-effect
            (lambda ()
              (let ((view (etaf-value observation)))
                (when (and (eq (etaf-gamekit-status session) 'ready)
                           (not (eq t (plist-get view :terminal)))
                           (integerp (plist-get view :player))
                           (integerp (plist-get view :current_player))
                           (/= (plist-get view :player) (plist-get view :current_player)))
                  (etaf-gamekit-action session "set-player" (list :player (plist-get view :current_player))))))
            :name "xiangqi-player-sync"))
  :view
  (column :width '(vw 100) :height '(vh 100) :cross-align 'center
    :background-color (etaf-xiangqi--color :ui-bg) :color (etaf-xiangqi--color :ui-fg)
    :on-dismiss (lambda () (when (etaf-value selected) (setf (etaf-value selected) nil)))
    :keys (list
           (list "u" (lambda () (when (eq t (etaf-gamekit-view session :can_undo))
                                  (etaf-xiangqi--send session selected "undo"))) "撤销")
           (list "y" (lambda () (when (eq t (etaf-gamekit-view session :can_redo))
                                  (etaf-xiangqi--send session selected "redo"))) "重做")
           (list "n" (lambda () (etaf-xiangqi--send session selected "reset" (list :seed (random most-positive-fixnum)))) "新局")
           (list "C-s" (lambda () (etaf-xiangqi--snapshot session selected "save")) "保存")
           (list "C-o" (lambda () (etaf-xiangqi--snapshot session selected "load")) "读取")
           (list "t" (lambda () (setf (etaf-value appearance)
                                      (if (eq (etaf-value appearance) 'dark) 'light 'dark))) "切换亮暗主题")
           (list "<f1>" (lambda () (setf (etaf-value help) t)) "游戏说明")
           (list "q" (lambda () (etaf-xiangqi-close session)) "退出"))
    (column :ref 'xiangqi-root :width 'stretch :max-width '(ch 88)
      :padding (if (etaf-value compact) '((lh 0) (ch 1)) '((lh 1) (ch 2)))
      :item-gap (if (etaf-value compact) '(lh 0) '(lh 1))
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        (etaf-label :text "CHU HE / 中国象棋" :variant 'strong :color (etaf-xiangqi--color :ui-accent))
        (row :item-gap '(ch 1) :focus-group 'horizontal :role 'region :aria-label "对局操作"
          (etaf-button :label "新局" :ref 'xiangqi-new :variant 'secondary
            :on-press (lambda () (etaf-xiangqi--send session selected "reset" (list :seed (random most-positive-fixnum)))))
          (etaf-button :label "撤销" :ref 'xiangqi-undo :variant 'ghost
            :disabled (not (eq t (etaf-gamekit-view session :can_undo)))
            :on-press (lambda () (etaf-xiangqi--send session selected "undo")))
          (etaf-button :label "重做" :ref 'xiangqi-redo :variant 'ghost
            :disabled (not (eq t (etaf-gamekit-view session :can_redo)))
            :on-press (lambda () (etaf-xiangqi--send session selected "redo")))
          (etaf-button :label "保存" :ref 'xiangqi-save :variant 'ghost
            :on-press (lambda () (etaf-xiangqi--snapshot session selected "save")))
          (etaf-button :label "读取" :ref 'xiangqi-load :variant 'ghost
            :on-press (lambda () (etaf-xiangqi--snapshot session selected "load")))
          (etaf-xiangqi--theme-switch :appearance appearance)
          (etaf-button :label "说明" :ref 'xiangqi-help :variant 'ghost
            :on-press (lambda () (setf (etaf-value help) t)))))
      (etaf-label :if (not (etaf-value compact)) :text "OpenSpiel 规则 · 红方先行 · 同机双人对弈" :variant 'muted)
      (etaf-divider)
      (etaf-label :if (null (etaf-value table)) :text "正在开局…" :variant 'muted)
      (flex :if (etaf-value table) :width 'stretch :gap '((lh 0) (ch 3))
        :justify-content (if (etaf-value wide) 'flex-start 'center) :align-items 'flex-start
        (column :width '(ch 36)
          (etaf-xiangqi--board :session session :table table :selected selected))
        (etaf-xiangqi--moves :if (etaf-value wide) :session session :table table :selected selected))
      (flex :width 'stretch :justify-content 'space-between
        (etaf-label :ref 'xiangqi-status
          :text (if (etaf-value table)
                    (if (plist-get (etaf-value table) :terminal)
                        "对局结束 · 可撤销回看或开始新局"
                      (format "%s行棋 · 第 %d 手"
                              (if (eq (plist-get (etaf-value table) :side) 'red) "红方" "黑方")
                              (plist-get (etaf-value table) :count)))
                  "正在开局…")
          :variant 'muted)
        (etaf-button :if (and (etaf-value table) (not (etaf-value wide))) :label "棋谱" :ref 'xiangqi-show-moves
          :variant 'secondary :on-press (lambda () (setf (etaf-value moves-open) t))))
      (etaf-label :text "点选棋子 → 点击高亮目标 · Tab / 方向键导航，Enter 确认" :variant 'muted)
      (etaf-alert :if (etaf-gamekit-last-error session) :title "走法未生效"
        :message (etaf-gamekit-last-error session) :variant 'danger)
      (etaf-dialog :open (and (etaf-value table) (not (etaf-value wide)) (etaf-value moves-open))
                   :title "棋谱 / LEGAL MOVES" :width '(ch 36) :compact t
                   :on-close (lambda () (setf (etaf-value moves-open) nil))
        (etaf-xiangqi--moves :session session :table table :selected selected))
      (etaf-dialog :open help :title "CHU HE · 玩法" :width '(ch 64) :compact t
                   :on-close (lambda () (setf (etaf-value help) nil))
        (column :item-gap '(lh 1)
          (etaf-label :text "红方先行。点选棋子，再点击高亮的目标格完成走法；合法性交给 OpenSpiel 判断。" :wrap-mode 'word)
          (etaf-label :text "双方轮流在同一窗口落子：走子后界面自动切换到当前行动的一方。" :wrap-mode 'word)
          (etaf-label :text "U / Y 撤销与重做，N 新局，T 切换亮暗主题，F1 打开本说明，Q 退出。" :wrap-mode 'word)
          (etaf-label :text "棋盘保持 9 × 10 固定尺寸；窄窗口把棋谱收进「棋谱」对话框，不缩放棋子。" :wrap-mode 'word))))))

(defun etaf-xiangqi--view (session)
  "Build this application's presentation through public framework APIs."
  (etaf-view (etaf-xiangqi--app :session session)))

(provide 'etaf-xiangqi-views)
;;; etaf-xiangqi-views.el ends here
