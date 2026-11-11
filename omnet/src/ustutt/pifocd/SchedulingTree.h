#pragma once

#include "inet/common/packet/Packet.h"
#include "inet/queueing/base/PacketQueueBase.h"
#include "inet/queueing/common/ActivePacketSinkRef.h"
#include "inet/queueing/common/ActivePacketSourceRef.h"
#include "inet/queueing/contract/IActivePacketSink.h"
#include "inet/queueing/contract/IActivePacketSource.h"
#include "inet/queueing/contract/IPacketQueue.h"
#include "queues/SchedulingQueue.h"
#include "queues/ShapingQueue.h"
#include "utils.h"
#include <cstdint>
#include <unordered_map>
#include <vector>
#include <optional>

using namespace inet;

class SchedulingTree : public queueing::PacketQueueBase {
protected:
  inet::queueing::ActivePacketSourceRef producer;
  inet::queueing::ActivePacketSinkRef collector;

  SchedulingQueue root;
  std::vector<ShapingQueue> leafs;

  // Timestamps of when a queue wants to be waked.
  std::vector<uint64_t> timers;
  omnetpp::cMessage *wakeMsg = nullptr;

public:

  bool isRgp;
  int flowCount;
  std::vector<ShapingOptions> shaping_options;



  int packet_counter = 0;
  std::unordered_map<int, Packet *> packet_storage;

public:
  SchedulingTree() : root(SchedulingQueue(false)) {
    this->root.setSchedulingTree(this);

    int leafsCount = 8;
    leafs.reserve(leafsCount);

    for (int i = 0; i < leafsCount; i++) {
      ShapingQueue q = ShapingQueue(true, (uint8_t)i);
      q.setSchedulingTree(this);

      root.addChild(&q);
      q.setParent(&root);

      this->leafs.push_back(q);
      this->timers.push_back(UINT64_MAX);
    }
  }

  ~SchedulingTree() {};

protected:
  void initialize(int stage) override;

public:
  int getMaxNumPackets() const override { return 1000; }
  int getNumPackets() const override;

  b getMaxTotalLength() const override { return b(1000); }
  b getTotalLength() const override { return b(0); }

  bool isEmpty() const override { return getNumPackets() == 0; }
  Packet *getPacket(int index) const override { return nullptr; };
  void removePacket(Packet *packet) override {};
  void removeAllPackets() override {};

  bool supportsPacketPushing(const cGate *gate) const override { return true; }
  bool canPushSomePacket(const cGate *gate) const override { return true; };
  bool canPushPacket(Packet *packet, const cGate *gate) const override {
    return getNumPackets() < getMaxNumPackets();
  };
  void pushPacket(Packet *packet, const cGate *gate) override;

  bool supportsPacketPulling(const cGate *gate) const override { return true; }
  bool canPullSomePacket(const cGate *gate) const override {
    return !isEmpty();
  }
  Packet *canPullPacket(const cGate *gate) const override;
  Packet *pullPacket(const cGate *gate) override;

  void handleMessage(omnetpp::cMessage *msg) override;

  void updateTimer(uint8_t id_, uint64_t rt);
  void scheduleWake();

  void notifyCanPullPacketChanged();

  std::optional<PIFOPacket> peekLeaf(uint8_t id, bool isRgp) const;
  std::optional<PIFOPacket> pullLeaf(uint8_t id, bool isRgp);
};
