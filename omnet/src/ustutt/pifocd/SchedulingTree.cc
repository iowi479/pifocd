#include "SchedulingTree.h"
#include "inet/common/INETDefs.h"
#include "inet/common/ModuleAccess.h"
#include "inet/common/packet/Packet.h"
#include "inet/protocolelement/redundancy/StreamTag_m.h"
#include "utils.h"
#include <omnetpp.h>
#include <string>
#include <vector>

using namespace omnetpp;

Define_Module(SchedulingTree);

void SchedulingTree::initialize(int stage) {
  PacketQueueBase::initialize(stage);
  if (stage == INITSTAGE_LOCAL) {
    producer.reference(inputGate, false);
    collector.reference(outputGate, false);
  } else if (stage == INITSTAGE_QUEUEING) {
    checkPacketOperationSupport(inputGate);
    checkPacketOperationSupport(outputGate);
    if (producer != nullptr)
      producer.handleCanPushPacketChanged();
  }

  this->wakeMsg = new cMessage("wake");

  // Read all parameters
  this->isRgp = par("useRgpProtocol").boolValue();
  this->flowCount = par("flowCount").intValue();
  cValueArray *phasesArray = check_and_cast<cValueArray*>(par("phases").objectValue());
  cValueArray *accumulatedDelaysArray = check_and_cast<cValueArray*>(par("accumulatedDelays").objectValue());
  cValueArray *periodsArray = check_and_cast<cValueArray*>(par("periods").objectValue());




  if (phasesArray->size() != flowCount) {
      throw cRuntimeError(
          "phases has %d elements, but flowCount is %d",
          phasesArray->size(),
          flowCount
      );
  }

  if (accumulatedDelaysArray->size() != flowCount) {
      throw cRuntimeError(
          "accumulatedDelays has %d elements, but flowCount is %d",
          accumulatedDelaysArray->size(),
          flowCount
      );
  }

  if (periodsArray->size() != flowCount) {
      throw cRuntimeError(
          "periods has %d elements, but flowCount is %d",
          periodsArray->size(),
          flowCount
      );
  }

  this->shaping_options.resize(flowCount);

  for (int i = 0; i < flowCount; i++) {
      uint64_t phase = static_cast<uint64_t>(phasesArray->get(i).intValue());
      uint64_t accumulatedDelays = static_cast<uint64_t>(accumulatedDelaysArray->get(i).intValue());
      uint64_t period = static_cast<uint64_t>(periodsArray->get(i).intValue());

      // Multiply by 1000 to go from us to ns.
      this->shaping_options[i] = ShapingOptions{
          phase * 1000,                    // phase
          period * 1000,                   // period
          accumulatedDelays * 1000,        // accumulated_delays
          0,                        // release_time
          0                         // counter
      };

      EV_INFO << "PIFOCD: phase ["<< i << "] = " << phase << EV_ENDL;
      EV_INFO << "PIFOCD: period ["<< i << "] = " << period << EV_ENDL;
      EV_INFO << "PIFOCD: accumulatedDelays ["<< i << "] = " << accumulatedDelays << EV_ENDL;

  }

  EV_INFO << "PIFOCD: flowCount = " << this->flowCount << EV_ENDL;


  EV_INFO << "PIFOCD: isRgp = " << this->isRgp << EV_ENDL;
  SchedulingQueue::SchedulingTransaction sdtxn = this->isRgp ? rgp_schedulingTransaction : pmp_schedulingTransaction;
  ShapingQueue::ShapingTransaction sptxn = this->isRgp ? rgp_shapingTransaction : pmp_shapingTransaction;

  this->root.setSchedulingTransaction(sdtxn);
  for (int i = 0; i < this->leafs.size(); i++) {
      this->leafs[i].setSchedulingTransaction(sdtxn);
      this->leafs[i].setShapingTransaction(sptxn);
   }
}

void SchedulingTree::pushPacket(Packet *packet, const cGate *gate) {
  Enter_Method("pushPacket");
  // Takes ownership of the packet.
  // Now the previous owner will no longer dictate its lifetime.
  // We keep ownership until we transmit the packet further.
  take(packet);

  std::string streamName = getStreamNameFromPacket(packet);
  int packet_id = this->packet_counter++;

  this->packet_storage[packet_id] = packet;

  PIFOPacket p{packet_id, streamName, getPacketFlow(streamName)};

  EV_INFO << "PIFOCD: Pushing packet (pcp=" << p.flow.pcp
          << ", flow=" << p.flow.id << "), of stream: " << p.streamName << EV_ENDL;

  this->leafs[p.flow.pcp].push(p);

  this->notifyCanPullPacketChanged();
}

void SchedulingTree::notifyCanPullPacketChanged() {
  if (collector != nullptr && getNumPackets() > 0) {
    EV_INFO << "PIFOCD: SchedulingTree notifyCanPullPacketChanged" << EV_ENDL;
    collector.handleCanPullPacketChanged();
  }
}

