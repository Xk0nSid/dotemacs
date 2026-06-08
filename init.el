;; -*- lexical-binding: t; -*-

;; Disable startup screen
(setq inhibit-startup-message t)

;; Disable UI clutter
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)

;; Better defaults
(setq ring-bell-function 'ignore)

;; Line numbers
(global-display-line-numbers-mode 1)
(setq display-line-numbers-type 'relative)

;; don't show line numbers in these modes
(dolist (mode '(term-mode-hook
                shell-mode-hook
                eshell-mode-hook
                vterm-mode-hook))
  (add-hook mode
            (lambda ()
              (display-line-numbers-mode 0))))

;; highlight current line
(global-hl-line-mode 1)

;; Simpler yes/no
(fset 'yes-or-no-p 'y-or-n-p)

;; clean whitespace
;; (add-hook 'before-save-hook #'delete-trailing-whitespace)

;; dedicated backup directory
(setq backup-directory-alist
      '(("." . "~/.emacs.d/backups")))

(setq create-lockfiles nil)
(setq auto-save-default nil)

;; display tabs and extra whitespaces
(setq whitespace-style '(face trailing))
(global-whitespace-mode 1)

;; Make ESC quit prompts
(global-set-key (kbd "<escape>") 'keyboard-escape-quit)

;; Start maximized
(add-to-list 'default-frame-alist
             '(fullscreen . maximized))

(set-face-attribute 'default nil
                    :font "JetBrainsMono Nerd Font"
                    :height 120)

;; Better frame title
(setq frame-title-format "%b")

;; auto load files changed in background
(global-auto-revert-mode 1)

;; Tabs and shifts
(setq-default tab-width 4)
(setq-default indent-tabs-mode nil)
(setq tab-always-indent t)

;; handle annoying `custom-set-variables` in `init.el`
(setq custom-file
      (expand-file-name "custom.el" user-emacs-directory))
(load custom-file 'noerror)

;; Better buffer management
(global-set-key
 (kbd "C-x C-b")
 #'ibuffer)

(setq project-switch-commands
      '((project-find-file "Find File")
        (consult-ripgrep "Ripgrep")
        (consule-project-buffer "Buffers")
        (project-dired "Dired")))

;; Package system
(require 'package)

(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("gnu"   . "https://elpa.gnu.org/packages/")))

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

;; setup use-package

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(eval-when-compile
  (require 'use-package))

(setq use-package-always-ensure t)

;; dired

;; disable new buffer creation while navigating
;; in dired mode
(setq dired-kill-when-opening-new-dired-buffer t)
(put 'dired-find-alternate-file 'disabled nil)
(with-eval-after-load 'dired
  (define-key dired-mode-map
              (kbd "RET")
              #'dired-find-alternate-file))

;; evil mode
(use-package evil
  :init
  (setq evil-want-C-u-scroll t)
  (setq evil-want-C-i-jump nil)
  (setq evil-want-keybinding nil)

  (setq evil-vsplit-window-right t)
  (setq evil-split-window-below t)

  :config
  (evil-mode 1)
  ;; Prevent yanks and deletes from modifying the system clipboard
  (setq select-enable-clipboard nil)

  ;; Prevent visual selections from modifying the X11 primary selection (Linux)
  (setq select-enable-primary nil)

  ;; Prevent mouse selection from auto-copying to the clipboard
  (setq mouse-drag-copy-region nil))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

(use-package which-key
  :config
  (which-key-mode))

(use-package vertico
  :init
  (vertico-mode))

(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides
        '((file (styles partial-completion)))))

(use-package marginalia
  :init
  (marginalia-mode))

(use-package consult
  :bind
  (("C-s"     . consult-line)
   ("C-x b"   . consult-buffer)
   ("M-y"     . consult-yank-pop)

   ;; Project
   ("C-c p f" . project-find-file)
   ("C-c p b" . consult-project-buffer)
   ("C-c p g" . consult-ripgrep)))

(use-package corfu
  :init
  (global-corfu-mode)

  :custom
  (corfu-auto t)
  (corfu-auto-prefix 2)

  :bind
  (:map corfu-map
        ("TAB" . corfu-next)
        ([tab] . corfu-next)
        ("S-TAB" . corfu-previous)
        ([backtab] . corfu-previous)))

(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-file))

;; Magit
(use-package magit
  :bind
  (("C-x g" . magit-status)))

;; Treesitter
(setq treesit-language-source-alist
      '((zsh "https://github.com/georgeharker/tree-sitter-zsh")
        (c      "https://github.com/tree-sitter/tree-sitter-c")
        (c3 "https://github.com/c3lang/tree-sitter-c3")
        (go     "https://github.com/tree-sitter/tree-sitter-go")
        (gomod  "https://github.com/camdencheek/tree-sitter-go-mod")
        (json   "https://github.com/tree-sitter/tree-sitter-json")
        (python "https://github.com/tree-sitter/tree-sitter-python")
        (rust   "https://github.com/tree-sitter/tree-sitter-rust")
        (toml   "https://github.com/tree-sitter/tree-sitter-toml")
        (yaml   "https://github.com/ikatyang/tree-sitter-yaml")
        (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
        (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")))

(setq treesit-font-lock-level 4)

(use-package eglot
  :init
  (setq eglot-extend-to-xref t)
  :hook
  ((go-ts-mode . eglot-ensure)
   (typescript-ts-mode . eglot-ensure)
   (tsx-ts-mode . eglot-ensure))
   (zig-mode . eglot-ensure))

(add-hook 'eglot-managed-mode-hook
          (lambda ()
            (when (fboundp 'eglot-inlay-hints-mode)
              (eglot-inlay-hints-mode -1))))

(use-package flymake
  :bind
  (("M-n" . flymake-goto-next-error)
   ("M-p" . flymake-goto-prev-error)))

;; DAP for debugging
(use-package dape)

(use-package general
  :after evil
  :config
  (general-create-definer xks/leader
    :states '(normal visual motion)
    :prefix "SPC"
    :keymaps 'override
    :global-prefix "C-SPC")
    ;; leader keymaps
    (xks/leader
      ;; errors
      "e" '(:ignore t :which-key "errors")
      "en" '(flymake-goto-next-error :which-key "next")
      "ep" '(flymake-goto-prev-error :which-key "previous")
      "el" '(flymake-show-buffer-diagnostics :which-key "list")

      ;; debug
      "d" '(:ignore t :which-key "debug")
      "dq" '(dape-quit :which-key "quit")
      "db" '(dape-breakpoint-toggle :which-key "toggle breakpoint")
      "ds" '(dape :which-key "start debugging")
      "dc" '(dape-continue :which-key "continue")
      "dn" '(dape-next :which-key "next")
      "di" '(dape-step-in :which-key "step in")
      "do" '(dape-step-out :which-key "step out")
      "dr" '(dape-restart :which-key "restart")

      ;; files
      "f" '(:ignore t :which-key "files")
      "ff" '(find-file :which-key "find file")
      "fr" '(consult-recent-file :which-key "recent")

      ;; buffers
      "b" '(:ignore t :which-key "buffers")
      "bb" '(consult-buffer :which-key "switch")
      "bk" '(kill-current-buffer :which-key "kill")
      "be" '(eval-buffer :which-key "eval")

      ;; projects
      "p" '(:ignore t :which-key "project")
      "pf" '(project-find-file :which-key "find file")
      "pg" '(consult-ripgrep :which-key "grep")
      "pb" '(consult-project-buffer :which-key "buffers")
      "pp" '(wt-find-project :which-key "Find Worktree Project")

      ;; git
      "g" '(:ignore t :which-key "git")
      "gs" '(magit-status :which-key "status")))

;; compile mode colors
(defun xks/colorize-compilation-buffer ()
  (ansi-color-apply-on-region
   compilation-filter-start
   (point)))

(use-package ansi-color
  :ensure t
  :hook
  (compilation-filter . xks/colorize-compilation-buffer))

(use-package golden-ratio
  :config
  (golden-ratio-mode 1))

(use-package vertico-posframe
  :config
  (vertico-posframe-mode 1))

;; Themes / UI

(use-package doom-themes
  :ensure t
  :config
  (load-theme 'doom-one t))

(use-package kanagawa-themes
  :ensure t)

;; modeline
(use-package doom-modeline
  :init
  (doom-modeline-mode 1))

(use-package solaire-mode
  :config
  (solaire-global-mode +1))

;; ===============
;; Languages
;; ===============

;; == Zig ==
(use-package zig-mode)
(add-hook 'zig-mode-hook
          (lambda ()
            (add-hook 'before-save-hook
                      #'eglot-format-buffer nil t)))
(add-hook 'zig-mode-hook
          (lambda ()
            (setq-local tab-width 4)
            (setq-local indent-tabs-mode nil)))
;; END == Zig ==

;; == Golang ==
(add-to-list 'major-mode-remap-alist
             '(go-mode . go-ts-mode))

(defun xks/go-format-buffer ()
  (when (derived-mode-p 'go-ts-mode)
    (eglot-format-buffer)))

(add-hook 'before-save-hook #'xks/go-format-buffer)

(defun xks-go-mode-setup ()
  (setq-local tab-width 4)
  (setq-local indent-tabs-mode t))

(add-hook 'go-ts-mode-hook #'xks-go-mode-setup)
;; End == Golang ==

;; == Typescript ==

(use-package prettier
  :ensure t)

(defun xks/typescript-style ()
  (setq-local tab-width 2)
  (setq-local standard-indent 2)
  (setq-local typescript-ts-mode-indent-offset 2)
  (setq-local js-indent-level 2)
  (setq-local evil-shift-width 2)
  (setq-local indent-tabs-mode nil))

(add-hook 'typescript-ts-mode-hook #'xks/typescript-style)
(add-hook 'tsx-ts-mode-hook #'xks/typescript-style)
(add-hook 'js-ts-mode-hook #'xks/typescript-style)

(add-hook 'typescript-ts-mode-hook #'eglot-ensure)
(add-hook 'tsx-ts-mode-hook #'eglot-ensure)

;; prettier
(add-hook 'typescript-ts-mode #'prettier-mode)
(add-hook 'tsx-ts-mode #'prettier-mode)

(add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode))
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))
;; END == Typescript ==

;; == Org Mode ==

(use-package org-modern
  :hook
  (org-mode . org-modern-mode))

(use-package mixed-pitch
  :ensure t)

(add-hook 'org-mode-hook #'mixed-pitch-mode)

(with-eval-after-load 'org
  (set-face-attribute 'org-level-1 nil :height 1.25 :weight 'bold)
  (set-face-attribute 'org-level-2 nil :height 1.15 :weight 'bold)
  (set-face-attribute 'org-level-3 nil :height 1.08 :weight 'bold))

(setq org-hide-emphasis-markers t)

;; END == Org Mode ==

(setq warning-minimum-level :error)
