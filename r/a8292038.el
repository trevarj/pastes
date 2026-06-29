(use-package pastes
  :vc (:url "git@github.com:trevarj/pastes.git"
       :branch "main"
       :lisp-dir "elisp"
       :main-file "pastes.el"
       :rev :newest)
  :commands (pastes-setup
             pastes-region
             pastes-buffer
             pastes-file
             pastes-clipboard-image
             pastes-delete-url))