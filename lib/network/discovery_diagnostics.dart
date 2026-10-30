/// Allowlisted, in-memory diagnostics. Never attach endpoints, native exception
/// text, service/TXT data, HTTP bodies, identities or game state here.
enum DiscoveryStage { idle, starting, active, failed }

enum DiscoveryFailure { permission, unsupported, busy, platform }

enum ProbeFailure {
  timeout,
  network,
  httpStatus,
  invalidResponse,
  tooLarge,
  invalidEndpoint,
}

class DiscoveryDiagnostics {
  DiscoveryDiagnostics({
    this.search = DiscoveryStage.idle,
    this.publication = DiscoveryStage.idle,
    this.searchFailure,
    this.publicationFailure,
    this.servicesSeen = 0,
    this.servicesChecked = 0,
    this.noUsableAddress = 0,
    this.roomsReachable = 0,
    Map<ProbeFailure, int> probeFailures = const {},
    this.manualProbeFailure,
  }) : probeFailures = Map.unmodifiable(probeFailures);

  final DiscoveryStage search;
  final DiscoveryStage publication;
  final DiscoveryFailure? searchFailure;
  final DiscoveryFailure? publicationFailure;
  final int servicesSeen;
  final int servicesChecked;
  final int noUsableAddress;
  final int roomsReachable;
  final Map<ProbeFailure, int> probeFailures;
  final ProbeFailure? manualProbeFailure;
  int get failedProbes => probeFailures.values.fold(0, (sum, n) => sum + n);

  /// Explicit user copy only; no automatic logging, storage or upload. Fixed
  /// keys + enums + counts make this safe even when remote inputs are hostile.
  String safeReport() => [
    'lan-discovery-v1',
    'search=${search.name}',
    'search_failure=${searchFailure?.name ?? 'none'}',
    'publication=${publication.name}',
    'publication_failure=${publicationFailure?.name ?? 'none'}',
    'services_seen=$servicesSeen',
    'services_checked=$servicesChecked',
    'no_usable_address=$noUsableAddress',
    'rooms_reachable=$roomsReachable',
    for (final reason in ProbeFailure.values)
      'probe_${reason.name}=${probeFailures[reason] ?? 0}',
    'manual_probe_failure=${manualProbeFailure?.name ?? 'none'}',
  ].join('\n');
}
