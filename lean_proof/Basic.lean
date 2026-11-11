-- This document is co-authored by Gemini 3.6 Flash (thinking mode)


import Mathlib

noncomputable section

open Finset Real Classical BigOperators

-- ============================================================================
-- 1. BASE NETWORK CALCULUS NAMESPACE
-- ============================================================================

namespace NetworkCalculus

/-- Model of a real-time periodic traffic flow in a Network Calculus framework. -/
structure NCFlow where
  id         : Nat  -- Unique tie-breaker identifier
  pcp        : Nat  -- Priority Code Point
  L          : ℝ    -- Maximum packet payload size
  T          : ℝ    -- Generation period / inter-arrival interval
  phi        : ℝ    -- Initial release phase at ingress
  L_pos      : 0 < L
  T_pos      : 0 < T
  pcp_nonneg : 0 ≤ pcp
  pcp_range  : pcp ≤ 7
  deriving DecidableEq

/-- Model of a physical network link or router port. -/
structure Hop where
  id    : Nat
  C     : ℝ    -- Link transmission capacity
  C_pos : 0 < C

/-- Lifecycle execution timestamps for packet instance `i` of flow `f`. -/
structure PacketExecution where
  f : NCFlow
  i : Nat
  a : ℝ  -- Arrival time at regulator queue
  r : ℝ  -- Input release time to scheduler
  s : ℝ  -- Transmission start time
  e : ℝ  -- Egress completion time

/-- Physical validity constraints for a single packet timeline on a hop. -/
structure ValidPacketTimeline (p : PacketExecution) (h : Hop) : Prop where
  a_le_r : p.a ≤ p.r
  r_le_s : p.r ≤ p.s
  s_lt_e : p.s < p.e
  transmission_duration : p.e - p.s ≤ p.f.L / h.C

/-- Initial packet release condition at network ingress. -/
def InitialHopRelease (p : PacketExecution) : Prop :=
  p.r = p.f.phi + p.i * p.f.T

/-- Physical latency components between network hops. -/
structure PhysicalLinkDelay where
  d_trans : ℝ
  d_prop  : ℝ
  d_proc  : ℝ
  d_trans_nonneg : 0 ≤ d_trans
  d_prop_nonneg  : 0 ≤ d_prop
  d_proc_nonneg  : 0 ≤ d_proc

/-- Total physical latency aggregate across transmission, propagation, and processing. -/
def total_physical_delay (phy : PhysicalLinkDelay) : ℝ :=
  phy.d_trans + phy.d_prop + phy.d_proc

-- ----------------------------------------------------------------------------
-- Aggregates & System Feasibility Definitions
-- ----------------------------------------------------------------------------

/-- Aggregate burst capacity of releasing one packet per flow in set `S`. -/
def aggregate_one_packet_burst (S : Finset NCFlow) : ℝ :=
  ∑ f ∈ S, f.L

/-- Aggregate long-term utilization across all flows in set `S`. -/
def aggregate_utilization (S : Finset NCFlow) : ℝ :=
  ∑ f ∈ S, (f.L / f.T)

/-- Subset of flows with priority level equal to or exceeding `p`. -/
def higher_or_equal_priority (flows : Finset NCFlow) (p : Nat) : Finset NCFlow :=
  flows.filter (fun f => f.pcp ≥ p)

