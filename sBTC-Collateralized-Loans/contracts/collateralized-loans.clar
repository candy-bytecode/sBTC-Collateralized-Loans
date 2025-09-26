;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant min-loan-amount u1000000) ;; 1 STX minimum
(define-constant max-loan-amount u100000000000) ;; 100,000 STX maximum
(define-constant min-interest-rate u1) ;; 1% minimum
(define-constant max-interest-rate u50) ;; 50% maximum
(define-constant min-collateral-ratio u110) ;; 110% minimum
(define-constant max-collateral-ratio u500) ;; 500% maximum

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

;; Data variables (changed platform-fee-rate from constant to data variable)
(define-data-var next-offer-id uint u1)
(define-data-var next-loan-id uint u1)
(define-data-var liquidation-threshold uint u150) ;; 150% collateral ratio
(define-data-var contract-paused bool false)
(define-data-var platform-fee-recipient principal contract-owner)
(define-data-var grace-period-blocks uint u144) ;; ~24 hours in blocks
(define-data-var max-offer-duration uint u52560) ;; ~1 year in blocks
(define-data-var platform-fee-rate uint u25) ;; 0.25% platform fee

;; Create a new loan offer
(define-public (create-loan-offer 
  (amount uint)
  (interest-rate uint)
  (collateral-ratio uint)
  (duration uint))
  (let ((caller tx-sender)
        (offer-id (var-get next-offer-id)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (and (>= amount min-loan-amount) (<= amount max-loan-amount)) err-invalid-amount)
    (asserts! (and (>= interest-rate min-interest-rate) (<= interest-rate max-interest-rate)) err-invalid-rate)
    (asserts! (and (>= collateral-ratio min-collateral-ratio) (<= collateral-ratio max-collateral-ratio)) err-invalid-ratio)
    (asserts! (<= duration (var-get max-offer-duration)) err-invalid-amount)
    (asserts! (>= (stx-get-balance caller) amount) err-insufficient-collateral)
    
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    
    (map-set loan-offers offer-id {
      lender: caller,
      amount: amount,
      interest-rate: interest-rate,
      collateral-ratio: collateral-ratio,
      duration: duration,
      active: true,
      created-at: stacks-block-height,
      expires-at: (+ stacks-block-height u8760) ;; Offer expires in ~60 days
    })
    
    (update-user-stats caller u0 amount u0 u1 u0)
    (var-set next-offer-id (+ offer-id u1))
    (ok offer-id)))

;; Deposit collateral
(define-public (deposit-collateral (amount uint))
  (let ((caller tx-sender))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (>= amount min-loan-amount) err-invalid-amount)
    (asserts! (>= (stx-get-balance caller) amount) err-insufficient-collateral)
    
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    
    (let ((current-collateral (default-to u0 (map-get? user-collateral caller))))
      (ok (map-set user-collateral caller (+ current-collateral amount))))))

;; Take a loan
(define-public (take-loan (offer-id uint))
  (let ((caller tx-sender)
        (offer (unwrap! (map-get? loan-offers offer-id) err-not-found))
        (loan-id (var-get next-loan-id))
        (user-collateral-amount (default-to u0 (map-get? user-collateral caller))))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (get active offer) err-not-found)
    (asserts! (< stacks-block-height (get expires-at offer)) err-payment-overdue)
    
    (let ((required-collateral (* (get amount offer) (get collateral-ratio offer)))
          (required-collateral-adjusted (/ required-collateral u100)))
      (asserts! (>= user-collateral-amount required-collateral-adjusted) err-insufficient-collateral)
      
      (let ((interest-amount (/ (* (get amount offer) (get interest-rate offer)) u100))
            (total-due (+ (get amount offer) interest-amount))
            (platform-fee (/ (* (get amount offer) (var-get platform-fee-rate)) u10000)))
        
        (try! (as-contract (stx-transfer? (get amount offer) tx-sender caller)))
        (try! (as-contract (stx-transfer? platform-fee tx-sender (var-get platform-fee-recipient))))
        
        (map-set active-loans loan-id {
          borrower: caller,
          lender: (get lender offer),
          principal-amount: (get amount offer),
          collateral-amount: required-collateral-adjusted,
          interest-rate: (get interest-rate offer),
          start-block: stacks-block-height,
          due-block: (+ stacks-block-height (get duration offer)),
          total-due: total-due,
          paid-back: false,
          liquidated: false,
          partial-payments: u0,
          grace-period: (var-get grace-period-blocks)
        })
        
        (map-set user-collateral caller (- user-collateral-amount required-collateral-adjusted))
        (map-set loan-offers offer-id (merge offer {active: false}))
        (update-user-stats caller (get amount offer) u0 u1 u0 u0)
        (update-platform-stats (get amount offer) platform-fee)
        (var-set next-loan-id (+ loan-id u1))
        
        (ok loan-id)))))

