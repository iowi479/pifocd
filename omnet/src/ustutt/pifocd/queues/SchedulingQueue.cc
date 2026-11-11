#include "SchedulingQueue.h"
#include "../SchedulingTree.h"

int SchedulingQueue::size() const { return pcp_pq.size(); }

bool SchedulingQueue::isEmpty() const { return size() == 0; }

void SchedulingQueue::clear() {
  while (pcp_pq.size() > 0) {
    pcp_pq.pop();
  }
}

void SchedulingQueue::push(PIFOPacket packet) {
  Entry entry{};
  uint64_t rank = this->schedulingTransaction.value()(packet);

  // assert pcp range, since we might use this as a ref into the children.
  // This allows us to safely downcast to uint8_t later as well.
  if (rank < 0 || rank > 7)
    throw cRuntimeError(
        "PIFOCD: SchedulingQueue Packet-rank is %lu which is not in [0; 7]", rank);

  // Either add packet or the rank which will point us to the ShapingQueue for
  // pcp=rank. The rank is the same as the ref to a ShapingQueue.
  entry.value = isLeaf ? V{packet} : V{(uint8_t) (7-rank)};
  entry.rank = rank;

  EV_INFO << "PIFOCD: SchedulingQueue enqueued 1 ref with rank=" << rank << EV_ENDL;

  pcp_pq.push(entry);

  // Propagate further if there is still a parent
  if (parent != nullptr) {
    parent->push(packet);
  }
}

std::optional<PIFOPacket> SchedulingQueue::pull(bool isRgp) {
  EV_INFO << "PIFOCD: SchedulingQueue pull" << EV_ENDL;

  if (pcp_pq.size() <= 0) {
      return std::nullopt;
  }

  Entry head = pcp_pq.top();

  // Actually remove the head element.
  pcp_pq.pop();

  if (std::holds_alternative<PIFOPacket>(head.value)) {
    if (!isLeaf)
      throw cRuntimeError("PIFOCD: SchedulingQueue is not a leaf");

    // We are a leaf and can return the packet *;
    return std::get<PIFOPacket>(head.value);
  } else {
    uint8_t ref = std::get<uint8_t>(head.value);

    EV_INFO << "PIFOCD: SchedulingQueue dequeued 1 ref with rank=" << (int)ref << EV_ENDL;
    // ref always has to point into the children.
    // If this is out-of-bounds, something went wrong.
    if (this->children.size() <= ref)
      throw cRuntimeError("PIFOCD: SchedulingQueue ref is pointing out of bounds");

    // This can go on recursively until it reaches the leaf.
    return this->st->pullLeaf(ref, isRgp);
  }
}

std::optional<PIFOPacket> SchedulingQueue::peek(bool isRgp) const {
  EV_INFO << "PIFOCD: SchedulingQueue peek" << EV_ENDL;

  if (pcp_pq.size() <= 0) {
      return std::nullopt;
  }

  Entry head = pcp_pq.top();

  if (std::holds_alternative<PIFOPacket>(head.value)) {
    if (!isLeaf)
      throw cRuntimeError("PIFOCD: SchedulingQueue is not a leaf");

    // We are a leaf and can return the packet *;
    return std::get<PIFOPacket>(head.value);
  } else {
    uint8_t ref = std::get<uint8_t>(head.value);

    // ref always has to point into the children.
    // If this is out-of-bounds, something went wrong.
    if (this->children.size() < ref)
      throw cRuntimeError("PIFOCD: SchedulingQueue ref is pointing out of bounds");

    // This can go on recursively until it reaches the leaf.
    EV_INFO << "PIFOCD: SchedulingQueue peek @child=" << (int)ref << EV_ENDL;

    if (!this->children[ref])
      throw cRuntimeError("PIFOCD: SchedulingQueue ref is not there");

    return this->st->peekLeaf(ref, isRgp);
  }
}
