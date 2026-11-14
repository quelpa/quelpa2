;;; quelpa2.el --- Next-gen decentralized package manager using package-vc -*- lexical-binding: t; -*-

;; Author: Reto Hubmann (@steckerhalter)
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:
;; Decentralized package manager built on top of Emacs 29+ `package-vc-install'.
;; Supports `Package-Origin' for self-tracking/updates and multi-line
;; `Package-Requires-Origins' for recursive dependency resolution.

;;; Code:

(require 'package)
(require 'package-vc)
(require 'cl-lib)

(defun quelpa2--extract-all-headers (file)
  "Extract `Package-Requires', `Package-Origin', and `Package-Requires-Origins' from FILE."
  (let ((requires nil)
        (origin   nil)
        (origins  nil))
    (with-temp-buffer
      (insert-file-contents file nil nil 4000)

      ;; 1. Parse Package-Requires
      (goto-char (point-min))
      (when (re-search-forward "^;; Package-Requires:[ \t]*\\(.+\\)" nil t)
        (setq requires (ignore-errors (read (match-string 1)))))

      ;; 2. Parse Package-Origin (Single plist for this package)
      (goto-char (point-min))
      (when (re-search-forward "^;; Package-Origin:[ \t]*\\(.+\\)" nil t)
        (setq origin (ignore-errors (read (match-string 1)))))

      ;; 3. Parse Package-Requires-Origins (Multi-line list for dependency origins)
      (goto-char (point-min))
      (when (re-search-forward "^;; Package-Requires-Origins:[ \t]*\\(.*\n\\(;;[ \t].*\n\\)*\\)" nil t)
        (let ((raw-block (match-string 1)))
          (with-temp-buffer
            (insert raw-block)
            (goto-char (point-min))
            (while (re-search-forward "^;*[ \t]*" nil t)
              (replace-match ""))
            (goto-char (point-min))
            (setq origins (ignore-errors (read (current-buffer))))))))
    (values requires origin origins)))

(defun quelpa2--get-installed-origin (pkg-name)
  "Look up `Package-Origin' header from an already installed PKG-NAME."
  (when-let* ((desc (cadr (assq pkg-name package-alist)))
              (dir (package-desc-dir desc))
              (main-file (expand-file-name (concat (symbol-name pkg-name) ".el") dir)))
    (when (file-exists-p main-file)
      (cl-multiple-value-bind (_reqs origin _orgs) (quelpa2--extract-all-headers main-file)
        origin))))

(defun quelpa2--resolve-dependencies (pkg-name)
  "Inspect PKG-NAME's installed source directory for dependencies and resolve them."
  (when-let* ((desc (cadr (assq pkg-name package-alist)))
              (dir (package-desc-dir desc))
              (main-file (expand-file-name (concat (symbol-name pkg-name) ".el") dir)))
    (when (file-exists-p main-file)
      (cl-multiple-value-bind (requires _origin origins) (quelpa2--extract-all-headers main-file)
        (dolist (req requires)
          (let ((dep-name (car req)))
            (unless (or (eq dep-name 'emacs) (package-installed-p dep-name))
              (message "quelpa2: Resolving dependency `%s' for `%s'" dep-name pkg-name)
              (condition-case nil
                  (package-install dep-name)
                (error
                 (if-let ((origin-plist (cdr (assq dep-name origins))))
                     (quelpa2 (cons dep-name origin-plist))
                   (error "quelpa2: Dependency `%s' required by `%s' not found" dep-name pkg-name))))
              (quelpa2--resolve-dependencies dep-name))))))))

;;;###autoload
(defun quelpa2 (repo-desc &optional backend)
  "Install or update a package using REPO-DESC (URL, spec list, or symbol),
automatically resolving dependencies via archives or `Package-Requires-Origins'."
  (interactive "sPackage or URL spec: ")
  (let* ((pkg-name (cond
                    ((symbolp repo-desc) repo-desc)
                    ((consp repo-desc) (car repo-desc))
                    (t nil)))
         ;; If given a symbol, check if it's already installed and has a Package-Origin header
         (resolved-desc
          (if (and (symbolp repo-desc) (not (assoc repo-desc package-archive-contents)))
              (if-let ((local-origin (quelpa2--get-installed-origin repo-desc)))
                  (cons repo-desc local-origin)
                repo-desc)
            repo-desc)))

    ;; Execute installation / update via package-install or package-vc-install
    (cond
     ((symbolp resolved-desc)
      (condition-case nil
          (package-install resolved-desc)
        (error (user-error "quelpa2: Package `%s' not in archives and no local Package-Origin found" resolved-desc))))
     (t
      (package-vc-install resolved-desc backend)))

    ;; Trigger recursive dependency resolution
    (when pkg-name
      (quelpa2--resolve-dependencies pkg-name))))

(provide 'quelpa2)
;;; quelpa2.el ends here
