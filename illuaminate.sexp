; -*- mode: Lisp;-*-

(at /
  (linters
    ;; It'd be nice to avoid this, but right now there's a lot of instances of
    ;; it.
    -var:set-loop

    ;; It's useful to name arguments for documentation, so we allow this. It'd
    ;; be good to find a compromise in the future, but this works for now.
    -var:unused-arg))

(at
  /lib
  (linters -var:unused-global)
  (lint (allow-toplevel-global true)))
