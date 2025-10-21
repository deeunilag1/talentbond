;; Talent Bond - Income Share Agreements on Blockchain
;; A production-ready smart contract for tokenizing future income streams

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u600))
(define-constant err-not-found (err u601))
(define-constant err-unauthorized (err u602))
(define-constant err-invalid-amount (err u603))
(define-constant err-bond-closed (err u604))
(define-constant err-bond-active (err u605))
(define-constant err-already-invested (err u606))
(define-constant err-goal-reached (err u607))
(define-constant err-goal-not-met (err u608))
(define-constant err-payment-failed (err u609))
(define-constant err-invalid-percentage (err u610))
(define-constant err-already-paid (err u611))

;; Maximum income share percentage (30% = 3000 basis points)
(define-constant max-income-share u3000)
(define-constant basis-points u10000)
(define-constant min-investment u5000000)

;; Data Variables
(define-data-var bond-nonce uint u0)
(define-data-var total-bonds uint u0)
(define-data-var total-funded uint u0)
(define-data-var total-repaid uint u0)

;; Talent Bond Structure
(define-map bonds
    uint
    {
        talent: principal,
        title: (string-utf8 100),
        description: (string-utf8 500),
        funding-goal: uint,
        total-raised: uint,
        income-share-percentage: uint,
        payment-cap: uint,
        duration-months: uint,
        total-repaid: uint,
        investor-count: uint,
        status: (string-ascii 20),
        created-at: uint,
        funded-at: (optional uint),
        deadline: uint,
        category: (string-ascii 30)
    }
)

;; Investment tracking
(define-map investments
    { bond-id: uint, investor: principal }
    {
        amount: uint,
        invested-at: uint,
        total-received: uint,
        share-percentage: uint
    }
)

;; Monthly payment records
(define-map payments
    { bond-id: uint, month: uint }
    {
        amount: uint,
        timestamp: uint,
        distributed: bool
    }
)

;; Talent statistics
(define-map talent-stats
    principal
    {
        total-bonds: uint,
        total-raised: uint,
        total-repaid: uint,
        active-bonds: uint,
        success-rate: uint
    }
)

;; Investor portfolio tracking
(define-map investor-bond-index
    { investor: principal, index: uint }
    uint
)

(define-map investor-bond-count
    principal
    uint
)

;; Read-Only Functions

(define-read-only (get-bond (bond-id uint))
    (ok (map-get? bonds bond-id))
)

(define-read-only (get-investment (bond-id uint) (investor principal))
    (ok (map-get? investments { bond-id: bond-id, investor: investor }))
)

(define-read-only (get-payment (bond-id uint) (month uint))
    (ok (map-get? payments { bond-id: bond-id, month: month }))
)

(define-read-only (get-talent-stats (talent principal))
    (ok (map-get? talent-stats talent))
)

(define-read-only (get-contract-stats)
    (ok {
        total-bonds: (var-get total-bonds),
        total-funded: (var-get total-funded),
        total-repaid: (var-get total-repaid)
    })
)

(define-read-only (calculate-investor-share (bond-id uint) (investor principal))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (investment (unwrap! (map-get? investments { bond-id: bond-id, investor: investor }) err-not-found))
        (total-raised (get total-raised bond))
    )
        (ok (/ (* (get amount investment) basis-points) total-raised))
    )
)

(define-read-only (calculate-expected-return (bond-id uint) (investor principal) (projected-income uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (investment (unwrap! (map-get? investments { bond-id: bond-id, investor: investor }) err-not-found))
        (investor-share (unwrap! (calculate-investor-share bond-id investor) err-not-found))
        (income-share (get income-share-percentage bond))
        (monthly-payment (/ (* projected-income income-share) basis-points))
        (investor-portion (/ (* monthly-payment investor-share) basis-points))
        (total-months (get duration-months bond))
    )
        (ok (* investor-portion total-months))
    )
)

(define-read-only (get-investor-bond-count (investor principal))
    (ok (default-to u0 (map-get? investor-bond-count investor)))
)

(define-read-only (get-investor-bond-id (investor principal) (index uint))
    (ok (map-get? investor-bond-index { investor: investor, index: index }))
)

;; Private helper functions

(define-private (add-to-investor-portfolio (investor principal) (bond-id uint))
    (let (
        (current-count (default-to u0 (map-get? investor-bond-count investor)))
    )
        (map-set investor-bond-index
            { investor: investor, index: current-count }
            bond-id
        )
        (map-set investor-bond-count investor (+ current-count u1))
    )
)

(define-private (update-talent-stats-new-bond (talent principal) (funding-goal uint))
    (let (
        (stats (default-to 
            { total-bonds: u0, total-raised: u0, total-repaid: u0, active-bonds: u0, success-rate: u0 }
            (map-get? talent-stats talent)))
    )
        (map-set talent-stats talent
            (merge stats {
                total-bonds: (+ (get total-bonds stats) u1)
            })
        )
    )
)

