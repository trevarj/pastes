;;; pastes-tests.el --- Tests for pastes.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Offline unit tests for path generation, URL deletion mapping, and git
;; orchestration.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'pastes)

(ert-deftest pastes-test-extension-for-file-wins ()
  (should (equal (pastes--extension-for-source "/tmp/a.rs" 'emacs-lisp-mode)
                 "rs")))

(ert-deftest pastes-test-extension-for-mode-fallback ()
  (should (equal (pastes--extension-for-source nil 'emacs-lisp-mode) "el"))
  (should (equal (pastes--extension-for-source nil 'fundamental-mode) "txt")))

(ert-deftest pastes-test-text-relpath ()
  (should (equal (pastes--text-relpath "abc123" ".el")
                 "r/abc123.el")))

(ert-deftest pastes-test-viewer-url-for-text-relpath ()
  (let ((pastes-public-base-url "https://trevs.site/pastes/"))
    (should (equal (pastes--url-for-relpath "r/abc123.el")
                   "https://trevs.site/pastes/#/t/abc123.el"))))

(ert-deftest pastes-test-viewer-url-for-image-relpath ()
  (let ((pastes-public-base-url "https://trevs.site/pastes/"))
    (should (equal (pastes--url-for-relpath "i/abc123.png")
                   "https://trevs.site/pastes/#/i/abc123.png"))))

(ert-deftest pastes-test-image-relpath ()
  (should (equal (pastes--image-relpath "abc123" ".png")
                 "i/abc123.png")))

(ert-deftest pastes-test-word-slug-shape ()
  (let ((pastes-slug-word-count 3)
        (indices '(0 1 2)))
    (cl-letf (((symbol-function 'pastes--random-slug-index)
               (lambda (_)
                 (prog1 (car indices)
                   (setq indices (cdr indices))))))
      (should (equal (pastes--word-slug)
                     "shell-byte-patch")))))

(ert-deftest pastes-test-word-slug-avoids-repeated-words ()
  (let ((pastes-slug-word-count 3)
        (indices '(0 0 1 1 2)))
    (cl-letf (((symbol-function 'pastes--random-slug-index)
               (lambda (_)
                 (prog1 (car indices)
                   (setq indices (cdr indices))))))
      (should (equal (pastes--word-slug)
                     "shell-byte-patch")))))

(ert-deftest pastes-test-random-text-path-retries-on-word-slug-collision ()
  (let ((pastes-repository-directory (make-temp-file "pastes-test-" t))
        (slugs '("shell-byte-patch"
                 "kernel-merge-daemon")))
    (make-directory (pastes--repo-file "r") t)
    (write-region "" nil
                  (pastes--repo-file
                   "r/shell-byte-patch.el"))
    (cl-letf (((symbol-function 'pastes--word-slug)
               (lambda ()
                 (prog1 (car slugs)
                   (setq slugs (cdr slugs))))))
      (should (equal (pastes--random-text-path "el")
                     '("kernel-merge-daemon"
                       . "r/kernel-merge-daemon.el"))))))

(ert-deftest pastes-test-relative-path-from-url ()
  (let ((pastes-public-base-url "https://trevs.site/pastes/"))
    (should (equal (pastes--relative-path-from-url
                    "https://trevs.site/pastes/#/t/abc.el")
                   "t/abc.el"))))

(ert-deftest pastes-test-relative-path-from-old-pages-url ()
  (let ((pastes-public-base-url "https://trevs.site/pastes/"))
    (should (equal (pastes--relative-path-from-url
                    "https://trevs.site/pastes/t/abc.html")
                   "t/abc.html"))))

(ert-deftest pastes-test-delete-text-path-includes-raw-sidecar ()
  (let ((pastes-repository-directory (make-temp-file "pastes-test-" t)))
    (make-directory (pastes--repo-file "r") t)
    (write-region "" nil (pastes--repo-file "r/abc.el"))
    (should (equal (sort (pastes--delete-relpaths "t/abc.html") #'string<)
                   '("r/abc.el" "t/abc.html")))))

(ert-deftest pastes-test-delete-viewer-text-path-deletes-raw ()
  (should (equal (pastes--delete-relpaths "t/abc.el") '("r/abc.el"))))

(ert-deftest pastes-test-delete-image-path ()
  (should (equal (pastes--delete-relpaths "i/abc.png") '("i/abc.png"))))

(ert-deftest pastes-test-unsafe-delete-path-rejected ()
  (should-error (pastes--delete-relpaths "t/../secret") :type 'user-error))

(ert-deftest pastes-test-clipboard-command-unavailable ()
  (let ((pastes-clipboard-image-commands
         '((missing :command "definitely-not-a-real-clipboard-tool"))))
    (should-error (pastes--clipboard-image-to-file "/tmp/nope.png")
                  :type 'user-error)))

(ert-deftest pastes-test-record-manifest-entry ()
  (let ((pastes-repository-directory (make-temp-file "pastes-test-" t)))
    (cl-letf (((symbol-function 'pastes--manifest-timestamp)
               (lambda () "2026-07-03T11:01:18Z")))
      (pastes--record-manifest-entry "r/a.el")
      (should (equal (pastes--manifest-lines)
                     '("2026-07-03T11:01:18Z\tr/a.el"))))))

(ert-deftest pastes-test-record-manifest-entry-replaces-existing-path ()
  (let ((pastes-repository-directory (make-temp-file "pastes-test-" t)))
    (pastes--write-manifest-lines
     '("2026-06-01T00:00:00Z\tr/a.el"
       "malformed"))
    (cl-letf (((symbol-function 'pastes--manifest-timestamp)
               (lambda () "2026-07-03T11:01:18Z")))
      (pastes--record-manifest-entry "r/a.el")
      (should (equal (pastes--manifest-lines)
                     '("malformed"
                       "2026-07-03T11:01:18Z\tr/a.el"))))))

(ert-deftest pastes-test-remove-manifest-entries ()
  (let ((pastes-repository-directory (make-temp-file "pastes-test-" t)))
    (pastes--write-manifest-lines
     '("2026-07-03T11:01:18Z\tr/a.el"
       "2026-07-03T11:01:18Z\ti/a.png"))
    (pastes--remove-manifest-entries '("r/a.el"))
    (should (equal (pastes--manifest-lines)
                   '("2026-07-03T11:01:18Z\ti/a.png")))))

(ert-deftest pastes-test-preview-text-uses-quit-key-buffer-mode ()
  (cl-letf (((symbol-function 'display-buffer) #'ignore)
            ((symbol-function 'yes-or-no-p) (lambda (_) t)))
    (should (pastes--preview-text "x.el" "(message \"x\")"))
    (with-current-buffer "*pastes preview*"
      (should (derived-mode-p 'pastes-preview-mode))
      (should buffer-read-only)
      (should (eq (keymap-lookup (current-local-map) "q") #'quit-window)))))

(ert-deftest pastes-test-preview-image-uses-quit-key-buffer-mode ()
  (let ((file (make-temp-file "pastes-test-image-" nil ".txt")))
    (unwind-protect
        (cl-letf (((symbol-function 'display-buffer) #'ignore)
                  ((symbol-function 'display-images-p) (lambda () nil))
                  ((symbol-function 'yes-or-no-p) (lambda (_) t)))
          (should (pastes--preview-image file))
          (with-current-buffer "*pastes image preview*"
            (should (derived-mode-p 'pastes-preview-mode))
            (should buffer-read-only)
            (should (eq (keymap-lookup (current-local-map) "q") #'quit-window))))
      (delete-file file))))

(ert-deftest pastes-test-publish-transaction-amends-and-pushes ()
  (let* ((pastes-repository-directory (make-temp-file "pastes-test-" t))
         (calls nil)
         (pastes--git-runner
          (lambda (args &optional allow-failure)
            (push args calls)
            (cond
             ((equal args '("status" "--porcelain")) "")
             ((equal args '("rev-parse" "--verify" "HEAD")) (cons 0 "HEAD"))
             ((equal args '("branch" "--show-current")) "main")
             ((equal args '("diff" "--cached" "--name-only")) "r/a.el")
             ((member "push" args) (if allow-failure (cons 0 "") ""))
             (allow-failure (cons 0 ""))
             (t "")))))
    (make-directory (pastes--repo-file ".git") t)
    (pastes--publish-transaction
     (lambda ()
       (pastes--write-string-file (pastes--repo-file "r/a.el") "x")
       '("r/a.el")))
    (setq calls (nreverse calls))
    (should (member '("commit" "--amend" "--no-edit") calls))
    (should (member '("push" "--force-with-lease" "origin" "main") calls))))

(ert-deftest pastes-test-publish-text-writes-raw-only ()
  (let* ((pastes-repository-directory (make-temp-file "pastes-test-" t))
         (pastes-public-base-url "https://trevs.site/pastes/")
         (calls nil)
         (pastes--git-runner
          (lambda (args &optional allow-failure)
            (push args calls)
            (cond
             ((equal args '("status" "--porcelain")) "")
             ((equal args '("rev-parse" "--verify" "HEAD")) (cons 0 "HEAD"))
             ((equal args '("branch" "--show-current")) "main")
             ((equal args '("diff" "--cached" "--name-only"))
              "r/shell-byte-patch.el\n.pastes-manifest")
             ((member "push" args) (if allow-failure (cons 0 "") ""))
             (allow-failure (cons 0 ""))
             (t "")))))
    (make-directory (pastes--repo-file ".git") t)
    (cl-letf (((symbol-function 'pastes--word-slug)
               (lambda () "shell-byte-patch"))
              ((symbol-function 'pastes--manifest-timestamp)
               (lambda () "2026-07-03T11:01:18Z"))
              ((symbol-function 'kill-new) #'ignore))
      (should (equal (pastes--publish-text "(message \"x\")" "x.el" "el")
                     "https://trevs.site/pastes/#/t/shell-byte-patch.el")))
    (should (file-exists-p (pastes--repo-file "r/shell-byte-patch.el")))
    (should-not (file-exists-p (pastes--repo-file "t/shell-byte-patch.html")))
    (should (equal (pastes--manifest-lines)
                   '("2026-07-03T11:01:18Z\tr/shell-byte-patch.el")))
    (should (member '("add" "-A" "--"
                      "r/shell-byte-patch.el"
                      ".pastes-manifest")
                    calls))))

(provide 'pastes-tests)
;;; pastes-tests.el ends here
