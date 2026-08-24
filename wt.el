;;; wt.el --- Worktree UI -*- lexical-binding: t; -*-

(require 'tabulated-list)

;; == Vars ==

(defvar wt-buffer-name "*Worktrees*")
(defvar-local wt-current-repo nil)

(defgroup wt nil
  "Git worktree management."
  :group 'tools)

(defcustom wt-projects-directory "~/workspace/projects"
  "Directory containing Git repositories."
  :type 'directory
  :group 'wt)

(defcustom wt-workspace-directory "workspace"
  "Directory inside a repo where worktrees are created."
  :type 'string
  :group 'wt)

;; == Utils ==

(defun wt-parse-group (group)
  (let (worktree branch root)
    (dolist (line group)
      (cond
       ((string-prefix-p "worktree " line)
        (setq worktree
              (string-remove-prefix "worktree " line)))

       ((string-prefix-p "branch " line)
        (setq branch
              (string-remove-prefix
               "refs/heads/"
               (string-remove-prefix "branch " line)))

        ;; normal worktrees are not root
        (setq root nil))

       ((string= line "bare")
        (setq root t))))

    (list :worktree worktree
          :branch branch
          :root root)))

(defun wt-parse-groups (groups)
  "Parse worktree list command output"
  (mapcar #'wt-parse-group groups))

(defun wt-list (repo)
  "Get a parsed list of worktrees for `repo`"
  (let ((result nil)
        (current nil))
    (dolist (line (process-lines "git" "-C" (expand-file-name repo) "worktree" "list" "--porcelain"))
      (if (string-empty-p line)
          (when current
            (push (nreverse current) result)
            (setq current nil))
        (push line current)))

    ;; final group
    (when current
      (push (nreverse current) result))

    ;; result is empty so reverse it
    (setq result (wt-parse-groups (nreverse result)))))

(defun wt-worktree-path (repo workspace-name)
  "Compute worktree path for REPO and WORKSPACE-NAME."
  (expand-file-name
   workspace-name
   (expand-file-name
    wt-workspace-directory
    (expand-file-name repo))))

;; == Worktree Major Mode ==

(define-derived-mode wt-mode tabulated-list-mode "Worktrees"
  "Major mode for viewing Git worktrees."

  ;; columns: NAME WIDTH SORTABLE?
  (setq tabulated-list-format
        [("Branch" 30 t)
         ("Path"   80 t)])

  (setq tabulated-list-padding 2)

  ;; refresh callback
  (setq tabulated-list-entries #'wt-tabulated-entries)

  (tabulated-list-init-header))

(defun wt-refresh ()
  (interactive)
  (message "Refreshing worktrees...")
  (tabulated-list-revert))

(defun wt-tabulated-entries ()
  "Generate tabulated list entries."
  (mapcar
   (lambda (wt)
     (let ((branch (or (plist-get wt :branch) "<bare>"))
           (path (plist-get wt :worktree)))
       ;; ID + vector of columns
       (list path
             (vector branch path))))
   (wt-list wt-current-repo)))

(defun wt-show (repo &optional fullscreen)
  "Show worktrees for REPO."
  (interactive "fRepo: ")

  (setq buffer-name
        (concat
         wt-buffer-name
         ": "
         (file-name-nondirectory (directory-file-name repo))))

  (let ((buf (get-buffer-create wt-buffer-name)))
    (with-current-buffer buf
      (wt-mode)
      (setq wt-current-repo repo)
      (tabulated-list-revert))
    (if fullscreen
        (switch-to-buffer buf)
    (pop-to-buffer buf))))

(defun wt-current-worktree ()
  "Get worktree path at point."
  (tabulated-list-get-id))

(defun wt-current-entry ()
  "Return worktree entry at point."
  (let ((path (tabulated-list-get-id)))
    (seq-find
     (lambda (wt)
       (equal path (plist-get wt :worktree)))
     (wt-list wt-current-repo))))

(defun wt-visit ()
  "Visit selected worktree."
  (interactive)

  (let ((path (tabulated-list-get-id)))
    (unless path
      (user-error "No worktree selected"))

    ;; Make project.el aware immediately
    (let ((default-directory path))
      (project-current t))

    (dired path)))

(defun wt-pull ()
  "Run git pull for worktree at point asynchronously."
  (interactive)

    (let* ((entry (wt-current-entry))
           (path (plist-get entry :worktree))
           (branch (plist-get entry :branch))
           (root (plist-get entry :root)))
    (unless path
      (user-error "No worktree selected"))

    (when root
      (user-error "Cannot run pull on root"))

    (message "Starting git pull for %s..." path)

    (make-process
     :name (format "wt-pull-%s" path)
     :buffer (get-buffer-create "*wt-pull*")
     :command (list "git" "-C" path "pull" "origin" branch)
     :noquery t
     :sentinel
     (lambda (proc event)
       (when (memq (process-status proc) '(exit signal))
         (if (= (process-exit-status proc) 0)
             (progn
               (message "git pull succeeded")

               ;; Delete the process output buffer on success.
               (let ((output-buffer (process-buffer proc)))
                 (when (buffer-live-p (process-buffer proc))
                   (kill-buffer output-buffer)))

               ;; refresh UI
               (when (buffer-live-p (current-buffer))
                 (with-current-buffer "*Worktrees*"
                   (tabulated-list-revert))))

           (display-buffer (process-buffer proc))
           (message "git pull failed: %s" event)))))))

(defun wt/git-fetch ()
  "Do a git fetch in the root of bare repo"
  (interactive)

  (let* ((remote (read-string "Remote: " "origin")))
    (message "Fetching remote/%s in %s" remote wt-current-repo)
    (make-process
     :name (format "wt-fetch-%s" remote)
     :buffer (get-buffer-create "*wt-fetch*")
     :command (list "git" "-C" wt-current-repo "fetch" remote)
     :noquery t
     :sentinel
     (lambda (proc event)
       (when (memq (process-status proc) '(exit signal))
           (if (= (process-exit-status proc) 0)
             (progn
               (message "git fetch succeeded")

               ;; Delete the process output buffer on success.
               (let ((output-buffer (process-buffer proc)))
                 (when (buffer-live-p (process-buffer proc))
                   (kill-buffer output-buffer)))

             (display-buffer (process-buffer proc))
             (message "git fetch failed: %s" event))))))))

(defun wt-create-worktree (repo branch workspace-name &optional create-branch commit)
  "Create worktree for BRANCH in WORKSPACE-NAME."

  (let ((path (wt-worktree-path repo workspace-name)))

    (when (file-exists-p path)
      (user-error "Worktree already exists: %s" path))

    (message "Creating worktree %s..." path)

    (make-process
     :name "wt-create"
     :buffer (get-buffer-create "*wt-create*")
     :command
     (if create-branch
         (if commit
            (list "git" "-C" repo
                "worktree" "add"
                "-b" branch
                path commit)
           (list "git" "-C" repo
               "worktree" "add"
               "-b" branch
               path))
       (list "git" "-C" repo
             "worktree" "add"
             path
             branch))

     :noquery t

     :sentinel
     (lambda (proc event)
       (when (memq (process-status proc) '(exit signal))

         (if (= (process-exit-status proc) 0)

             (progn
               (message "Created worktree %s" path)

               ;; Delete the process output buffer on success.
               (let ((output-buffer (process-buffer proc)))
                 (when (buffer-live-p (process-buffer proc))
                   (kill-buffer output-buffer)))

               (when (buffer-live-p (get-buffer "*Worktrees*"))
                 (with-current-buffer "*Worktrees*"
                   (wt-refresh))))

           (display-buffer (process-buffer proc))
           (message "Failed to create worktree")))))))

(defun wt-create-custom ()
  "Create a custom worktree."
  (interactive)

  (let* ((branch (read-string "Branch: "))
         (workspace (read-string "Workspace name: ")))

    (wt-create-worktree wt-current-repo branch workspace t)))

(defun wt-create-commit ()
  "Create a custom worktree from a commit"
  (interactive)

  (let* ((branch (read-string "Branch: "))
         (workspace (read-string "Workspace name: "))
         (commit (read-string "Commit/Branch: ")))

    (wt-create-worktree wt-current-repo branch workspace t commit)))

(defun wt-create-existing ()
  "Create a worktree for existing branch"
  (interactive)

  (let* ((branch (read-string "Branch: "))
         (workspace (read-string "Workspace name: "))
         (commit (read-string "Commit/Branch: ")))

    (wt-create-worktree wt-current-repo branch workspace nil commit)))

(defun wt-create-main ()
  "Create main worktree."
  (interactive)

  (wt-create-worktree wt-current-repo "main" "main"))

(defun wt-create-develop ()
  "Create develop worktree."
  (interactive)

  (wt-create-worktree wt-current-repo "develop" "develop"))

(defun wt-delete ()
  "Delete selected worktree and its branch."
  (interactive)

  (let* ((entry (wt-current-entry))
         (path (plist-get entry :worktree))
         (branch (plist-get entry :branch))
         (root (plist-get entry :root)))

    (when root
      (user-error "Cannot delete root worktree"))

    (when (member branch '("main" "master" "develop"))
      (user-error "Refusing to delete protected branch"))

    (unless entry
      (user-error "No worktree selected"))

    (unless
        (yes-or-no-p
         (format "Delete worktree %s%s? "
                 path
                 (if branch
                     (format " and branch %s" branch)
                   "")))
      (user-error "Cancelled"))

    (message "Deleting worktree %s..." path)

    (make-process
     :name "wt-delete"
     :buffer (get-buffer-create "*wt-delete*")
     :command (list "git"
                     "-C" (expand-file-name wt-current-repo)
                     "worktree" "remove"
                     "--force"
                     path)
     :noquery t
     :sentinel
     (lambda (proc event)
       (when (memq (process-status proc) '(exit signal))

         (if (= (process-exit-status proc) 0)

             (progn
               ;; delete branch if present
               (when branch
                 (call-process
                  "git" nil nil nil
                  "-C" (expand-file-name wt-current-repo)
                  "branch" "-D" branch))

               (message "Deleted worktree %s" path)

               ;; Delete the process output buffer on success.
               (let ((output-buffer (process-buffer proc)))
                 (when (buffer-live-p (process-buffer proc))
                   (kill-buffer output-buffer)))

               (when (buffer-live-p (get-buffer "*Worktrees*"))
                 (with-current-buffer "*Worktrees*"
                   (wt-refresh))))

           (display-buffer (process-buffer proc))
           (message "Failed to delete worktree")))))))

(defun wt-term ()
  "Open ansi-term in selected worktree."
  (interactive)

  (let* ((path (tabulated-list-get-id))
         (name (concat "term: " (file-name-nondirectory (directory-file-name path))))
         (default-directory path))

    (ghostel)))

(defun wt-project-candidates ()
  (directory-files
   (expand-file-name wt-projects-directory)
   t
   "\\.git/?$"))

(defun wt-find-project ()
  (interactive)

  (message "%S" (wt-project-candidates))
  (let* ((projects (wt-project-candidates))
         (choices
          (mapcar
           (lambda (p)
             (cons (file-name-nondirectory
                    (directory-file-name p))
                   p))
           projects))

         (selected
          (completing-read
           "Project: "
           choices
           nil
           t)))

    (wt-show (cdr (assoc selected choices)) t)))

;; == Keymaps ==

;; Refresh
;;   Emacs
(define-key wt-mode-map (kbd "r") #'wt-refresh)
;;   Evil
(with-eval-after-load 'evil
  (evil-define-key 'normal wt-mode-map
    (kbd "gr") #'wt-refresh))

;; Update/Git Pull
;;   Emacs
(define-key wt-mode-map (kbd "u") #'wt-pull)
;;   Evit
(with-eval-after-load 'evil
  (evil-define-key 'normal wt-mode-map
    (kbd "u") #'wt-pull))

;; Create
;;   Emacs
;;   Evil
(with-eval-after-load 'evil
  (evil-define-key 'normal wt-mode-map
    (kbd "wcn") #'wt-create-custom
    (kbd "wcc") #'wt-create-commit
    (kbd "wcm") #'wt-create-main
    (kbd "wce") #'wt-create-existing
    (kbd "wcd") #'wt-create-develop
    (kbd "wgf") #'wt/git-fetch))

;; Remove Worktree/Delete Branch
;;   Emacs
(define-key wt-mode-map (kbd "d") #'wt-delete)
;;   Evil
(with-eval-after-load 'evil
  (evil-define-key 'normal wt-mode-map
    (kbd "d") #'wt-delete))

;; Open Terminal in worktree
;;  Emacs
(define-key wt-mode-map (kbd "t") #'wt-term)
;;  Evil
(with-eval-after-load 'evil
  (evil-define-key 'normal wt-mode-map
    (kbd "t") #'wt-term))

;; Open as project
;;   Emacs
(define-key wt-mode-map (kbd "RET") #'wt-visit)
;;   Evil
(with-eval-after-load 'evil
  (evil-define-key 'normal wt-mode-map
    (kbd "RET") #'wt-visit))

(provide 'wt)
;;; wt.el ends here
