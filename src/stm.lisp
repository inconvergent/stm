(in-package #:stm)

(declaim (inline r/identity r/cons r/print r/print*))

(defmacro later (expr)
  "wrap expression in (lambda () ...) to evaluate later."
  `(lambda () ,expr))

(defun r/identity (v rule)
  (declare (optimize speed) (ignore rule) (keyword rule))
  "default function for act / *act*."
  v)

(defun r/cons (v rule res)
  (declare (optimize speed) (ignore rule) (keyword rule))
  "default function for acc."
  (cons v res))

(defun r/print (v rule)
  (declare (optimize speed) (ignore rule) (keyword rule))
  "print rule and value. return v."
  (format t "~&~a~&" v) v)

(defun r/print* (v rule)
  (declare (optimize speed) (keyword rule))
  "print rule and value. return v."
  (format t "~&; {~a}: ~a~&" rule v) v)

(declaim (function *act*))
(defvar *act* #'r/identity
  "function that is called for each iteration. requires
two arguments. the first argument is the value. must return the desired return
value for each iteration.
the second is the (keyword) name of the current rule.")

; TODO: until state

(defun replace-rule-placeholder (name expr) ; TODO: broken
  (lqn:qry expr (?txpr (equal _ '?_) (kw! name))))

(defmacro stx/lambda ((name arg vfx) &body expr)
  (stm::with-gensyms (v nxt act)
    `(lambda (&optional ,act) ; stx
       (let ((,arg (funcall ,vfx)))
         (multiple-value-bind (,v ,nxt) (progn ,@expr) ; expr returns v, nxt
           (cond ((and ,nxt (functionp ,nxt))
                  (values ,nxt #1=(funcall (the function (or ,act *act*)) ,v
                                           ,(lqn:kw! name))))
                 (,nxt (values nil #1#)) ; last value, no more stx
                 (t (values nil nil)))))))) ; fin

(defun make-rule-label (name arg expr)
  "create rule label with name, argument and rule/condition."
  (declare (symbol name arg))
  (stm::with-gensyms (vfx)
    `((,name (,vfx)
       (declare (function ,vfx))
       (stx/lambda (,name ,arg ,vfx)
        ,(replace-rule-placeholder name expr))))))

  ; (lambda (v rule res) (cons v res))

(defmacro with-rules (rules &body body)
  (declare (list rules))
  "state machine context with rules/states.
ex:

  ; (with-rules
  ;   ((ping l (values l (new pong (list (1+ (cadr l)) :pong))))
  ;    (pong l (values l (new ping (list :ping (1+ (car l)))))))

  ;   (let* ((sm0 (new ping `(:ping 0)))  ; initial value. not evaluated here
  ;          (sm3 (itr/n sm0 3 #'princ))) ; eval & print 3 ping-pongs
  ;     (itr/n sm3 11 #'print)))          ; eval & print the next 11

see iterators and accumulators:
  - acc/all acc/n acc/until
  - itr/all itr/n itr/until

all iterators and accumulators use the act function to process each value
  before it is returned. the default is:

  ; (lambda (v rule) v) ; aka #'r/identity, which just returns the value.

  NOTE: also see r/print and r/print*, which are useful for development.
  NOTE: to override for the entire context set: stm:*act*.

all accumulators also have an acc and a res option:
  - acc is used for accumulation. the default is

    ; (lambda (v rule res) (cons v res)) ; aka. #'r/cons

    NOTE: you can filter which values are accumulated like this:

    ; (lambda (v rule res)
    ;   (if (my-testp rule v) (cons v res) res))

  - res is the initial value of the accumulation. default: (list).
    res does not have to be a list, but if you override you have to override
    acc to be compatible and vice-versa.
" `(labels (,@(mapcan (lambda (o) (apply #'make-rule-label o))
                      rules))
     ,@body))

(defmacro new (name expr)
  (declare (symbol name))
  "new state with this rule and expression. see with-rules."
  `(,name (later ,(replace-rule-placeholder name expr))))
(defmacro ? (&rest rest) "alias for new." `(new ,@rest))


(defun acc/all (stx &optional (acc #'cons) act res)
  (declare (optimize speed) (function acc))
  "accumulate all. see with-rules."
  (if stx (multiple-value-bind (nxt val) (funcall (the function stx) act)
               (acc/all nxt acc act (funcall acc val res)))
          (values nil res)))

(defun acc/n (stx &optional (n 1) (acc #'cons) act res)
  (declare (optimize speed) (fixnum n) (function acc))
  "accumulate at most n times. see with-rules."
  (if (and stx (> n 0))
      (multiple-value-bind (nxt val) (funcall (the function stx) act)
           (acc/n nxt (1- n) acc act (funcall acc val res)))
      (values stx res)))

(defun acc/until (stx &optional (until #'identity) (acc #'cons) act res)
  (declare (optimize speed) (function until acc))
  "accumulate until. see with-rules."
  (if stx (multiple-value-bind (nxt val) (funcall (the function stx) act)
               (if (not (funcall until val))
                   (acc/until nxt until acc act (funcall acc val res))
                   (values nxt (funcall acc val res))))
          (values nil res)))


(defun itr/all (stx &optional act res)
  (declare (optimize speed))
  "iterate all. see with-rules."
  (acc/all stx #'values act res))

(defun itr/n (stx &optional (n 1) act res)
  (declare (optimize speed) (fixnum n))
  "iterate at most n times. see with-rules."
  (acc/n stx n #'values act res))

(defun itr/until (stx &optional (until #'identity) act res)
  (declare (optimize speed) (function until))
  "iterate until. see with-rules."
  (acc/until stx until #'values act res))