/-- Maximum transmission delay of a single packet across all flows on hop `h` for preemtion packets. -/
def S_max (flows : Finset NCFlow) (h : Hop) : ℝ :=
  if hf : flows.Nonempty then
    (flows.sup' hf NCFlow.L) / h.C
  else
    0

/-- System feasibility condition: total utilization must be strictly less than capacity. -/
def IsFeasible (flows : Finset NCFlow) (h : Hop) : Prop :=
  aggregate_utilization flows < h.C

/-- Class-level feasibility condition for flows with priority `≥ p`. -/
def ClassFeasibility (flows : Finset NCFlow) (h : Hop) (p : Nat) : Prop :=
  aggregate_utilization (higher_or_equal_priority flows p) < h.C

/-- Utilization of higher-priority flows is bounded by total utilization. -/
lemma higher_priority_utilization_le (flows : Finset NCFlow) (p : Nat) :
    aggregate_utilization (higher_or_equal_priority flows p) ≤ aggregate_utilization flows := by
  dsimp [aggregate_utilization, higher_or_equal_priority]
  apply sum_le_sum_of_subset_of_nonneg
  · exact filter_subset _ _
  · intro f _ _
    exact div_nonneg (le_of_lt f.L_pos) (le_of_lt f.T_pos)

/-- System-wide feasibility implies class-level feasibility for any priority class. -/
theorem system_feasibility_implies_class_feasibility
    (flows : Finset NCFlow) (h : Hop) (p : Nat)
    (h_feas : IsFeasible flows h) : ClassFeasibility flows h p := by
  dsimp [ClassFeasibility, IsFeasible] at *
  have h_le := higher_priority_utilization_le flows p
  exact lt_of_le_of_lt h_le h_feas

/-- Feasibility guarantees a strictly positive stability margin `C - ∑ (L/T)`. -/
lemma positive_stability_margin
    (flows : Finset NCFlow) (h : Hop) (p : Nat)
    (h_stab : ClassFeasibility flows h p) :
    0 < h.C - aggregate_utilization (higher_or_equal_priority flows p) := by
  dsimp [ClassFeasibility] at h_stab
  linarith

-- ============================================================================
-- SHARED ARRIVAL CURVE DEFINITIONS
-- ============================================================================

/-- Arrival curve envelope `α(t) = L * ⌈t / T⌉` for packetized traffic. -/
def alpha (f : NCFlow) (t : ℝ) : ℝ :=
  f.L * (Nat.ceil (t / f.T))

/-- Aggregate arrival curve envelope across set `S`. -/
def aggregate_alpha (S : Finset NCFlow) (t : ℝ) : ℝ :=
  ∑ f ∈ S, alpha f t

/-- Linear upper bound estimation: `α(t) ≤ t * (L / T) + L`. -/
lemma alpha_linear_bound (f : NCFlow) (t : ℝ) (ht : 0 ≤ t) :
    alpha f t ≤ t * (f.L / f.T) + f.L := by
  dsimp [alpha]
  have hT_pos : 0 < f.T := f.T_pos
  have h_div_nonneg : 0 ≤ t / f.T := div_nonneg ht (le_of_lt hT_pos)
  have h_ceil : (Nat.ceil (t / f.T) : ℝ) ≤ t / f.T + 1 := by
    have h_lt := Nat.ceil_lt_add_one h_div_nonneg
    linarith
  have hL_pos : 0 ≤ f.L := le_of_lt f.L_pos
  have h_mul : f.L * (Nat.ceil (t / f.T) : ℝ) ≤ f.L * (t / f.T + 1) := by
    nlinarith [h_ceil, hL_pos]
  have h_ring : f.L * (t / f.T + 1) = t * (f.L / f.T) + f.L := by ring
  linarith [h_mul, h_ring]

/-- Linear upper bound for aggregate arrival curve `aggregate_alpha`. -/
lemma aggregate_alpha_linear_bound (S : Finset NCFlow) (t : ℝ) (ht : 0 ≤ t) :
    aggregate_alpha S t ≤ t * aggregate_utilization S + aggregate_one_packet_burst S := by
  dsimp [aggregate_alpha, aggregate_utilization, aggregate_one_packet_burst]
  have h_sum : ∑ f ∈ S, alpha f t ≤ ∑ f ∈ S, (t * (f.L / f.T) + f.L) := by
    apply sum_le_sum
    intro f _
    exact alpha_linear_bound f t ht
  have h_split : ∑ f ∈ S, (t * (f.L / f.T) + f.L) = t * (∑ f ∈ S, f.L / f.T) + (∑ f ∈ S, f.L) := by
    rw [sum_add_distrib, ← mul_sum]
  linarith

-- ============================================================================
-- SHARED SERVICE CURVE DEFINITIONS
-- ============================================================================

/-- Standard rate-latency service curve β(t) = R * max(0, t - θ). -/
def beta (R theta t : ℝ) : ℝ :=
  R * max 0 (t - theta)

/-- Leftover transmission rate capacity after servicing higher-or-equal priority flows. -/
def leftover_rate (flows : Finset NCFlow) (h : Hop) (p : Nat) : ℝ :=
  h.C - aggregate_utilization (higher_or_equal_priority flows p)

/-- Maximum leftover latency bound θ experienced by a priority class. -/
def leftover_latency (flows : Finset NCFlow) (h : Hop) (p : Nat) : ℝ :=
  (aggregate_one_packet_burst (higher_or_equal_priority flows p) + h.C * S_max flows h) /
  leftover_rate flows h p

/-- Strict leftover rate-latency service curve β_leftover(t) for priority class p. -/
def beta_leftover (flows : Finset NCFlow) (h : Hop) (p : Nat) (t : ℝ) : ℝ :=
  beta (leftover_rate flows h p) (leftover_latency flows h p) t

-- ----------------------------------------------------------------------------
-- Active Packet Sets & Overlap Predicates
-- ----------------------------------------------------------------------------

/-- Predicate checking if execution interval of packet `p` overlaps open interval `(r, s)`. -/
def OverlapsInterval (p : PacketExecution) (r s : ℝ) : Prop :=
  p.s < s ∧ r < p.e

/-- Finite set of candidate packet executions generated within window `s`. -/
def candidate_packet_set (flows : Finset NCFlow) (s : ℝ) : Finset (NCFlow × Nat) :=
  flows.biUnion (fun f => (Finset.range (Nat.ceil (s / f.T) + 1)).image (fun j => (f, j)))

/-- Set of active higher-or-equal priority packets overlapping packet `(f, i)`'s interval. -/
def active_higher_prio_packets
    (flows : Finset NCFlow) (exec : NCFlow → Nat → PacketExecution)
    (f : NCFlow) (i : Nat) : Finset (NCFlow × Nat) :=
  (candidate_packet_set flows (exec f i).s).filter (fun ⟨f', j⟩ =>
    f'.pcp ≥ f.pcp ∧ OverlapsInterval (exec f' j) (exec f i).r (exec f i).s)

/-- Set of active lower-priority packets overlapping packet `(f, i)`'s interval. -/
def active_lower_prio_packets
    (flows : Finset NCFlow) (exec : NCFlow → Nat → PacketExecution)
    (f : NCFlow) (i : Nat) : Finset (NCFlow × Nat) :=
  (candidate_packet_set flows (exec f i).s).filter (fun ⟨f', j⟩ =>
    f'.pcp < f.pcp ∧ OverlapsInterval (exec f' j) (exec f i).r (exec f i).s)

-- ----------------------------------------------------------------------------
-- Latency Component Decompositions
-- ----------------------------------------------------------------------------

/-- Time spent in shaping regulator queue awaiting release. -/
def regulator_delay (p : PacketExecution) : ℝ :=
  p.r - p.a

/-- Time spent in scheduler queue awaiting transmission start. -/
def scheduler_wait_delay (p : PacketExecution) : ℝ :=
  p.s - p.r