;; Make partial payment
(define-public (make-partial-payment (loan-id uint) (payment-amount uint))
  (let ((caller tx-sender)
        (loan (unwrap! (map-get? active-loans loan-id) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq caller (get borrower loan)) err-unauthorized)
    (asserts! (not (get paid-back loan)) err-loan-active)
    (asserts! (not (get liquidated loan)) err-loan-active)
    (asserts! (>= (stx-get-balance caller) payment-amount) err-insufficient-collateral)
    (asserts! (<= payment-amount (- (get total-due loan) (get partial-payments loan))) err-invalid-amount)
    
    (try! (stx-transfer? payment-amount caller (get lender loan)))
    
    (let ((new-partial-payments (+ (get partial-payments loan) payment-amount)))
      (if (>= new-partial-payments (get total-due loan))
        ;; Full payment made
        (begin
          (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender caller)))
          (ok (map-set active-loans loan-id (merge loan {paid-back: true, partial-payments: new-partial-payments}))))
        ;; Partial payment only
        (ok (map-set active-loans loan-id (merge loan {partial-payments: new-partial-payments})))))))

;; Repay loan in full
(define-public (repay-loan (loan-id uint))
  (let ((caller tx-sender)
        (loan (unwrap! (map-get? active-loans loan-id) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq caller (get borrower loan)) err-unauthorized)
    (asserts! (not (get paid-back loan)) err-loan-active)
    (asserts! (not (get liquidated loan)) err-loan-active)
    
    (let ((remaining-due (- (get total-due loan) (get partial-payments loan))))
      (asserts! (>= (stx-get-balance caller) remaining-due) err-insufficient-collateral)
      
      (try! (stx-transfer? remaining-due caller (get lender loan)))
      (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender caller)))
      
      (ok (map-set active-loans loan-id (merge loan {paid-back: true}))))))

;; Liquidate overdue loan
(define-public (liquidate-loan (loan-id uint))
  (let ((loan (unwrap! (map-get? active-loans loan-id) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (> stacks-block-height (+ (get due-block loan) (get grace-period loan))) err-loan-not-due)
    (asserts! (not (get paid-back loan)) err-loan-active)
    (asserts! (not (get liquidated loan)) err-already-liquidated)
    
    (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender (get lender loan))))
    (update-user-stats (get borrower loan) u0 u0 u0 u0 u1)
    
    (ok (map-set active-loans loan-id (merge loan {liquidated: true})))))

;; Emergency liquidation for under-collateralized loans
(define-public (emergency-liquidate (loan-id uint))
  (let ((loan (unwrap! (map-get? active-loans loan-id) err-not-found))
        (liquidation-ratio (calculate-liquidation-risk loan-id)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (< liquidation-ratio (var-get liquidation-threshold)) err-insufficient-collateral)
    (asserts! (not (get paid-back loan)) err-loan-active)
    (asserts! (not (get liquidated loan)) err-already-liquidated)
    
    (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender (get lender loan))))
    (update-user-stats (get borrower loan) u0 u0 u0 u0 u1)
    
    (ok (map-set active-loans loan-id (merge loan {liquidated: true})))))

;; Extend loan duration (with agreement from lender)
(define-public (extend-loan (loan-id uint) (additional-blocks uint) (additional-interest uint))
  (let ((caller tx-sender)
        (loan (unwrap! (map-get? active-loans loan-id) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq caller (get lender loan)) err-unauthorized)
    (asserts! (not (get paid-back loan)) err-loan-active)
    (asserts! (not (get liquidated loan)) err-loan-active)
    (asserts! (<= additional-blocks (var-get max-offer-duration)) err-invalid-amount)
    
    (let ((new-due-block (+ (get due-block loan) additional-blocks))
          (new-total-due (+ (get total-due loan) additional-interest)))
      
      (ok (map-set active-loans loan-id 
        (merge loan {
          due-block: new-due-block,
          total-due: new-total-due
        }))))))

;; Withdraw available collateral
(define-public (withdraw-collateral (amount uint))
  (let ((caller tx-sender)
        (available-collateral (default-to u0 (map-get? user-collateral caller))))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (>= available-collateral amount) err-insufficient-collateral)
    
    (try! (as-contract (stx-transfer? amount tx-sender caller)))
    
    (ok (map-set user-collateral caller (- available-collateral amount)))))

