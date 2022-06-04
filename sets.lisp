;;;; fuzzy.lisp

(in-package #:fuzzy)

;; Crisp Sets have characteristic functions that map elements of X and determines
;; membership. For a Crisp Set, membership is determined by a boolean.
;; Number of members is referred to as cardinality

;; Fuzzy Sets generalise the characteristic function as a membership function.
;; A membership function grades an element by membership level between 0 and 1.
;; We will use fsets for representation of both Crisp and Fuzzy sets.

(defun range (first &optional (second nil) (step 1))
  "Creates a list of numbers in a range"
  (macrolet ((for (second word first)
               `(loop :for x :from ,second ,word ,first :by step
                      :collect x)))
    (cond ((and second (> second first)) (for first to second))
          (second (for first downto second))
          (t (for 0 to first)))))

(serapeum:defconstructor fuzzy-cons
  (value t)
  (weight single-float))

(deftype mu-fn (a) `(serapeum:-> (,a) fuzzy-cons))

(deftype set-elem ()
  `(or fuzzy-cons t))

(deftype any-set ()
  `(or fuzzy-set fset:wb-set))

(deftype fuzzy-set ()
  `(satisfies fuzzy-set-p))

(serapeum:-> fuzzy-set-p (fset:wb-set) boolean)
(defun fuzzy-set-p (xs)
  (and
   (every (lambda (x) (typep x 'fuzzy-cons)) (fset:convert 'list xs))))

;; (defun correct-fuzzy-set (s)
;;   (fset:reduce
;;    (lambda (acc x)
;;      (if (some (lambda (y) (and
;;                        (= (fuzzy-cons-weight y) (fuzzy-cons-weight x))
;;                        (equalp (fuzzy-cons-value y) (fuzzy-cons-value x))))
;;                (fset:convert 'list acc))
;;          acc
;;          (fset:union (fset:set x) acc)))
;;    s
;;    :initial-value
;;    (fset:set (fset:arb s))))

(serapeum:-> fuzzy-members ((mu-fn t) fset:wb-set) fuzzy-set)
(defun fuzzy-members (func xs)
  "Calculate membership function over domain"
  (serapeum:assure fset:wb-set
    
    (fset:image func xs)))

(serapeum:-> strong-alpha-cut (fuzzy-set single-float) fuzzy-set)
(defun strong-alpha-cut (s alpha)
  (serapeum:assure fuzzy-set
    (fset:filter (lambda (x) (> (fuzzy-cons-weight x) alpha)) s)))

(serapeum:-> alpha-cut (fuzzy-set single-float) fuzzy-set)
(defun alpha-cut (s alpha)
  (serapeum:assure fuzzy-set
    (fset:filter (lambda (x) (>= (fuzzy-cons-weight x) alpha)) s)))

(serapeum:-> fuzzy-support (fuzzy-set) fset:wb-set)
(defun fuzzy-support (s)
  (serapeum:assure fset:wb-set
    (fset:image #'fuzzy-cons-value (strong-alpha-cut s 0.0))))

(serapeum:-> crisp-members ((mu-fn t) fset:wb-set) fset:wb-set)
(defun crisp-members (func xs)
  (fuzzy-support (fuzzy-members func xs)))

(serapeum:-> compl ((mu-fn t)) (mu-fn t))
(defun compl (func)
  "Complementary membership function"
  (lambda (x)
    (multiple-value-bind (value weight)
        (serapeum:deconstruct (funcall func x))
      (fuzzy-cons value (- 1.0 weight)))))

(serapeum:-> fuzzy-intersection ((mu-fn t) (mu-fn t)) (mu-fn t))
(defun fuzzy-intersection (fn1 fn2)
  "Takes the minimum mu"
  (lambda (x)
    (serapeum:mvlet ((v1 w1 (serapeum:deconstruct (funcall fn1 x)))
                     (v2 w2 (serapeum:deconstruct (funcall fn2 x))))
      (if (< w1 w2)
          (fuzzy-cons v1 w1)
          (fuzzy-cons v2 w2)))))

(serapeum:-> fuzzy-union ((mu-fn t) (mu-fn t)) (mu-fn t))
(defun fuzzy-union (fn1 fn2)
  "Takes the maximum mu"
  (lambda (x)
    (serapeum:mvlet ((v1 w1 (serapeum:deconstruct (funcall fn1 x)))
                     (v2 w2 (serapeum:deconstruct (funcall fn2 x))))
      (if (> w1 w2)
          (fuzzy-cons v1 w1)
          (fuzzy-cons v2 w2)))))

(serapeum:-> height (fuzzy-set) single-float)
(defun height (s)
  "Finds the largest weight"
  (serapeum:assure single-float
    (fset:reduce (lambda (acc x)
                   (if (> (fuzzy-cons-weight x) acc)
                       (fuzzy-cons-weight x)
                       acc))
                 s
                 :initial-value
                 (fuzzy-cons-weight (fset:arb s)))))

(serapeum:-> fuzzy-subset? ((mu-fn t) (mu-fn t) list) boolean)
(defun fuzzy-subset? (fn1 fn2 domain)
  (every (lambda (x)
           (<=
            (fuzzy-cons-weight (funcall fn1 x))
            (fuzzy-cons-weight (funcall fn2 x))))
         domain))

(serapeum:-> scalar-cardinality (fuzzy-set) single-float)
(defun scalar-cardinality (s)
  (serapeum:assure single-float
    (serapeum:~>> s
                  (fset:image #'fuzzy-cons-weight)
                  (fset:reduce #'+))))

(serapeum:-> relative-cardinality (fuzzy-set list) single-float)
(defun relative-cardinality (s domain)
  "Tells you the relative size of the fuzzy set to the domain"
  (serapeum:assure single-float
    (/ (scalar-cardinality s) (fset:size (fset:convert 'fset:wb-set domain)))))

(serapeum:-> fuzzy-cardinality (fuzzy-set) fuzzy-set)
(defun fuzzy-cardinality (s)
  (serapeum:assure fuzzy-set
    (fset:image (lambda (x)
                  (fuzzy-cons (scalar-cardinality (alpha-cut s (fuzzy-cons-weight x)))
                              (fuzzy-cons-weight x))) s)))


;; So perhaps if were doing this through an object oriented approach, we could
;; represent fuzzy sets to the user as a kind of object, struct, or construct
;; with slots of domain and a membership function and the 'print' method
;; would then be just the calculation of membership function over a domain.
;; It's interesting to note how the concept of sets doesn't require any calculations
;; on the members of the set to calculate the members of new sets, but simply requires
;; composition of membership functions. This makes perfect sense mathematically once
;; you think about it!

(serapeum:-> fuzzy-analysis ((mu-fn t) list) fset:wb-map)
(defun fuzzy-analysis (func domain)
  (serapeum:assure fset:wb-map
    (let* ((elements (fuzzy-members func (fset:convert 'fset:wb-set domain)))
           (size (scalar-cardinality elements))
           (domain-size (fset:size (fset:convert 'fset:wb-set domain)))
           (relative-size (relative-cardinality elements domain))
           (fuzzy-size (fuzzy-cardinality elements))
           (height (height elements))
           (support (fuzzy-support elements)))
      (fset:map ('elements elements)
                ('size size)
                ('domain-size domain-size)
                ('relative-size relative-size)
                ('fuzzy-size fuzzy-size)
                ('height height)
                ('support support)
                ('domain domain)
                ('mu func)))))

;; FSet kind of sucks for this sycamore would be better.
