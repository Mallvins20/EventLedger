;; ------------------------------------------------------------
;; StagePass.clar
;; StagePass NFT: Decentralized Event Ticketing Protocol
;; Version: 2.0.0
;; Author: your-handle
;; ------------------------------------------------------------

;; -----------------------------
;; Errors
;; -----------------------------
(define-constant ERR-UNAUTHORIZED        u100)
(define-constant ERR-NOT-INITIALIZED     u101)
(define-constant ERR-ALREADY-INITIALIZED u102)
(define-constant ERR-NOT-OWNER           u103)
(define-constant ERR-NOT-LISTED          u104)
(define-constant ERR-ALREADY-LISTED      u105)
(define-constant ERR-ZERO-PRICE          u106)
(define-constant ERR-INVALID_BPS         u107)
(define-constant ERR-SELF_PURCHASE       u108)
(define-constant ERR-NOT-TOKEN-OWNER     u109)
(define-constant ERR-BAD-INPUT           u110)
(define-constant ERR-INVALID-TOKEN-ID    u111)
(define-constant ERR-INVALID-PRINCIPAL   u112)

;; -----------------------------
;; NFT Core
;; -----------------------------
(define-non-fungible-token stagepass uint)

;; -----------------------------
;; State
;; -----------------------------
(define-data-var initialized bool false)
(define-data-var contract-owner principal tx-sender)
(define-data-var performer principal tx-sender)
(define-data-var royalty-bps uint u1000) ;; 10%
(define-data-var total-supply uint u0)

;; metadata
(define-map pass-meta
  { id: uint }
  {
    event: (string-ascii 48),
    date: uint,
    venue: (string-ascii 48),
    uri: (optional (string-utf8 256))
  }
)

;; marketplace
(define-map marketplace
  { id: uint }
  { price: uint })

;; -----------------------------
;; Validation Helpers
;; -----------------------------
(define-private (valid-id (id uint))
  (and (> id u0) (<= id u1000000))
)