;; Cancel active loan offer
(define-public (cancel-loan-offer (offer-id uint))
  (let ((caller tx-sender)
        (offer (unwrap! (map-get? loan-offers offer-id) err-not-found)))
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (is-eq caller (get lender offer)) err-unauthorized)
    (asserts! (get active offer) err-not-found)
    
    (try! (as-contract (stx-transfer? (get amount offer) tx-sender caller)))
    
    (ok (map-set loan-offers offer-id (merge offer {active: false})))))

;; Read-only functions
(define-read-only (get-loan-offer (offer-id uint))
  (map-get? loan-offers offer-id))

(define-read-only (get-loan-info (loan-id uint))
  (map-get? active-loans loan-id))

(define-read-only (get-user-collateral (user principal))
  (default-to u0 (map-get? user-collateral user)))

(define-read-only (get-user-stats (user principal))
  (default-to {
    total-borrowed: u0,
    total-lent: u0,
    loans-taken: u0,
    loans-given: u0,
    defaults: u0,
    reputation-score: u100
  } (map-get? user-stats user)))

(define-read-only (calculate-liquidation-risk (loan-id uint))
  (let ((loan (map-get? active-loans loan-id)))
    (match loan
      loan-data
      (let ((collateral-value (get collateral-amount loan-data))
            (debt-value (- (get total-due loan-data) (get partial-payments loan-data))))
        (if (> debt-value u0)
          (/ (* collateral-value u100) debt-value)
          u0))
      u0)))

(define-read-only (get-loan-health (loan-id uint))
  (let ((loan (map-get? active-loans loan-id)))
    (match loan
      loan-data
      (let ((blocks-remaining (- (get due-block loan-data) stacks-block-height))
            (payment-progress (/ (* (get partial-payments loan-data) u100) (get total-due loan-data)))
            (collateral-ratio (calculate-liquidation-risk loan-id)))
        {
          blocks-remaining: blocks-remaining,
          payment-progress: payment-progress,
          collateral-ratio: collateral-ratio,
          is-healthy: (and (> blocks-remaining u0) (>= collateral-ratio (var-get liquidation-threshold)))
        })
      {
        blocks-remaining: u0,
        payment-progress: u0,
        collateral-ratio: u0,
        is-healthy: false
      })))

;; Administrative functions
(define-public (set-liquidation-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= new-threshold u110) (<= new-threshold u200)) err-invalid-ratio)
    (ok (var-set liquidation-threshold new-threshold))))

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u100) err-invalid-rate) ;; Max 1%
    (ok (var-set platform-fee-rate new-rate))))

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (var-set contract-paused (not (var-get contract-paused))))))

(define-public (set-grace-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-period u1008) err-invalid-amount) ;; Max 1 week
    (ok (var-set grace-period-blocks new-period))))

;; Helper functions
(define-private (update-user-stats 
  (user principal)
  (borrowed uint)
  (lent uint)
  (loans-taken uint)
  (loans-given uint)
  (defaults uint))
  (let ((current-stats (get-user-stats user)))
    (map-set user-stats user {
      total-borrowed: (+ (get total-borrowed current-stats) borrowed),
      total-lent: (+ (get total-lent current-stats) lent),
      loans-taken: (+ (get loans-taken current-stats) loans-taken),
      loans-given: (+ (get loans-given current-stats) loans-given),
      defaults: (+ (get defaults current-stats) defaults),
      reputation-score: (if (> defaults u0)
        (if (>= (get reputation-score current-stats) u10)
          (- (get reputation-score current-stats) u10)
          u0)
        (if (<= (get reputation-score current-stats) u99)
          (+ (get reputation-score current-stats) u1)
          u100))
    })))

(define-private (update-platform-stats (volume uint) (fees uint))
  (let ((current-stats (default-to {
    total-loans-created: u0,
    total-volume: u0,
    total-fees-collected: u0,
    active-loans-count: u0,
    liquidated-loans-count: u0
  } (map-get? platform-stats u0))))
    (map-set platform-stats u0 {
      total-loans-created: (+ (get total-loans-created current-stats) u1),
      total-volume: (+ (get total-volume current-stats) volume),
      total-fees-collected: (+ (get total-fees-collected current-stats) fees),
      active-loans-count: (+ (get active-loans-count current-stats) u1),
      liquidated-loans-count: (get liquidated-loans-count current-stats)
    })))

(define-read-only (get-platform-stats)
  (default-to {
    total-loans-created: u0,
    total-volume: u0,
    total-fees-collected: u0,
    active-loans-count: u0,
    liquidated-loans-count: u0
  } (map-get? platform-stats u0)))