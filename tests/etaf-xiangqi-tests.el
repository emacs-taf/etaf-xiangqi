;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-tests.el --- Public Xiangqi behavior
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'ert)
(require 'etaf-xiangqi)

(defun etaf-xiangqi-test--wait (session &optional predicate failure)
  "Await SESSION's painted board and PREDICATE; expect rejection with FAILURE."
  (let ((end (+ (float-time) 8)))
    (while (and (< (float-time) end)
                (not (memq (etaf-gamekit-status session) '(failed closed)))
                (or (not (eq (etaf-gamekit-status session) 'ready))
                    (and predicate (not (funcall predicate)))))
      (accept-process-output nil 0.01)))
  (should (eq (etaf-gamekit-status session) 'ready))
  (if failure (should (etaf-gamekit-last-error session))
    (should-not (etaf-gamekit-last-error session)))
  (when predicate (should (funcall predicate))))

(defun etaf-xiangqi-test--close (session)
  "Dispose the application INSTANCE and its buffer."
  (when session (etaf-xiangqi-close session)))

(defun etaf-xiangqi-test--start (seed &optional opponent level)
  "Start an independent match with integer SEED, OPPONENT and LEVEL.
The application reads both variables when the view mounts, which happens
inside `etaf-gamekit-start'."
  (let ((etaf-xiangqi-opponent (or opponent etaf-xiangqi-opponent))
        (etaf-xiangqi-level (or level etaf-xiangqi-level)))
    (let* ((session (etaf-gamekit-start etaf-xiangqi-game :options (list :seed seed)))
           (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))))
      (etaf-runtime-refit runtime 1100 44)
      (etaf-xiangqi-test--wait session)
      (etaf-xiangqi-test--wait session (lambda () (etaf-host-ref-size runtime 'xiangqi-board)))
      session)))

(ert-deftest etaf-xiangqi-hot-seat-moves-and-undo-restores ()
  "Red and black alternate through the public board; undo restores the opening."
  (let ((session (etaf-xiangqi-test--start 11 'hot-seat)))
    (unwind-protect
        (let* ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
               (before (etaf-gamekit-observation session)))
          (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
          (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1)))
          (should-not (equal before (etaf-gamekit-observation session)))
          (etaf-xiangqi-test--wait session (lambda () (equal 1 (etaf-gamekit-view session :player))))
          (should (consp (etaf-gamekit-view session :legal_actions)))
          (let* ((action (car (etaf-gamekit-view session :legal_actions)))
                 (ref (intern (format "xiangqi-move-%d" (plist-get action :id)))))
            (etaf-dispatch-event runtime 'xiangqi-show-moves 'press)
            (etaf-dispatch-event runtime ref 'press)
            (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 2)))
            (etaf-xiangqi-test--wait session (lambda () (equal 0 (etaf-gamekit-view session :player)))))
          (etaf-dispatch-event runtime 'xiangqi-undo 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1)))
          (etaf-dispatch-event runtime 'xiangqi-undo 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 0)))
          (should (equal (plist-get before :observation) (etaf-gamekit-view session :observation))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-invalid-action-preserves-the-board ()
  "An action that is not legal for the side to move preserves the match."
  (let ((session (etaf-xiangqi-test--start 11 'hot-seat)))
    (unwind-protect
        (let ((before (etaf-gamekit-observation session)))
          (etaf-gamekit-action session "act" (list :action 1234567))
          (accept-process-output nil 0.3)
          (should (etaf-gamekit-last-error session))
          (should (equal before (etaf-gamekit-observation session))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-themes-preserve-the-match ()
  "Light/dark switching preserves the match, selection and board metrics."
  (let ((session (etaf-xiangqi-test--start 11 'hot-seat)))
    (unwind-protect
        (let* ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
               (before (etaf-gamekit-observation session))
               (size (etaf-host-ref-size runtime 'xiangqi-board)))
          (etaf-focus runtime 'xiangqi-cell-6-4)
          (etaf-activate runtime)
          (dotimes (_ 2)
            (etaf-dispatch-event runtime 'xiangqi-theme 'press)
            (let ((after (etaf-gamekit-observation session))
                  (geometry (etaf-host-ref-size runtime 'xiangqi-board))
                  (focus (etaf-focused-host-ref runtime)))
              (should (equal before after))
              (should (equal size geometry))
              (should (eq focus 'xiangqi-cell-6-4))))
          (dolist (viewport '((1400 . 48) (950 . 44) (550 . 42) (1000 . 34) (320 . 20)))
            (etaf-runtime-refit runtime (car viewport) (cdr viewport))
            (let ((geometry (etaf-host-ref-size runtime 'xiangqi-board))
                  (focus (etaf-focused-host-ref runtime)))
              (should (equal size geometry))
              (should (eq focus 'xiangqi-cell-6-4))))
          (etaf-runtime-refit runtime 1100 44)
          (let ((next (etaf-direction 'up runtime)))
            (should (eq next 'xiangqi-cell-5-4)))
          (etaf-activate runtime)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-matches-are-independent ()
  "A move in one match cannot change a second match."
  (let ((first (etaf-xiangqi-test--start 11 'hot-seat)))
    (unwind-protect
        (let ((second (etaf-xiangqi-test--start 11 'hot-seat)))
          (unwind-protect
              (let ((before (etaf-gamekit-observation second))
                    (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer first))))
                (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
                (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
                (etaf-xiangqi-test--wait first (lambda () (= (etaf-gamekit-view first :action_count) 1)))
                (should (equal before (etaf-gamekit-observation second))))
            (etaf-xiangqi-test--close second)))
      (etaf-xiangqi-test--close first))))

(ert-deftest etaf-xiangqi-dialog-and-escape-dismiss-one-layer ()
  "Help closes before Escape clears a selected stone; neither changes the match."
  (let ((session (etaf-xiangqi-test--start 11 'hot-seat)))
    (unwind-protect
        (let* ((buffer (etaf-gamekit-buffer session))
               (runtime (etaf-runtime-for-buffer buffer))
               (before (etaf-gamekit-observation session)))
          (etaf-focus runtime 'xiangqi-cell-6-4)
          (etaf-activate runtime)
          (etaf-focus runtime 'xiangqi-help)
          (etaf-activate runtime)
          (with-current-buffer buffer
            (call-interactively (key-binding (kbd "<escape>")))
            (let ((text (buffer-substring-no-properties (point-min) (point-max))))
              (should-not (string-match-p "规则与操作" text))
              (should (string-match-p "已选 红兵" text)))
            (call-interactively (key-binding (kbd "<escape>")))
            (let ((text (buffer-substring-no-properties (point-min) (point-max))))
              (should-not (string-match-p "已选" text))))
          (let ((after (etaf-gamekit-observation session)))
            (should (equal before after))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-computer-replies-with-a-search-move ()
  "The default match answers a human move without a second local turn."
  (let ((session (etaf-xiangqi-test--start 11)))
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))))
          (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
          (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 2)))
          (should (= 0 (etaf-gamekit-view session :player)))
          (should (= 0 (etaf-gamekit-view session :current_player)))
          (should (equal "search" (plist-get (etaf-gamekit-view session :bot) :policy)))
          (let ((report (etaf-gamekit-view session :bot)))
            (should (= 4 (plist-get report :requested_depth)))
            (should (<= 1 (plist-get report :depth) 4))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-computer-opening-move-arrives-first ()
  "With the computer on red, its opening move needs no local input."
  (let ((session (etaf-xiangqi-test--start 11 'computer-red)))
    (unwind-protect
        (progn
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1)))
          (should (= 1 (etaf-gamekit-view session :player)))
          (should (= 1 (etaf-gamekit-view session :current_player)))
          ;; Before the human has moved, undo cannot just replay the opening.
          (let ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))))
            (let* ((props (etaf-runtime-host-props-for runtime 'xiangqi-undo))
                   (disabled (plist-get props :disabled)))
              (should disabled))
            (with-current-buffer (etaf-gamekit-buffer session)
              (call-interactively (key-binding (kbd "u"))))
            (etaf-xiangqi-test--wait session)
            (should (= 1 (etaf-gamekit-view session :action_count)))
            (etaf-dispatch-event runtime 'xiangqi-cell-3-4 'press)
            (etaf-dispatch-event runtime 'xiangqi-cell-4-4 'press)
            (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 3)))
            (etaf-dispatch-event runtime 'xiangqi-undo 'press)
            (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1)))
            (should (= 1 (etaf-gamekit-view session :current_player)))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-computer-undo-restores-the-human-turn ()
  "One undo takes back the computer's reply and the human's own move."
  (let ((session (etaf-xiangqi-test--start 11 'computer-black)))
    (unwind-protect
        (let ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))))
          (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
          (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 2)))
          (etaf-dispatch-event runtime 'xiangqi-undo 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 0)))
          (should (eq t (etaf-gamekit-view session :can_redo)))
          (should (= 0 (etaf-gamekit-view session :player)))
          (etaf-dispatch-event runtime 'xiangqi-redo 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 2)))
          (should (= 0 (etaf-gamekit-view session :current_player)))
          (etaf-dispatch-event runtime 'xiangqi-new 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 0))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-settings-switch-to-hot-seat ()
  "The settings dialog hands both sides to the local player."
  (let ((session (etaf-xiangqi-test--start 11 'computer-black)))
    (unwind-protect
        (let* ((buffer (etaf-gamekit-buffer session))
               (runtime (etaf-runtime-for-buffer buffer)))
          (etaf-dispatch-event runtime 'xiangqi-settings 'press)
          (etaf-dispatch-event runtime 'xiangqi-opponent-hot-seat 'press)
          (with-current-buffer buffer (call-interactively (key-binding (kbd "<escape>"))))
          (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
          (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1)))
          (accept-process-output nil 0.5)
          (should (= 1 (etaf-gamekit-view session :action_count)))
          (should (= 1 (etaf-gamekit-view session :player)))
          (with-current-buffer buffer
            (should (string-match-p "同机双人" (buffer-substring-no-properties (point-min) (point-max))))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-settings-level-drives-the-search ()
  "The difficulty picker selects the search budget the backend uses."
  (let ((session (etaf-xiangqi-test--start 11 'computer-black)))
    (unwind-protect
        (let* ((buffer (etaf-gamekit-buffer session))
               (runtime (etaf-runtime-for-buffer buffer)))
          (etaf-dispatch-event runtime 'xiangqi-settings 'press)
          (etaf-dispatch-event runtime 'xiangqi-level-easy 'press)
          (with-current-buffer buffer (call-interactively (key-binding (kbd "<escape>"))))
          (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
          (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 2)))
          (should (= 2 (plist-get (etaf-gamekit-view session :bot) :requested_depth))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-computer-rejection-stops-and-new-match-recovers ()
  "A bot rejection stays visible without retries, and New match recovers."
  (let ((session (etaf-xiangqi-test--start 11 'hot-seat)))
    (unwind-protect
        (let* ((buffer (etaf-gamekit-buffer session))
               (runtime (etaf-runtime-for-buffer buffer)))
          (etaf-gamekit-action session "bot" '(:depth 0))
          (etaf-xiangqi-test--wait session nil t)
          (etaf-dispatch-event runtime 'xiangqi-settings 'press)
          (etaf-dispatch-event runtime 'xiangqi-opponent-computer-red 'press)
          (with-current-buffer buffer (call-interactively (key-binding (kbd "<escape>"))))
          (accept-process-output nil 0.1)
          (etaf-xiangqi-test--wait session nil t)
          (should (= 0 (etaf-gamekit-view session :action_count)))
          (let ((text (with-current-buffer buffer
                        (buffer-substring-no-properties (point-min) (point-max)))))
            (should (string-match-p "操作失败" text))
            (should-not (string-match-p "电脑思考中" text)))
          (etaf-dispatch-event runtime 'xiangqi-new 'press)
          (etaf-xiangqi-test--wait session (lambda () (= (etaf-gamekit-view session :action_count) 1)))
          (should (= 1 (etaf-gamekit-view session :current_player))))
      (etaf-xiangqi-test--close session))))

(provide 'etaf-xiangqi-tests)
;;; etaf-xiangqi-tests.el ends here
