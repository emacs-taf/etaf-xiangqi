;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-views.el --- A board-first chess table with a computer opponent
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'etaf-ui)
(require 'etaf-xiangqi-theme)
(require 'etaf-xiangqi-model)
(require 'etaf-xiangqi-board)
(declare-function etaf-xiangqi-close "etaf-xiangqi" (&optional instance))
(defvar etaf-xiangqi-appearance)
(defvar etaf-xiangqi-opponent)
(defvar etaf-xiangqi-level)

(defun etaf-xiangqi--turn-text (state computer failure)
  "Describe public STATE with COMPUTER on one side and optional FAILURE."
  (cond ((null state) "正在开局")
        ((plist-get state :terminal)
         (pcase (plist-get state :result)
           ('red "红方胜") ('black "黑方胜") ('draw "和棋") (_ "对局结束")))
        (failure "操作失败，请重试或重开")
        ((eq (plist-get state :side) computer) "电脑思考中…")
        (computer "轮到你走棋")
        ((eq (plist-get state :side) 'red) "红方行棋")
        (t "黑方行棋")))

(defun etaf-xiangqi--match-text (computer)
  "Describe the running match's players, with COMPUTER on one side or nil."
  (if computer
      (format "人机对战 · 你执%s" (if (eq computer 'black) "红" "黑"))
    "同机双人"))

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
             (opponent (etaf-ref etaf-xiangqi-opponent))
             (level (etaf-ref etaf-xiangqi-level))
             (computer (etaf-computed
                        (lambda ()
                          (when (member "bot" (etaf-gamekit-capabilities session))
                            (etaf-xiangqi--computer (etaf-value opponent))))
                        :test #'eq))
             (ready (etaf-computed (lambda ()
                                    (etaf-value observation)
                                    (eq (etaf-gamekit-status session) 'ready))))
             (undo-available (etaf-computed
                              (lambda ()
                                (and (eq t (etaf-gamekit-view session :can_undo))
                                     (not (and (eq (etaf-value computer) 'red)
                                               (= (etaf-gamekit-view session :action_count) 1)))))))
             (blocked (etaf-computed
                       (lambda ()
                         (let ((state (etaf-value table)))
                           (or (not (etaf-value ready))
                               (and state (not (plist-get state :terminal))
                                    (or (eq (plist-get state :side) (etaf-value computer))
                                        (/= (plist-get state :player)
                                            (if (eq (plist-get state :side) 'red) 0 1)))))))
                       :test #'eq))
             (playable (etaf-computed
                        (lambda ()
                          (let ((state (etaf-value table)))
                            (when state
                              (if (etaf-value blocked)
                                  (plist-put (copy-sequence state) :moves nil)
                                state))))
                        :test #'equal))
             (selected (etaf-ref nil)) (help (etaf-ref nil)) (moves-open (etaf-ref nil))
             (settings (etaf-ref nil))
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
       ;; Track published changes, but decide from the latest accepted position.
       ;; Sending immediately makes the session busy, preventing duplicate work.
       (etaf-value observation)
       (let ((computer-side (etaf-value computer)) (strength (etaf-value level)))
         (when (and (eq (etaf-gamekit-status session) 'ready)
                    (not (etaf-gamekit-last-error session)))
           (let* ((view (etaf-gamekit-observation session))
                  (current (plist-get view :current_player))
                  (seat (if computer-side (if (eq computer-side 'red) 1 0) current)))
             (when (and (not (eq t (plist-get view :terminal))) (memq current '(0 1)))
               (cond
                ((/= (plist-get view :player) seat)
                 (setf (etaf-value selected) nil)
                 (etaf-gamekit-action session "set-player" (list :player seat)))
                ((and computer-side (/= current seat))
                 (setf (etaf-value selected) nil)
                 (etaf-gamekit-action session "bot" (etaf-xiangqi--bot-arguments strength)))))))))
     :name "xiangqi-turn-policy"))
  :view
  (column :width '(vw 100) :height '(vh 100)
    :cross-align (if (< (or (car (etaf-value viewport)) 0)
                       (* (frame-char-width) (+ 4 (* 9 (plist-get metrics :columns)))))
                     'start 'center)
    :background-color (etaf-xiangqi--color :ui-bg) :color (etaf-xiangqi--color :ui-fg)
    :on-dismiss (lambda () (setf (etaf-value selected) nil))
    :keys (list
           (list "u" (lambda ()
                       (when (and (not (etaf-value blocked))
                                  (etaf-value undo-available))
                         (etaf-xiangqi--send session selected "undo"
                                             (list :count (etaf-xiangqi--step-count (etaf-value computer)
                                                                                      (etaf-gamekit-view session :action_count))))))
                 "悔棋")
           (list "y" (lambda ()
                       (when (and (not (etaf-value blocked))
                                  (eq t (etaf-gamekit-view session :can_redo)))
                         (etaf-xiangqi--send session selected "redo"
                                             (list :count (etaf-xiangqi--step-count (etaf-value computer)
                                                                                      (etaf-gamekit-view session :action_count))))))
                 "重做")
           (list "n" (lambda () (etaf-xiangqi--send session selected "reset"
                                                        (list :seed (random most-positive-fixnum)))) "新局")
           (list "C-s" (lambda () (etaf-xiangqi--snapshot session selected "save")) "保存")
           (list "C-o" (lambda () (etaf-xiangqi--snapshot session selected "load")) "读取")
           (list "t" (lambda () (setf (etaf-value appearance)
                                      (if (eq (etaf-value appearance) 'dark) 'light 'dark))) "切换亮暗主题")
           (list "o" (lambda () (setf (etaf-value settings) t)) "对局设置")
           (list "<f1>" (lambda () (setf (etaf-value help) t)) "规则")
           (list "q" (lambda () (etaf-xiangqi-close session)) "退出"))
    (column :ref 'xiangqi-root :width (list 'ch (+ 4 (* 9 (plist-get metrics :columns))))
      :padding (if (etaf-value compact) '((lh 0) (ch 2)) '((lh 1) (ch 2)))
      :item-gap (if (etaf-value compact) '(lh 0) '(lh 1))
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        (etaf-label :text "中国象棋" :variant 'strong)
        (etaf-label :ref 'xiangqi-status
          :text (etaf-xiangqi--turn-text (etaf-value table) (etaf-value computer)
                                         (etaf-gamekit-last-error session))
          :color (etaf-xiangqi--color :ui-accent)))
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        :region '(:id xiangqi-controls :label "对局操作" :key "a" :enter xiangqi-new)
        (row :item-gap '(ch 1)
          (etaf-button :label "新局" :ref 'xiangqi-new :variant 'secondary
            :disabled (not (etaf-value ready))
            :on-press (lambda () (etaf-xiangqi--send session selected "reset"
                                                        (list :seed (random most-positive-fixnum)))))
          (etaf-button :label "悔棋" :ref 'xiangqi-undo :variant 'ghost
            :disabled (or (etaf-value blocked) (not (etaf-value undo-available)))
            :on-press (lambda ()
                        (etaf-xiangqi--send session selected "undo"
                                            (list :count (etaf-xiangqi--step-count (etaf-value computer)
                                                                                      (etaf-gamekit-view session :action_count))))))
          (etaf-button :label "重做" :ref 'xiangqi-redo :variant 'ghost
            :disabled (or (etaf-value blocked) (not (eq t (etaf-gamekit-view session :can_redo))))
            :on-press (lambda ()
                        (etaf-xiangqi--send session selected "redo"
                                            (list :count (etaf-xiangqi--step-count (etaf-value computer)
                                                                                      (etaf-gamekit-view session :action_count)))))))
        (row :item-gap '(ch 1)
          (etaf-button :label "保存" :ref 'xiangqi-save :variant 'ghost
            :disabled (not (etaf-value ready))
            :on-press (lambda () (etaf-xiangqi--snapshot session selected "save")))
          (etaf-button :label "读取" :ref 'xiangqi-load :variant 'ghost
            :disabled (not (etaf-value ready))
            :on-press (lambda () (etaf-xiangqi--snapshot session selected "load")))
          (etaf-xiangqi--theme-switch :appearance appearance)))
      (etaf-label :if (null (etaf-value table)) :text "正在开局…" :variant 'muted)
      (etaf-xiangqi--board :if (etaf-value table) :session session :table playable
        :selected selected :palette theme :metrics metrics)
      (etaf-label :ref 'xiangqi-selection
        :text (if-let* ((coord (etaf-value selected)))
                  (format "已选 %s · 点击圆点落子"
                          (etaf-xiangqi--name (etaf-xiangqi--cell (etaf-value table) (car coord) (cdr coord))))
                "选择棋子，再点目标落子")
        :variant 'muted)
      (flex :width 'stretch :justify-content 'space-between :align-items 'center
        (etaf-label :text (format "%s  ·  %d 手" (etaf-xiangqi--match-text (etaf-value computer))
                                  (or (plist-get (etaf-value table) :count) 0))
          :variant 'muted)
        (row :item-gap '(ch 1)
          (etaf-button :label "走法" :ref 'xiangqi-show-moves :variant 'ghost
            :disabled (etaf-value blocked)
            :on-press (lambda () (setf (etaf-value moves-open) t)))
          (etaf-button :label "规则" :ref 'xiangqi-help :variant 'ghost
            :on-press (lambda () (setf (etaf-value help) t)))
          (etaf-button :label "设置" :ref 'xiangqi-settings :variant 'ghost
            :on-press (lambda () (setf (etaf-value settings) t)))))
      (etaf-alert :if (and (etaf-value ready)
                           (etaf-xiangqi--computer (etaf-value opponent))
                           (not (member "bot" (etaf-gamekit-capabilities session))))
        :title "电脑对手不可用" :message "请更新 etaf-gamekit；当前可同机双人对战。" :variant 'warning)
      (etaf-alert :if (etaf-gamekit-last-error session) :title "操作未生效"
        :message (etaf-gamekit-last-error session) :variant 'danger)
      (etaf-dialog :open moves-open :title "可走位置" :width '(ch 36) :compact t
        :on-close (lambda () (setf (etaf-value moves-open) nil))
        (etaf-xiangqi--moves :session session :table playable :selected selected
          :on-chosen (lambda () (setf (etaf-value moves-open) nil))))
      (etaf-dialog :open settings :title "对局设置" :width '(ch 46) :compact t :close-label "关闭"
        :on-close (lambda () (setf (etaf-value settings) nil))
        (column :item-gap '(lh 1)
          (etaf-label :text "对手" :variant 'strong)
          (row :item-gap '(ch 1)
            (etaf-button :label "同机双人" :ref 'xiangqi-opponent-hot-seat
              :variant (if (eq (etaf-value opponent) 'hot-seat) 'secondary 'ghost)
              :aria-selected (eq (etaf-value opponent) 'hot-seat)
              :disabled (not (etaf-value ready))
              :on-press (lambda () (setf (etaf-value opponent) 'hot-seat)))
            (etaf-button :label "电脑执黑" :ref 'xiangqi-opponent-computer-black
              :variant (if (eq (etaf-value opponent) 'computer-black) 'secondary 'ghost)
              :aria-selected (eq (etaf-value opponent) 'computer-black)
              :disabled (or (not (etaf-value ready))
                            (not (member "bot" (etaf-gamekit-capabilities session))))
              :on-press (lambda () (setf (etaf-value opponent) 'computer-black)))
            (etaf-button :label "电脑执红" :ref 'xiangqi-opponent-computer-red
              :variant (if (eq (etaf-value opponent) 'computer-red) 'secondary 'ghost)
              :aria-selected (eq (etaf-value opponent) 'computer-red)
              :disabled (or (not (etaf-value ready))
                            (not (member "bot" (etaf-gamekit-capabilities session))))
              :on-press (lambda () (setf (etaf-value opponent) 'computer-red))))
          (etaf-label :text "难度" :variant 'strong)
          (row :item-gap '(ch 1)
            (etaf-button :label "简单" :ref 'xiangqi-level-easy
              :variant (if (eq (etaf-value level) 'easy) 'secondary 'ghost)
              :aria-selected (eq (etaf-value level) 'easy)
              :disabled (null (etaf-value computer))
              :on-press (lambda () (setf (etaf-value level) 'easy)))
            (etaf-button :label "普通" :ref 'xiangqi-level-normal
              :variant (if (eq (etaf-value level) 'normal) 'secondary 'ghost)
              :aria-selected (eq (etaf-value level) 'normal)
              :disabled (null (etaf-value computer))
              :on-press (lambda () (setf (etaf-value level) 'normal)))
            (etaf-button :label "困难" :ref 'xiangqi-level-hard
              :variant (if (eq (etaf-value level) 'hard) 'secondary 'ghost)
              :aria-selected (eq (etaf-value level) 'hard)
              :disabled (null (etaf-value computer))
              :on-press (lambda () (setf (etaf-value level) 'hard))))
          (etaf-label :text "红方先行。换对手后轮到电脑时它会自动走子，难度从下一手开始生效。"
            :variant 'muted :wrap-mode 'word)))
      (etaf-dialog :open help :title "中国象棋 · 规则与操作" :width '(ch 58) :compact t
        :on-close (lambda () (setf (etaf-value help) nil))
        (column :item-gap '(lh 1)
          (etaf-label :text "默认与电脑对战：你执红先行，电脑执黑。电脑轮到时自动走子，不需要你替它走。" :wrap-mode 'word)
          (etaf-label :text "点选棋子后，圆点标出合法目标，细环标出可吃的棋子。方向键移动棋盘光标，Enter 选中或落子。" :wrap-mode 'word)
          (etaf-label :text "U 悔棋，Y 重做，N 新局，O 对局设置，T 主题，Q 退出。人机对战里悔棋回到你上一个回合。" :wrap-mode 'word)
          (etaf-label :text "Tab 切换控件，Escape 取消选择或关闭弹窗。保存与读取使用本地文件，不自动覆盖棋局。" :wrap-mode 'word)
          (etaf-label :text "走法与胜负由 OpenSpiel Xiangqi 判定，电脑走子由 GameKit 的 OpenSpiel 适配器搜索。" :wrap-mode 'word))))))

(defun etaf-xiangqi--view (session)
  "Build this application's presentation through public framework APIs."
  (etaf-view (etaf-xiangqi--app :session session)))

(provide 'etaf-xiangqi-views)
;;; etaf-xiangqi-views.el ends here