(define-private (update-talent-stats-funded (talent principal) (amount uint))
    (let (
        (stats (unwrap! (map-get? talent-stats talent) false))
    )
        (map-set talent-stats talent
            (merge stats {
                total-raised: (+ (get total-raised stats) amount),
                active-bonds: (+ (get active-bonds stats) u1)
            })
        )
        true
    )
)

;; Public Functions

;; Create a new talent bond
(define-public (create-bond
    (title (string-utf8 100))
    (description (string-utf8 500))
    (funding-goal uint)
    (income-share-percentage uint)
    (payment-cap uint)
    (duration-months uint)
    (deadline-blocks uint)
    (category (string-ascii 30)))
    (let (
        (bond-id (+ (var-get bond-nonce) u1))
        (deadline (+ stacks-block-height deadline-blocks))
    )
        (asserts! (> funding-goal u0) err-invalid-amount)
        (asserts! (and (> income-share-percentage u0) (<= income-share-percentage max-income-share)) err-invalid-percentage)
        (asserts! (> payment-cap u0) err-invalid-amount)
        (asserts! (and (>= duration-months u12) (<= duration-months u120)) err-invalid-amount)
        (asserts! (> deadline-blocks u0) err-invalid-amount)
        (asserts! (> (len title) u0) err-invalid-amount)
        
        (map-set bonds bond-id {
            talent: tx-sender,
            title: title,
            description: description,
            funding-goal: funding-goal,
            total-raised: u0,
            income-share-percentage: income-share-percentage,
            payment-cap: payment-cap,
            duration-months: duration-months,
            total-repaid: u0,
            investor-count: u0,
            status: "fundraising",
            created-at: stacks-block-height,
            funded-at: none,
            deadline: deadline,
            category: category
        })
        
        (update-talent-stats-new-bond tx-sender funding-goal)
        
        (var-set bond-nonce bond-id)
        (var-set total-bonds (+ (var-get total-bonds) u1))
        
        (ok bond-id)
    )
)

;; Invest in a talent bond
(define-public (invest (bond-id uint) (amount uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (existing-investment (map-get? investments { bond-id: bond-id, investor: tx-sender }))
        (new-total (+ (get total-raised bond) amount))
    )
        (asserts! (>= amount min-investment) err-invalid-amount)
        (asserts! (is-eq (get status bond) "fundraising") err-bond-closed)
        (asserts! (<= stacks-block-height (get deadline bond)) err-bond-closed)
        (asserts! (<= new-total (get funding-goal bond)) err-goal-reached)
        (asserts! (not (is-eq tx-sender (get talent bond))) err-unauthorized)
        
        ;; Transfer investment to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update or create investment record
        (match existing-investment
            investment
            (map-set investments
                { bond-id: bond-id, investor: tx-sender }
                (merge investment {
                    amount: (+ (get amount investment) amount)
                })
            )
            (begin
                (map-set investments
                    { bond-id: bond-id, investor: tx-sender }
                    {
                        amount: amount,
                        invested-at: stacks-block-height,
                        total-received: u0,
                        share-percentage: u0
                    }
                )
                (add-to-investor-portfolio tx-sender bond-id)
                (map-set bonds bond-id
                    (merge bond {
                        investor-count: (+ (get investor-count bond) u1)
                    })
                )
            )
        )
        
        ;; Update bond total
        (map-set bonds bond-id
            (merge bond {
                total-raised: new-total
            })
        )
        
        ;; Check if funding goal reached and finalize if so
        (if (is-eq new-total (get funding-goal bond))
            (finalize-funding bond-id)
            (ok true)
        )
    )
)

;; Finalize funding and release funds to talent
(define-public (finalize-funding (bond-id uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (talent (get talent bond))
        (total-raised (get total-raised bond))
    )
        (asserts! (is-eq (get status bond) "fundraising") err-bond-closed)
        (asserts! (is-eq total-raised (get funding-goal bond)) err-goal-not-met)
        
        ;; Transfer funds to talent
        (try! (as-contract (stx-transfer? total-raised tx-sender talent)))
        
        ;; Update bond status
        (map-set bonds bond-id
            (merge bond {
                status: "active",
                funded-at: (some stacks-block-height)
            })
        )
        
        ;; Update talent stats
        (update-talent-stats-funded talent total-raised)
        
        ;; Update global stats
        (var-set total-funded (+ (var-get total-funded) total-raised))
        
        (ok true)
    )
)