Packet *SchedulingTree::pullPacket(const cGate *gate) {
  Enter_Method("pullPacket");

  std::optional<PIFOPacket> opt = std::nullopt;

  if (root.size() > 0) {
      // At least one packet is ready. So dequeue this packet.
      opt = root.pull(isRgp);

  } else if (this->isRgp) {
      uint64_t now = simtime_to_nsec(simTime());
      // reset rg
      for (ShapingOptions& options : shaping_options) {
          options.release_time = now;
      }

      // update all leafs packets with the new release guard.


      // There is a packet waiting but not in root.
      // Since we are in RGP we can conditionally dequeue

      int pcp_counter = this->leafs.size() - 1;
      while (pcp_counter >= 0 && !opt.has_value()) {
          this->leafs[pcp_counter].updatedRG();
          pcp_counter -= 1;
      }

      if (root.size() > 0) {
          // now a packet was released
          opt = root.pull(isRgp);
      }
  }


  if (!opt.has_value()) {
      return nullptr;
  }

  PIFOPacket p = opt.value();
  Packet *packet = nullptr;

  packet = this->packet_storage[p.packet_id];
  this->packet_storage.erase(p.packet_id);

  if (collector != nullptr)
      animatePullPacket(packet, outputGate, collector.getReferencedGate());

  return packet;
}

Packet *SchedulingTree::canPullPacket(const cGate *gate) const {
  // INFO:
  // This seems as it is not being used by omnet to determine if a packet can be
  // pulled. It seems as it only uses the getNumPackets() function to check
  // whether this is non-zero.

  EV_INFO << "PIFOCD: SchedulingTree canPullPacket" << EV_ENDL;

  std::optional<PIFOPacket> opt = std::nullopt;

  opt = root.peek(this->isRgp);

  if (this->isRgp && !opt.has_value()) {
      int pcp_counter = this->leafs.size() - 1;
      while (pcp_counter >= 0 && !opt.has_value()) {
          opt = this->leafs[pcp_counter].peek(true);
          pcp_counter -= 1;
      }
  }

  Packet *packet = nullptr;

  if (opt.has_value()) {
      packet = this->packet_storage.at(opt.value().packet_id);
  }

  return packet;
}

int SchedulingTree::getNumPackets() const {
  // This seems to determine if omnet will pull a packet from this construct.
  // If this is non-empty a packet will be pulled.

   if (this->isRgp) {
       return this->packet_storage.size();
   } else {
       return this->root.size();
   }
}

void SchedulingTree::handleMessage(omnetpp::cMessage *msg) {
  if (msg == wakeMsg) {
    uint64_t now = simtime_to_nsec(simTime());

    EV_INFO << "PIFOCD: SchedulingTree: Woken @" << now << "ns" << EV_ENDL;

    for (size_t i = 0; i < timers.size(); ++i) {
      uint64_t ts = timers[i];

      if (ts <= now) {
        // Reset timer to not wake this again.
        timers[i] = UINT64_MAX;

        this->leafs[i].wake();
      }
    }

    return;
  }
}

/*
 * Reschedule WakeTimer based on the this->timers.
 */
void SchedulingTree::scheduleWake() {
  cancelEvent(wakeMsg);

  uint64_t now = simtime_to_nsec(simTime());

  uint64_t minTs = timers[0];
  EV_INFO << "timers: " << EV_ENDL;

  for (uint64_t x : timers) {
    EV_INFO << x << ", ";
    minTs = std::min(minTs, x);
  }
  EV_INFO << EV_ENDL;

  // This would cause issues since the message would not arrive.
  if (now > minTs) {
    // if (now >= minTs) {
    throw cRuntimeError("PIFOCD: New Waketime is not in the future now=%lu, minTs=%lu",
                        now, minTs);
  }

  if (minTs == UINT64_MAX) {
    EV_INFO << "PIFOCD: SchedulingTree: No next Wake since no timer requested"
            << EV_ENDL;
    return;
  }

  simtime_t t = SimTime(minTs, SIMTIME_NS);

  scheduleAt(t, wakeMsg);
  EV_INFO << "PIFOCD: SchedulingTree: Next Wake @" << minTs << "ns" << EV_ENDL;
}

void SchedulingTree::updateTimer(uint8_t id, uint64_t rt) {
  this->timers[id] = rt;
  this->scheduleWake();
}

std::optional<PIFOPacket> SchedulingTree::peekLeaf(uint8_t id, bool isRgp) const {
  return this->leafs[id].peek(isRgp);
}

std::optional<PIFOPacket> SchedulingTree::pullLeaf(uint8_t id, bool isRgp) {
  return this->leafs[id].pull(isRgp);
}
