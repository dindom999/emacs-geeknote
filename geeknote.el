;;; geeknote.el --- Use Evernote in Emacs through geeknote

;; Copyright (C) 2015 Evan Dale Aromin

;; Author: Evan Dale Aromin
;; Modifications: David A. Shamma
;; Version: 0.3
;; Package-Version: 20150223.815
;; Keywords: evernote, geeknote, note, emacs-evernote, evernote-mode
;; Package-Requires: ((emacs "24"))
;; URL: http://github.com/avendael/emacs-geeknote

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package wraps common geeknote commands into elisp.  With this, geeknote
;; can be interacted with within emacs instead of through a shell.
;;
;; The command `geeknote' is expected to be present on the user's `$PATH'.
;; Please follow the geeknote installation instructions to obtain this command.

;;; Code:
(defgroup geeknote nil
  "Interact with evernote through emacs."
  :group 'tools
  :group 'convenience)

(defcustom geeknote-command "geeknote"
  "The geeknote command.
It's either a path to the geeknote script as an argument to python, or simply
`geeknote` if the command is already on your PATH."
  :group 'geeknote
  :type 'string)

(defconst geeknote--expect-script
  (concat "expect -c 'spawn "
          geeknote-command
          " %s; set pid $spawn_id; set timeout 1; set count 5; while { $count > 0 } { expect \"^\\-\\- More \\-\\-\"; if {[catch {send -i $pid \" \"} err]} { exit } else { set count [expr $count-1]} }'"))

(defvar geeknote-mode-hook nil)

(defvar geeknote-mode-map
  (let ((map (make-keymap)))
    (define-key map "q" 'kill-this-buffer)
    (define-key map "j" 'next-line)
    (define-key map "k" 'previous-line)
    map)
  "Keymap for Geeknote major mode")

(regexp-opt '("Total found") t)

(defconst geeknote-font-lock-keywords-1
  (list
   '("\\(Total found:\\)" . font-lock-constant-face))
  "Minimal highlighting keywords for geeknote mode")

(defconst geeknote-font-lock-keywords-2
  (append geeknote-font-lock-keywords-1
          (list '("\\(^\s-+[0-9]+\\)" . font-lock-keyword-face)))
  "Additional Keywords to highlight in geeknote mode")

(defconst geeknote-font-lock-keywords-3
  (append geeknote-font-lock-keywords-2
          (list '(" : \\(.+\\)$" . font-lock-builting-face)))
  "Additional Keywords to highlight in geeknote mode")

(defvar geeknote-font-lock-keywords geeknote-font-lock-keywords-3
  "Default highlighting expressions for geeknote mode")

(defun geeknote-mode ()
  "Major mode for navigation Geeknote mode listings."
  (kill-all-local-variables)
  (use-local-map geeknote-mode-map)
  (set (make-local-variable 'font-lock-defaults) '(geeknote-font-lock-keywords))
  (setq major-mode 'geeknote-mode)
  (setq mode-name "geeknote")
  (run-hooks 'geeknote-mode-hook))

(provide 'geeknote-mode)

;;;###autoload
(defun geeknote-setup ()
  "Setup geeknote."
  (interactive)
  (message (concat "geeknote: "
                   (shell-command-to-string
                    (concat geeknote-command
                            " settings --editor emacsclient")))))

;;;###autoload
(defun geeknote-create (title)
  "Create a new note with the given title.

TITLE the title of the new note to be created."
  (interactive "sName: ")
  (message (format "geeknote creating note: %s" title))
  (let* ((note-title (geeknote--parse-title title))
        (note-notebook (geeknote--helm-search-notebooks))
        ;; (cmd (format (concat geeknote-command " create --content WRITE --title %s "
        (cmd (format (concat geeknote-command " create --rawmd --content WRITE --title %s "
                        (when note-notebook " --notebook %s"))
                (shell-quote-argument note-title)
                (shell-quote-argument (or note-notebook ""))))
        )
    (async-shell-command cmd)
    (set-process-sentinel (get-buffer-process "*Async Shell Command*") #'dindom/kill--buffer-when-done)
    ))

(defun geeknote-create-notebook (title stack)
  "Create a new note with the given title.

TITLE the title of the new note to be created."
  (interactive "sName: \nsStack: ")
  (message (format "geeknote creating notebook: %s" title))
  (async-shell-command
   (format (concat geeknote-command " notebook-create --title %s "
                   (when stack " --stack %s"))
           (shell-quote-argument title)
           (shell-quote-argument stack))
   )
  (set-process-sentinel (get-buffer-process "*Async Shell Command*") #'dindom/kill--buffer-when-done)
  )

(defun geeknote-create-no-helm (title)
  "Create a new note with the given title.

TITLE the title of the new note to be created.
this is the old create func, enter everythong and create"
  (interactive "sName: ")
  (message (format "geeknote creating note: %s" title))
  (let ((note-title (geeknote--parse-title title))
	(note-tags (geeknote--parse-tags title))
	(note-notebook (geeknote--parse-notebook title)))
    (async-shell-command
   (format (concat geeknote-command " create --content WRITE --title %s -tg %s"
                   (when note-notebook " --notebook %s"))
           (shell-quote-argument note-title)
           (shell-quote-argument (or note-tags ""))
           (shell-quote-argument (or note-notebook ""))))
     (set-process-sentinel (get-buffer-process "*Async Shell Command*") #'dindom/kill--buffer-when-done)
))

;;;###autoload
(defun geeknote-show ()
  "Open an existing note.

TITLE the title of the note to show."
  (interactive)
  (let
      ((title (geeknote--helm-notes-list-index)))
    (message (format "geeknote showing note: %s" title))
    (let* ((note (shell-command-to-string
                  (format (concat geeknote-command " show %s")
                          (shell-quote-argument title))))
           (lines (split-string note "\n"))
           (name (cadr lines))
           (buf-name (format "GEEKNOTE LIST --: %s*" name)))
      (with-current-buffer (get-buffer-create buf-name)
        (display-buffer buf-name)
        (read-only-mode 0)
        (erase-buffer)
        (insert note)
        (read-only-mode t)
        (markdown-mode))
      (other-window 1)))
  )
;;;###autoload
(defun geeknote-helm-edit ()
  "Open up an existing note for editing.

TITLE the title of the note to edit."
  (interactive)
  (let
      ((title (geeknote--helm-notes-list-index)))
    (message (format "Editing note: %s" title))
    (let ((cmd (format (concat geeknote-command " edit --note %s")
                       (shell-quote-argument title)))
          (buf (dindom/get--geeknotelist-buffer))
          )
      (if buf
          (with-current-buffer (get-buffer-create buf)
            (pop-to-buffer buf)
            (read-only-mode 0)
            (async-shell-command cmd buf)
            (set-process-sentinel (get-buffer-process buf) #'dindom/kill--buffer-when-done)
            )
        (progn
          ;; (message (format "%s,%s" cmd buf))
          (async-shell-command cmd)
          (set-process-sentinel (get-buffer-process "*Async Shell Command*") #'dindom/kill--buffer-when-done)
          )
        )
      )
    )
  )

;;;###autoload
(defun geeknote-edit (title)
  (interactive "sName: ")
  (message (format "Editing note: %s" title))
  (async-shell-command
   (format (concat geeknote-command " edit --note %s")
           (shell-quote-argument title))))

;;;###autoload
(defun geeknote-remove ()
  "Delete an existing note.

TITLE the title of the note to delete."
  (interactive)
  (let
      ((title (geeknote--helm-notes-list-index)))
  (message (format "geeknote deleting note: %s" title))
  (message (concat "geeknote: "
                   (shell-command-to-string
                    (format (concat geeknote-command
                                    " remove --note %s --force")
                            (shell-quote-argument title))))))
  )
;;;###autoload
(defun geeknote-find (keyword)
  "Search for a note with the given keyword.

KEYWORD the keyword to search the notes with."
  (interactive "skeyword: ")
  (geeknote--find-with-args
   (format 
    (concat geeknote-command
            " find --search %s --count 40 --content-search")
    (shell-quote-argument keyword))
   keyword))

(defun geeknote--helm-search-notebooks ()
  "Search for a note with the given keyword.
KEYWORD the keyword to search the notes with."
  (interactive)
  (let ((notebook (completing-read "notebook"
                                   (s-split "\n"
                                            (s-chomp
                                             (shell-command-to-string "geeknote notebook-list | perl -pe 's/^Found.*$//g' | perl -lane 'splice @F,0,2;print \"@F\"' | sed '/^$/d'"))))))
    notebook))

(defun geeknote--helm-notes-list-index ()
  "Search for a note with the given keyword.
  return number of index. its useful for some unnormal title"
  (interactive)
  (let* ((notebook (completing-read "recent notes:"
                                   (s-split "\n"
                                            (s-chomp
                                             (shell-command-to-string "geeknote find --count 40|awk '$5!=\"\" {$2=\"\";$3=\"\";$4=\"\";print}'| sed 's/   //'"))))
                  )
        )
    (car (s-split " " notebook))
    )
  )

(defun geeknote--helm-notes-list ()
  "Search for a note with the given keyword.
  return title"
  (interactive)
  (let ((notebook (completing-read "recent notes:"
                                   (s-split "\n"
                                            (s-chomp
                                             (shell-command-to-string "geeknote find --count 40|awk '$5!=\"\" {$1=\"\";$2=\"\";$3=\"\";$4=\"\";print}'| sed 's/^    //'"))))
                  )
        )
    notebook))

(defun geeknote-find-in-notebook (keyword)
  "Search for a note with the given keyword.

KEYWORD the keyword to search the notes with."
  (interactive "sKeyword: ")
  (let ((notebook (geeknote--helm-search-notebooks))
	)
  (geeknote--find-with-args
   (format
    (concat geeknote-command
            " find --search %s --count 40 --content-search --notebook %s")
    (shell-quote-argument keyword)
    (shell-quote-argument notebook))
   keyword)

    ))


(defun geeknote-find-in-notebook-orig (notebook keyword)
  "Search for a note with the given keyword.

KEYWORD the keyword to search the notes with."
  (interactive "sNotebook: \nsKeyword: ")
  (geeknote--find-with-args
   (format 
    (concat geeknote-command
            " find --search %s --count 20 --content-search --notebooks %s")
    (shell-quote-argument keyword)
    (shell-quote-argument notebook))
   keyword))

(defun geeknote--find-with-notebook (notebook)
  (let* ((m "Search notebook '%s' with: ")
         (p (format m notebook))
         (keyword (read-from-minibuffer p)))
    (geeknote--find-with-args
     (format 
      (concat geeknote-command
              " find --search %s --count 20 --content-search --notebooks %s")
      (shell-quote-argument keyword)
      (shell-quote-argument notebook))
     keyword)))
    
(defun geeknote-find-tags (tags)
  "Search for a note with the given keyword.

TAGS the tags to search the notes with."
  (interactive "stags: ")
  (geeknote--find-with-args
   (format 
    (concat geeknote-command
            " find -tg %s --count 20")
    (shell-quote-argument tags))
   tags))

(defun geeknote--find-with-args (command keyword)
  "Search for a note with the given arg string.

COMMAND basically the full geeknote command to exec.
KEYWORD is used for display and buffer title only."
  (let* ((notes (shell-command-to-string command))
         (lines (split-string notes "\n"))
         (buf-name (format "*GEEKNOTE LIST -- Find: %s*" keyword)))
    (with-current-buffer (get-buffer-create buf-name)
      (display-buffer buf-name)
      (switch-to-buffer buf-name)
      (read-only-mode 0)
      (erase-buffer)
      (dotimes (i 2)
        (insert (concat (car lines) "\n"))
        (setq lines (cdr lines)))
      (while lines
        (let ((l (car lines)))
          (insert-button l
                         'follow-link t
                         'help-echo "Edit this note."
                         'action (lambda (x)
                                   (geeknote-edit
                                    (car (split-string (button-get x 'name) " : "))))
                         'name l)
          (insert "\n"))
        (setq lines (cdr lines)))
      (read-only-mode t)
      (geeknote-mode))
    ;; (other-window 1)
    ))

;;;###autoload
(defun geeknote-tag-list ()
  "Show the list of existing tags in your Evernote."
  (interactive)
  (let* ((tags (shell-command-to-string
                (format geeknote--expect-script "tag-list")))
         (lines (split-string tags "\n"))
         (buf-name "*GEEKNOTE LIST -- Tags*"))
    (with-current-buffer (get-buffer-create buf-name)
      (display-buffer buf-name)
      (read-only-mode 0)
      (erase-buffer)
      (setq lines (cdr lines))
      (insert (replace-regexp-in-string
               "\^M" ""
               (concat "Total found: "
                       (cadr (split-string (car lines) "Total found: "))
                       "\n")))
      (setq lines (cdr lines))
      (while lines
        (let ((l 
               (geeknote--chomp-end (replace-regexp-in-string
                                     "\^M" ""
                                     (replace-regexp-in-string "^.*\^M\s+\^M" ""
                                                               (car lines))))))
          (unless (zerop (length (geeknote--chomp l)))
            (insert-button l
                           'follow-link t
                           'help-echo "Find notes with this tag."
                           'action (lambda (x)
                                     (geeknote-find-tags
                                      (cadr (split-string (button-get x 'name) " : "))))
                           'name l)
          (insert "\n")))
        (setq lines (cdr lines)))
      (read-only-mode t)
      (geeknote-mode))
    (other-window 1)))

;;;###autoload
(defun geeknote-notebook-list ()
  "Show the list of existing notebooks in your Evernote."
  (interactive)
  (let* ((books (shell-command-to-string
                (format geeknote--expect-script "notebook-list")))
         (lines (split-string books "\n")))
    (with-current-buffer (get-buffer-create "*GEEKNOTE LIST -- Notebooks*")
      (display-buffer "*GEEKNOTE LIST -- Notebooks*")
      (read-only-mode 0)
      (erase-buffer)
      (setq lines (cdr lines))
      (insert (replace-regexp-in-string
               "\^M" ""
               (concat "Total found: "
                       (cadr (split-string (car lines) "Total found: "))
                       "\n")))
      (setq lines (cdr lines))
      (while lines
        (let ((l 
               (geeknote--chomp-end (replace-regexp-in-string
                                     "\^M" ""
                                     (replace-regexp-in-string "^.*\^M\s+\^M" ""
                                                               (car lines))))))
          (unless (zerop (length (geeknote--chomp l)))
            (insert-button l
                           'follow-link t
                           'help-echo "Search in this notebook."
                           'action (lambda (x)
                                     (geeknote--find-with-notebook
                                      (cadr (split-string (button-get x 'name) " : "))))
                           'name l)
            (insert "\n")))
        (setq lines (cdr lines)))
      (read-only-mode t)
      (geeknote-mode))
    (other-window 1)))

;;;###autoload
(defun geeknote--notebook-edit-with-oldtitle (oldtitle)
  "Rename an existing notebook with a target.

TITLE the title of the notebook to rename."
  (let* ((m "Rename notebook '%s' to: ")
         (p (format m oldtitle))
         (newtitle (read-from-minibuffer p)))
    (message (format "Renaming notebook: %s to %s." oldtitle newtitle))
    (geeknote-notebook-edit oldtitle newtitle)))

;;;###autoload
(defun geeknote-notebook-edit (oldtitle newtitle)
  "Rename an existing notebook.

TITLE the title of the notebook to rename."
  (interactive "sRename existing notebook: \nsTo new notebook name: ")
  (message (format "Renaming notebook: %s to %s." oldtitle newtitle))
  (message (shell-command-to-string
            (format (concat geeknote-command
                            " notebook-edit --notebook %s --title %s")
                    (shell-quote-argument oldtitle)
                    (shell-quote-argument newtitle)))))

;;;###autoload
(defun geeknote-user ()
  "Show information about active user."
  (interactive)
  (with-output-to-temp-buffer "*Geeknote User Info*"
    (princ (shell-command-to-string
            (format (concat geeknote-command " user")))))
  (other-window 1))

;;;###autoload
(defun geeknote-move (note notebook)
  "Move a NOTE to a different NOTEBOOK.  If the provided NOTEBOOK is
non-existent, it will be created.

NOTE the title of the note to move.
NOTEBOOK the title of the notebook where NOTE should be moved."
  (interactive "sName: \nsMove note %s to notebook: ")
  (message (format "Moving note %s to notebook %s..." note notebook))
  (async-shell-command
   (format (concat geeknote-command " edit --note %s --notebook %s")
                   (shell-quote-argument note)
                   (shell-quote-argument notebook))))

(defun geeknote--parse-title (title)
  "Rerieve the title from the provided string. Filters out @notebooks and #tags.

TITLE is the input given when asked for a new note title."
  (let ((wordlist (split-string title)))
    (mapconcat (lambda (s) s)
	       (delq nil
		     (mapcar (lambda (str)
			       (cond
				((string-prefix-p "@" str) nil)
				((string-prefix-p "#" str) nil)
				(t str)))
			     wordlist))
	       " ")))

(defun geeknote--parse-notebook (title)
  "Rerieve the @notebook from the provided string. Returns nil if none.

TITLE is the input given when asked for a new note title."
  (let ((wordlist (split-string title)))
    (elt
     (delq nil
	   (mapcar (lambda (str)
		     (cond
		      ((string-prefix-p "@" str) (substring str 1))
		      (t nil)))
		   wordlist))
     0)))

(defun geeknote--parse-tags (title)
  "Rerieve the #tags from the provided string. Returns nil if none.

TITLE is the input given when asked for a new note title."
  (let ((wordlist (split-string title)))
    (mapconcat (lambda (s) s)
	       (delq nil
		     (mapcar (lambda (str)
			       (cond
				((string-prefix-p "#" str) (substring str 1))
				(t nil)))
			     wordlist))
	       ", ")))

(defun geeknote--chomp-end (str)
  "Chomp tailing whitespace from STR."
  (replace-regexp-in-string (rx (* (any " \t\n")) eos)
                            ""
                            str))

(defun geeknote--chomp (str)
  "Chomp leading and tailing whitespace from STR."
  (replace-regexp-in-string (rx (or (: bos (* (any " \t\n")))
                                    (: (* (any " \t\n")) eos)))
                            ""
                            str))

;; (defun string-starts-with-p (string prefix)
;;   "Return t if STRING starts with prefix."
;;   (and
;;    (string-match (rx-to-string `(: bos ,prefix) t) string)
;;    t))

(defun dindom/kill--buffer-when-done (process signal)
  (when (and (process-buffer process)
             (memq (process-status process) '(exit signal)))
    (message "%s: %s."
             (car (cdr (cdr (process-command process))))
             (substring signal 0 -1))
    (sleep-for 1)
    (kill-buffer (process-buffer process))))

(defun dindom/get--buffer-subname (str)
  (loop for buffer in (buffer-list)
        do (if (string-prefix-p str (buffer-name buffer))
               (return (buffer-name buffer))
             ))
  )

(defun dindom/get--geeknotelist-buffer ()
  (dindom/get--buffer-subname "*GEEKNOTE LIST --")
  )

(provide 'geeknote)
;;; geeknote.el ends here
