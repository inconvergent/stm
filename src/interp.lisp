(in-package :evl)

(defun evl (expr env)
  "EVL"
  (labels ((car-is (l s) (and (consp l) (equal (car l) s)))
           (extend- (env kk vv)
             (lambda (y) (loop for k in kk and v in vv
                               if (equal k y) do (return v)
                               finally (return (funcall env y))))))
    (cond ((null expr)    nil)
          ((numberp expr) expr)
          ((keywordp expr) expr)
          ((symbolp expr) (funcall env expr))
          ((car-is expr 'progn)
           (first (last (mapcar (lambda (e) (evl e env)) (cdr expr)))))
          ((car-is expr 'if)
           (destructuring-bind (test then &optional else) (cdr expr)
             (if (evl test env) (evl then env) (evl else env))))
          ((car-is expr 'lambda)
           (destructuring-bind (kk body) (cdr expr)
             (lambda (&rest vv) (evl body (extend- env kk vv)))))
          ((car-is expr 'let)
           (destructuring-bind (vars &rest body) (cdr expr)
             (evl `((lambda ,(mapcar #'car vars)
                            (progn ,@body))
                    ,@(mapcar #'second vars))
                  env)))
          ((consp expr)
           (handler-case
             (apply (evl (car expr) env)
                    (mapcar (lambda (x) (evl x env))
                            (cdr expr)))
             (error (e) (error "EVL: error at ~a: ~a" expr e))))
          (t (error "EVL: invalid expression: ~a" expr)))))