/-- Transmission delay duration on the physical hop link. -/
def transmission_delay (p : PacketExecution) (h : Hop) : ℝ :=
  p.f.L / h.C

/-- Total per-hop processing delay from arrival to egress completion. -/
def total_hop_delay (p : PacketExecution) : ℝ :=
  p.e - p.a

/-- Decomposition of total hop delay into regulator, scheduler, and transmission components. -/
lemma total_delay_decomposition (p : PacketExecution) (h : Hop) (h_tl : ValidPacketTimeline p h) :
    total_hop_delay p ≤ regulator_delay p + scheduler_wait_delay p + transmission_delay p h := by
  unfold total_hop_delay regulator_delay scheduler_wait_delay transmission_delay
  have h_trans := h_tl.transmission_duration
  linarith

-- ----------------------------------------------------------------------------
-- Base Priority Scheduler Axioms and Properties
-- ----------------------------------------------------------------------------

/-- Core operational axioms governing priority scheduling behavior. -/
structure BaseSchedulerSystem (flows : Finset NCFlow) (h : Hop) where
  exec : NCFlow → Nat → PacketExecution

  exec_f : ∀ f ∈ flows, ∀ i, (exec f i).f = f
  exec_i : ∀ f ∈ flows, ∀ i, (exec f i).i = i

  timeline : ∀ f ∈ flows, ∀ i, ValidPacketTimeline (exec f i) h

  /-- Priority Order: Released higher-priority packets defer lower-priority start. -/
  priority_order : ∀ f1 ∈ flows, ∀ f2 ∈ flows, ∀ i j,
    f1.pcp < f2.pcp →
    (exec f2 j).r ≤ (exec f1 i).s →
    (exec f2 j).s ≤ (exec f1 i).s

  /-- FIFO Order: Equal-priority packets are served by release order (or tie-broken by ID). -/
  same_class_order : ∀ f1 ∈ flows, ∀ f2 ∈ flows, ∀ i j,
    f1.pcp = f2.pcp →
    ((exec f1 i).r < (exec f2 j).r ∨
     ((exec f1 i).r = (exec f2 j).r ∧ f1.id < f2.id)) →
    (exec f1 i).s ≤ (exec f2 j).s

  /-- Non-Overlapping: Unique packet transmission intervals are strictly disjoint. -/
  non_overlapping : ∀ f1 ∈ flows, ∀ f2 ∈ flows, ∀ i j,
    (f1 ≠ f2 ∨ i ≠ j) →
    (exec f1 i).s ≤ (exec f2 j).s →
    (exec f1 i).e ≤ (exec f2 j).s

  /-- Work Conservation: Queue delay implies busy link with equal or higher priority work. -/
  work_conservation : ∀ f ∈ flows, ∀ i,
    (exec f i).s - (exec f i).r ≤
      ∑ p ∈ (active_lower_prio_packets flows exec f i ∪ active_higher_prio_packets flows exec f i),
        ((exec p.1 p.2).e - (exec p.1 p.2).s)

-- ----------------------------------------------------------------------------
-- Shared Base System Lemmas
-- ----------------------------------------------------------------------------

/-- Packet queueing time in the scheduler is non-negative. -/
lemma waiting_time_nonneg
    (flows : Finset NCFlow) (h : Hop) (sys : BaseSchedulerSystem flows h)
    (f : NCFlow) (hf : f ∈ flows) (i : Nat) :
    0 ≤ (sys.exec f i).s - (sys.exec f i).r := by
  have h_r_le_s := (sys.timeline f hf i).r_le_s
  linarith

/-- Any packet in the active lower-priority set originates from a valid system flow. -/
lemma active_lower_prio_flow
    {flows : Finset NCFlow} {exec : NCFlow → Nat → PacketExecution}
    {f : NCFlow} {i : Nat} {p : NCFlow × Nat}
    (hp : p ∈ active_lower_prio_packets flows exec f i) : p.1 ∈ flows := by
  dsimp [active_lower_prio_packets] at hp
  rw [mem_filter] at hp
  dsimp [candidate_packet_set] at hp
  rw [mem_biUnion] at hp
  rcases hp.1 with ⟨f', hf', hj⟩
  rw [mem_image] at hj
  rcases hj with ⟨j', _, rfl⟩
  exact hf'

