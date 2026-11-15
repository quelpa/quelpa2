;;; quelpa2-test.el --- Tests for quelpa2 -*- lexical-binding: t; -*-

(require 'ert)
(require 'quelpa2)

;;; Helper: Sandboxed package environment
(defmacro quelpa2-with-sandbox (&rest body)
  "Execute BODY with an isolated `package-user-dir' and `package-alist'."
  (declare (indent 0))
  `(let* ((sandbox-dir (make-temp-file "quelpa2-sandbox-" t))
          (package-user-dir (expand-file-name "elpa" sandbox-dir))
          (package-alist nil)
          (package-activated-list nil)
          (package-vc-selected-packages nil))
     (unwind-protect
         (progn
           (make-directory package-user-dir t)
           ,@body)
       (delete-directory sandbox-dir t))))

;;; Helper: Create a temporary local Git repo for a mock package
(defun quelpa2-test--create-mock-repo (base-dir pkg-name header-lines)
  "Create a Git repo in BASE-DIR for PKG-NAME with HEADER-LINES."
  (let* ((repo-dir (expand-file-name (symbol-name pkg-name) base-dir))
         (el-file (expand-file-name (format "%s.el" pkg-name) repo-dir)))
    (make-directory repo-dir t)
    (with-temp-file el-file
      (insert (format ";;; %s.el --- Mock package -*- lexical-binding: t; -*-\n\n" pkg-name))
      (insert ";; Version: 0.1.0\n")
      (dolist (line header-lines)
        (insert line "\n"))
      (insert (format "\n(provide '%s)\n;;; %s.el ends here\n" pkg-name pkg-name)))
    (let ((default-directory repo-dir))
      (call-process "git" nil nil nil "init" "-b" "master")
      (call-process "git" nil nil nil "config" "user.email" "test@example.com")
      (call-process "git" nil nil nil "config" "user.name" "Test")
      (call-process "git" nil nil nil "add" ".")
      (call-process "git" nil nil nil "commit" "-m" "Initial commit"))
    repo-dir))

;;; Unit Test: Header Parsing
(ert-deftest quelpa2-test-header-parsing ()
  "Verify extraction of Package-Requires, Package-Origin, and Package-Requires-Origins."
  (let ((temp-el (make-temp-file "quelpa2-hdr-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp-el
            (insert ";;; demo.el --- Demo -*- lexical-binding: t; -*-\n"
                    ";; Package-Origin: (demo :url \"https://example.com/demo\")\n"
                    ";; Package-Requires: ((emacs \"29.1\") (dep-a \"1.0\"))\n"
                    ";; Package-Requires-Origins: ((dep-a :url \"https://example.com/dep-a\"))\n"))
          (cl-multiple-value-bind (reqs origin origins)
              (quelpa2--extract-all-headers temp-el)
            (should (equal reqs '((emacs "29.1") (dep-a "1.0"))))
            (should (equal origin '(demo :url "https://example.com/demo")))
            (should (equal origins '((dep-a :url "https://example.com/dep-a"))))))
      (delete-file temp-el))))

;;; Unit Test: Spec Normalization
(ert-deftest quelpa2-test-normalize-spec ()
  "Verify `quelpa2--normalize-spec' correctly handles symbols, strings, and specs."
  (should (equal (quelpa2--normalize-spec '(foo :url "https://github.com/bar/foo"))
                 '(foo :url "https://github.com/bar/foo")))
  (should (equal (quelpa2--normalize-spec "https://github.com/bar/foo.git")
                 '(foo :url "https://github.com/bar/foo.git")))
  (should (null (quelpa2--normalize-spec 'foo))))

;;; Integration Test: Recursive Dependency Installation in Sandbox
(ert-deftest quelpa2-test-recursive-vc-install ()
  "Test installing `mock-pkg-a' which recursively pulls `mock-dep-b' via `Package-Requires-Origins'."
  (quelpa2-with-sandbox
   (let* ((repos-dir (expand-file-name "repos" sandbox-dir))
          (repo-b (quelpa2-test--create-mock-repo
                   repos-dir 'mock-dep-b
                   '(";; Package-Requires: ((emacs \"29.1\"))")))
          (repo-a (quelpa2-test--create-mock-repo
                   repos-dir 'mock-pkg-a
                   (list ";; Package-Requires: ((emacs \"29.1\") (mock-dep-b \"0.1.0\"))"
                         (format ";; Package-Origin: (mock-pkg-a :url %S)" (expand-file-name "mock-pkg-a" repos-dir))
                         (format ";; Package-Requires-Origins: ((mock-dep-b :url %S))" repo-b)))))
     ;; Install mock-pkg-a via quelpa2 using its local repo path/spec
     (quelpa2 `(mock-pkg-a :url ,repo-a))
     ;; Verify both parent and transitive dependency were installed cleanly
     (should (package-installed-p 'mock-pkg-a))
     (should (package-installed-p 'mock-dep-b)))))

(provide 'quelpa2-test)
;;; quelpa2-test.el ends here
