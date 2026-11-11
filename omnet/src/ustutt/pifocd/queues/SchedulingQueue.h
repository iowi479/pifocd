#pragma once

#include "inet/common/packet/Packet.h"
#include "../utils.h"
#include <queue>
#include <variant>
#include <vector>
#include <optional>

using namespace inet;

// INFO: Forward declaration to avoid compiler issues.
class SchedulingTree;

class SchedulingQueue {
public:
  using SchedulingTransaction = std::function<uint64_t(PIFOPacket)>;
  using V = std::variant<PIFOPacket, uint8_t>;

  struct Entry {
    V value;
    uint64_t rank;
  };

  struct Compare {
    bool operator()(const Entry &a, const Entry &b) const {
      // INFO: This is not stable. But it doesn't need to.
      // When there are elements with the same rank, we don't guarantee anything
      // about the order of the elements.
      return a.rank > b.rank;
    }
  };

protected:
  std::priority_queue<Entry, std::vector<Entry>, Compare> pcp_pq;

  bool isLeaf;
  std::vector<SchedulingQueue *> children;
  SchedulingQueue *parent;

  std::optional<SchedulingTransaction> schedulingTransaction;
  SchedulingTree *st = nullptr;

public:
  SchedulingQueue(bool isLeaf) : isLeaf(isLeaf) {
    this->pcp_pq = {};
    this->children = {};
    this->parent = nullptr;
    this->schedulingTransaction = std::nullopt;
  };

  virtual ~SchedulingQueue() { this->clear(); };

  void setSchedulingTree(SchedulingTree *st) { this->st = st; }

  void setParent(SchedulingQueue *parent) { this->parent = parent; }

  void addChild(SchedulingQueue *child) { this->children.push_back(child); }

  void setSchedulingTransaction(SchedulingTransaction sdtxn) { this->schedulingTransaction = sdtxn;}

  int size() const;
  bool isEmpty() const;
  void clear();

  virtual void push(PIFOPacket packet);
  virtual std::optional<PIFOPacket> pull(bool isRgp);
  virtual std::optional<PIFOPacket> peek(bool isRgp) const;
};
