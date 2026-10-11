;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-views.el --- A board-first hot-seat chess table
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-ui)
(require 'etaf-xiangqi-theme)
(require 'etaf-xiangqi-model)
(require 'etaf-xiangqi-board)
(declare-function etaf-xiangqi-close "etaf-xiangqi" (&optional instance))
(defvar etaf-xiangqi-appearance)

(defun etaf-xiangqi--turn-text (state)
  "Describe the side to move in public STATE."
  (cond ((null state) "正在开局")
        ((plist-get state :terminal) "对局结束")
        ((eq (plist-get state :side) 'red) "红方行棋")
        (t "黑方行棋")))

(etaf-define-component etaf-xiangqi--theme-switch (&key appearance)
  :view
  (etaf-button :label (if (eq (etaf-value appearance) 'dark) "浅色" "暗色")
    :ref 'xiangqi-theme :variant 'ghost :help-echo "切换亮暗主题 · T"
    :on-press (lambda () (setf (etaf-value appearance)
                              (if (eq (etaf-value appearance) 'dark) 'light 'dark)))))

(etaf-define-component etaf-xiangqi--moves (&key session table selected on-chosen)
  :bindings ((moves (etaf-computed
                     (lambda ()
                       (let ((all (plist-get (etaf-value table) :moves)))
                         (if-let* ((coord (etaf-value selected)))
                             (cl-remove-if-not (lambda (move) (equal coord (plist-get move :from))) all)
                           all))) :test #'equal)))
  :view
  (column :width 'stretch :item-gap '(lh 1)
    (etaf-label :text (if (etaf-value selected) "这枚棋子的可走位置" "本回合的合法走法") :variant 'strong)
    (column :height '(lh 12) :overflow 'scroll :width 'stretch
      (etaf-button :for (move (etaf-value moves)) :key (plist-get move :id)
        :ref (intern (format "xiangqi-move-%d" (plist-get move :id)))
        :label (let* ((from (plist-get move :from)) (to (plist-get move :to)))
                 (format "%s · %d路 → %d路%d行"
                         (etaf-xiangqi--name (etaf-xiangqi--cell (etaf-value table) (car from) (cdr from)))
                         (1+ (cdr from)) (1+ (cdr to)) (1+ (car to))))
        :variant 'ghost :disabled (not (eq (etaf-gamekit-status session) 'ready))
        :on-press (lambda ()
                    (etaf-xiangqi--send session selected "act" (list :action (plist-get move :id)))
                    (when on-chosen (funcall on-chosen)))))
    (etaf-label :if (null (etaf-value moves)) :text "当前没有可用走法。" :variant 'muted)))

(etaf-define-component etaf-xiangqi--app (&key session)
  :bindings ((appearance (etaf-ref (if (eq etaf-xiangqi-appearance 'auto)
                                      (if (eq (frame-parameter nil 'background-mode) 'dark) 'dark 'light)
                                    etaf-xiangqi-appearance)))
             (theme (etaf-computed (lambda () (if (eq (etaf-value appearance) 'dark)
                                                 etaf-xiangqi--dark-theme etaf-xiangqi--light-theme)) :test #'equal))
             (metrics (etaf-xiangqi--board-metrics))
             (observation (etaf-computed (lambda () (etaf-gamekit-view session)) :test #'equal))
             (table (etaf-computed (lambda () (etaf-xiangqi--table (etaf-value observation))) :test #'equal))
             (selected (etaf-ref nil)) (help (etaf-ref nil)) (moves-open (etaf-ref nil))
             (viewport (etaf-computed (lambda () (etaf-viewport)) :test #'equal))
             (compact (etaf-computed (lambda () (< (or (cdr (etaf-value viewport)) 44) 40)))))
  :setup
  (progn
    (etaf-theme-provide theme)
    ;; Emacs keeps automatic horizontal scrolling after a tiny window grows.
    ;; Restore the whole table only when it fits; never change the focused cell.
    (etaf-watch viewport
      (lambda (_size _old)
        (when-let* ((buffer (etaf-gamekit-buffer session))
                    (runtime (etaf-runtime-for-buffer buffer))
                    (bounds (etaf-host-ref-size runtime 'xiangqi-root)))
          (dolist (window (get-buffer-window-list buffer nil t))
            (when (>= (window-body-width window t) (car bounds))
              (set-window-hscroll window 0))
            (when (>= (window-body-height window) (cdr bounds))
              (set-window-start window (with-current-buffer buffer (point-min)) t)))))
      :flush 'post)
    (etaf-watch-effect
     (lambda ()
       (let ((view (etaf-value observation)))
         (when (and (eq (etaf-gamekit-status session) 'ready)
                    (not (eq t (plist-get view :terminal)))
                    (integerp (plist-get view :player))
                    (memq (plist-get view :current_player) '(0 1))
                    (/= (plist-get view :player) (plist-get view :current_player)))
           (etaf-gamekit-action session "set-player" (list :player (plist-get view :current_player))))))
     :name "xiangqi-player-sync"))
  :view
  (column :width '(vw 100) :height '(vh 100)
    :cross-align (if (< (or (car (etaf-value viewport)) 0)
                       (* (frame-char-width) (+ 4 (* 9 (plist-get metrics :columns)))))
                     'start 'center)
    :background-color (etaf-xiangqi--color :ui-bg) :color (etaf-xiangqi--color :ui-fg)
    :on-dismiss (lambda () (setf (etaf-value selected) nil))
    :keys (list
           (list "u" (lambda () (when (eq t (etaf-gamekit-view session :can_undo))
                                  (etaf-xiangqi--send session selected "undo"))) "悔棋")
           (list "y" (lambda () (when (eq t (etaf-gamekit-view session :can_redo))
                                  (etaf-xiangqi--send session selected "redo"))) "重做")
           (list "n" (lambda () (etaf-xiangqi--send session selected "reset")) "新局")
           (list "C-s" (lambda () (etaf-xiangqi--snapshot session selected "save")) "保存")
           (list "C-o" (lambda () (etaf-xiangqi--snapshot session selected "load")) "读取")
           (list "t" (lambda () (setf (etaf-value appearance)
                                      (if (eq (etaf-value appearance) 'dark) 'light 'dark))) "切换亮暗主题")
           (list "<f1>" (lambda () (setf (etaf-value help) t)) "规则")
           (list "q" (lambda () (etaf-xiangqi-close session)) "退出"))
    (column :ref 'xiangqi-root :width (list 'ch (+ 4 (* 9 (plist-get metrics :columns))))
      :padding (if (etaf-value compact) '((lh 0) (ch 2)) '((lh 1) (ch 2)))
      :item-gap (if (etaf-value compact) '(lh 0) '(lh 1))
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        (etaf-label :text "中国象棋" :variant 'strong)
        (etaf-label :ref 'xiangqi-status :text (etaf-xiangqi--turn-text (etaf-value table))
          :color (etaf-xiangqi--color :ui-accent)))
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        :region '(:id xiangqi-controls :label "对局操作" :key "a" :enter xiangqi-new)
        (row :item-gap '(ch 1)
          (etaf-button :label "新局" :ref 'xiangqi-new :variant 'secondary
            :on-press (lambda () (etaf-xiangqi--send session selected "reset")))
          (etaf-button :label "悔棋" :ref 'xiangqi-undo :variant 'ghost
            :disabled (not (eq t (etaf-gamekit-view session :can_undo)))
            :on-press (lambda () (etaf-xiangqi--send session selected "undo")))
          (etaf-button :label "重做" :ref 'xiangqi-redo :variant 'ghost
            :disabled (not (eq t (etaf-gamekit-view session :can_redo)))
            :on-press (lambda () (etaf-xiangqi--send session selected "redo"))))
        (row :item-gap '(ch 1)
          (etaf-button :label "保存" :ref 'xiangqi-save :variant 'ghost
            :on-press (lambda () (etaf-xiangqi--snapshot session selected "save")))
          (etaf-button :label "读取" :ref 'xiangqi-load :variant 'ghost
            :on-press (lambda () (etaf-xiangqi--snapshot session selected "load")))
          (etaf-xiangqi--theme-switch :appearance appearance)))
      (etaf-label :if (null (etaf-value table)) :text "正在开局…" :variant 'muted)
      (etaf-xiangqi--board :if (etaf-value table) :session session :table table
        :selected selected :palette theme :metrics metrics)
      (etaf-label :ref 'xiangqi-selection
        :text (if-let* ((coord (etaf-value selected)))
                  (format "已选 %s · 点击圆点落子"
                          (etaf-xiangqi--name (etaf-xiangqi--cell (etaf-value table) (car coord) (cdr coord))))
                "选择棋子，再点目标落子")
        :variant 'muted)
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        (etaf-label :text (format "同机双人  ·  %d 手" (or (plist-get (etaf-value table) :count) 0)) :variant 'muted)
        (row :item-gap '(ch 1)
          (etaf-button :label "走法" :ref 'xiangqi-show-moves :variant 'ghost
            :on-press (lambda () (setf (etaf-value moves-open) t)))
          (etaf-button :label "规则" :ref 'xiangqi-help :variant 'ghost
            :on-press (lambda () (setf (etaf-value help) t)))))
      (etaf-alert :if (etaf-gamekit-last-error session) :title "走法未生效"
        :message (etaf-gamekit-last-error session) :variant 'danger)
      (etaf-dialog :open moves-open :title "可走位置" :width '(ch 36) :compact t
        :on-close (lambda () (setf (etaf-value moves-open) nil))
        (etaf-xiangqi--moves :session session :table table :selected selected
          :on-chosen (lambda () (setf (etaf-value moves-open) nil))))
      (etaf-dialog :open help :title "中国象棋 · 规则与操作" :width '(ch 58) :compact t
        :on-close (lambda () (setf (etaf-value help) nil))
        (column :item-gap '(lh 1)
          (etaf-label :text "红方先行，双方在同一棋盘轮流落子。点选棋子后，圆点标出合法目标，细环标出可吃的棋子。" :wrap-mode 'word)
          (etaf-label :text "方向键移动棋盘光标，Enter 选中或落子；Tab 切换控件，Escape 取消选择。" :wrap-mode 'word)
          (etaf-label :text "U 悔棋，Y 重做，N 新局，T 主题，Q 退出。保存与读取使用本地文件，不自动覆盖棋局。" :wrap-mode 'word)
          (etaf-label :text "走法与胜负由 OpenSpiel Xiangqi 判定。棋盘在图形 Emacs 中使用矢量绘制，每个交叉点仍是原生可聚焦、可激活的 ETAF 控件。" :wrap-mode 'word))))))

(defun etaf-xiangqi--view (session)
  "Build this application's presentation through public framework APIs."
  (etaf-view (etaf-xiangqi--app :session session)))

(provide 'etaf-xiangqi-views)
;;; etaf-xiangqi-views.el ends here
