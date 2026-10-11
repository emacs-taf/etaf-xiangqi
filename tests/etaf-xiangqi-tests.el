;;; -*- lexical-binding: t; -*-
;;; etaf-xiangqi-tests.el --- Public Xiangqi behavior
;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Code:
(require 'ert)
(require 'etaf-xiangqi)

(defun etaf-xiangqi-test--wait (session &optional predicate)
  "Await SESSION's painted board and optional PREDICATE."
  (let ((end (+ (float-time) 8)))
    (while (and (< (float-time) end)
                (not (memq (etaf-gamekit-status session) '(failed closed)))
                (or (not (eq (etaf-gamekit-status session) 'ready))
                    (and predicate (not (funcall predicate)))))
      (accept-process-output nil 0.01)))
  (should (eq (etaf-gamekit-status session) 'ready))
  (should-not (etaf-gamekit-last-error session))
  (when predicate (should (funcall predicate))))

(defun etaf-xiangqi-test--close (session)
  "Dispose the application INSTANCE and its buffer."
  (when session (etaf-xiangqi-close session)))

(defun etaf-xiangqi-test--start (seed)
  "Start an independent match with integer SEED and its painted board."
  (let* ((session (etaf-gamekit-start etaf-xiangqi-game :options (list :seed seed)))
         (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session))))
    (etaf-runtime-refit runtime 1100 44)
    (etaf-xiangqi-test--wait session)
    (etaf-xiangqi-test--wait session (lambda () (etaf-host-ref-size runtime 'xiangqi-board)))
    session))

(ert-deftest etaf-xiangqi-hot-seat-moves-and-undo-restores ()
  "Red and black alternate through the public board; undo restores the opening."
  (let ((session (etaf-xiangqi-test--start 11)))
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
  (let ((session (etaf-xiangqi-test--start 11)))
    (unwind-protect
        (let ((before (etaf-gamekit-observation session)))
          (etaf-gamekit-action session "act" (list :action 1234567))
          (accept-process-output nil 0.3)
          (should (etaf-gamekit-last-error session))
          (should (equal before (etaf-gamekit-observation session))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-themes-preserve-the-match ()
  "Light/dark switching preserves the match, selection and board metrics."
  (let ((session (etaf-xiangqi-test--start 11)))
    (unwind-protect
        (let* ((runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer session)))
               (before (etaf-gamekit-observation session))
               (size (etaf-host-ref-size runtime 'xiangqi-board)))
          (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
          (dotimes (_ 2)
            (etaf-dispatch-event runtime 'xiangqi-theme 'press)
            (should (equal before (etaf-gamekit-observation session)))
            (should (equal size (etaf-host-ref-size runtime 'xiangqi-board)))))
      (etaf-xiangqi-test--close session))))

(ert-deftest etaf-xiangqi-matches-are-independent ()
  "A move in one match cannot change a second match."
  (let ((first (etaf-xiangqi-test--start 11)))
    (unwind-protect
        (let ((second (etaf-xiangqi-test--start 11)))
          (unwind-protect
              (let ((before (etaf-gamekit-observation second))
                    (runtime (etaf-runtime-for-buffer (etaf-gamekit-buffer first))))
                (etaf-dispatch-event runtime 'xiangqi-cell-6-4 'press)
                (etaf-dispatch-event runtime 'xiangqi-cell-5-4 'press)
                (etaf-xiangqi-test--wait first (lambda () (= (etaf-gamekit-view first :action_count) 1)))
                (should (equal before (etaf-gamekit-observation second))))
            (etaf-xiangqi-test--close second)))
      (etaf-xiangqi-test--close first))))

(provide 'etaf-xiangqi-tests)
;;; etaf-xiangqi-tests.el ends here