;; Talent makes income share payment
(define-public (make-payment (bond-id uint) (month uint) (payment-amount uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (existing-payment (map-get? payments { bond-id: bond-id, month: month }))
    )
        (asserts! (is-eq tx-sender (get talent bond)) err-unauthorized)
        (asserts! (is-eq (get status bond) "active") err-bond-closed)
        (asserts! (is-none existing-payment) err-already-paid)
        (asserts! (> payment-amount u0) err-invalid-amount)
        (asserts! (<= month (get duration-months bond)) err-invalid-amount)
        
        ;; Transfer payment to contract
        (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
        
        ;; Record payment
        (map-set payments
            { bond-id: bond-id, month: month }
            {
                amount: payment-amount,
                timestamp: stacks-block-height,
                distributed: false
            }
        )
        
        ;; Update bond totals
        (let (
            (new-total-repaid (+ (get total-repaid bond) payment-amount))
        )
            (map-set bonds bond-id
                (merge bond {
                    total-repaid: new-total-repaid
                })
            )
            
            ;; Update global stats
            (var-set total-repaid (+ (var-get total-repaid) payment-amount))
            
            ;; Check if payment cap reached
            (if (>= new-total-repaid (get payment-cap bond))
                (begin
                    (map-set bonds bond-id
                        (merge bond {
                            status: "completed",
                            total-repaid: new-total-repaid
                        })
                    )
                    (ok true)
                )
                (ok true)
            )
        )
    )
)

;; Investor claims their share of a payment
(define-public (claim-payment (bond-id uint) (month uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (payment (unwrap! (map-get? payments { bond-id: bond-id, month: month }) err-not-found))
        (investment (unwrap! (map-get? investments { bond-id: bond-id, investor: tx-sender }) err-not-found))
        (investor-share (unwrap! (calculate-investor-share bond-id tx-sender) err-not-found))
        (payment-amount (get amount payment))
        (investor-portion (/ (* payment-amount investor-share) basis-points))
    )
        (asserts! (not (get distributed payment)) err-already-paid)
        (asserts! (> investor-portion u0) err-invalid-amount)
        
        ;; Transfer investor's share
        (try! (as-contract (stx-transfer? investor-portion tx-sender tx-sender)))
        
        ;; Update investment record
        (map-set investments
            { bond-id: bond-id, investor: tx-sender }
            (merge investment {
                total-received: (+ (get total-received investment) investor-portion)
            })
        )
        
        (ok investor-portion)
    )
)

;; Mark payment as fully distributed
(define-public (mark-payment-distributed (bond-id uint) (month uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (payment (unwrap! (map-get? payments { bond-id: bond-id, month: month }) err-not-found))
    )
        (asserts! (is-eq tx-sender (get talent bond)) err-unauthorized)
        
        (map-set payments
            { bond-id: bond-id, month: month }
            (merge payment { distributed: true })
        )
        
        (ok true)
    )
)

;; Request refund if funding goal not met by deadline
(define-public (request-refund (bond-id uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (investment (unwrap! (map-get? investments { bond-id: bond-id, investor: tx-sender }) err-not-found))
        (refund-amount (get amount investment))
    )
        (asserts! (is-eq (get status bond) "fundraising") err-bond-active)
        (asserts! (> stacks-block-height (get deadline bond)) err-bond-active)
        (asserts! (< (get total-raised bond) (get funding-goal bond)) err-goal-reached)
        (asserts! (> refund-amount u0) err-invalid-amount)
        
        ;; Transfer refund
        (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
        
        ;; Clear investment record
        (map-delete investments { bond-id: bond-id, investor: tx-sender })
        
        (ok refund-amount)
    )
)

;; Cancel bond (talent only, before funding)
(define-public (cancel-bond (bond-id uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
    )
        (asserts! (is-eq tx-sender (get talent bond)) err-unauthorized)
        (asserts! (is-eq (get status bond) "fundraising") err-bond-active)
        (asserts! (is-eq (get total-raised bond) u0) err-invalid-amount)
        
        (map-set bonds bond-id
            (merge bond { status: "cancelled" })
        )
        
        (ok true)
    )
)

;; Update bond description (talent only, before funding)
(define-public (update-bond-description (bond-id uint) (new-description (string-utf8 500)))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
    )
        (asserts! (is-eq tx-sender (get talent bond)) err-unauthorized)
        (asserts! (is-eq (get status bond) "fundraising") err-bond-active)
        (asserts! (> (len new-description) u0) err-invalid-amount)
        
        (map-set bonds bond-id
            (merge bond { description: new-description })
        )
        
        (ok true)
    )
)

;; Early completion (talent can pay remaining cap to close bond)
(define-public (complete-early (bond-id uint))
    (let (
        (bond (unwrap! (map-get? bonds bond-id) err-not-found))
        (remaining (- (get payment-cap bond) (get total-repaid bond)))
    )
        (asserts! (is-eq tx-sender (get talent bond)) err-unauthorized)
        (asserts! (is-eq (get status bond) "active") err-bond-closed)
        (asserts! (> remaining u0) err-invalid-amount)
        
        ;; Transfer remaining amount
        (try! (stx-transfer? remaining tx-sender (as-contract tx-sender)))
        
        ;; Update bond
        (map-set bonds bond-id
            (merge bond {
                status: "completed",
                total-repaid: (get payment-cap bond)
            })
        )
        
        ;; Update stats
        (var-set total-repaid (+ (var-get total-repaid) remaining))
        
        (ok true)
    )
)