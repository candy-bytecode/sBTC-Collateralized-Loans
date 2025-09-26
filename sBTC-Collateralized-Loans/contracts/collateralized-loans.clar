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

;; Loan offer structure
(define-map loan-offers
  uint
  {
    lender: principal,
    amount: uint,
    interest-rate: uint,
    collateral-ratio: uint,
    duration: uint,
    active: bool,
    created-at: uint,
    expires-at: uint
  })

;; Active loan structure
(define-map active-loans
  uint
  {
    borrower: principal,
    lender: principal,
    principal-amount: uint,
    collateral-amount: uint,
    interest-rate: uint,
    start-block: uint,
    due-block: uint,
    total-due: uint,
    paid-back: bool,
    liquidated: bool,
    partial-payments: uint,
    grace-period: uint
  })

;; User collateral tracking
(define-map user-collateral
  principal
  uint)

;; User statistics
(define-map user-stats
  principal
  {
    total-borrowed: uint,
    total-lent: uint,
    loans-taken: uint,
    loans-given: uint,
    defaults: uint,
    reputation-score: uint
  })

;; Platform statistics
(define-map platform-stats
  uint
  {
    total-loans-created: uint,
    total-volume: uint,
    total-fees-collected: uint,
    active-loans-count: uint,
    liquidated-loans-count: uint
  })

;; Data variables
(define-data-var next-offer-id uint u1)
(define-data-var next-loan-id uint u1)
(define-data-var liquidation-threshold uint u150) ;; 150% collateral ratio
(define-data-var contract-paused bool false)
(define-data-var platform-fee-recipient principal contract-owner)
(define-data-var grace-period-blocks uint u144) ;; ~24 hours in blocks
(define-data-var max-offer-duration uint u52560) ;; ~1 year in blocks