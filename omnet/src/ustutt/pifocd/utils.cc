#include "utils.h"
#include "inet/common/packet/Packet.h"
#include "inet/protocolelement/redundancy/StreamTag_m.h"
#include <regex>
#include <stdexcept>
#include <string>

using namespace inet;

// INFO: Has to be updated with omnetpp.ini.

std::string getStreamNameFromPacket(inet::Packet *packet) {

  if (packet == nullptr) {
    throw std::runtime_error("PIFOCD: getPacketFlow(): packet is nullptr");
  }

  packet->getName();

  inet::Ptr<const StreamReq> streamReq = packet->findTag<inet::StreamReq>();

  if (streamReq == nullptr) {
    using namespace omnetpp;
    EV_INFO << "PIFOCD: Packet has no StreamReq tag: " << packet->getName() << endl;
    throw std::out_of_range("PIFOCD: No StreamReq tag found!");
  }

  const char *streamName = streamReq->getStreamName();

  if (streamName == nullptr) {
    throw std::out_of_range("PIFOCD: No StreamName found!");
  }

  std::string streamNameStr(streamName);

  return streamNameStr;
}

Flow getPacketFlow(std::string &streamName) {
  // Expected format: "Stream-(pcp)-(id)"
  // Example: "Stream-(3)-(42)"
  std::regex pattern(R"(Stream-\(([0-7])\)-\(([0-9]+)\))");
  std::smatch match;

  if (!std::regex_match(streamName, match, pattern)) {
    throw std::out_of_range(
        "PIFOCD: StreamName is not fitting: expected 'Stream-(pcp)-(id)'");
  }

  int pcp = std::stoi(match[1].str());
  int id = std::stoi(match[2].str());

  return Flow{pcp, id};
}


uint64_t pmp_shapingTransaction(PIFOPacket p, std::vector<ShapingOptions> &shaping_options) {
    ShapingOptions &opt = shaping_options[p.flow.id];

    /*
        Recursive Definition:
          r_{f,i}^{(0)} = phi_f + i * T_f
          r_{f,i}^{(h)} = r_{f,i}^{(h-1)} + W_{f,i}^{(h-1)} + D_phy^{(h-1)}   (for h > 0)

        Closed-Form Summation:
          r_{f,i}^{(h)} = phi_f + i * T_f + SUM_{k=0}^{h-1} ( W_{f,i}^{(k)} + D_phy^{(k)} )
    */

    uint64_t release_time = opt.phase + opt.accumulated_delays + (opt.counter * opt.period);
    opt.release_time = release_time;


    opt.counter++;
    return release_time;
}

uint64_t pmp_schedulingTransaction(PIFOPacket p) { return 7 - p.flow.pcp; }

uint64_t rgp_shapingTransaction(PIFOPacket p, std::vector<ShapingOptions> &shaping_options) {
  uint64_t now = simtime_to_nsec(simTime());
  ShapingOptions &opt = shaping_options[p.flow.id];

  uint64_t release_time;
  if (opt.counter == 0) {
      release_time = now;
    opt.release_time = now + opt.period;
  } else {
      release_time = opt.release_time;
      opt.release_time += opt.period;
  }

  // INFO: This releasetime can be modified when conditionally dequeuing in RGP as well!

  opt.counter++;
  return release_time;
}

uint64_t rgp_schedulingTransaction(PIFOPacket p) { return 7 - p.flow.pcp; }

uint64_t simtime_to_nsec(inet::simtime_t t) {
  return (uint64_t)(SIMTIME_DBL(t) * 1e9 + 0.5);
}
