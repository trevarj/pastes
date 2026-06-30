;;; pastes.el --- Git-backed pastebin frontend  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Trevor Arjeski

;; Author: Trevor Arjeski <tmarjeski@gmail.com>
;; Keywords: comm, convenience, files
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Publish text and image pastes to a personal Git repository.  Uploads
;; preview before publishing, copy a single viewer URL to the kill ring, and
;; keep the public branch as a single live snapshot by amending and pushing
;; with --force-with-lease.
;;
;; Deletion is best-effort public cleanup only.  Once content has been pushed
;; to GitHub or GitHub Pages, treat it as exposed.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-parse)

(defgroup pastes nil
  "Publish pastes to a GitHub Pages repository."
  :group 'comm
  :prefix "pastes-")

(defcustom pastes-repository-directory
  (expand-file-name "~/Workspace/pastes")
  "Local checkout used for publishing pastes."
  :type 'directory)

(defcustom pastes-repository-url
  "git@github.com:trevarj/pastes.git"
  "Git remote URL used by `pastes-setup' when cloning the repository."
  :type 'string)

(defcustom pastes-public-base-url
  "https://trevs.site/pastes/"
  "Public GitHub Pages viewer base URL for paste links."
  :type 'string)

(defcustom pastes-branch "main"
  "Branch used for the GitHub Pages root."
  :type 'string)

(defcustom pastes-slug-length 8
  "Obsolete length of random hexadecimal paste slugs."
  :type 'natnum)

(make-obsolete-variable 'pastes-slug-length
                        'pastes-slug-word-count
                        "0.2.0")

(defcustom pastes-slug-word-count 3
  "Number of words in generated paste slugs."
  :type 'natnum)

(defcustom pastes-large-file-warning-bytes (* 5 1024 1024)
  "Warn before publishing content larger than this many bytes.
Set to nil to disable the warning."
  :type '(choice natnum (const :tag "No warning" nil)))

(defcustom pastes-clipboard-image-commands
  '((wl-paste :command "wl-paste" :args ("--type" "image/png"))
    (xclip :command "xclip" :args ("-selection" "clipboard" "-t" "image/png" "-o"))
    (pngpaste :command "pngpaste" :file-arg t))
  "Clipboard image commands tried by `pastes-clipboard-image'.
Entries with :file-arg receive the output file path as the final argument.
Other entries are expected to write PNG bytes to stdout."
  :type '(repeat sexp))

(defconst pastes--mode-extension-alist
  '((emacs-lisp-mode . "el")
    (lisp-interaction-mode . "el")
    (scheme-mode . "scm")
    (rust-mode . "rs")
    (rust-ts-mode . "rs")
    (python-mode . "py")
    (python-ts-mode . "py")
    (sh-mode . "sh")
    (bash-ts-mode . "sh")
    (c-mode . "c")
    (c-ts-mode . "c")
    (c++-mode . "cpp")
    (c++-ts-mode . "cpp")
    (js-mode . "js")
    (js-ts-mode . "js")
    (json-mode . "json")
    (json-ts-mode . "json")
    (css-mode . "css")
    (css-ts-mode . "css")
    (html-mode . "html")
    (mhtml-mode . "html")
    (yaml-mode . "yaml")
    (yaml-ts-mode . "yaml")
    (org-mode . "org")
    (markdown-mode . "md")
    (markdown-ts-mode . "md")
    (makefile-gmake-mode . "mk"))
  "Major-mode to file-extension mapping for text pastes.")

(defconst pastes--image-extensions
  '("png" "jpg" "jpeg" "gif" "webp" "svg" "avif")
  "Image file extensions published as direct image URLs.")

(defvar pastes--git-runner nil
  "Function used to run git commands.
Tests bind this to avoid invoking git.")

(define-derived-mode pastes-preview-mode special-mode "Pastes-Preview"
  "Major mode for paste preview buffers.")

(defun pastes--repo-dir ()
  "Return normalized `pastes-repository-directory'."
  (file-name-as-directory (expand-file-name pastes-repository-directory)))

(defun pastes--repo-file (relative)
  "Return absolute path for RELATIVE inside the paste repository."
  (expand-file-name relative (pastes--repo-dir)))

(defun pastes--url-for-relpath (relative)
  "Return public viewer URL for repository-relative path RELATIVE."
  (concat (file-name-as-directory pastes-public-base-url)
          "#/"
          (if (string-prefix-p "r/" relative)
              (concat "t/" (substring relative 2))
            relative)))

(defun pastes--ensure-parent-directory (file)
  "Create FILE's parent directory if needed."
  (make-directory (file-name-directory file) t))

(defun pastes--write-string-file (file string)
  "Write STRING to FILE as UTF-8."
  (pastes--ensure-parent-directory file)
  (let ((coding-system-for-write 'utf-8-unix))
    (with-temp-file file
      (insert string))))

(defun pastes--write-binary-file (file string)
  "Write STRING bytes to FILE without coding conversion."
  (pastes--ensure-parent-directory file)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file file
      (insert string))))

(defun pastes--git-run (args &optional allow-failure)
  "Run git ARGS in `pastes-repository-directory'.
When ALLOW-FAILURE is non-nil, return (STATUS . OUTPUT).  Otherwise
signal `user-error' on failure and return OUTPUT."
  (let ((default-directory (pastes--repo-dir)))
    (with-temp-buffer
      (let ((status (apply #'process-file "git" nil (list (current-buffer) t) nil args))
            (output (string-trim (buffer-string))))
        (if allow-failure
            (cons status output)
          (unless (zerop status)
            (user-error "git %s failed: %s" (string-join args " ") output))
          output)))))

(defun pastes--git (args &optional allow-failure)
  "Run git ARGS through `pastes--git-runner' or `pastes--git-run'."
  (funcall (or pastes--git-runner #'pastes--git-run) args allow-failure))

(defun pastes--ensure-repo ()
  "Signal unless `pastes-repository-directory' is a Git checkout."
  (unless (file-directory-p (pastes--repo-file ".git"))
    (user-error "Paste checkout missing; run M-x pastes-setup")))

(defun pastes--git-clean-p ()
  "Return non-nil when the paste checkout has no local changes."
  (string-empty-p (pastes--git '("status" "--porcelain"))))

(defun pastes--ensure-clean ()
  "Signal unless the paste checkout is clean."
  (unless (pastes--git-clean-p)
    (user-error "Paste checkout is dirty; resolve it before publishing")))

(defun pastes--head-exists-p ()
  "Return non-nil when the paste checkout has at least one commit."
  (zerop (car (pastes--git '("rev-parse" "--verify" "HEAD") t))))

(defun pastes--ensure-branch ()
  "Ensure the checkout is on `pastes-branch'."
  (if (pastes--head-exists-p)
      (let ((branch (pastes--git '("branch" "--show-current"))))
        (unless (string= branch pastes-branch)
          (user-error "Paste checkout is on %s, expected %s" branch pastes-branch)))
    (pastes--git (list "checkout" "-B" pastes-branch))))

(defun pastes--bootstrap-tree ()
  "Ensure the repository has the directories used by pastes."
  (dolist (dir '("elisp" "r" "i"))
    (make-directory (pastes--repo-file dir) t))
  (dolist (keep '("r/.gitkeep" "i/.gitkeep"))
    (unless (file-exists-p (pastes--repo-file keep))
      (pastes--write-string-file (pastes--repo-file keep) ""))))

(defconst pastes--slug-words
  ["shell" "byte" "patch" "agent" "alias" "api" "archive" "array"
   "async" "atom" "backend" "backup" "binary" "bind" "bit" "blob"
   "block" "branch" "buffer" "build" "bundle" "cache" "call" "channel"
   "check" "cipher" "class" "client" "clone" "cloud" "codec" "commit"
   "config" "console" "core" "cursor" "daemon" "data" "debug" "delta"
   "deploy" "diff" "digest" "disk" "docker" "domain" "driver" "dump"
   "edge" "editor" "entry" "event" "export" "fetch" "fiber" "field"
   "file" "filter" "flag" "frame" "gateway" "graph" "grid" "hash"
   "hook" "host" "index" "input" "kernel" "key" "lambda" "ledger"
   "link" "linux" "list" "loader" "lock" "log" "macro" "map"
   "matrix" "merge" "message" "module" "monitor" "mount" "node" "object"
   "origin" "output" "packet" "page" "parse" "path" "peer" "pipe"
   "pixel" "plugin" "port" "process" "proxy" "queue" "query" "record"
   "ref" "remote" "render" "repo" "request" "route" "runtime" "schema"
   "script" "server" "signal" "socket" "source" "stack" "state" "store"
   "stream" "string" "sync" "system" "target" "task" "terminal" "thread"
   "token" "trace" "tree" "tty" "type" "unit" "update" "vector"
   "vendor" "view" "worker" "zone"]
  "Words used to generate hacker-style paste slugs.")

(defvar pastes--slug-random-counter 0
  "Counter mixed into slug randomness.")

(defun pastes--slug-word-space-size ()
  "Return the number of available slug words."
  (length pastes--slug-words))

(defun pastes--random-slug-index (limit)
  "Return a random index below LIMIT."
  (setq pastes--slug-random-counter (1+ pastes--slug-random-counter))
  (mod
   (string-to-number
    (substring
     (secure-hash 'sha256
                  (format "%s:%s:%s:%s:%s:%s"
                          (float-time)
                          (random t)
                          (emacs-pid)
                          (user-uid)
                          pastes--slug-random-counter
                          limit))
     0 12)
    16)
   limit))

(defun pastes--slug-word (index)
  "Return slug word at INDEX."
  (aref pastes--slug-words index))

(defun pastes--word-slug ()
  "Return a random human-friendly paste slug."
  (unless (and (integerp pastes-slug-word-count)
               (> pastes-slug-word-count 0))
    (user-error "pastes-slug-word-count must be a positive integer"))
  (let ((space-size (pastes--slug-word-space-size)))
    (when (> pastes-slug-word-count space-size)
      (user-error "pastes-slug-word-count exceeds available slug words"))
    (string-join
     (cl-loop with chosen = nil
              repeat pastes-slug-word-count
              for index = (let ((candidate
                                 (pastes--random-slug-index space-size)))
                            (while (memq candidate chosen)
                              (setq candidate
                                    (pastes--random-slug-index space-size)))
                            candidate)
              do (push index chosen)
              collect (pastes--slug-word index))
     "-")))

(defun pastes--text-relpath (slug extension)
  "Return raw text relative path for SLUG and EXTENSION."
  (let ((ext (string-remove-prefix "." extension)))
    (format "r/%s.%s" slug ext)))

(defun pastes--image-relpath (slug extension)
  "Return image relative path for SLUG and EXTENSION."
  (format "i/%s.%s" slug (string-remove-prefix "." extension)))

(defun pastes--path-exists-p (relative)
  "Return non-nil when RELATIVE exists in the paste checkout."
  (file-exists-p (pastes--repo-file relative)))

(defun pastes--random-text-path (extension)
  "Return random non-colliding text path for EXTENSION."
  (cl-loop
   for slug = (pastes--word-slug)
   for path = (pastes--text-relpath slug extension)
   unless (pastes--path-exists-p path)
   return (cons slug path)))

(defun pastes--random-image-path (extension)
  "Return random non-colliding image path for EXTENSION."
  (cl-loop
   for slug = (pastes--word-slug)
   for path = (pastes--image-relpath slug extension)
   unless (pastes--path-exists-p path)
   return (cons slug path)))

(defun pastes--extension-for-source (&optional file mode)
  "Return text extension for FILE or MODE."
  (or (and file (file-name-extension file))
      (alist-get (or mode major-mode) pastes--mode-extension-alist)
      "txt"))

(defun pastes--image-file-p (file)
  "Return non-nil when FILE has a supported image extension."
  (member (downcase (or (file-name-extension file) "")) pastes--image-extensions))

(defun pastes--preview-text (title text)
  "Preview TEXT under TITLE and return non-nil when confirmed."
  (let ((buffer (get-buffer-create "*pastes preview*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text)
        (goto-char (point-min))
        (pastes-preview-mode)))
    (display-buffer buffer)
    (yes-or-no-p (format "Publish text paste %s? " title))))

(defun pastes--preview-image (file)
  "Preview image FILE and return non-nil when confirmed."
  (let ((buffer (get-buffer-create "*pastes image preview*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (display-images-p)
            (condition-case _
                (insert-image (create-image file))
              (error (insert (format "Image: %s\n" file))))
          (insert (format "Image: %s\n" file)))
        (goto-char (point-min))
        (pastes-preview-mode)))
    (display-buffer buffer)
    (yes-or-no-p (format "Publish image %s? " (file-name-nondirectory file)))))

(defun pastes--confirm-large-string (string)
  "Confirm when STRING is larger than `pastes-large-file-warning-bytes'."
  (or (not pastes-large-file-warning-bytes)
      (<= (string-bytes string) pastes-large-file-warning-bytes)
      (yes-or-no-p
       (format "Paste is %.1f MiB; publish anyway? "
               (/ (float (string-bytes string)) 1048576)))))

(defun pastes--confirm-large-file (file)
  "Confirm when FILE is larger than `pastes-large-file-warning-bytes'."
  (or (not pastes-large-file-warning-bytes)
      (<= (file-attribute-size (file-attributes file)) pastes-large-file-warning-bytes)
      (yes-or-no-p
       (format "File is %.1f MiB; publish anyway? "
               (/ (float (file-attribute-size (file-attributes file))) 1048576)))))

(defun pastes--commit-staged ()
  "Commit staged changes by creating or amending the live snapshot."
  (if (pastes--head-exists-p)
      (pastes--git '("commit" "--amend" "--no-edit"))
    (pastes--git (list "commit" "-m" "Initialize pastes"))))

(defun pastes--push (&optional allow-failure)
  "Push the live snapshot.
When ALLOW-FAILURE is non-nil, return a git status cons."
  (pastes--git (list "push" "--force-with-lease" "origin" pastes-branch)
               allow-failure))

(defun pastes--commit-relative-files (relative-files)
  "Stage and commit RELATIVE-FILES."
  (pastes--git (append '("add" "-A" "--") relative-files))
  (let ((diff (pastes--git '("diff" "--cached" "--name-only"))))
    (when (string-empty-p diff)
      (user-error "No paste changes to publish")))
  (pastes--commit-staged))

(defun pastes--publish-transaction (writer)
  "Publish changes produced by WRITER.
WRITER writes files into the checkout and returns repository-relative files to
stage.  On a lease failure, fetch/reset to the remote branch, replay WRITER,
and retry once."
  (pastes--ensure-repo)
  (pastes--ensure-clean)
  (pastes--ensure-branch)
  (let* ((relative-files (funcall writer)))
    (pastes--commit-relative-files relative-files)
    (pcase-let ((`(,status . ,output) (pastes--push t)))
      (if (zerop status)
          output
        (pastes--git (list "fetch" "origin" pastes-branch))
        (pastes--git (list "reset" "--hard" (format "origin/%s" pastes-branch)))
        (setq relative-files (funcall writer))
        (pastes--commit-relative-files relative-files)
        (pcase-let ((`(,retry-status . ,retry-output) (pastes--push t)))
          (unless (zerop retry-status)
            (user-error "git push failed: %s\nInitial failure: %s"
                        retry-output output))
          retry-output)))))

(defun pastes--publish-text (text _title extension)
  "Publish TEXT with EXTENSION and return the public URL."
  (let* ((slug-and-path (pastes--random-text-path extension))
         (raw-relative (cdr slug-and-path))
         (url (pastes--url-for-relpath raw-relative)))
    (pastes--publish-transaction
     (lambda ()
       (pastes--write-string-file (pastes--repo-file raw-relative) text)
       (list raw-relative)))
    (kill-new url)
    (message "Paste URL: %s" url)
    url))

(defun pastes--publish-image (file)
  "Publish image FILE and return the public URL."
  (let* ((extension (downcase (or (file-name-extension file) "png")))
         (slug-and-path (pastes--random-image-path extension))
         (relative (cdr slug-and-path))
         (url (pastes--url-for-relpath relative)))
    (pastes--publish-transaction
     (lambda ()
       (copy-file file (pastes--repo-file relative) t)
       (list relative)))
    (kill-new url)
    (message "Paste URL: %s" url)
    url))

(defun pastes--read-text-file (file)
  "Return textual contents of FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

;;;###autoload
(defun pastes-setup ()
  "Clone or bootstrap `pastes-repository-directory'."
  (interactive)
  (unless (file-directory-p (pastes--repo-dir))
    (make-directory (file-name-directory (directory-file-name (pastes--repo-dir))) t)
    (let ((default-directory (file-name-directory (directory-file-name (pastes--repo-dir)))))
      (with-temp-buffer
        (let ((status (process-file "git" nil (list (current-buffer) t) nil
                                    "clone" pastes-repository-url
                                    (file-name-nondirectory
                                     (directory-file-name (pastes--repo-dir))))))
          (unless (zerop status)
            (user-error "git clone failed: %s" (string-trim (buffer-string))))))))
  (pastes--ensure-repo)
  (pastes--ensure-clean)
  (pastes--ensure-branch)
  (pastes--bootstrap-tree)
  (message "pastes checkout ready: %s" (pastes--repo-dir)))

;;;###autoload
(defun pastes-region (start end)
  "Preview and publish the active region from START to END."
  (interactive "r")
  (unless (use-region-p)
    (user-error "No active region"))
  (let* ((text (buffer-substring-no-properties start end))
         (extension (pastes--extension-for-source buffer-file-name major-mode))
         (title (format "paste.%s" extension)))
    (when (and (pastes--confirm-large-string text)
               (pastes--preview-text title text))
      (pastes--publish-text text title extension))))

;;;###autoload
(defun pastes-buffer ()
  "Preview and publish the current buffer."
  (interactive)
  (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
         (extension (pastes--extension-for-source buffer-file-name major-mode))
         (title (or (buffer-file-name)
                    (buffer-name))))
    (when (and (pastes--confirm-large-string text)
               (pastes--preview-text (file-name-nondirectory title) text))
      (pastes--publish-text text (file-name-nondirectory title) extension))))

;;;###autoload
(defun pastes-file (file)
  "Preview and publish FILE."
  (interactive "fPaste file: ")
  (setq file (expand-file-name file))
  (unless (file-regular-p file)
    (user-error "Not a regular file: %s" file))
  (if (pastes--image-file-p file)
      (when (and (pastes--confirm-large-file file)
                 (pastes--preview-image file))
        (pastes--publish-image file))
    (let* ((text (pastes--read-text-file file))
           (extension (pastes--extension-for-source file major-mode)))
      (when (and (pastes--confirm-large-string text)
                 (pastes--preview-text (file-name-nondirectory file) text))
        (pastes--publish-text text (file-name-nondirectory file) extension)))))

(defun pastes--clipboard-command ()
  "Return the first available clipboard image command spec."
  (cl-find-if
   (lambda (entry)
     (executable-find (plist-get (cdr entry) :command)))
   pastes-clipboard-image-commands))

(defun pastes--clipboard-image-to-file (file)
  "Write clipboard image PNG bytes to FILE."
  (let* ((entry (pastes--clipboard-command))
         (spec (cdr entry)))
    (unless entry
      (user-error "No clipboard image command found; install wl-paste, xclip, or pngpaste"))
    (if (plist-get spec :file-arg)
        (with-temp-buffer
          (let ((status (apply #'process-file
                               (plist-get spec :command) nil
                               (list (current-buffer) t) nil
                               (append (plist-get spec :args) (list file)))))
            (unless (zerop status)
              (user-error "%s failed: %s"
                          (plist-get spec :command)
                          (string-trim (buffer-string))))))
      (with-temp-buffer
        (let ((coding-system-for-read 'no-conversion)
              (coding-system-for-write 'no-conversion)
              (status (apply #'process-file
                             (plist-get spec :command) nil t nil
                             (plist-get spec :args))))
          (unless (zerop status)
            (user-error "%s failed reading clipboard image" (plist-get spec :command)))
          (pastes--write-binary-file file (buffer-string)))))))

;;;###autoload
(defun pastes-clipboard-image ()
  "Preview and publish a PNG image from the system clipboard."
  (interactive)
  (let ((file (make-temp-file "pastes-clipboard-" nil ".png")))
    (unwind-protect
        (progn
          (pastes--clipboard-image-to-file file)
          (when (and (pastes--confirm-large-file file)
                     (pastes--preview-image file))
            (pastes--publish-image file)))
      (when (file-exists-p file)
        (delete-file file)))))

(defun pastes--relative-path-from-url (url)
  "Return repository-relative paste path for public URL URL."
  (let* ((base (file-name-as-directory pastes-public-base-url))
         (parsed (url-generic-parse-url url))
         (path (url-filename parsed))
         (target (url-target parsed)))
    (cond
     ((and target (string-prefix-p "/" target))
      (substring target 1))
     ((and target (not (string-empty-p target)))
      target)
     ((string-prefix-p base url)
      (substring url (length base)))
     ((string-prefix-p "/pastes/" path)
      (substring path (length "/pastes/")))
     (t
      (user-error "URL is not under %s" base)))))

(defun pastes--safe-relative-path-p (relative)
  "Return non-nil when RELATIVE is a safe paste path."
  (and (not (string-empty-p relative))
       (not (string-prefix-p "/" relative))
       (not (string-match-p "\\(?:^\\|/\\)\\.\\.\\(?:/\\|$\\)" relative))))

(defun pastes--delete-relpaths (relative)
  "Return repository-relative files deleted for RELATIVE."
  (unless (pastes--safe-relative-path-p relative)
    (user-error "Unsafe paste path: %s" relative))
  (pcase-let ((`(,kind ,name) (split-string relative "/" t)))
    (pcase kind
      ("t"
       (if (string-suffix-p ".html" name)
           (let* ((slug (file-name-sans-extension name))
                  (raws (directory-files (pastes--repo-file "r") nil
                                         (concat "\\`" (regexp-quote slug) "\\."))))
             (append (list relative)
                     (mapcar (lambda (raw) (concat "r/" raw)) raws)))
         (list (concat "r/" name))))
      ("r"
       (let ((slug (file-name-sans-extension name)))
         (list relative (format "t/%s.html" slug))))
      ("i" (list relative))
      (_ (user-error "Not a paste URL path: %s" relative)))))

;;;###autoload
(defun pastes-delete-url (url)
  "Delete paste files addressed by public URL URL and publish the removal."
  (interactive "sPaste URL: ")
  (let* ((relative (pastes--relative-path-from-url url))
         (targets (cl-remove-if-not #'pastes--path-exists-p
                                    (pastes--delete-relpaths relative))))
    (unless targets
      (user-error "No matching paste files for %s" url))
    (unless (yes-or-no-p
             "Delete from current Pages snapshot? This is not secure deletion. ")
      (user-error "Aborted"))
    (pastes--publish-transaction
     (lambda ()
       (dolist (target targets)
         (let ((file (pastes--repo-file target)))
           (when (file-exists-p file)
             (delete-file file))))
       targets))
    (message "Deleted paste from current Pages snapshot: %s" url)))

(provide 'pastes)
;;; pastes.el ends here
