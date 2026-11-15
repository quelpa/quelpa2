;;; quelpa2.el --- Next-gen decentralized package manager -*- lexical-binding: t; -*-

;; Author: Reto Hubmann (@steckerhalter)
;; Version: 0.1.0
;; Package-Origin: (quelpa2 :url "https://github.com/quelpa/quelpa2")
;; Package-Requires: ((emacs "29.1"))
;; Keywords: tools, package, vc

;;; Commentary:

;; `quelpa2' is a lightweight, decentralized dependency-resolution layer built
;; directly on top of Emacs 29+'s `package-vc-install'.  Packages declare their
;; own upstream coordinates via `Package-Origin' and fallback dependency sources
;; via `Package-Requires-Origins' using native `package-vc' specification lists:
;;
;;   ;; Package-Origin: (my-pkg :url "https://github.com/user/my-pkg")
;;   ;; Package-Requires: ((emacs "29.1") (dep-a "1.0"))
;;   ;; Package-Requires-Origins: ((dep-a :url "https://github.com/user/dep-a"))

;;; Code:

(require 'cl-lib)
(require 'lisp-mnt)
(require 'package)
(require 'package-vc)

(defgroup quelpa2 nil
  "Decentralized, registry-free package management built on `package-vc'."
  :group 'package
  :prefix "quelpa2-")

;;;; Header Extraction

(defun quelpa2--read-header (header-name)
  "Read and parse Lisp sexp from HEADER-NAME in the current buffer.
Returns nil if HEADER-NAME is absent, empty, or malformed."
  (when-let* ((raw (lm-header header-name))
              (trimmed (string-trim raw)))
    (unless (string-empty-p trimmed)
      (condition-case nil
          (car (read-from-string trimmed))
        ((end-of-file invalid-read-syntax) nil)))))

(defun quelpa2--extract-all-headers (file)
  "Extract `Package-Requires', `Package-Origin', and `Package-Requires-Origins' from FILE.
Returns a list of three elements: (REQUIRES ORIGIN REQUIRES-ORIGINS)."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (list (quelpa2--read-header "Package-Requires")
            (quelpa2--read-header "Package-Origin")
            (quelpa2--read-header "Package-Requires-Origins")))))

(defun quelpa2--find-package-main-file (pkg-name)
  "Locate the primary `.el' file for installed PKG-NAME."
  (when-let* ((desc (cadr (assq pkg-name package-alist)))
              (dir (package-desc-dir desc)))
    (let ((candidate (expand-file-name (format "%s.el" pkg-name) dir)))
      (when (file-readable-p candidate)
        candidate))))

;;;; Specification Normalization

(defun quelpa2--normalize-spec (pkg-or-spec)
  "Normalize PKG-OR-SPEC into a `(NAME . PLIST)' VC spec, or nil if only a symbol.
Accepts:
- A symbol `foo' -> returns nil (requires lookup via `Package-Origin' or archives)
- A URL string \"https://...\" -> derives name from URL and returns `(name :url URL)'
- A VC spec list `(foo :url \"...\")' -> returned directly."
  (cond
   ((consp pkg-or-spec)
    pkg-or-spec)
   ((stringp pkg-or-spec)
    (let ((name (intern (file-name-base (directory-file-name pkg-or-spec)))))
      (list name :url pkg-or-spec)))
   ((symbolp pkg-or-spec)
    nil)
   (t
    (user-error "Invalid package specification: %S" pkg-or-spec))))

;;;; Recursive Dependency Resolution

(defun quelpa2--resolve-dependencies (pkg-name &optional visited)
  "Inspect installed PKG-NAME and recursively install missing dependencies.
VISITED tracks already-processed package symbols to prevent cycles."
  (unless (memq pkg-name visited)
    (let* ((visited (cons pkg-name visited))
           (main-file (quelpa2--find-package-main-file pkg-name))
           (headers (quelpa2--extract-all-headers main-file))
           (requires (nth 0 headers))
           (origins-map (nth 2 headers))
           (installed-any nil))
      (dolist (req requires)
        (let ((dep-name (car req)))
          (unless (or (eq dep-name 'emacs)
                      (package-installed-p dep-name))
            (setq installed-any t)
            ;; 1. EAFP: Try standard configured ELPA archives first
            (condition-case nil
                (progn
                  (when (and package-archives (not package-archive-contents))
                    (package-refresh-contents))
                  (package-install dep-name))
              (error
               ;; 2. Fallback: Look up `(dep-name :url ...)' in Package-Requires-Origins
               (if-let ((dep-spec (assq dep-name origins-map)))
                   (progn
                     (message "quelpa2: Resolving %s via Package-Requires-Origins..." dep-name)
                     (package-vc-install dep-spec)
                     (quelpa2--resolve-dependencies dep-name visited))
                 (error "quelpa2: Dependency `%s' required by `%s' not found in archives or Package-Requires-Origins"
                        dep-name pkg-name)))))))
      ;; Re-activate PKG-NAME if new dependencies were installed after it
      (when installed-any
        (package-activate pkg-name)))))

;;;; Public Entry Point

;;;###autoload
(defun quelpa2 (pkg-or-spec)
  "Install or upgrade PKG-OR-SPEC and recursively resolve its VC dependencies.
PKG-OR-SPEC can be:
- A VC specification list, e.g. `(my-pkg :url \"https://github.com/user/my-pkg\")'
- A repository URL string, e.g. \"https://github.com/user/my-pkg\"
- A package symbol `my-pkg' (resolved from its installed `Package-Origin'
  header or standard `package-archives')."
  (interactive
   (list (read-from-minibuffer "Package symbol or VC spec: " nil nil t)))
  (let ((spec (quelpa2--normalize-spec pkg-or-spec)))
    (cond
     ;; Case 1: Explicit VC spec or URL provided
     (spec
      (let ((pkg-name (car spec)))
        (if (package-installed-p pkg-name)
            (package-vc-upgrade (cadr (assq pkg-name package-alist)))
          (package-vc-install spec))
        (quelpa2--resolve-dependencies pkg-name)))

     ;; Case 2: Bare symbol provided (e.g. `(quelpa2 'quelpa2)')
     ((symbolp pkg-or-spec)
      (let* ((pkg-name pkg-or-spec)
             (main-file (quelpa2--find-package-main-file pkg-name))
             (origin-spec (nth 1 (quelpa2--extract-all-headers main-file))))
        (cond
         ;; Already installed with a `(name :url ...)' Package-Origin header
         ((and origin-spec (consp origin-spec))
          (if (package-installed-p pkg-name)
              (package-vc-upgrade (cadr (assq pkg-name package-alist)))
            (package-vc-install origin-spec))
          (quelpa2--resolve-dependencies pkg-name))
         ;; Already installed without Package-Origin: delegate to package-vc-upgrade
         ((package-installed-p pkg-name)
          (package-vc-upgrade (cadr (assq pkg-name package-alist)))
          (quelpa2--resolve-dependencies pkg-name))
         ;; Not installed yet: fall back to standard ELPA archives
         (t
          (unless package-archive-contents
            (package-refresh-contents))
          (package-install pkg-name)
          (quelpa2--resolve-dependencies pkg-name))))))))

(provide 'quelpa2)
;;; quelpa2.el ends here