(define-private (valid-principal (who principal))
  (not (is-eq who 'SP000000000000000000002Q6VF78))
)

(define-private (valid-string (str (string-ascii 48)))
  (and (> (len str) u0) (<= (len str) u48))
)

(define-private (valid-date (date uint))
  (and (>= date u20200101) (<= date u30001231))
)

;; -----------------------------
;; Internal
;; -----------------------------
(define-read-only (only-owner)
  (ok (is-eq tx-sender (var-get contract-owner)))
)

(define-read-only (initialized?)
  (ok (var-get initialized))
)

(define-private (calc-royalty (price uint))
  (ok (/ (* price (var-get royalty-bps)) u10000))
)

;; -----------------------------
;; Setup
;; -----------------------------
(define-public (initialize)
  (begin
    (asserts! (not (var-get initialized)) (err ERR-ALREADY-INITIALIZED))
    (var-set contract-owner tx-sender)
    (var-set performer tx-sender)
    (var-set initialized true)
    (ok true)
  )
)

(define-public (set-performer (who principal))
  (begin
    (asserts! (unwrap-panic (only-owner)) (err ERR-UNAUTHORIZED))
    (asserts! (unwrap-panic (initialized?)) (err ERR-NOT-INITIALIZED))
    (asserts! (valid-principal who) (err ERR-INVALID-PRINCIPAL))
    (var-set performer who)
    (ok who)
  )
)

(define-public (set-royalty (bps uint))
  (begin
    (asserts! (unwrap-panic (only-owner)) (err ERR-UNAUTHORIZED))
    (asserts! (<= bps u2000) (err ERR-INVALID_BPS))
    (var-set royalty-bps bps)
    (ok bps)
  )
)

;; -----------------------------
;; Issue Pass (Mint)
;; -----------------------------
(define-public (issue-pass
  (id uint)
  (recipient principal)
  (event (string-ascii 48))
  (date uint)
  (venue (string-ascii 48))
  (uri (optional (string-utf8 256))))
  (begin
    (asserts! (unwrap-panic (only-owner)) (err ERR-UNAUTHORIZED))
    (asserts! (unwrap-panic (initialized?)) (err ERR-NOT-INITIALIZED))

    (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
    (asserts! (valid-principal recipient) (err ERR-INVALID-PRINCIPAL))
    (asserts! (valid-string event) (err ERR-BAD-INPUT))
    (asserts! (valid-date date) (err ERR-BAD-INPUT))
    (asserts! (valid-string venue) (err ERR-BAD-INPUT))

    (try! (nft-mint? stagepass id recipient))

    (map-set pass-meta { id: id }
      { event: event, date: date, venue: venue, uri: uri })

    (var-set total-supply (+ (var-get total-supply) u1))
    (ok id)
  )
)

;; -----------------------------
;; Marketplace
;; -----------------------------
(define-public (list-pass (id uint) (price uint))
  (let ((owner (unwrap! (nft-get-owner? stagepass id) (err ERR-NOT-TOKEN-OWNER))))
    (begin
      (asserts! (is-eq owner tx-sender) (err ERR-NOT-OWNER))
      (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
      (asserts! (> price u0) (err ERR-ZERO-PRICE))

      (match (map-get? marketplace { id: id })
        existing (err ERR-ALREADY-LISTED)
        (begin
          (map-set marketplace { id: id } { price: price })
          (ok true)
        )
      )
    )
  )
)

(define-public (update-pass-price (id uint) (price uint))
  (let ((owner (unwrap! (nft-get-owner? stagepass id) (err ERR-NOT-TOKEN-OWNER))))
    (begin
      (asserts! (is-eq owner tx-sender) (err ERR-NOT-OWNER))
      (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
      (asserts! (> price u0) (err ERR-ZERO-PRICE))
      (asserts! (is-some (map-get? marketplace { id: id })) (err ERR-NOT-LISTED))

      (map-set marketplace { id: id } { price: price })
      (ok true)
    )
  )
)

(define-public (delist-pass (id uint))
  (let ((owner (unwrap! (nft-get-owner? stagepass id) (err ERR-NOT-TOKEN-OWNER))))
    (begin
      (asserts! (is-eq owner tx-sender) (err ERR-NOT-OWNER))
      (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
      (asserts! (is-some (map-get? marketplace { id: id })) (err ERR-NOT-LISTED))

      (map-delete marketplace { id: id })
      (ok true)
    )
  )
)

;; -----------------------------
;; Purchase
;; -----------------------------
(define-public (purchase-pass (id uint))
  (let ((listing (map-get? marketplace { id: id })))
    (begin
      (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
      (asserts! (is-some listing) (err ERR-NOT-LISTED))

      (let (
        (price (get price (default-to { price: u0 } listing)))
        (seller (unwrap! (nft-get-owner? stagepass id) (err ERR-NOT-TOKEN-OWNER)))
      )
        (begin
          (asserts! (> price u0) (err ERR-ZERO-PRICE))
          (asserts! (not (is-eq tx-sender seller)) (err ERR-SELF_PURCHASE))

          (let (
            (royalty (unwrap-panic (calc-royalty price)))
            (creator (var-get performer))
          )
            (begin
              (try! (stx-transfer? (- price royalty) tx-sender seller))
              (try! (stx-transfer? royalty tx-sender creator))

              (try! (nft-transfer? stagepass id seller tx-sender))

              (map-delete marketplace { id: id })
              (ok true)
            )
          )
        )
      )
    )
  )
)

;; -----------------------------
;; Standard Interface
;; -----------------------------
(define-read-only (get-pass-holder (id uint))
  (begin
    (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
    (ok (nft-get-owner? stagepass id))
  )
)

(define-read-only (get-pass-uri (id uint))
  (begin
    (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
    (match (map-get? pass-meta { id: id })
      meta (ok (get uri meta))
      (ok none)
    )
  )
)

(define-public (transfer (id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
    (asserts! (valid-principal sender) (err ERR-INVALID-PRINCIPAL))
    (asserts! (valid-principal recipient) (err ERR-INVALID-PRINCIPAL))
    (asserts! (is-eq sender tx-sender) (err ERR-UNAUTHORIZED))

    (try! (nft-transfer? stagepass id sender recipient))
    (ok true)
  )
)

;; -----------------------------
;; Views
;; -----------------------------
(define-read-only (get-total-supply) (ok (var-get total-supply)))
(define-read-only (get-performer) (ok (var-get performer)))
(define-read-only (get-royalty) (ok (var-get royalty-bps)))

(define-read-only (get-listing (id uint))
  (begin
    (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
    (ok (map-get? marketplace { id: id }))
  )
)

(define-read-only (get-metadata (id uint))
  (begin
    (asserts! (valid-id id) (err ERR-INVALID-TOKEN-ID))
    (ok (map-get? pass-meta { id: id }))
  )
)