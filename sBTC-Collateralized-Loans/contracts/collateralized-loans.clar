;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant min-loan-amount u1000000) ;; 1 STX minimum
(define-constant max-loan-amount u100000000000) ;; 100,000 STX maximum
(define-constant min-interest-rate u1) ;; 1% minimum
(define-constant max-interest-rate u50) ;; 50% maximum
(define-constant min-collateral-ratio u110) ;; 110% minimum
(define-constant max-collateral-ratio u500) ;; 500% maximum
(define-constant platform-fee-rate u25) ;; 0.25% platform fee

;; Error constants
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-collateral (err u102))
(define-constant err-loan-active (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-payment-overdue (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant err-invalid-rate (err u107))
(define-constant err-invalid-ratio (err u108))
(define-constant err-contract-paused (err u109))
(define-constant err-loan-not-due (err u110))
(define-constant err-already-liquidated (err u111))