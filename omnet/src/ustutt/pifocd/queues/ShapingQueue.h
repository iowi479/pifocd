#pragma once

#include "SchedulingQueue.h"
#include "../utils.h"
#include "inet/common/packet/Packet.h"
#include <queue>
#include <variant>
#include <vector>
#include <optional>

using namespace inet;

class ShapingQueue : public SchedulingQueue {
public:
  using ShapingTransaction = std::function<uint64_t(PIFOPacket, std::vector<ShapingOptions> &)>;


protected:
  std::priority_queue<Entry, std::vector<Entry>, Compare> rt_sq;
  std::priority_queue<Entry, std::vector<Entry>, Compare> rt_pq;

  uint8_t id;
  std::optional<ShapingTransaction> shapingTransaction;

public:
  ShapingQueue(bool isLeaf, uint8_t id) : SchedulingQueue(isLeaf), id(id) {
    this->rt_pq = {};
    this->shapingTransaction = std::nullopt;

    if (!isLeaf)
      throw cRuntimeError("PIFOCD: ShapingQueue(id=%d) is not a leaf", id);
  }

  ~ShapingQueue() {};

  void setShapingTransaction(ShapingTransaction sptxn) { this->shapingTransaction = sptxn;}

  int size() const;
  bool isEmpty() const;
  void clear();

  void push(PIFOPacket packet) override;
  std::optional<PIFOPacket> pull(bool isRgp) override;
  std::optional<PIFOPacket> peek(bool isRgp) const override;

  void updatedRG();
  void updateRank(std::priority_queue<Entry, std::vector<Entry>, Compare>& pq, PIFOPacket packet, int newRank);

  /**
   * Something in the queue updated.
   * It may be that the tree will be informed to reschedule the wake timer.
   */
  void updated();

  /**
   * Wakes up the queue on a timer event.
   * The queue will make sure to handle the wake and forward packet-refs
   * accordingly.
   */
  void wake();
};
