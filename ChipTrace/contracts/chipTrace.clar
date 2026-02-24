;; chip-trace: Semiconductor Supply Chain Tracker
;; A smart contract for tracking chips from fabrication to assembly

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-stage (err u104))
(define-constant err-chip-flagged (err u105))

;; Data Variables
(define-data-var chip-counter uint u0)

;; Supply Chain Stages
(define-constant stage-fabricated u1)
(define-constant stage-tested u2)
(define-constant stage-packaged u3)
(define-constant stage-distributed u4)
(define-constant stage-assembled u5)

;; Data Maps
(define-map chips
  { chip-id: uint }
  {
    manufacturer: principal,
    chip-model: (string-ascii 50),
    serial-number: (string-ascii 100),
    fabrication-date: uint,
    current-stage: uint,
    current-holder: principal,
    is-flagged: bool,
    device-assembled: (optional (string-ascii 100))
  }
)

(define-map authorized-entities
  { entity: principal }
  { entity-type: (string-ascii 20), authorized: bool }
)

(define-map stage-history
  { chip-id: uint, stage: uint }
  {
    timestamp: uint,
    handler: principal,
    location: (string-ascii 100),
    notes: (string-ascii 200)
  }
)

;; Authorization Functions
(define-public (authorize-entity (entity principal) (entity-type (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-entities
      { entity: entity }
      { entity-type: entity-type, authorized: true }
    ))
  )
)

(define-public (revoke-entity (entity principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-entities
      { entity: entity }
      { entity-type: "", authorized: false }
    ))
  )
)

(define-read-only (is-authorized (entity principal))
  (default-to false
    (get authorized (map-get? authorized-entities { entity: entity }))
  )
)

;; Chip Registration
(define-public (register-chip 
  (chip-model (string-ascii 50))
  (serial-number (string-ascii 100))
  (fabrication-date uint)
  (location (string-ascii 100)))
  (let
    (
      (new-chip-id (+ (var-get chip-counter) u1))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (is-none (map-get? chips { chip-id: new-chip-id })) err-already-exists)
    
    (map-set chips
      { chip-id: new-chip-id }
      {
        manufacturer: tx-sender,
        chip-model: chip-model,
        serial-number: serial-number,
        fabrication-date: fabrication-date,
        current-stage: stage-fabricated,
        current-holder: tx-sender,
        is-flagged: false,
        device-assembled: none
      }
    )
    
    (map-set stage-history
      { chip-id: new-chip-id, stage: stage-fabricated }
      {
        timestamp: burn-block-height,
        handler: tx-sender,
        location: location,
        notes: "Chip fabricated"
      }
    )
    
    (var-set chip-counter new-chip-id)
    (ok new-chip-id)
  )
)

;; Update Chip Stage
(define-public (update-stage
  (chip-id uint)
  (new-stage uint)
  (location (string-ascii 100))
  (notes (string-ascii 200)))
  (let
    (
      (chip-data (unwrap! (map-get? chips { chip-id: chip-id }) err-not-found))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (not (get is-flagged chip-data)) err-chip-flagged)
    (asserts! (<= new-stage stage-assembled) err-invalid-stage)
    (asserts! (> new-stage (get current-stage chip-data)) err-invalid-stage)
    
    (map-set chips
      { chip-id: chip-id }
      (merge chip-data {
        current-stage: new-stage,
        current-holder: tx-sender
      })
    )
    
    (map-set stage-history
      { chip-id: chip-id, stage: new-stage }
      {
        timestamp: burn-block-height,
        handler: tx-sender,
        location: location,
        notes: notes
      }
    )
    
    (ok true)
  )
)

;; Transfer Chip Custody
(define-public (transfer-custody
  (chip-id uint)
  (new-holder principal)
  (location (string-ascii 100)))
  (let
    (
      (chip-data (unwrap! (map-get? chips { chip-id: chip-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get current-holder chip-data)) err-unauthorized)
    (asserts! (not (get is-flagged chip-data)) err-chip-flagged)
    (asserts! (is-authorized new-holder) err-unauthorized)
    
    (map-set chips
      { chip-id: chip-id }
      (merge chip-data { current-holder: new-holder })
    )
    
    (ok true)
  )
)

;; Mark Chip as Assembled into Device
(define-public (mark-assembled
  (chip-id uint)
  (device-info (string-ascii 100)))
  (let
    (
      (chip-data (unwrap! (map-get? chips { chip-id: chip-id }) err-not-found))
    )
    (asserts! (is-authorized tx-sender) err-unauthorized)
    (asserts! (not (get is-flagged chip-data)) err-chip-flagged)
    (asserts! (is-eq (get current-stage chip-data) stage-assembled) err-invalid-stage)
    
    (map-set chips
      { chip-id: chip-id }
      (merge chip-data { device-assembled: (some device-info) })
    )
    
    (ok true)
  )
)

;; Flag Suspicious Chip
(define-public (flag-chip (chip-id uint))
  (let
    (
      (chip-data (unwrap! (map-get? chips { chip-id: chip-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set chips
      { chip-id: chip-id }
      (merge chip-data { is-flagged: true })
    )
    
    (ok true)
  )
)

(define-public (unflag-chip (chip-id uint))
  (let
    (
      (chip-data (unwrap! (map-get? chips { chip-id: chip-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set chips
      { chip-id: chip-id }
      (merge chip-data { is-flagged: false })
    )
    
    (ok true)
  )
)

;; Read-Only Functions
(define-read-only (get-chip-info (chip-id uint))
  (map-get? chips { chip-id: chip-id })
)

(define-read-only (get-stage-info (chip-id uint) (stage uint))
  (map-get? stage-history { chip-id: chip-id, stage: stage })
)

(define-read-only (get-chip-count)
  (var-get chip-counter)
)

(define-read-only (verify-authenticity (chip-id uint))
  (match (map-get? chips { chip-id: chip-id })
    chip-data (ok {
      exists: true,
      is-flagged: (get is-flagged chip-data),
      manufacturer: (get manufacturer chip-data),
      current-stage: (get current-stage chip-data)
    })
    (ok { exists: false, is-flagged: false, manufacturer: contract-owner, current-stage: u0 })
  )
)

;; Initialize contract owner as authorized
(map-set authorized-entities
  { entity: contract-owner }
  { entity-type: "admin", authorized: true }
)