/-- Lower-priority packets cannot commence transmission during higher-priority queueing. -/
lemma lower_priority_cannot_start_during_wait
    (flows : Finset NCFlow) (h : Hop) (sys : BaseSchedulerSystem flows h)
    (f f' : NCFlow) (hf : f ∈ flows) (hf' : f' ∈ flows) (i j : Nat)
    (h_low_prio : f'.pcp < f.pcp)
    (h_released : (sys.exec f i).r ≤ (sys.exec f' j).s) :
    (sys.exec f i).s ≤ (sys.exec f' j).s := by
  exact sys.priority_order f' hf' f hf j i h_low_prio h_released

/-- Active lower-priority packets in the waiting window must have started before release `r`. -/
lemma lower_prio_started_before_r
    (flows : Finset NCFlow) (h : Hop) (sys : BaseSchedulerSystem flows h)
    (f : NCFlow) (hf : f ∈ flows) (i : Nat)
    (p : NCFlow × Nat)
    (hp_in : p ∈ active_lower_prio_packets flows sys.exec f i)
    (hp_flow : p.1 ∈ flows) :
    (sys.exec p.1 p.2).s < (sys.exec f i).r := by
  have hp := hp_in
  dsimp [active_lower_prio_packets] at hp
  rw [mem_filter] at hp
  rcases hp with ⟨_, h_low, h_overlaps⟩
  dsimp [OverlapsInterval] at h_overlaps
  rcases h_overlaps with ⟨h_s_lt_s, _⟩
  by_contra h_ge
  have h_released : (sys.exec f i).r ≤ (sys.exec p.1 p.2).s := by linarith
  have h_s_order := lower_priority_cannot_start_during_wait flows h sys f p.1 hf hp_flow i p.2 h_low h_released
  linarith

/-- At most one non-preemptive lower-priority packet can block a higher-priority packet. -/
lemma active_lower_prio_card_le_one
    (flows : Finset NCFlow) (h : Hop) (sys : BaseSchedulerSystem flows h)
    (f : NCFlow) (hf : f ∈ flows) (i : Nat) :
    (active_lower_prio_packets flows sys.exec f i).card ≤ 1 := by
  by_contra h_gt
  have h_ge : 2 ≤ (active_lower_prio_packets flows sys.exec f i).card := by linarith
  rcases Finset.one_lt_card_iff.mp h_ge with ⟨p1, p2, hp1, hp2, hne⟩
  have hp1_flow : p1.1 ∈ flows := active_lower_prio_flow hp1
  have hp2_flow : p2.1 ∈ flows := active_lower_prio_flow hp2
  have h1_s := lower_prio_started_before_r flows h sys f hf i p1 hp1 hp1_flow
  have h2_s := lower_prio_started_before_r flows h sys f hf i p2 hp2 hp2_flow
  have hp1_filter := hp1
  have hp2_filter := hp2
  dsimp [active_lower_prio_packets] at hp1_filter hp2_filter
  rw [mem_filter] at hp1_filter hp2_filter
  rcases hp1_filter with ⟨_, _, h1_overlaps⟩
  rcases hp2_filter with ⟨_, _, h2_overlaps⟩
  dsimp [OverlapsInterval] at h1_overlaps h2_overlaps
  rcases h1_overlaps with ⟨_, h1_e⟩
  have h2_e := h2_overlaps.2
  rcases le_total (sys.exec p1.1 p1.2).s (sys.exec p2.1 p2.2).s with hs12 | hs21
  · have h_ne : p1.1 ≠ p2.1 ∨ p1.2 ≠ p2.2 := by
      by_contra hc; push Not at hc
      exact hne (Prod.ext hc.1 hc.2)
    have h_no := sys.non_overlapping p1.1 hp1_flow p2.1 hp2_flow p1.2 p2.2 h_ne hs12
    linarith
  · have h_ne : p2.1 ≠ p1.1 ∨ p2.2 ≠ p1.2 := by
      by_contra hc; push Not at hc
      exact hne.symm (Prod.ext hc.1 hc.2)
    have h_no := sys.non_overlapping p2.1 hp2_flow p1.1 hp1_flow p2.2 p1.2 h_ne hs21
    linarith

/-- Blocking work from lower-priority traffic is bounded by maximum frame transmission time. -/
lemma lower_prio_work_bound
    (flows : Finset NCFlow) (h : Hop) (sys : BaseSchedulerSystem flows h)
    (f : NCFlow) (hf : f ∈ flows) (i : Nat) :
    let low_set := active_lower_prio_packets flows sys.exec f i
    ∑ p ∈ low_set, p.1.L ≤ h.C * S_max flows h := by
  intro low_set
  have h_card := active_lower_prio_card_le_one flows h sys f hf i
  have hf_nonempty : flows.Nonempty := ⟨f, hf⟩
  have h_smax : S_max flows h = (flows.sup' hf_nonempty NCFlow.L) / h.C := by
    simp [S_max, hf_nonempty]
  rw [h_smax]
  have hC_pos : 0 < h.C := h.C_pos
  have h_cancel : h.C * ((flows.sup' hf_nonempty NCFlow.L) / h.C) = flows.sup' hf_nonempty NCFlow.L :=
    mul_div_cancel₀ _ (ne_of_gt hC_pos)
  rw [h_cancel]
  rcases Nat.le_one_iff_eq_zero_or_eq_one.mp h_card with h0 | h1
  · have h0_set : (active_lower_prio_packets flows sys.exec f i) = ∅ := Finset.card_eq_zero.mp h0
    dsimp [low_set]
    rw [h0_set, sum_empty]
    have h_le : f.L ≤ flows.sup' hf_nonempty NCFlow.L := le_sup' NCFlow.L hf
    have h_f_pos : 0 ≤ f.L := le_of_lt f.L_pos
    linarith
  · rcases Finset.card_eq_one.mp h1 with ⟨p, hp⟩
    dsimp [low_set]
    rw [hp, sum_singleton]
    have hp_in : p ∈ active_lower_prio_packets flows sys.exec f i := by rw [hp]; exact mem_singleton_self p
    have hp_flow : p.1 ∈ flows := active_lower_prio_flow hp_in
    exact le_sup' NCFlow.L hp_flow

/-- Total backlog served during queueing is bounded by aggregate packet payload sums. -/
lemma work_conservation_sum_bound
    (flows : Finset NCFlow) (h : Hop) (sys : BaseSchedulerSystem flows h)
    (f : NCFlow) (hf : f ∈ flows) (i : Nat) :
    let W := (sys.exec f i).s - (sys.exec f i).r
    let low_set := active_lower_prio_packets flows sys.exec f i
    let ge_set := active_higher_prio_packets flows sys.exec f i
    W * h.C ≤ (∑ p ∈ low_set, p.1.L) + (∑ p ∈ ge_set, p.1.L) := by
  intro W low_set ge_set
  have h_disjoint : Disjoint low_set ge_set := by
    rw [Finset.disjoint_left]
    intro x hx1 hx2
    dsimp [low_set, ge_set, active_lower_prio_packets, active_higher_prio_packets] at hx1 hx2
    rw [mem_filter] at hx1 hx2
    linarith [hx1.2.1, hx2.2.1]
  have h_wc := sys.work_conservation f hf i
  have hC_pos : 0 < h.C := h.C_pos
  have h_duration : ∀ p ∈ (low_set ∪ ge_set), (sys.exec p.1 p.2).e - (sys.exec p.1 p.2).s ≤ p.1.L / h.C := by
    intro p hp
    have hp_flow : p.1 ∈ flows := by
      rcases mem_union.mp hp with h_low | h_ge
      · exact active_lower_prio_flow h_low
      · dsimp [ge_set, active_higher_prio_packets] at h_ge
        rw [mem_filter] at h_ge
        dsimp [candidate_packet_set] at h_ge
        rw [mem_biUnion] at h_ge
        rcases h_ge.1 with ⟨f', hf', hj⟩
        rw [mem_image] at hj
        rcases hj with ⟨j', _, rfl⟩
        exact hf'
    have h_timeline := (sys.timeline p.1 hp_flow p.2).transmission_duration
    have h_f := sys.exec_f p.1 hp_flow p.2
    rw [h_f] at h_timeline
    exact h_timeline

  have h_sum_le : (∑ p ∈ (low_set ∪ ge_set), ((sys.exec p.1 p.2).e - (sys.exec p.1 p.2).s)) ≤ (∑ p ∈ (low_set ∪ ge_set), p.1.L / h.C) := by
    apply sum_le_sum
    intro p hp
    exact h_duration p hp

  have h_trans_bound : W ≤ ∑ p ∈ (low_set ∪ ge_set), p.1.L / h.C := by linarith
  rw [← sum_div] at h_trans_bound
  have h_mul := (le_div_iff₀ hC_pos).mp h_trans_bound
  rw [sum_union h_disjoint] at h_mul
  exact h_mul

end NetworkCalculus

-- ============================================================================
-- 2. PHASE MODIFICATION PROTOCOL (PMP)
-- ============================================================================

namespace NetworkCalculus.PMP

open NetworkCalculus

/-- Operational structure and delay bounds for Phase Modification Protocol (PMP). -/
structure PMPSystem (flows : Finset NCFlow) (h : Hop) extends BaseSchedulerSystem flows h where
  /-- Constant inter-release spacing constraint under PMP. -/
  release_spacing : ∀ f ∈ flows, ∀ i, (exec f (i + 1)).r = (exec f i).r + f.T

  /-- Scheduler waiting delay bounded by flow period `T` (cyclic traffic guarantee). -/
  sched_wait_lt_T : ∀ f ∈ flows, ∀ i, scheduler_wait_delay (exec f i) < f.T

  /-- Arrival curve bound on higher-priority workload interfering in waiting window. -/
  prio_bound : ∀ f ∈ flows, ∀ i,
    ∑ p ∈ active_higher_prio_packets flows exec f i, p.1.L ≤
      aggregate_alpha (higher_or_equal_priority flows f.pcp) ((exec f i).s - (exec f i).r)

  /-- Upper bound on regulator delay prior to release. -/
  regulator_delay_bound : ∀ f ∈ flows, ∀ i,
    ∃ D_reg : ℝ, 0 ≤ D_reg ∧ (exec f i).r - (exec f i).a ≤ D_reg

/-- Upper bound on scheduler waiting latency under PMP utilizing θ_leftover. -/
theorem pmp_scheduler_delay_bound
    (flows : Finset NCFlow)
    (h : Hop)
    (sys : PMPSystem flows h)
    (f : NCFlow)
    (hf : f ∈ flows)
    (i : Nat)
    (h_stable : ClassFeasibility flows h f.pcp) :
    scheduler_wait_delay (sys.exec f i) ≤ leftover_latency flows h f.pcp := by
  dsimp [scheduler_wait_delay, leftover_latency, leftover_rate]
  set S_ge := higher_or_equal_priority flows f.pcp
  set W := (sys.exec f i).s - (sys.exec f i).r
  have hW_nonneg : 0 ≤ W := waiting_time_nonneg flows h sys.toBaseSchedulerSystem f hf i
  have hC_pos : 0 < h.C := h.C_pos
  have h_low := lower_prio_work_bound flows h sys.toBaseSchedulerSystem f hf i
  have h_high : ∑ p ∈ active_higher_prio_packets flows sys.exec f i, p.1.L ≤ aggregate_alpha S_ge W := sys.prio_bound f hf i
  have h_wc := work_conservation_sum_bound flows h sys.toBaseSchedulerSystem f hf i
  have h_work : W * h.C ≤ h.C * S_max flows h + aggregate_alpha S_ge W := by linarith
  have h_alpha := aggregate_alpha_linear_bound S_ge W hW_nonneg
  have h1 : W * h.C ≤ h.C * S_max flows h + (W * aggregate_utilization S_ge + aggregate_one_packet_burst S_ge) := by linarith
  have h2 : W * (h.C - aggregate_utilization S_ge) ≤ aggregate_one_packet_burst S_ge + h.C * S_max flows h := by linarith
  have h_denom_pos : 0 < h.C - aggregate_utilization S_ge := positive_stability_margin flows h f.pcp h_stable
  exact (le_div_iff₀ h_denom_pos).mpr h2

/-- End-to-end single-hop latency bound under PMP utilizing θ_leftover. -/
theorem pmp_total_hop_delay_bound
    (flows : Finset NCFlow)
    (h : Hop)
    (sys : PMPSystem flows h)
    (f : NCFlow)
    (hf : f ∈ flows)
    (i : Nat)
    (h_stable : ClassFeasibility flows h f.pcp) :
    ∃ D_reg : ℝ, 0 ≤ D_reg ∧
      total_hop_delay (sys.exec f i) ≤
        D_reg + leftover_latency flows h f.pcp + (f.L / h.C) := by
  rcases sys.regulator_delay_bound f hf i with ⟨D_reg, hD_pos, h_reg_bound⟩
  use D_reg
  refine ⟨hD_pos, ?_⟩
  have h_tl := sys.timeline f hf i
  have h_decomp := total_delay_decomposition (sys.exec f i) h h_tl
  have h_sched_bound := pmp_scheduler_delay_bound flows h sys f hf i h_stable
  have h_f := sys.exec_f f hf i
  dsimp [total_hop_delay, regulator_delay, scheduler_wait_delay, transmission_delay] at h_decomp h_sched_bound ⊢
  rw [h_f] at h_decomp
  linarith

/-- Multi-hop network timeline specification for PMP. -/
structure PMPMultiHopTimeline (f : NCFlow) where
  r : Nat → Nat → ℝ  -- `r h i`: release time of packet `i` at hop `h`
  phy : Nat → PhysicalLinkDelay
  hop_C : Nat → Hop
  flows_at_hop : Nat → Finset NCFlow
  hf_at_hop : ∀ h, f ∈ flows_at_hop h
  h_stable : ∀ h, ClassFeasibility (flows_at_hop h) (hop_C h) f.pcp

  release_hop_zero : ∀ i, r 0 i = f.phi + i * f.T
  release_hop_succ : ∀ h i,
    r (h + 1) i = r h i +
      leftover_latency (flows_at_hop h) (hop_C h) f.pcp +
      total_physical_delay (phy h)

/-- Inter-release time preservation theorem for multi-hop PMP networks. -/
theorem pmp_multihop_spacing_preserved
    (f : NCFlow) (timeline : PMPMultiHopTimeline f) (h : Nat) (i : Nat) :
    timeline.r h (i + 1) = timeline.r h i + f.T := by
  induction h with
  | zero =>
    rw [timeline.release_hop_zero, timeline.release_hop_zero]
    push_cast
    ring
  | succ h ih =>
    rw [timeline.release_hop_succ, timeline.release_hop_succ, ih]
    ring

/--
  End-to-end multihop delay bound for PMP.
  Measures the accumulated delay from the initial ingress release (excluding shaping)
  to the release at hop H, summing scheduler and physical delays.
-/
theorem pmp_multihop_e2e_delay_bound
    (f : NCFlow) (timeline : PMPMultiHopTimeline f) (H : Nat) (i : Nat) :
    timeline.r H i - timeline.r 0 i =
      ∑ h ∈ Finset.range H, (
        leftover_latency (timeline.flows_at_hop h) (timeline.hop_C h) f.pcp +
        total_physical_delay (timeline.phy h)
      ) := by
  induction H with
  | zero =>
    simp
  | succ H ih =>
    rw [Finset.sum_range_succ]
    have h_step := timeline.release_hop_succ H i
    linarith

end NetworkCalculus.PMP

-- ============================================================================
-- 3. RELEASE GUARD PROTOCOL (RGP)
-- ============================================================================

namespace NetworkCalculus.RGP

open NetworkCalculus

/--
  Work-conserving RGP release rule:
  The release time `r_i` is bounded strictly below by arrival `a_i` and bounded
  above by the classical release guard spacing `max(a_i, r_{i-1} + T)`.
-/
def RGPReleaseRule (exec_curr : PacketExecution) (exec_prev : PacketExecution) : Prop :=
  exec_curr.a ≤ exec_curr.r ∧ exec_curr.r ≤ max exec_curr.a (exec_prev.r + exec_curr.f.T)

/-- Operational system structure for Release Guard Protocol (RGP). -/
structure RGPSystem (flows : Finset NCFlow) (h : Hop) extends BaseSchedulerSystem flows h where
  /-- Release Guard spacing rule supporting work-conserving early dequeueing. -/
  rgp_release_spacing : ∀ f ∈ flows, ∀ i > 0,
    RGPReleaseRule (exec f i) (exec f (i - 1))

  prio_bound : ∀ f ∈ flows, ∀ i,
    ∑ p ∈ active_higher_prio_packets flows exec f i, p.1.L ≤
      aggregate_alpha (higher_or_equal_priority flows f.pcp) ((exec f i).s - (exec f i).r)

  regulator_delay_bound : ∀ f ∈ flows, ∀ i,
    ∃ D_up : ℝ, 0 ≤ D_up ∧ (exec f i).r - (exec f i).a ≤ D_up * (1 - f.L / (h.C * f.T))

/-- Upper bound on scheduler waiting delay under RGP utilizing θ_leftover. -/
theorem rgp_scheduler_delay_bound
    (flows : Finset NCFlow)
    (h : Hop)
    (sys : RGPSystem flows h)
    (f : NCFlow)
    (hf : f ∈ flows)
    (i : Nat)
    (h_stable : ClassFeasibility flows h f.pcp) :
    scheduler_wait_delay (sys.exec f i) ≤ leftover_latency flows h f.pcp := by
  dsimp [scheduler_wait_delay, leftover_latency, leftover_rate]
  set S_ge := higher_or_equal_priority flows f.pcp
  set W := (sys.exec f i).s - (sys.exec f i).r
  have hW_nonneg : 0 ≤ W := waiting_time_nonneg flows h sys.toBaseSchedulerSystem f hf i
  have hC_pos : 0 < h.C := h.C_pos
  have h_low := lower_prio_work_bound flows h sys.toBaseSchedulerSystem f hf i
  have h_high : ∑ p ∈ active_higher_prio_packets flows sys.exec f i, p.1.L ≤ aggregate_alpha S_ge W := sys.prio_bound f hf i
  have h_wc := work_conservation_sum_bound flows h sys.toBaseSchedulerSystem f hf i
  have h_work : W * h.C ≤ h.C * S_max flows h + aggregate_alpha S_ge W := by linarith
  have h_alpha := aggregate_alpha_linear_bound S_ge W hW_nonneg
  have h1 : W * h.C ≤ h.C * S_max flows h + (W * aggregate_utilization S_ge + aggregate_one_packet_burst S_ge) := by linarith
  have h2 : W * (h.C - aggregate_utilization S_ge) ≤ aggregate_one_packet_burst S_ge + h.C * S_max flows h := by linarith
  have h_denom_pos : 0 < h.C - aggregate_utilization S_ge := positive_stability_margin flows h f.pcp h_stable
  exact (le_div_iff₀ h_denom_pos).mpr h2

/-- End-to-end single-hop latency bound under RGP utilizing θ_leftover. -/
theorem rgp_total_hop_delay_bound
    (flows : Finset NCFlow)
    (h : Hop)
    (sys : RGPSystem flows h)
    (f : NCFlow)
    (hf : f ∈ flows)
    (i : Nat)
    (h_stable : ClassFeasibility flows h f.pcp) :
    ∃ D_up : ℝ, 0 ≤ D_up ∧
      total_hop_delay (sys.exec f i) ≤
        D_up * (1 - f.L / (h.C * f.T)) +
        leftover_latency flows h f.pcp +
        (f.L / h.C) := by
  rcases sys.regulator_delay_bound f hf i with ⟨D_up, hD_pos, h_reg_bound⟩
  use D_up
  refine ⟨hD_pos, ?_⟩
  have h_tl := sys.timeline f hf i
  have h_decomp := total_delay_decomposition (sys.exec f i) h h_tl
  have h_sched_bound := rgp_scheduler_delay_bound flows h sys f hf i h_stable
  have h_f := sys.exec_f f hf i
  dsimp [total_hop_delay, regulator_delay, scheduler_wait_delay, transmission_delay] at h_decomp h_sched_bound ⊢
  rw [h_f] at h_decomp
  linarith

/-- Multi-hop network timeline specification for RGP. -/
structure RGPMultiHopTimeline (f : NCFlow) where
  a : Nat → Nat → ℝ  -- `a h i`: arrival time of packet `i` at hop `h`
  r : Nat → Nat → ℝ  -- `r h i`: release time of packet `i` at hop `h`
  e : Nat → Nat → ℝ  -- `e h i`: egress time of packet `i` at hop `h`
  phy : Nat → PhysicalLinkDelay
  flows_at_hop : Nat → Finset NCFlow
  hop_C : Nat → Hop

  hf_at_hop : ∀ h, f ∈ flows_at_hop h
  h_stable : ∀ h, ClassFeasibility (flows_at_hop h) (hop_C h) f.pcp

  -- Hop 0 is the ingress, packets released strictly periodically based on phase
  release_hop_zero : ∀ i, r 0 i = f.phi + (i : ℝ) * f.T

  -- Bound on local delay (scheduler + transmission) at any hop utilizing θ_leftover
  hop_delay_bound : ∀ h i, e h i - r h i ≤
    leftover_latency (flows_at_hop h) (hop_C h) f.pcp + (f.L / (hop_C h).C)

  -- Arrival at hop h+1 is egress at hop h plus physical link delay
  link_propagation : ∀ h i, a (h + 1) i = e h i + total_physical_delay (phy h)

  -- Order of arrivals: packets arrive in order
  arrival_mono : ∀ h i, a h i ≤ a h (i + 1)

  -- RGP work-conserving release rule across successive hops
  release_rule_succ_zero : ∀ h, r (h + 1) 0 = a (h + 1) 0
  release_rule_succ : ∀ h i, 0 < i →
    a (h + 1) i ≤ r (h + 1) i ∧ r (h + 1) i ≤ max (a (h + 1) i) (r (h + 1) (i - 1) + f.T)

/-- Helper definition abstracting the maximum per-hop scheduling and transmission delay. -/
def rgp_hop_bound (f : NCFlow) (timeline : RGPMultiHopTimeline f) (h : Nat) : ℝ :=
  leftover_latency (timeline.flows_at_hop h) (timeline.hop_C h) f.pcp +
  (f.L / (timeline.hop_C h).C)

/--
  Inductive proof establishing that the RGP release time at any hop `h`
  never trails the initial ingress release by more than the cumulative sum of bounds.
-/
lemma rgp_release_bound (f : NCFlow) (timeline : RGPMultiHopTimeline f) (h i : Nat) :
    timeline.r h i ≤ timeline.r 0 i + ∑ k ∈ Finset.range h, (rgp_hop_bound f timeline k + total_physical_delay (timeline.phy k)) := by
  revert i -- Generalize i so the induction hypothesis applies to any packet index
  induction h with
  | zero =>
    intro i
    simp
  | succ h ih_h =>
    intro i
    rw [Finset.sum_range_succ]
    induction i with
    | zero =>
      have h_rule := timeline.release_rule_succ_zero h
      have h_prop := timeline.link_propagation h 0
      have h_delay := timeline.hop_delay_bound h 0
      have h_delay' : timeline.e h 0 - timeline.r h 0 ≤ rgp_hop_bound f timeline h := h_delay
      have h_ih := ih_h 0
      linarith
    | succ i ih_i =>
      have h_rule := (timeline.release_rule_succ h (i + 1) (Nat.zero_lt_succ i)).2
      apply le_trans h_rule
      apply max_le
      · -- Case 1: Release is bounded directly by arrival time
        have h_prop := timeline.link_propagation h (i + 1)
        have h_delay := timeline.hop_delay_bound h (i + 1)
        have h_delay' : timeline.e h (i + 1) - timeline.r h (i + 1) ≤ rgp_hop_bound f timeline h := h_delay
        have h_ih := ih_h (i + 1)
        linarith
      · -- Case 2: Release is held back by the Release Guard (T spacing)
        have h_step : timeline.r 0 i + f.T = timeline.r 0 (i + 1) := by
          rw [timeline.release_hop_zero i, timeline.release_hop_zero (i + 1)]
          push_cast
          ring
        have h_idx : i + 1 - 1 = i := rfl
        rw [h_idx]
        have h_bound := ih_i
        linarith

/--
  End-to-end multihop delay bound for RGP.
  Measures delay from ingress release to egress of hop H, showing the pay-burst-only-once property.
-/
theorem rgp_multihop_e2e_delay_bound
    (f : NCFlow) (timeline : RGPMultiHopTimeline f) (H : Nat) (i : Nat) :
    timeline.e H i - timeline.r 0 i ≤
      (∑ h ∈ Finset.range H, (rgp_hop_bound f timeline h + total_physical_delay (timeline.phy h))) +
      rgp_hop_bound f timeline H := by
  have h_rel := rgp_release_bound f timeline H i
  have h_del := timeline.hop_delay_bound H i
  have h_del' : timeline.e H i - timeline.r H i ≤ rgp_hop_bound f timeline H := h_del
  linarith

end NetworkCalculus.RGP

-- ============================================================================
-- 4. CYCLIC TRAFFIC RELAXATIONS
-- ============================================================================

namespace NetworkCalculus.CyclicTraffic

open NetworkCalculus

def PSCT_Invariant (flows : Finset NCFlow) (_h : Hop) (exec : NCFlow → Nat → PacketExecution) : Prop :=
  ∀ f ∈ flows, ∀ i, scheduler_wait_delay (exec f i) ≤ f.T

def PHCT_Invariant (flows : Finset NCFlow) (_h : Hop) (exec : NCFlow → Nat → PacketExecution)
    (z : NCFlow → Nat → ℝ) : Prop :=
  ∀ f ∈ flows, ∀ i, (exec f i).r + scheduler_wait_delay (exec f i) - z f i ≤ f.T

lemma psct_relaxed_bound (flows : Finset NCFlow) (_h : Hop) (exec : NCFlow → Nat → PacketExecution)
    (f : NCFlow) (i : Nat) (hf : f ∈ flows)
    (h_psct : PSCT_Invariant flows _h exec) :
    (exec f i).s - (exec f i).r ≤ f.T := by
  exact h_psct f hf i

def pmp_earliest_arrival {f : NCFlow} (timeline : PMP.PMPMultiHopTimeline f) (h i : Nat) : ℝ :=
  if h = 0 then timeline.r 0 i else timeline.r (h - 1) i

theorem phct_implies_psct (flows : Finset NCFlow) (_h : Hop)
    (exec : NCFlow → Nat → PacketExecution) (z : NCFlow → Nat → ℝ)
    (h_release_after_z : ∀ f ∈ flows, ∀ i, z f i ≤ (exec f i).r)
    (h_phct : PHCT_Invariant flows _h exec z) :
    PSCT_Invariant flows _h exec := by
  intro f hf i
  have h_phct_f := h_phct f hf i
  have h_z_le_r := h_release_after_z f hf i
  linarith

end NetworkCalculus.CyclicTraffic


#print axioms NetworkCalculus.higher_priority_utilization_le
#print axioms NetworkCalculus.system_feasibility_implies_class_feasibility
#print axioms NetworkCalculus.positive_stability_margin
#print axioms NetworkCalculus.alpha_linear_bound
#print axioms NetworkCalculus.aggregate_alpha_linear_bound
#print axioms NetworkCalculus.total_delay_decomposition
#print axioms NetworkCalculus.waiting_time_nonneg
#print axioms NetworkCalculus.active_lower_prio_flow
#print axioms NetworkCalculus.lower_priority_cannot_start_during_wait
#print axioms NetworkCalculus.lower_prio_started_before_r
#print axioms NetworkCalculus.active_lower_prio_card_le_one
#print axioms NetworkCalculus.lower_prio_work_bound
#print axioms NetworkCalculus.work_conservation_sum_bound

#print axioms NetworkCalculus.beta
#print axioms NetworkCalculus.leftover_rate
#print axioms NetworkCalculus.leftover_latency
#print axioms NetworkCalculus.beta_leftover

#print axioms NetworkCalculus.PMP.pmp_scheduler_delay_bound
#print axioms NetworkCalculus.PMP.pmp_total_hop_delay_bound
#print axioms NetworkCalculus.PMP.pmp_multihop_spacing_preserved
#print axioms NetworkCalculus.PMP.pmp_multihop_e2e_delay_bound

#print axioms NetworkCalculus.RGP.rgp_scheduler_delay_bound
#print axioms NetworkCalculus.RGP.rgp_total_hop_delay_bound
#print axioms NetworkCalculus.RGP.rgp_release_bound
#print axioms NetworkCalculus.RGP.rgp_multihop_e2e_delay_bound

#print axioms NetworkCalculus.CyclicTraffic.psct_relaxed_bound
#print axioms NetworkCalculus.CyclicTraffic.phct_implies_psct
