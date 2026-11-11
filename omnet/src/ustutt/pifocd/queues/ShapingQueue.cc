#include "ShapingQueue.h"
#include "../SchedulingTree.h"
#include "../utils.h"
#include "inet/common/packet/Packet.h"
#include <omnetpp.h>
#include <optional>

using namespace omnetpp;

int ShapingQueue::size() const { return rt_pq.size(); }

bool ShapingQueue::isEmpty() const { return size() == 0; }

void ShapingQueue::clear() {
  while (rt_pq.size() > 0) {
    rt_pq.pop();
  }

  while (rt_sq.size() > 0) {
      rt_sq.pop();
  }

  // Notify the scheduling tree that queue state updated
    this->updated();
}


void ShapingQueue::push(PIFOPacket packet) {
  Entry sq_entry{};
  Entry pq_entry{};

  ShapingTransaction sptxn = this->shapingTransaction.value();
  uint64_t rt = sptxn(packet, this->st->shaping_options);

  pq_entry.value = packet;
  pq_entry.rank = rt;

  // This is only needed for the delayed propagation to the root later.
  // We will need the packet to calculate the rank later.
  // This could also be done with more variants and calculating the rank here.
  // This works for now and is simpler.
  sq_entry.value = packet;
  sq_entry.rank = rt;

  rt_pq.push(pq_entry);

  EV_INFO << "PIFOCD: ShapingQueue(id=" << (int)this->id
          << ") enqueued 1 packet with rt=" << rt << EV_ENDL;

  uint64_t now = simtime_to_nsec(simTime());

  EV_INFO << "now=" << now << " rt=" << rt << EV_ENDL;

  if (now >= rt) {
    // rt is already reached. So we can propagate further without putting the
    // element into the queue
    if (parent != nullptr) {
      parent->push(packet);
    }
  } else {
    // insert the element into the shaping queue
    rt_sq.push(sq_entry);

    EV_INFO << "PIFOCD: ShapingQueue(id=" << (int)this->id
            << ") enqueued 1 shaping-ref with rt=" << rt << EV_ENDL;
  }

  this->updated();
}

std::optional<PIFOPacket> ShapingQueue::pull(bool isRgp) {
    // There are three different cases to look at:
    // 1. Whole Queue is empty
    // 2. There is a released packet
    // 3. There is no released packet yet. (Conditional dequeuing)

    std::optional<PIFOPacket> peeked = this->peek(isRgp);

    if (rt_pq.empty()) {
        // No packets in this complete Shaping queue
        return std::nullopt;
    } else if (rt_sq.size() < rt_pq.size()) {
        // This packet is not in sq anymore.
        rt_pq.pop();

        return peeked;
    } else if (isRgp && rt_pq.size() == rt_sq.size()) {
        throw cRuntimeError("PIFOCD: SHOULD NEVER HAPPEN");
        // packet if RGP are released by updatedRG and not this pull function

    } else {
        // This should not happen. (Fall back)
        EV_INFO << "PIFOCD: peeking at queue in weird state: rt_sq.size() = " << rt_sq.size()
                << ", rt_pq.size() = " << rt_pq.size() << EV_ENDL;

        return std::nullopt;
    }
}

std::optional<PIFOPacket> ShapingQueue::peek(bool isRgp) const {
    // There are three different cases to look at:
    // 1. Whole Queue is empty
    // 2. There is a released packet
    // 3. There is no released packet yet. (Conditional dequeuing)

    if (rt_pq.empty()) {
        // No packets in this complete Shaping queue
        return std::nullopt;
    } else if (rt_sq.size() < rt_pq.size()) {
        // This packet is not in sq anymore.
        Entry released_packet_entry = rt_pq.top();

        uint64_t now = simtime_to_nsec(simTime());
        if (released_packet_entry.rank > now) {
            throw cRuntimeError("PIFOCD: packet dequeued from haping queue before rank=%lu and now=%lu",
                    released_packet_entry.rank, now);
        }

        PIFOPacket packet = std::get<PIFOPacket>(released_packet_entry.value);
        return packet;
    } else if (isRgp && rt_pq.size() == rt_sq.size()) {
        // There is atleast one packet since !rt_pq.empty() and all are waiting for release.
        Entry unreleased_packet_entry = rt_pq.top();
        PIFOPacket packet = std::get<PIFOPacket>(unreleased_packet_entry.value);
        return packet;
    } else {
        // This should not happen. (Fall back)
        EV_INFO << "PIFOCD: peeking at queue in weird state: rt_sq.size() = " << rt_sq.size()
                << ", rt_pq.size() = " << rt_pq.size() << EV_ENDL;

        return std::nullopt;
    }
}

void ShapingQueue::updatedRG() {
    // update all owned packets by their releaseguard
    uint64_t now = simtime_to_nsec(simTime());

    int size_sq = rt_sq.size();

    int index = 0;
    while (index < rt_sq.size()) {
        Entry shaping_packet_entry = rt_sq.top();
        PIFOPacket packet = std::get<PIFOPacket>(shaping_packet_entry.value);

        ShapingOptions &opt = this->st->shaping_options[packet.flow.id];

        if (opt.release_time <= now) {
            // release this packet
            rt_sq.pop();

            if (parent != nullptr) {
                parent->push(packet);
            }

            // go through the rt_pq and update the rt as well
            updateRank(rt_pq, packet, opt.release_time);

            // update its rg
            opt.release_time += opt.period;
        } else {
            // not releasing now
            index += 1;
        }
    }

    EV_INFO << "PIFOCD: updatedRg: from" << size_sq << "to: " << rt_sq.size() << EV_ENDL;
}

void ShapingQueue::updateRank(
    std::priority_queue<Entry, std::vector<Entry>, Compare>& pq,
    PIFOPacket packet,
    int newRank)
{
    std::vector<Entry> entries;

    while (!pq.empty()) {
        Entry entry = pq.top();
        pq.pop();

        PIFOPacket entry_packet = std::get<PIFOPacket>(entry.value);
        if (entry_packet.streamName == packet.streamName && entry_packet.packet_id == packet.packet_id) {
            entry.rank = newRank;
        }

        entries.push_back(entry);
    }

    for (const Entry& entry : entries) {
        pq.push(entry);
    }
}

void ShapingQueue::updated() {
    if (rt_sq.empty()) {
        // No packets left.
        this->st->updateTimer(id, UINT64_MAX);
    } else {
        // Still packets in the sq.
        uint64_t rt = rt_sq.top().rank;

        this->st->updateTimer(id, rt);
    }


    // A update happened.
    // It may be possible, a packet is now ready for pulling.
    this->st->notifyCanPullPacketChanged();
}

void ShapingQueue::wake() {
  uint64_t now = simtime_to_nsec(simTime());
  Entry head;

  EV_INFO << "PIFOCD: ShapingQueue(id=" << (int)this->id << ") got woken @" << now << EV_ENDL;

  // Dequeue all packet-refs which timers expired and forward them.
  while (rt_sq.size() > 0) {
    head = rt_sq.top();
    uint64_t rt = head.rank;

    if (now >= rt) {
      PIFOPacket packet = std::get<PIFOPacket>(head.value);
      rt_sq.pop();

      if (parent != nullptr) {
        parent->push(packet);
      }
    } else {
      break;
    }
  }

  // The queue updated itself, so handle these changes.
  this->updated();
}
