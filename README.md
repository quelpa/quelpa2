# quelpa2

[![Build Status](https://github.com/quelpa/quelpa2/actions/workflows/ci.yml/badge.svg)](https://github.com/quelpa/quelpa2/actions/workflows/ci.yml)

**Decentralized, registry-free package management for Emacs 29+.**

`quelpa2` is a lightweight dependency-resolution layer built directly on top of Emacs's built-in `package-vc-install`. It eliminates the need for centralized recipe repositories by allowing Emacs Lisp packages to declare their own upstream coordinates and fallback dependency origins directly inside standard file headers.

---

## Why `quelpa2`?

Historically, installing Emacs packages directly from source repositories required maintaining centralized recipe registries—the problem original `quelpa` solved by fetching and building MELPA recipes locally.

With Emacs 29+, `package-vc-install` brought native version-control installation straight into core Emacs. However, `package-vc-install` still leaves two key gaps:
1. **No recursive VC dependency resolution:** If Package A depends on Package B, and Package B is not on GNU ELPA or NonGNU ELPA, `package-vc-install` fails unless you manually install Package B first.
2. **External recipe dependency:** Without a central registry, there is no standard place for a package to tell Emacs how to be built and where to fetch and build its dependencies from.

`quelpa2` bridges this gap with zero external registries.

**The vision**:  Every package carries its own self-contained origin metadata in its header comments—making the Emacs package ecosystem completely decentralized while remaining 100% backwards-compatible with existing Emacs tooling.

So far so good. Since this project has only just been started, almost no packages include the mentioned headers. Every maintainer that adopts these headers contributes to a truly decentralized Emacs ecosystem, but adoption could take a while. Who knows? People might not care and everything stays fragmented over different package managers, repositories etc. But it's worth a try, isn't it? So there you have it... 

---

## The Header Specification

`quelpa2` introduces two optional file headers alongside standard `Package-Requires`:

1. **`Package-Origin`**: Declares the package's own canonical source repository using the exact `(name :url ...)` specification format expected by `package-vc-install`.
2. **`Package-Requires-Origins`**: Maps dependencies listed in `Package-Requires` to their upstream repository coordinates, used as a fallback when a dependency is not available in standard `package.el` archives.

### Example Package Header

```elisp
;;; my-pkg.el --- Example decentralized package -*- lexical-binding: t; -*-

;; Author: Your Name
;; Version: 1.0.0
;; Package-Origin:           (my-pkg :url "https://github.com/username/my-pkg")
;; Package-Requires:         ((emacs "29.1") (nav-flash "1.0.0"))
;; Package-Requires-Origins: ((nav-flash :url "https://github.com/steckerhalter/nav-flash"))

;;; Code:
```

### How Resolution Works

1. **`Package-Requires` stays untouched:** Native Emacs tools, byte-compilers, and package linters continue to work normally without modification.
2. **EAFP (Easier to Ask for Forgiveness than Permission):** When resolving a dependency from `Package-Requires`, `quelpa2` first attempts a standard `package-install` from configured archives (ELPA/NonGNU ELPA).
3. **Decentralized Fallback:** If the dependency is not found in standard archives, `quelpa2` looks up the package in `Package-Requires-Origins` and recursively installs it via `package-vc-install`—inspecting *that* package's headers in turn.
4. **Remote `HEAD` by default:** Omitting `:branch` lets Git automatically track the remote repository's default `HEAD` (e.g., `master`), though `:branch` or `:rev` can be passed explicitly in any plist when pinning is required.

---

## Requirements

* **Emacs 29.1** or later (requires built-in `package-vc`).
* **Git** (or the relevant VCS backend) available in your `exec-path`.

---

## Installation

You can bootstrap `quelpa2` directly using Emacs's built-in `package-vc-install`:

```elisp
(unless (package-installed-p 'quelpa2)
  (package-vc-install '(quelpa2 :url "https://github.com/quelpa/quelpa2")))
```

Or with `use-package` (Emacs 29+):

```elisp
(use-package quelpa2
  :vc (:url "https://github.com/quelpa/quelpa2"))
```

---

## Usage

`quelpa2` mirrors the argument signature of `package-vc-install`, accepting a package symbol, a URL string, or a full VC specification list:

### Install from a repository specification
```elisp
(quelpa2 '(my-pkg :url "https://github.com/username/my-pkg"))
```

### Install or update a package by symbol
If the package is already installed and includes a `Package-Origin` header (or exists in your configured `package-archives`), `quelpa2` resolves its origin automatically:

```elisp
(quelpa2 'quelpa2)
```

### Interactive Use
Run `M-x quelpa2` and enter a package name or repository specification to install and recursively resolve all dependencies.

## Update Flags

Two flags control upgrades:

* **`quelpa-self-update-p`** (default `t`): whether `quelpa2` upgrades the
  installed `quelpa2` itself the first time it is called. Set it to nil to
  turn this off.
* **`quelpa2-update-p`** (default `nil`): whether `quelpa2` upgrades
  already-installed packages. The per-specification `:update` keyword takes
  precedence, e.g. `(quelpa2 '(foo :url "..." :update t))`.

With the defaults, already-installed packages are left alone at startup.

---

## Testing

`quelpa2` uses Emacs's built-in `ERT` testing framework with isolated, temporary sandboxes so tests never affect your personal Emacs configuration or `package-user-dir`.

### Running Tests Locally

Use the included `Makefile` to run the test suite:

* **Run the full test suite (including live network & recursive dependency tests):**
  ```sh
  make test
  ```

* **Run offline unit and sandbox tests only:**
  ```sh
  RUN_NETWORK_TESTS=0 make test
  ```

* **Test against a specific Emacs binary:**
  ```sh
  EMACS=/path/to/emacs make test
  ```

* **Clean up byte-compiled files:**
  ```sh
  make clean
  ```

### Test Architecture

* **Offline Sandbox Tests:** Verify header parsing (`Package-Origin` and `Package-Requires-Origins`), spec normalization, and local Git repository dependency chains without touching external networks.
* **Network Integration Tests:** Pull pinned revisions of real repositories (such as `quelpa-use-package` and `nav-flash`) to validate end-to-end `package-vc` checkout and recursive resolution in the wild.

---

## Relationship to Original `quelpa`

`quelpa2` is developed as a standalone, modern foundation designed to eventually serve as the next-generation backend for `quelpa`, allowing existing users to transition smoothly from recipe-based builds to native `package-vc` workflows.

---

## License

GPL-3.0-or-later (same as GNU Emacs).
